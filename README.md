# homelab-ops

GitOps source repository for the `pegasus` (non-prod) and `galactica` (prod)
Kubernetes clusters.

## Documentation

- [Flux Operator installation](docs/flux-operator-install.md) — Helm, Terraform,
  GitHub App authentication, and verification
- [Minikube deployment](docs/minikube-deployment.md) — create and bootstrap the
    `pegasus` and `galactica` local test clusters
- [Storage and databases](docs/storage-databases.md) — Longhorn PVCs
    and CloudNative-PG clusters
- [Networking](docs/networking.md) — Gateway API and Envoy Gateway