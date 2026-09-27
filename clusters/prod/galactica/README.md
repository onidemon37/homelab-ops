# Galactica Production Cluster

Galactica is the production workload cluster. It does not deploy Vault; the authoritative Vault
service runs on Atlantis and is consumed remotely through private TLS at `vault.ninhu.xyz`.

## Deployment Prerequisite

Deploy Atlantis before Galactica. Atlantis provides the Vault service, its internal Gateway, and
the Cert-Manager-issued certificate for `vault.ninhu.xyz`. Galactica's remote SecretStores cannot
become Ready until Atlantis is running, Vault is initialized and unsealed, private DNS resolves
the Vault hostname, and the Vault CA is available in the Galactica secrets overlay.

Recommended order:

1. Bootstrap Atlantis and wait for its Flux foundation, Gateway, Vault, and certificate.
2. Initialize and unseal Vault, then configure the Galactica Kubernetes auth mount and roles.
3. Confirm `https://vault.ninhu.xyz` is reachable from the private network and verify the CA.
4. Bootstrap Galactica and wait for `rbac` before enabling its `secrets` wave.

Destroying and recreating Galactica does not require recreating Atlantis or the Vault KV data, but
the Galactica Kubernetes reviewer JWT must be regenerated and applied to Vault after each rebuild.

## Reconciliation Order

The initial rebuild intentionally activates only the Atlantis-proven baseline:

```text
flux-system -> infrastructure -> networking -> observability collectors
```

CNPG/databases and remote Vault secrets are kept out of the Galactica root until this baseline
is healthy. Add those waves one at a time after a successful clean rebuild.

```text
infrastructure
  -> cert-manager, External Secrets, Longhorn, metrics-server, Reloader

secrets
  -> Galactica SecretStores and ExternalSecrets backed by Atlantis Vault

databases
  -> CNPG operator and Grafana PostgreSQL cluster

networking
  -> Envoy Gateway and internal Gateway VIP

observability
  -> kube-state-metrics, Alloy, Prometheus, Grafana, Loki, Tempo, dashboards, alerts
```

The secrets wave requires Atlantis Vault to be initialized, unsealed, and configured with:

- `auth/kubernetes-galactica`
- `app-galactica-cert-manager`
- `app-galactica-grafana`
- Galactica-scoped secret paths under `secret/apps/prod/galactica/`
- A Galactica `vault-ca` Secret

## Cluster-Scoped Overlays

```text
apps/overlays/prod/galactica/
  infrastructure/
  secrets/
  databases/
  networking/
  observability/
```

CNPG is owned only by `databases`. Vault is not present in any Galactica overlay.

The internal Gateway uses a separate service VIP from the Kubernetes API VIP:

```text
192.168.89.120  Kubernetes API
192.168.89.121  Galactica internal Gateway
```

