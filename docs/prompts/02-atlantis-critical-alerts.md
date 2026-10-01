# Prompt: critical-service alerts (Vault and Galactica PostgreSQL)

## Goal
Add alerts for a **small set of critical services only**, not for every pod in the cluster:
1. Vault sealed or down on Atlantis.
2. The Galactica PostgreSQL (CNPG) cluster down or degraded.

## Why Atlantis needs this
Atlantis hosts Vault. A sealed or restarted Vault silently stops every ExternalSecret sync on
Galactica. Atlantis currently runs only collectors (Alloy, kube-state-metrics), so it has no
alerting of its own. Decide, and ask the user, between:
- **A.** Atlantis ships metrics to Galactica's Prometheus and Galactica alerts on them (simple,
  but Atlantis alerts die if Galactica is down), or
- **B.** Atlantis runs its own small Prometheus and Alertmanager (more resources, independent).
Recommend A plus a heartbeat check (see below) because of the low resources.

## Tasks
1. **Vault metrics:** enable Vault telemetry (`unauthenticated_metrics_access` or a token for the
   scrape), add a `ServiceMonitor` or Alloy scrape, and confirm `vault_core_unsealed` shows up.
2. **Vault alerts** (`PrometheusRule`, labelled `severity: critical`):
   - `VaultSealed`: `vault_core_unsealed == 0` for 1m.
   - `VaultDown`: `up{job=~".*vault.*"} == 0` for 2m.
   - `VaultNoActiveLeader`, if Raft is used: no `vault_core_active == 1`.
3. **Pod-down alerts for critical workloads only:** use `kube_pod_status_ready` or
   `kube_statefulset_status_replicas_ready`, filtered by namespace/name, for Vault pods
   (namespace `vault`) and the Galactica CNPG pods (`cnpg.io/cluster` label). Do not add a
   catch-all.
4. **PostgreSQL alerts (Galactica):** `cnpg_collector_up == 0`, no primary, replica lag, and
   `cnpg_pg_replication_lag` above a threshold. Enable the CNPG `PodMonitor`
   (`monitoring.enablePodMonitor: true`).
5. **Routing:** a `critical` route in Alertmanager to Discord (see `docs/alerting.md`), grouped by
   `alertname`, with a sensible `repeat_interval` (for example 4h) so the channel isn't spammed.
6. **Heartbeat:** the Watchdog alert goes to Healthchecks.io or Uptime Kuma, so silence from
   Alertmanager itself also raises an alarm.
7. **Test:** on pegasus first. Seal Vault or scale the CNPG cluster to 0 and confirm the Discord
   message arrives and clears.

## Constraints
Pegasus and Galactica first. Do not seal or restart the real Atlantis Vault without explicit
approval. Keep the alert rules in a base, with thresholds patched per overlay.
