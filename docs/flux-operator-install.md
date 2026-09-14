# Installing the Flux Operator

Steps to install the Flux Operator (CRDs + controller-manager) and bootstrap a Flux
instance per cluster in this repo, plus what's already been verified against
`pegasus`/`galactica` minikube test clusters.

## 1. Install the Flux Operator itself

The operator is a one-time, out-of-band install (not something Flux manages for
itself, since Flux doesn't exist yet at this point) — done once per cluster, into the
`flux-system` namespace.

### Option A: Helm (used for the local minikube test)

```sh
helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --kube-context <pegasus|galactica>
```

Verify it came up:

```sh
kubectl --context <pegasus|galactica> -n flux-system rollout status deploy/flux-operator
```

### Option B: Terraform

Officially supported via the
[`flux-operator-bootstrap`](https://github.com/controlplaneio-fluxcd/terraform-kubernetes-flux-operator-bootstrap)
module, which installs both the operator and the `FluxInstance` in one apply. Roots
already scaffolded in this repo: `terraform/non-prod/` (pegasus) and `terraform/prod/`
(galactica), each with its own `helm`/`kubernetes` provider config pointing at the
matching kubeconfig context:

```sh
cd terraform/non-prod   # or terraform/prod
tofu init
tofu apply -var kube_context=pegasus   # or galactica
```

Terraform reaches the cluster the same way `kubectl --context <ctx>` does — via the
local `~/.kube/config` file and the named context (`config_path`/`config_context` on
both providers), no separate credentials needed. Each root's `main.tf` reads the same
`clusters/<env>/flux-system/flux-instance.yaml` already committed here, so the
Kubernetes-manifest and Terraform installation paths stay in sync — no duplicated
config.

### Option C: kubectl (dev/test only, not recommended for real clusters)

```sh
kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/install.yaml
```

## 2. Create the git credentials secret (private repo)

Required before the `FluxInstance`'s `sync` block can successfully clone this repo.

- **Terraform path (Option B above)**: handled automatically via
  `managed_resources.secrets_yaml`, sourced from the `git_token` variable — pass it
  with `-var git_token=...` or a `TF_VAR_git_token` env var, never commit it.
- **Manual path**: create directly via `kubectl`, never commit the token to git:

```sh
kubectl --context <pegasus|galactica> -n flux-system create secret generic flux-system \
  --from-literal=username=git \
  --from-literal=password='<token>'
```

## 3. Apply the FluxInstance (installs the actual Flux controllers)

```sh
kubectl --context <pegasus|galactica> apply -k clusters/<non-prod|prod>/flux-system
```

This installs `source-controller`, `kustomize-controller`, `helm-controller`, and
`notification-controller` per the `components` list in `flux-instance.yaml`, and
begins syncing from `spec.sync` once the repo content (this directory) is pushed.

## 4. Verify

```sh
kubectl --context <pegasus|galactica> get fluxreport/flux -n flux-system -o yaml
kubectl --context <pegasus|galactica> get kustomizations -A
```

## 5. Access the Flux Web UI

```sh
kubectl --context <pegasus|galactica> -n flux-system port-forward svc/flux-operator 9080:9080
```

Then open `http://localhost:9080`.
