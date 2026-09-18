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

External Secrets Operator is installed, but no `ClusterSecretStore` is created yet.
Before creating one, configure Vault's Kubernetes authentication method, a least-
privilege policy, and a dedicated External Secrets service account/role. This avoids
committing database or application credentials to Git.
