# Proxmox VE Prometheus Exporter

This runbook installs `prometheus-pve-exporter` on the Hyperion Proxmox host and
scrapes it from Galactica Prometheus.

The exporter listens on Hyperion port `9221`. It queries the Proxmox API using a
dedicated read-only API user and token.

## 1. Create the Proxmox read-only user

Run these commands on Hyperion as `root` or another account with Proxmox
permission-management privileges:

```sh
pveum user add prometheus@pve
pveum role add PrometheusPVEAuditor -privs "Auditor"
pveum acl modify / --users prometheus@pve --roles PrometheusPVEAuditor
```

You can use the built-in `PVEAuditor` role instead of creating a custom role:

```sh
pveum acl modify / --users prometheus@pve --roles PVEAuditor
```

Use one approach, not both. A dedicated custom role makes the intended exporter
permissions explicit; `PVEAuditor` is the simpler built-in option.

## 2. Create the API token

Create a token named `exporter` for the user:

```sh
pveum user token add prometheus@pve exporter
```

Proxmox prints the token secret once. Record it in a password manager. The full
identity is:

```text
prometheus@pve!exporter
```

Do not commit the token secret to Git.

## 3. Install Docker on Hyperion

Hyperion is a Proxmox host, so a small dedicated VM or LXC is preferable for the
exporter. If running it directly on Hyperion is intentional:

```sh
apt update
apt install -y docker.io docker-compose
systemctl enable --now docker
```

Verify Docker:

```sh
docker info
docker compose version
```

## 4. Create the exporter directory

```sh
mkdir -p /opt/prometheus-pve-exporter
cd /opt/prometheus-pve-exporter
```

Create `pve.yaml` with the Proxmox token secret:

```yaml
default:
  user: prometheus@pve
  token_name: exporter
  token_value: "REPLACE_WITH_THE_PROXMOX_TOKEN_SECRET"
  verify_ssl: true
```

Protect the file:

```sh
chmod 600 pve.yaml
```

If Hyperion's Proxmox API certificate is not trusted by the exporter, use
`verify_ssl: false` only on this private management network. Prefer installing the
correct CA and keeping verification enabled.

## 5. Run the exporter with Docker Compose

Create `compose.yaml`:

```yaml
services:
  pve-exporter:
    image: prompve/prometheus-pve-exporter:latest
    container_name: prometheus-pve-exporter
    restart: unless-stopped
    ports:
      - "9221:9221"
    volumes:
      - ./pve.yaml:/etc/prometheus/pve.yaml:ro
    command:
      - --config.file=/etc/prometheus/pve.yaml
      - --web.listen-address=0.0.0.0:9221
```

The image already provides the `pve_exporter` entrypoint. Do not include
`pve_exporter` again in `command`.

Start it:

```sh
docker compose up -d
docker compose ps
docker compose logs --tail=100
```

## 6. Verify the exporter

Check that port `9221` is listening:

```sh
ss -tnlp | grep 9221
curl http://127.0.0.1:9221/metrics
```

Check a Proxmox target query:

```sh
curl 'http://127.0.0.1:9221/pve?target=hyperion.ninhu.xyz'
```

From a Galactica-connected machine, verify the private network path:

```sh
curl 'http://hyperion.ninhu.xyz:9221/pve?target=hyperion.ninhu.xyz'
```

A connection refusal means no process is listening or a firewall blocks TCP/9221.
An exporter authentication or TLS error means the Proxmox token or certificate
configuration needs attention.

## 7. Galactica Prometheus configuration

Galactica keeps the target in:

```text
apps/overlays/prod/galactica/observability/prometheus-patches.yaml
```

The scrape job uses the exporter's `/pve` endpoint:

```yaml
- job_name: proxmox-ve-exporter
  scrape_interval: 30s
  scrape_timeout: 10s
  metrics_path: /pve
  params:
    target:
      - hyperion.ninhu.xyz
  static_configs:
    - targets:
        - hyperion.ninhu.xyz:9221
      labels:
        instance: proxmox-ve
```

After pushing a configuration change:

```sh
flux reconcile kustomization observability -n flux-system --with-source
```

Verify the target in Prometheus. It should report `UP` after Hyperion's exporter
is reachable.

## Token rotation

Create a replacement Proxmox API token, update `/opt/prometheus-pve-exporter/pve.yaml`,
and restart the container:

```sh
docker compose up -d --force-recreate
docker compose logs --tail=100
```

After confirming the replacement token works, revoke the old token:

```sh
pveum user token remove prometheus@pve exporter
```

Keep port `9221` restricted to the private management network. Do not expose the
exporter publicly.
