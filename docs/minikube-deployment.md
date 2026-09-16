# Minikube Deployment: Pegasus and Galactica

This runbook creates two local Minikube clusters for testing the GitOps bootstrap:

- `pegasus` represents non-prod and uses `terraform/non-prod/`.
- `galactica` represents prod and uses `terraform/prod/`.

The clusters are independent Minikube profiles. Terraform connects to each profile
through the matching kubeconfig context and installs the Flux Operator, Flux
controllers, FluxInstance, and GitHub App Secret.

## Prerequisites

Install and verify:

```sh
minikube version
kubectl version --client
helm version
cd /home/onidemon/Development/homelab-ops
```

The Docker driver is used below. Docker must be running:

```sh
docker version
```

The GitHub App must have **Contents: Read-only** access to the `homelab-ops`
repository. Keep the downloaded private PEM file outside Git and use restrictive
permissions:

```sh
chmod 600 "$HOME/Downloads/<github-app-private-key>.pem"
```

## 1. Create both Minikube clusters

```sh
minikube start \
  -p pegasus \
  --driver=docker \
  --kubernetes-version=stable \
  --memory=3200 \
  --cpus=2

minikube start \
  -p galactica \
  --driver=docker \
  --kubernetes-version=stable \
  --memory=3200 \
  --cpus=2
```

Confirm both profiles and contexts:

```sh
minikube profile list
kubectl config get-contexts
kubectl --context pegasus get nodes
kubectl --context galactica get nodes
```

## 2. Bootstrap non-prod (`pegasus`)

Set the GitHub App values in your shell. Do not commit these values or the PEM file:

```sh
export TF_VAR_github_app_id='<app-id>'
export TF_VAR_github_app_installation_id='<installation-id>'
export TF_VAR_github_app_private_key_file="$HOME/Downloads/<github-app-private-key>.pem"
```

Run Terraform from the non-prod root:

```sh
cd /home/onidemon/Development/homelab-ops/terraform/non-prod
tofu init
tofu plan
tofu apply
```

The provider configuration uses:

```text
kubeconfig: ~/.kube/config
context: pegasus
```

Terraform installs the Flux Operator and creates the FluxInstance. The FluxInstance
uses native GitHub App authentication and refreshes its own GitHub installation tokens;
no one-hour token needs to be minted manually.

Verify:

```sh
kubectl --context pegasus -n flux-system get pods
kubectl --context pegasus -n flux-system get fluxinstance flux
kubectl --context pegasus -n flux-system get gitrepositories,kustomizations
```

Expected resources:

- `flux-operator`, `source-controller`, `kustomize-controller`,
  `helm-controller`, and `notification-controller` are `Running`.
- `FluxInstance/flux` is `Ready=True`.
- `GitRepository/flux-system` is `Ready=True`.
- `Kustomization/flux-system` and `Kustomization/apps` are `Ready=True`.

## 3. Bootstrap prod (`galactica`)

Use the same GitHub App variables, then run the production root:

```sh
cd /home/onidemon/Development/homelab-ops/terraform/prod
tofu init
tofu plan
tofu apply
```

The provider configuration uses:

```text
kubeconfig: ~/.kube/config
context: galactica
```

Verify:

```sh
kubectl --context galactica -n flux-system get pods
kubectl --context galactica -n flux-system get fluxinstance flux
kubectl --context galactica -n flux-system get gitrepositories,kustomizations
```

## 4. Access the Flux dashboard

Port-forward each cluster separately:

```sh
kubectl --context pegasus -n flux-system port-forward svc/flux-operator 9080:9080
```

Open `http://localhost:9080`.

For Galactica, use another terminal and port:

```sh
kubectl --context galactica -n flux-system port-forward svc/flux-operator 9081:9080
```

Open `http://localhost:9081`.

## 5. Force reconciliation

```sh
kubectl --context pegasus -n flux-system annotate \
  gitrepository flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite

kubectl --context galactica -n flux-system annotate \
  gitrepository flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite
```

## 6. Reset and start over

Destroy the Terraform bootstrap first, then delete the Minikube profiles:

```sh
cd /home/onidemon/Development/homelab-ops/terraform/non-prod
tofu destroy -auto-approve

cd ../prod
tofu destroy -auto-approve

minikube delete -p pegasus
minikube delete -p galactica
```

This removes only the local Minikube clusters and their Terraform-managed Flux
bootstrap resources. It does not delete GitHub repositories, Packer images, Proxmox
VMs, or files in this repository.

## Troubleshooting

Check the generated Flux resources and recent events:

```sh
kubectl --context <pegasus|galactica> -n flux-system get fluxinstance,gitrepository,kustomization
kubectl --context <pegasus|galactica> -n flux-system get events --sort-by=.lastTimestamp
kubectl --context <pegasus|galactica> -n flux-system logs deploy/source-controller --since=10m
```

If `GitRepository` says `provider is not set to github`, ensure the committed
`clusters/<environment>/flux-system/flux-instance.yaml` contains:

```yaml
sync:
  provider: github
```

Then push the change and force reconciliation. If Terraform has already handed the
FluxInstance to Flux, bump `bootstrap_revision` to force the bootstrap module to run
again:

```sh
tofu apply -var bootstrap_revision=2
```

If a stale artifact keeps restoring an older manifest, temporarily suspend the root
Kustomization, restore the provider, force the GitRepository reconciliation, and
resume the Kustomization:

```sh
kubectl --context <pegasus|galactica> -n flux-system patch kustomization flux-system \
  --type merge -p '{"spec":{"suspend":true}}'

kubectl --context <pegasus|galactica> -n flux-system patch fluxinstance flux \
  --type merge -p '{"spec":{"sync":{"provider":"github"}}}'

kubectl --context <pegasus|galactica> -n flux-system annotate \
  gitrepository flux-system \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" \
  --overwrite

kubectl --context <pegasus|galactica> -n flux-system patch kustomization flux-system \
  --type merge -p '{"spec":{"suspend":false}}'
```
