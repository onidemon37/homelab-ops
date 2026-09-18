# Vault Manual Bootstrap

Vault is a three-replica Raft cluster using Longhorn-backed persistent data and audit
volumes. It is deliberately deployed sealed. Manual initialization and unseal are
required because this homelab does not have an external KMS or HSM.

This guide uses the `pegasus-non-prod` kubeconfig context.

## Verify the Flux deployment

```sh
kubectl --context pegasus-non-prod -n flux-system get helmrelease vault external-secrets
kubectl --context pegasus-non-prod -n vault get pods,pvc
kubectl --context pegasus-non-prod -n external-secrets get pods
```

Wait for `vault-0`, `vault-1`, and `vault-2` and their data/audit PVCs to be
`Running` and `Bound`.

## Initialize Vault once

Run this exactly once for a fresh Vault data volume:

```sh
kubectl --context pegasus-non-prod -n vault exec -it vault-0 -- \
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
kubectl --context pegasus-non-prod -n vault exec -it vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault operator unseal <unseal-key-1>'

kubectl --context pegasus-non-prod -n vault exec -it vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault operator unseal <unseal-key-2>'
```

Verify:

```sh
kubectl --context pegasus-non-prod -n vault exec vault-0 -- \
  sh -c 'VAULT_ADDR=https://127.0.0.1:8200 VAULT_SKIP_VERIFY=true vault status'
```

Expected: `Sealed: false`.

## Access the UI locally

Vault uses an internal Cert-Manager-issued TLS certificate. The browser will not trust
this private CA by default; use the port-forward for initial local administration and
accept the private-CA warning only after verifying the forwarded destination.

```sh
kubectl --context pegasus-non-prod -n vault port-forward svc/vault-ui 8200:8200
```

Open `https://localhost:8200` and authenticate with the initial root token only long
enough to configure safer access.

## After a Pod restart

The Longhorn volumes preserve Vault data, but manual-unseal Vault returns sealed after
a restart. Submit two unseal shares to each affected Pod again, then confirm `vault
status` reports `Sealed: false`.

## Next configuration step

External Secrets Operator is installed, but no application `SecretStore` is created
yet. Before creating one, configure Vault's Kubernetes authentication method, a least-
privilege policy, and a dedicated External Secrets service account/role. This avoids
committing database or application credentials to Git. Configure Vault Kubernetes
authentication and the External Secrets role/policy with the matching
`infrastructure-live/tofu/vault/` OpenTofu root.

Port-forward Vault in one terminal:

```sh
kubectl --context pegasus-non-prod -n vault port-forward svc/vault-active 8200:8200
```

In another terminal, set the bootstrap root token only for this one-time configuration
run, then apply the non-production Vault root:

```sh
export TF_VAR_vault_token='<initial-root-token>'

cd ../infrastructure-live/tofu/vault/non-production
tofu init
tofu apply
```

The workspace creates the KV v2 `secret/` mount, Kubernetes auth backend, and an
per-application policy and Kubernetes auth role. Do not grant the ESO controller a
wildcard policy. Instead, declare each application's namespace, ServiceAccount, and
single allowed KV-v2 path in the matching `infrastructure-live/tofu/vault/<environment>`
root:

```hcl
app_vault_access = {
  example-api = {
    namespace       = "example"
    service_account = "example-api"
    secret_path     = "apps/example-api/database"
  }
}
```

This creates the `app-example-api` Vault policy and Kubernetes auth role, allowing
only `secret/data/apps/example-api/database` to be read. Pair it with a namespaced
ESO `SecretStore` that uses the `example-api` ServiceAccount. A shared store would
weaken the application isolation boundary.

Repeat this pattern with a different namespace, ServiceAccount, Vault path, policy,
and namespaced `SecretStore` for each application.

## Grafana database bootstrap

Grafana uses a CloudNative-PG cluster named `grafana` in the `observability`
namespace. Its credentials are read from the app-specific Vault path
`secret/apps/grafana/database` and synchronized by the `grafana-vault` SecretStore.

Before reconciling the observability workload, add the Grafana values to Vault using
the restricted automation token. Do not commit these values:

```sh
vault kv put secret/apps/grafana/database \
  username=grafana \
  password='<database-password>' \
  admin_username='<grafana-admin-user>' \
  admin_password='<grafana-admin-password>'
```

Because a namespaced `SecretStore` cannot read a Secret in the `vault` namespace,
copy only the public `ca.crt` value from `vault/vault-ca` into a Secret named
`vault-ca` in `observability`. Do not copy the Vault TLS private key:

```sh
kubectl --context pegasus-non-prod -n vault get secret vault-ca \
  -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/vault-ca.crt
kubectl --context pegasus-non-prod -n observability create secret generic vault-ca \
  --from-file=ca.crt=/tmp/vault-ca.crt \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f /tmp/vault-ca.crt
```

Then reconcile Flux and verify the generated credentials, CNPG cluster, and Grafana:

```sh
flux --context pegasus-non-prod reconcile kustomization apps --with-source
kubectl --context pegasus-non-prod -n observability \
  get secretstore,externalsecret,cluster,pods,pvc
```
