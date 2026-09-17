# Phase 5: Gateway API and Envoy Gateway

Phase 5 adds the edge networking layer on top of the Phase 4 foundation. The first
slice uses Envoy Gateway and Gateway API, managed by Flux through the OCI chart
published by Envoy Proxy.

## What is installed

- Gateway API CRDs, supplied by the Envoy Gateway chart.
- Envoy Gateway controller in `envoy-gateway-system`.
- One controller replica in non-prod.
- Two controller replicas in prod.

The chart source is:

```text
oci://docker.io/envoyproxy/gateway-helm
```

The repository does not create application routes yet. Routes should be added with
`Gateway`, `HTTPRoute`, `ReferenceGrant`, and TLS resources alongside the application
that owns the route.

## Verify the installation

After pushing the Phase 5 manifests and waiting for Flux:

```sh
kubectl get helmrepositories,ocirepositories -n flux-system
kubectl get helmreleases -A
kubectl get pods -n envoy-gateway-system
kubectl get crd gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io
```

Inspect a failed release:

```sh
kubectl -n envoy-gateway-system describe helmrelease envoy-gateway
kubectl -n flux-system get events --sort-by=.lastTimestamp
```

## Create a Gateway

A shared Gateway is usually managed per environment. This example creates an HTTP
listener; add TLS only after Cert-Manager and the required DNS strategy are ready:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public
  namespace: networking
spec:
  gatewayClassName: envoy-gateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

Confirm the GatewayClass name provided by the controller before applying this
resource:

```sh
kubectl get gatewayclass
```

## Route an application

An application namespace can expose a Service through an `HTTPRoute`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
  namespace: app
spec:
  parentRefs:
    - name: public
      namespace: networking
  hostnames:
    - app.nignu.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: app
          port: 8080
```

For cross-namespace routing, the Gateway listener must allow the application
namespace and a `ReferenceGrant` may be required by the referenced object type. Keep
route ownership with the application onboarding files so deleting an application also
removes its public route.

## TLS and Cloudflare

The intended later flow is:

1. Cert-Manager creates a certificate using a Cloudflare DNS-01 solver.
2. The certificate Secret is created in the route namespace.
3. The Gateway listener references that Secret.
4. Cloudflare DNS or Cloudflare Tunnel directs the hostname to the cluster edge.

Do not expose the Flux dashboard, Vault, Longhorn, or database administration endpoints
publicly until authentication, TLS, and access policy are defined. Prefer private
routes or port-forwarding during development.
