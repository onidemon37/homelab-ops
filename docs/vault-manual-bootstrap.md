# Vault Manual Bootstrap

Vault is a three-replica Raft cluster using Longhorn-backed persistent data and audit
volumes. It is deliberately deployed sealed. Manual initialization and unseal are
required because this homelab does not have an external KMS or HSM.

This guide uses the `atlantis-vault` kubeconfig context. Atlantis is the dedicated
Vault cluster; Pegasus and Galactica consume it remotely and do not host Vault.

## Deployment Order

Atlantis must be deployed before Galactica. Atlantis supplies the Vault service, its internal
Gateway, and the Cert-Manager-issued TLS certificate for `vault.ninhu.xyz`. Do not bootstrap
Galactica's remote SecretStores first; they cannot validate until Atlantis is reachable and Vault
has been initialized, unsealed, and configured.

The required order is:

1. Deploy Atlantis and wait for its Flux foundation, internal Gateway, Vault, and Certificate.
2. Initialize and unseal Vault, then configure the Galactica Kubernetes auth mount and roles.
3. Verify private DNS, the Vault endpoint, and the CA used by Galactica's `vault-ca` Secret.
4. Deploy or recreate Galactica, regenerate its reviewer JWT, and reconcile `rbac` before `secrets`.

The Vault KV data survives Galactica rebuilds because it lives in Atlantis. The Kubernetes
reviewer JWT does not: generate a new one for every rebuilt Galactica cluster and update the
Vault auth backend configuration.

Use the infrastructure helper for token rotation or after rebuilding Galactica. It generates the
current Galactica CA and reviewer JWT, increments the write-only token version, applies the Vault
configuration, refreshes both SecretStores, and reconciles the Flux secrets wave:

```sh
/home/onidemon/Development/infrastructure-live/scripts/rotate-galactica-vault-auth.sh
```

Set `GALACTICA_TOKEN_REVIEWER_JWT_VERSION` explicitly only when a controlled version is needed;
the helper otherwise uses the current Unix timestamp to guarantee a new write-only version.

## Verify the Flux deployment

```sh
kubectl --context atlantis-vault -n flux-system get kustomization shared-services
kubectl --context atlantis-vault -n vault get helmrelease vault
kubectl --context atlantis-vault -n vault get pods,pvc,certificate
```

Wait for `vault-0`, `vault-1`, and `vault-2` and their data/audit PVCs to be
`Running` and `Bound`.

## Initialize Vault once

Run this exactly once for a fresh Vault data volume:

```sh
kubectl --context atlantis-vault -n vault exec -it vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault operator init -key-shares=3 -key-threshold=2'
```

Vault prints one initial root token and three unseal key shares. Store them outside
Git and outside the Kubernetes cluster. Any two shares are required to unseal this
Vault. The root token is only for initial configuration; create limited operators and
policies before using Vault for workloads.

## Unseal Vault

After initialization, submit any two different unseal key shares to **each** Vault
Pod. Start with `vault-0`, then repeat for `vault-1` and `vault-2` so they can join
the Raft cluster:

```sh
kubectl --context atlantis-vault -n vault exec -it vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault operator unseal <unseal-key-1>'

kubectl --context atlantis-vault -n vault exec -it vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault operator unseal <unseal-key-2>'
```

Verify:

```sh
kubectl --context atlantis-vault -n vault exec vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault status'
```

Expected: `Sealed: false`.

## Access the UI locally

Vault uses an internal Cert-Manager-issued TLS certificate. The browser will not trust
this private CA by default; use the port-forward for initial local administration and
accept the private-CA warning only after verifying the forwarded destination.

```sh
kubectl --context atlantis-vault -n vault port-forward svc/vault-ui 8200:8200
```

Open `https://localhost:8200` and authenticate with the initial root token only long
enough to configure safer access.

## After a Pod restart

The Longhorn volumes preserve Vault data, but manual-unseal Vault returns sealed after
a restart. Submit two unseal shares to each affected Pod again, then confirm `vault
status` reports `Sealed: false`.

## Enable audit logging

The HelmRelease creates a dedicated Longhorn-backed audit volume mounted at
`/vault/audit`, but mounting the volume does not enable a Vault audit device. After
Vault is initialized and unsealed, enable the file audit device once with the initial
root token:

```sh
kubectl --context atlantis-vault -n vault exec vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=<initial-root-token> vault audit enable file file_path=/vault/audit/audit.log'
```

Verify the device and file:

```sh
kubectl --context atlantis-vault -n vault exec vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true VAULT_TOKEN=<initial-root-token> vault audit list'

kubectl --context atlantis-vault -n vault exec vault-0 -- \
  test -f /vault/audit/audit.log
```

Audit logs contain sensitive request metadata. Restrict access to the audit PVC and
monitor its Longhorn capacity.

## Verify the private endpoint

Atlantis exposes Vault through Envoy Gateway with TLS passthrough. Private DNS must
resolve `vault.ninhu.xyz` to `192.168.89.131`. Vault terminates TLS with the
Cert-Manager-issued certificate.

```sh
getent hosts vault.ninhu.xyz
curl --cacert vault-ca.crt https://vault.ninhu.xyz/v1/sys/health
```

A sealed Vault normally returns HTTP `503`; an uninitialized Vault may return `501`.
Either response confirms DNS, Gateway routing, and TLS when the certificate verifies.

## Next configuration stage

Do not enable `apps/base/vault-integrations` during initial bootstrap. Atlantis is
the Vault server; Galactica only consumes it through External Secrets.

### Configure Galactica Kubernetes authentication

The Galactica RBAC wave creates the `system:auth-delegator` binding required by
Vault's Kubernetes auth method. It must be Ready before the Vault auth backend is
configured:

```sh
flux reconcile kustomization rbac -n flux-system --with-source

kubectl --context galactica-prod auth can-i create tokenreviews \
  --as=system:serviceaccount:external-secrets:external-secrets
```

The second command must return `yes`. Generate the Galactica CA and reviewer JWT
without committing either value:

```sh
export TF_VAR_galactica_kubernetes_ca_cert="$(
  kubectl --context galactica-prod config view --raw --minify --flatten \
    -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' |
  base64 -d
)"

export TF_VAR_galactica_token_reviewer_jwt="$(
  kubectl --context galactica-prod -n external-secrets \
    create token external-secrets --duration=8760h
)"
```

Apply the Vault configuration from the production OpenTofu root. It creates the
`kubernetes-galactica` auth mount and the cert-manager/Grafana roles. Then add the
Grafana database secret through Vault, never Git:

```sh
vault kv put secret/apps/prod/galactica/grafana/database \
  username=grafana password="$TF_VAR_grafana_database_password" \
  admin_username=admin admin_password="$TF_VAR_grafana_admin_password"
```

Finally reconcile the secrets wave and verify both namespaced SecretStores and
ExternalSecrets report `Ready=True` before enabling Grafana:

```sh
flux reconcile kustomization secrets -n flux-system --with-source
kubectl --context galactica-prod -n cert-manager get secretstore,externalsecret
kubectl --context galactica-prod -n observability get secretstore,externalsecret

## Troubleshooting Galactica consumers

Check the Flux dependency chain first:

```sh
kubectl --context galactica-prod -n flux-system \
  get kustomization rbac secrets databases observability
```

The expected order is `rbac`, `secrets`, `databases`, then `observability`, with
each resource reporting `Ready=True`.

### TokenReview permission is `no`

The External Secrets service account needs the cluster-scoped
`system:auth-delegator` binding. Confirm it and the permission:

```sh
kubectl --context galactica-prod get clusterrolebinding \
  external-secrets-auth-delegator

kubectl --context galactica-prod auth can-i create tokenreviews \
  --as=system:serviceaccount:external-secrets:external-secrets
```

The second command must return `yes`. Reconcile `rbac` before retrying the
Vault configuration.

### Vault Kubernetes login returns 403

Confirm that the Galactica auth mount and roles exist in Atlantis Vault:

```sh
vault auth list
vault read auth/kubernetes-galactica/config
vault read auth/kubernetes-galactica/role/app-galactica-cert-manager
vault read auth/kubernetes-galactica/role/app-galactica-grafana
```

Re-export the current Galactica CA and reviewer JWT, then run `tofu plan` and
`tofu apply` from `infrastructure-live/tofu/vault/production`. Do not commit
either value. A reviewer JWT belongs to the current Galactica cluster and must
be regenerated after rebuilding that cluster.

### SecretStore is not Ready

Inspect the namespaced store rather than the ExternalSecret first:

```sh
kubectl --context galactica-prod -n cert-manager describe secretstore cert-manager-vault
kubectl --context galactica-prod -n observability describe secretstore grafana-vault
```

Common causes are a missing `vault-ca` Secret, a missing service account, or a
stale status from before RBAC was applied. After correcting the cause, force a
new reconciliation:

```sh
kubectl --context galactica-prod -n observability annotate secretstore grafana-vault \
  force-sync="$(date +%s)" --overwrite
```

### ExternalSecret is not synced

Verify the Vault KV-v2 metadata and property names without printing secret data:

```sh
vault kv metadata get secret/apps/prod/galactica/grafana/database
vault kv get -format=json secret/apps/prod/galactica/grafana/database | \
  jq -r '.data.data | keys[]'
```

Grafana requires `username`, `password`, `admin_username`, and
`admin_password`. After correcting the data, annotate the ExternalSecret to
trigger an immediate retry:

```sh
kubectl --context galactica-prod -n observability annotate externalsecret \
  grafana-database-credentials force-sync="$(date +%s)" --overwrite
```

### Flux reconciliation appears stuck

The Galactica `secrets` Kustomization uses `wait: true`, so Flux intentionally
waits while SecretStores and ExternalSecrets become Ready. Check the dependent
resource instead of repeatedly deleting the Kustomization. Once the failing
resource is healthy, reconcile it with:

```sh
flux reconcile kustomization secrets -n flux-system --with-source
```

### CNPG is still setting up the primary

Check the Cluster and its pods before enabling Grafana:

```sh
kubectl --context galactica-prod -n observability get cluster grafana
kubectl --context galactica-prod -n observability get pods \
  -l cnpg.io/cluster=grafana
```

Do not enable Grafana until `Cluster/grafana` reports `Ready=True` and the
`grafana-database-credentials` Secret exists.

## Rebuild verification checklist

After destroying and recreating Galactica, regenerate the reviewer JWT, apply
the Vault configuration again, and verify the waves in order:

```sh
kubectl --context galactica-prod -n flux-system \
  get kustomization rbac secrets databases observability
kubectl --context galactica-prod -n observability \
  get secretstore,externalsecret,cluster
```

Only after CNPG is Ready should `grafana.enabled` be changed to `true`. Verify
the Grafana pod and database connection before adding or testing its private
Gateway route.