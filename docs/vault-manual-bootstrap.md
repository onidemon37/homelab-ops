# Vault Manual Bootstrap

Vault is a three-replica Raft cluster using Longhorn-backed persistent data and audit
volumes. It is deliberately deployed sealed. Manual initialization and unseal are
required because this homelab does not have an external KMS or HSM.

This guide uses the `atlantis-vault` kubeconfig context. Atlantis is the dedicated
Vault cluster; Pegasus and Galactica consume it remotely and do not host Vault.

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

Do not enable `apps/base/vault-integrations` during initial bootstrap. Atlantis does
not need an application `ExternalSecret` to run Vault.

Before Pegasus or Galactica consume secrets, create separate Kubernetes auth mounts
or otherwise distinct auth configuration for each workload cluster. Each application
must receive a least-privilege policy for one exact KV-v2 path and a namespaced
`SecretStore`; do not grant the External Secrets controller a wildcard policy.

The existing `infrastructure-live/tofu/vault/production` and `non-production` roots
still contain workload-cluster assumptions. Review and refactor them for remote
Atlantis authentication before applying them to this Vault instance.
