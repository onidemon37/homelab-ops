# homelab-ops

GitOps source repository for three Kubernetes clusters, reconciled by Flux Operator:

| Cluster | Environment | Role | Flux entrypoint |
| --- | --- | --- | --- |
| `pegasus` | non-prod | Test bed: try things by hand, codify them in kustomize, then promote | `clusters/non-prod/pegasus` |
| `galactica` | prod | Production workloads | `clusters/prod/galactica` |
| `atlantis` | prod | Vault and shared services; deploy it before galactica | `clusters/prod/atlantis` |

Layout: `apps/base` holds shared manifests, `apps/overlays/<env>/<cluster>` holds per-cluster
patches, `clusters/` holds the Flux entrypoints, and `terraform/` bootstraps Flux on each cluster.

## Common tasks

`task` and `make` expose the same targets, so use whichever you prefer:

| Task | Make | Purpose |
| --- | --- | --- |
| `task validate` | `make validate [CLUSTER=pegasus]` | Render every cluster with kustomize |
| `task lint` | `make lint` | yamllint, shellcheck and `tofu fmt` |
| `task flux:status` | `make flux-status [CONTEXT=ctx]` | Show Kustomizations and HelmReleases |
| `task flux:reconcile` | `make flux-reconcile [CONTEXT=ctx]` | Reconcile the git source and root Kustomization |

## Documentation

- [Flux Operator installation](docs/flux-operator-install.md) — Helm, Terraform,
  GitHub App authentication, and verification
- [Minikube deployment](docs/minikube-deployment.md) — create and bootstrap the
    `pegasus` and `galactica` local test clusters
- Cluster notes: [atlantis](clusters/prod/atlantis/README.md),
    [galactica](clusters/prod/galactica/README.md)
- [Storage and databases](docs/storage-databases.md) — Longhorn PVCs
    and CloudNative-PG clusters
- [Networking](docs/networking.md) — Gateway API and Envoy Gateway
- [Vault manual bootstrap](docs/vault-manual-bootstrap.md) — initialize and unseal
    the non-prod Vault deployment
- [Proxmox VE exporter](docs/proxmox-ve-exporter.md) — create the read-only API
    user/token and run the Dockerized exporter for Prometheus
- [Cloudflare DNS and tunnel](docs/cloudflare-tunnel.md) — public DNS and tunnel for galactica
- [Prompts](docs/prompts/README.md) — working prompts for ongoing improvements
