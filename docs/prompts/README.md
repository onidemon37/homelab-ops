# Prompts

Reusable working prompts for this repo. Paste (or point Claude Code at) one file per session.

| File | Purpose |
| --- | --- |
| [01-repo-cleanup-and-hardening.md](01-repo-cleanup-and-hardening.md) | Ordered backlog: CI/path fixes, renames, docs, backups, TLS, pinning, Renovate, pegasus/galactica parity |
| [02-atlantis-critical-alerts.md](02-atlantis-critical-alerts.md) | Alerts for the critical services only: Vault sealed/down, Galactica PostgreSQL down |
| [03-kyverno.md](03-kyverno.md) | Kyverno policy engine: Audit first on pegasus, then promote to galactica and atlantis |
| [04-vulnerability-management.md](04-vulnerability-management.md) | Trivy Operator in-cluster plus Trivy scans in CI for images, manifests and Terraform |

Conventions for every prompt:

- Pegasus (non-prod) first, then galactica, then atlantis. Never touch anything live without asking.
- One task = one commit (conventional commits), verified with `kustomize build` before committing.
- Justify a change before writing it; verify assumptions empirically (render, `helm search`, `tofu validate`).
