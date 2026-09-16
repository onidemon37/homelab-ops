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
tofu apply \
  -var='github_app_id=<app-id>' \
  -var='github_app_installation_id=<installation-id>' \
  -var="github_app_private_key_file=$HOME/Downloads/<github-app-private-key>.pem"
```

Terraform reaches the cluster the same way `kubectl --context <ctx>` does — via the
local `~/.kube/config` file and the named context (`config_path`/`config_context` on
both providers), no separate credentials needed. Each root's `main.tf` reads the same
`clusters/<env>/flux-system/flux-instance.yaml` already committed here, so the
Kubernetes-manifest and Terraform installation paths stay in sync — no duplicated
config.

The Terraform root also creates the GitHub App Secret required by the private
repository sync. The PEM file is read locally during `tofu apply`; it is not part of
the repository. The bootstrap module treats the managed Secret as sensitive and keeps
only a content hash for change detection.

### Option C: kubectl (dev/test only, not recommended for real clusters)

```sh
kubectl apply -f https://github.com/controlplaneio-fluxcd/flux-operator/releases/latest/download/install.yaml
```

## 2. Configure GitHub App credentials

Terraform creates the `flux-system` Secret from the GitHub App details. The private
key stays in the local PEM file and must never be committed.

The App needs repository **Contents: Read-only** access to `homelab-ops`, and the
installation ID must belong to that repository. Flux generates and refreshes its own
short-lived GitHub installation tokens from the App private key, so the old
`get-git-app-token.sh` helper is not needed for steady-state reconciliation.

The Flux App Secret contains `githubAppID`, `githubAppInstallationID`, and
`githubAppPrivateKey`. Because the `FluxInstance` uses `provider: github`, Flux does
not expect `username`/`password`, an SSH `identity`, or `known_hosts` for this setup.

For a shell-friendly alternative to `-var`, use environment variables:

```sh
export TF_VAR_github_app_id='<app-id>'
export TF_VAR_github_app_installation_id='<installation-id>'
export TF_VAR_github_app_private_key_file="$HOME/Downloads/<github-app-private-key>.pem"

cd terraform/non-prod   # or terraform/prod
tofu apply
```

Use a fresh `tofu apply` after rotating the App private key or changing the App
installation. If the bootstrap module has already handed resources to Flux, bump
`bootstrap_revision` (for example, `-var bootstrap_revision=2`) to force a new
bootstrap run. Do not add the PEM file, token, or generated Terraform state to Git.

## 3. Verify the bootstrap

```sh
kubectl --context pegasus get fluxinstance,fluxreport -n flux-system
kubectl --context pegasus get gitrepository,kustomization -n flux-system

# Repeat with galactica for production.
kubectl --context galactica get fluxinstance,fluxreport -n flux-system
kubectl --context galactica get gitrepository,kustomization -n flux-system
```

Expected state is `Ready=True` for `FluxInstance/flux`, `FluxReport/flux`,
`GitRepository/flux-system`, `Kustomization/flux-system`, and `Kustomization/apps`.

## 4. Reset and re-bootstrap Flux

Use this only when Flux bootstrap is stuck or was created with an incorrect
authentication configuration. It removes Flux-generated resources and the Terraform
bootstrap release, but does not remove the Kubernetes cluster or application data
outside the Flux bootstrap resources.

For non-prod / `pegasus`:

```sh
kubectl --context pegasus -n flux-system delete \
  fluxinstance flux \
  gitrepository flux-system \
  kustomization apps \
  kustomization flux-system \
  --ignore-not-found

cd terraform/non-prod
tofu destroy -auto-approve
```

For prod / `galactica`:

```sh
kubectl --context galactica -n flux-system delete \
  fluxinstance flux \
  gitrepository flux-system \
  kustomization apps \
  kustomization flux-system \
  --ignore-not-found

cd terraform/prod
tofu destroy -auto-approve
```

Confirm both Terraform roots are empty before recreating the bootstrap:

```sh
cd terraform/non-prod && tofu state list
cd ../prod && tofu state list
```

Re-bootstrap one environment at a time using the GitHub App credentials from Step 2:

```sh
cd terraform/non-prod   # or terraform/prod
tofu init
tofu apply \
  -var bootstrap_revision=1 \
  -var='github_app_id=<app-id>' \
  -var='github_app_installation_id=<installation-id>' \
  -var="github_app_private_key_file=$HOME/Downloads/<github-app-private-key>.pem"
```

If a live `FluxInstance` is missing `provider: github` while diagnosing the
bootstrap, apply the committed manifest once:

```sh
kubectl --context galactica apply \
  -f clusters/prod/flux-system/flux-instance.yaml
```

## 5. Apply the FluxInstance manually (non-Terraform path)

```sh
kubectl --context <pegasus|galactica> apply -k clusters/<non-prod|prod>/flux-system
```

This installs `source-controller`, `kustomize-controller`, `helm-controller`, and
`notification-controller` per the `components` list in `flux-instance.yaml`, and
begins syncing from `spec.sync` once the repo content (this directory) is pushed.

## 6. Verify

```sh
kubectl --context <pegasus|galactica> get fluxreport/flux -n flux-system -o yaml
kubectl --context <pegasus|galactica> get kustomizations -A
```

## 7. Access the Flux Web UI

```sh
kubectl --context <pegasus|galactica> -n flux-system port-forward svc/flux-operator 9080:9080
```

Then open `http://localhost:9080`.
