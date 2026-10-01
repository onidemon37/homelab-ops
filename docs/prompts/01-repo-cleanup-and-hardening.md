# Prompt: homelab-ops cleanup and hardening backlog

## Context

GitOps repo for three clusters managed by Flux Operator:

- `atlantis` (prod, shared services: Vault, internal gateway)
- `galactica` (prod, workloads)
- `pegasus` (non-prod, the lab where things are installed by hand first, then codified into
  kustomize, then promoted to galactica)

This is a home lab used to study CKA (current), CKAD and CKS, and to prototype future company
deployments. Resources are limited. Replica counts are deliberately 1 for now. Security
hardening (NetworkPolicies, PSA) is deferred, so do not add it.

Work through the tasks in order. Before each task, state what you will change and why. After
each task, run `kustomize build` on every affected path and commit it separately.

## Tasks

### 1. Fix CI
- `flux-local.yaml` and `validate.yaml` reference `apps/overlays/non-prod/pegasus/infrastructure/controllers`
  and `.../services`, which do not exist. Fix the paths, or restructure per task 12, whichever is
  consistent with the Flux Kustomizations in the pegasus cluster folder.
- Remove or repair the `ansible` job, since `infrastructure/ansible` does not exist (task 5).
- CI hardening (accepted):
  - Pin every GitHub Action to a commit SHA, with a version comment.
  - Replace `imranismail/setup-kustomize` with the kustomize release binary or `fluxcd/flux2/action`.
  - Add `kubeconform` with Flux/CRD schemas, `shellcheck` on `scripts/`, and `tofu fmt -check` and
    `tofu validate` for each `terraform/*` directory.
  - Switch the render job to real `flux-local test`, since the workflow is named after it.
  - Keep `labeler.yaml` on `pull_request_target` only while it never checks out PR code; add a
    comment saying so.

### 2. Fix the pegasus Terraform path
`terraform/non-prod/main.tf` loads `clusters/non-prod/flux-system/flux-instance.yaml`. Point it at
the real file (after the rename in task 4 it becomes `clusters/non-prod/pegasus/flux-system/`).

### 3. Taskfile parity with a Makefile
- `Taskfile.yaml` includes `taskfiles/{flux,lint,validation}.yaml`, which do not exist.
- **Open question, ask first:** homelab-ops has no Makefile. Sibling repos do, for example
  `../kubernetes-lab-environment/Makefile`. Confirm which one is the reference.
- Create the `taskfiles/` files so that every Makefile target has an equivalent `task` target.
  Keep the Makefile too, so people can choose either. Keep both thin and calling the same scripts
  or commands, so they cannot drift.

### 4. Rename `clusters/non-prod/atlantis` to `clusters/non-prod/pegasus`
- Use `git mv`. Update every reference: CI matrices, `flux-instance.yaml` `sync.path`, Terraform,
  docs, README files, `.github/labeler.yaml`, and comments.
- Finish with `grep -rn "non-prod/atlantis"` returning nothing.

### 5. README and docs
- Update the root README: list all three clusters and their roles, and link every doc.
- Fix `clusters/prod/galactica/README.md`. Its reconciliation-order section is stale, because
  CNPG, databases and secrets are now in the root kustomization.
- Delete the `infrastructure/` folder, along with its README and the `area/infrastructure` label
  entries in `.github/labeler.yaml` and `labels.yaml`.
- Fix the usage text in `scripts/get-git-app-token.sh` to use placeholders instead of the real
  App ID, installation ID and PEM filename.

### 6. Replicas
Out of scope for now. Do not change replica counts.

### 7. Prompts folder
Done: this folder. Keep `README.md` in sync when adding prompts.

### 8. Backups, pegasus first
Replication is not a backup. Design and implement for **pegasus only**, then document how to copy
the pattern to galactica:
- **CNPG (Postgres):** continuous WAL archiving plus a `ScheduledBackup`. Check the current CNPG
  docs. The in-tree `barmanObjectStore` is being replaced by the Barman Cloud plugin, so use
  whichever is current for the pinned CNPG version.
- **Longhorn:** configure a backup target and a `RecurringJob` (daily snapshot plus backup, with
  `retain` kept small).
- **Target storage:** propose options and let the user choose: MinIO on pegasus (simplest, but it
  shares the failure domain), or NFS or S3 on a Proxmox host or NAS (better). Credentials come from
  Vault through ExternalSecrets, never from Git.
- Write `docs/backups.md` with a restore procedure, and perform a test restore of the `grafana`
  database.

### 9. Alerting documentation
- Add `docs/alerting.md`: how to wire Alertmanager to a Discord webhook (webhook URL stored in
  Vault, pulled in by ExternalSecret, referenced by `alertmanagerConfig`), a routing example by
  severity, and a dead-man's-switch (Watchdog) route.
- Include the free-tool comparison:
  - Paging, PagerDuty-like: PagerDuty free tier, Grafana Cloud IRM, Better Stack free tier. For a
    lab, ntfy (self-hosted or ntfy.sh) is the simplest push channel.
  - Uptime and heartbeat: Uptime Kuma (self-hosted), UptimeRobot free tier, Healthchecks.io
    (Watchdog heartbeat).
  - Free-tier limits change, so verify current limits before recommending anything.
- Alertmanager currently has no receivers configured. The rules in `proxmox-alerts.yaml` and
  `raspberry-pi-temperature-rules.yaml` fire into nothing.

### 10. Atlantis critical alerts
Handled by [02-atlantis-critical-alerts.md](02-atlantis-critical-alerts.md).

### 11. Retention caps (low-resource lab)
Prometheus currently has `retention: 7d` on a 10Gi PVC and no size cap. Proposal (confirm with the
user, then apply per overlay):

| Component | Pegasus | Galactica |
| --- | --- | --- |
| Prometheus | `retention: 3d`, `retentionSize: 4GB` on the current PVC | `retention: 7d`, `retentionSize: 7GB` on 10Gi |
| Loki | 72h | 7d |
| Tempo | 24h | 48h |

Keep `retentionSize` at about 70-80% of the PVC so compaction has headroom. Put the defaults in
base and the differences in the overlays.

### 12. Match prod and non-prod structure
Make `apps/overlays/non-prod/pegasus/*` mirror `apps/overlays/prod/galactica/*` (same folder names
and the same Flux Kustomization waves), differing only in values such as sizes and hostnames.
- Share the duplicated dashboards (`dashboard-proxmox.yaml`, Raspberry Pi) through a base.
- Pegasus has `external-secrets` and `storage` commented out, and no Vault. **Open question:** does
  pegasus use the Atlantis Vault, or keep a local Vault? Ask before wiring.
- Keep pegasus as the place to try things by hand first, so document the promotion path: pegasus,
  then codify in kustomize, then galactica.

### 13. Grafana database TLS
`GF_DATABASE_SSL_MODE: disable` in `kube-prometheus-stack.yaml`. CNPG already issues server certs.
Switch to `verify-full` (or `require` if the CA wiring is awkward), mounting the CNPG CA, and
verify that Grafana connects on pegasus first.

### 14. Pin chart versions to latest, update apiVersions
- For every HelmRelease and OCIRepository, find the latest stable version (`helm search repo`,
  registry tags). Do not guess. Replace ranges like `>=70.0.0 <80.0.0` with exact versions.
- Read the release notes for breaking changes between the current and new versions of
  kube-prometheus-stack, Loki, Tempo, Vault, CNPG, Alloy and kube-state-metrics.
- Check every `apiVersion` in the repo against the Flux version. For example, HelmRelease is
  `helm.toolkit.fluxcd.io/v2`, and Gateway API and cert-manager resources may need bumps.
- Do pegasus first and leave galactica for a separate commit.

### 15. Pin the FluxInstance
`distribution.version: "2.x"` becomes an exact minor (look up the current release). Do it in all
three `flux-instance.yaml` files.

### 16. Dependency automation
**Recommendation: Renovate, not Dependabot.** Dependabot cannot update chart versions inside Flux
`HelmRelease` or `OCIRepository` manifests. Renovate's `flux` and `helmv3` managers can, and it
also handles GitHub Actions, Terraform, and the `ghcr.io` image tags. Add `renovate.json` with
grouped PRs and a weekly schedule. Leave major bumps for manual review, and add `dependabot.yml`
only if the user wants GitHub Actions covered by both.

### 17. Terraform pinning
Change `>=` to `~>` for the helm and kubernetes providers in `terraform/*/providers.tf`. The
module is already pinned at 0.8.0. Re-run `tofu init -upgrade` and commit the lock files.

### 18. Explanations the user asked for (add as `docs/ci-and-quality.md`)
Write short plain-language notes for the original items 23-25:
- **CI checks syntax, not meaning:** `kustomize build` proves the YAML renders. It does not prove
  the Kubernetes objects are valid for the cluster. `kubeconform` validates against the schemas
  and `kube-linter` or `kyverno` flags bad practice such as missing limits or `latest` tags.
- **Resource requests and limits:** requests are what the scheduler reserves, and limits are the
  ceiling. Without them, one pod can starve a node. Add a LimitRange per namespace as a backstop,
  and set values on Vault, Envoy and Alloy.
- **Day-2 runbooks:** bootstrap docs exist, but upgrade, restore and node-replacement procedures
  are missing. Write `docs/runbooks/` with one page each for: Vault unseal and restore, rebuilding
  galactica, replacing a Longhorn node, and a chart upgrade.

## Done criteria
Every task is a separate commit, CI is green on the PR, `kustomize build` passes for all paths,
and no live cluster has been touched without explicit approval.
