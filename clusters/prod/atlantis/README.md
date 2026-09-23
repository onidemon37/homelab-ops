# Atlantis GitOps Cluster

Atlantis is the dedicated Vault cluster. It is a separate failure and trust domain from the
workload clusters:

- `clusters/non-prod` manages non-production Pegasus workloads.
- `clusters/prod/galactica` manages production workloads.
- `clusters/prod/atlantis` manages the Vault cluster foundation and shared services.

## Why Atlantis Exists

Vault is a dependency of application secrets, database credentials, and external integrations.
Running authoritative Vault inside Pegasus or Galactica creates a circular bootstrap dependency:

```text
storage -> Vault -> ExternalSecret -> database credentials -> CNPG -> Grafana
```

Atlantis breaks that cycle. Pegasus and Galactica can be rebuilt independently while Vault data
remains in its own cluster and storage domain.

## Current Scope

Atlantis currently reconciles only the foundation Kustomization:

```text
apps/overlays/prod/atlantis/infrastructure/
  cert-manager
  Longhorn
  External Secrets Operator
  Metrics Server
  Reloader
```

Atlantis does not deploy CNPG, Grafana, observability, tenant workloads, or public application
networking.

The future shared-services layer is:

```text
apps/overlays/prod/atlantis/shared-services/
```

It is intentionally not reconciled yet. It will later contain Vault and Vault-dependent shared
integrations after the foundation is healthy.

## Reconciliation Order

```text
infrastructure
  -> Longhorn StorageClass and foundation controllers

shared-services
  -> Vault TLS and Vault HA/Raft

manual gate
  -> Vault init, unseal, auth, policies, and credentials

secret integrations
  -> SecretStores and ExternalSecrets
```

The manual gate is deliberate until an independent KMS or HSM is available for auto-unseal.

## Foundation Checks

Follow the central [Flux Operator installation guide](../../../docs/flux-operator-install.md#bootstrap-atlantis)
for the Atlantis Terraform bootstrap, GitHub App inputs, and handoff verification.

```sh
kubectl --context atlantis-vault get nodes -o wide
kubectl --context atlantis-vault get kustomizations -n flux-system
kubectl --context atlantis-vault get helmreleases -A
kubectl --context atlantis-vault get pods -A
kubectl --context atlantis-vault get storageclass
```

Do not add Vault-dependent resources until the foundation Kustomization is `Ready=True` and
Longhorn is healthy.
