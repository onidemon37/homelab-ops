# Cloudflare DNS + Tunnel - galactica (andorigna.com)

Flux deploys `external-dns` and a locally configured Cloudflare Tunnel for
`andorigna.com` on the `galactica` (prod) cluster. Applying the manifests
requires the Vault roles and the two pre-populated Vault secrets below.

## Components

### cloudflare-dns
- **What**: `external-dns` HelmRelease (chart: `oci://ghcr.io/home-operations/charts-mirror/external-dns`, `1.20.0`)
- **Namespace**: `networking`
- **Base path**: `apps/base/cloudflare-dns/`
- **Auth**: Cloudflare API Token (scoped `Zone - DNS - Edit`, `andorigna.com` zone only)
- **Sources**: watches `DNSEndpoint` and `HTTPRoute` resources attached to the `internal` Gateway; only `andorigna.com` is managed.

### cloudflare-tunnel
- **What**: `cloudflared` connector (via bjw-s `app-template` chart)
- **Namespace**: `networking`
- **Base path**: `apps/base/cloudflare-tunnel/`
- **Auth**: Tunnel Token (not the Tunnel ID — see below)
- **Ingress**: local config sends Grafana and Prometheus to the Gateway VIP at `192.168.89.121:443`, using each hostname as the origin TLS server name; unmatched hosts return 404. This expects a locally managed tunnel, not Dashboard-managed ingress.

## Credentials

Three distinct values, only two of which are secrets:

| Value | What it's for | Secret? | Where it's used |
|---|---|---|---|
| Tunnel ID | CNAME target (`<id>.cfargotunnel.com`) | No | `DNSEndpoint` manifest, plaintext |
| Tunnel Token | Authenticates the `cloudflared` pod to the tunnel | Yes | Vault → `TUNNEL_TOKEN` env var |
| Cloudflare API Token | Lets `external-dns` manage DNS records in the zone | Yes | Vault → `CF_API_TOKEN` env var |

For a locally created tunnel, obtain its connector token:
```bash
cloudflared tunnel token <TUNNEL-ID-or-NAME>
```

## Vault paths

The connector token is stored under
`secret/apps/prod/galactica/cloudflare-tunnel/tunnel` as `token`; the DNS-edit
API token is stored under `secret/apps/prod/galactica/cloudflare-dns/api` as
`api-token`. Do not commit either value to Git or print it in terminal logs.

Verify:
```bash
vault kv metadata get secret/apps/prod/galactica/cloudflare-tunnel/tunnel
vault kv metadata get secret/apps/prod/galactica/cloudflare-dns/api
```

Each path is read via its own `SecretStore` → `ExternalSecret` pair, mirroring
the other Galactica secret integrations, using the `kubernetes-galactica`
Vault auth mount, with dedicated roles/policies:
- `app-galactica-cloudflare-tunnel`
- `app-galactica-cloudflare-dns`

each bound to their respective ServiceAccount in the `networking` namespace.

## Networking

The `internal` Gateway serves only the standalone HTTP routes for
`*.galactica.ninhu.xyz`. The `external` Gateway has a separate Envoy Service,
`envoy-external.networking.svc.cluster.local:443`, and accepts public HTTPS
routes from the `observability` namespace. The kube-prometheus-stack
HelmRelease provisions the Grafana and Prometheus public HTTPRoutes there.
ExternalDNS reads those hostnames and the external Gateway's
`external-dns.alpha.kubernetes.io/target: external.andorigna.com` annotation.
The only explicit DNSEndpoint maps `external.andorigna.com` to
`2d3955f1-b237-4acf-85d5-9fe132eb8bcc.cfargotunnel.com`. Grafana and
Prometheus DNS records are therefore generated from HTTPRoutes, not hand-written
DNSEndpoints. The Cloudflare edge connects to the tunnel, which forwards to the
external HTTPS Gateway.

## Flux wiring

The `secrets` wave creates both Cloudflare ExternalSecrets and a Vault CA in
`networking`. Apply the production Vault Terraform changes to create their
Kubernetes auth roles and read-only policies before reconciling this wave.
The `cloudflare-dns` and `cloudflare-tunnel` waves wait for `secrets` and
`networking`. A separate `cloudflare-dns-records` wave waits for
`cloudflare-dns` to install the DNSEndpoint CRD before applying the CNAME.

## Known gaps / follow-ups
- Confirm the connector is healthy and `external.andorigna.com` and the
  route-derived Grafana/Prometheus records point to the intended tunnel.
- The origin must be reachable from cloudflared and present a trusted
  certificate covering both public hostnames. Check route attachment and
  `cloudflared` logs if the tunnel connects but the sites return 502.