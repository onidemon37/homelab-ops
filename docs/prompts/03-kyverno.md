# Prompt: add Kyverno to the clusters

## Goal
Add Kyverno as a policy engine on all three clusters, rolled out **pegasus first, then galactica,
then atlantis**. It starts in `Audit` mode so it reports problems without blocking anything.
Policies are promoted to `Enforce` one at a time. This fits the CKS study goal and the "validate
meaning, not just syntax" gap in `01-repo-cleanup-and-hardening.md`.

## Constraints
- Home lab with limited resources: one replica of each controller for now (replicas are a later
  topic), with explicit requests and limits.
- Flux owns everything. Install through a `HelmRelease`, not `kubectl apply`. Experiment by hand on
  pegasus first, then codify.
- Pin the chart to an exact version. Look up the latest stable one (`helm search repo`), do not
  guess, and read the release notes for breaking changes.
- Do not touch live Atlantis or Galactica without explicit approval.

## Plan

### 1. Base and install (`apps/base/kyverno/`)
- `namespace.yaml`, `repository.yaml` (HelmRepository, `https://kyverno.github.io/kyverno/`),
  `helmrelease.yaml`, `kustomization.yaml`. Follow the layout of `apps/base/cert-manager`.
- Install CRDs through the chart (`crds: CreateReplace`, as in kube-prometheus-stack).
- Enable only what is needed: the admission, background and reports controllers. Disable the
  cleanup controller unless a policy needs it.
- Set `ServiceMonitor` metrics on, so Prometheus scrapes it.
- Exclude `kube-system`, `flux-system`, `kyverno` and `longhorn-system` from policies by default,
  so a bad policy cannot lock Flux or storage out of the cluster.

### 2. Two Flux waves (the CRDs must exist before the policies)
- `kyverno` (the controller) in the infrastructure wave, with `wait: true`.
- `kyverno-policies` as a separate Flux Kustomization with `dependsOn: kyverno` and path
  `apps/base/kyverno-policies`. Patch each cluster through overlays
  (`apps/overlays/<env>/<cluster>/kyverno-policies`).

### 3. Starter policies (all `validationFailureAction: Audit` at first)
Start small and CKS-relevant:
1. Disallow the `latest` tag and require an explicit tag.
2. Require CPU and memory requests and limits (this closes the gap from the review).
3. Disallow privileged containers, `hostPath`, `hostNetwork` and `hostPID`.
4. Require `runAsNonRoot` and drop `ALL` capabilities, with exceptions where the Helm charts
   need otherwise.
5. Restrict image registries to a list, for example `ghcr.io`, `quay.io`, `registry.k8s.io`,
   `docker.io`.
6. Require standard labels (`app.kubernetes.io/name`).

Use `PolicyException` resources for Longhorn, Vault and anything else that legitimately breaks a
rule. Document each exception with the reason.

### 4. Promotion path
1. Install on pegasus and let it run in Audit for a week.
2. Review `PolicyReport` and `ClusterPolicyReport` (`kubectl get polr -A`). Fix workloads or add
   exceptions.
3. Flip one policy at a time to `Enforce` on pegasus, then promote the same commit to galactica,
   then atlantis.
4. Because Atlantis hosts Vault, enforce there last and test a Vault pod restart afterwards.

### 5. CI integration
- Add the `kyverno` CLI to `flux-local.yaml`: `kyverno apply apps/base/kyverno-policies --resource
  <rendered manifests>` against the output of `kustomize build`. This shifts the checks left, so a
  bad manifest fails the PR instead of the cluster.
- Add `kyverno test` with a few pass/fail fixtures in `tests/kyverno/`.
- Pin the CLI version and the action SHA, per the CI hardening task.

### 6. Observability
- Add a Grafana dashboard for policy results (a community Kyverno dashboard is available; check
  it matches the pinned version).
- Alert on admission controller down. Failure policy `Fail` blocks the API when Kyverno is down, so
  use `failurePolicy: Ignore` on non-critical policies and alert on the webhook being unavailable.
  Add this to `02-atlantis-critical-alerts.md` only if the user agrees.

### 7. Docs
- `docs/kyverno.md`: what is installed, how to read the reports, how to write an exception,
  how to test a policy locally, and the promotion path.
- Update the root README and `docs/prompts/README.md`.

## Open questions, ask before starting
- Which policies first? Use the starter list above, or a subset?
- Allowed registry list for item 5.
- Should Vault on Atlantis be exempt from the security policies permanently, or only until its
  chart values are tightened?

## Done criteria
Kyverno is running on pegasus in Audit mode with the starter policies, the report shows real
findings, CI runs the policies against rendered manifests, and promotion to galactica and atlantis
is a separate approved step.
