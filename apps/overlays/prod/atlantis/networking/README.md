# Atlantis Internal Networking

This overlay installs the Envoy Gateway controller and creates Atlantis's private internal
Gateway. It does not create public DNS, Cloudflare routes, or a public listener.

## IP Ownership

Atlantis reserves two different LAN addresses:

| Address | Purpose |
|---|---|
| `192.168.89.130` | Kubernetes API control-plane VIP |
| `192.168.89.131` | Internal Envoy Gateway LoadBalancer VIP |

The addresses must not overlap with each other, node addresses, or the DHCP pool.

Kube-VIP owns both functions but handles them independently:

- Control-plane mode advertises `192.168.89.130` for kubeadm and the Kubernetes API.
- Service mode watches `LoadBalancer` Services and advertises `192.168.89.131` for Envoy.

The Kube-VIP static-pod configuration is managed by the Atlantis Ansible bootstrap playbook in
`infrastructure-live`.

## Resources

The overlay contains:

- `../networking-controller/envoy-gateway-patches.yaml`: control-plane tolerations for the Envoy controller and certgen Job
- `namespace.yaml`: the `networking` namespace
- `internal-gateway.yaml`: `EnvoyProxy`, `GatewayClass`, and `Gateway`

The `EnvoyProxy` requests a Kube-VIP-managed LoadBalancer Service at `192.168.89.131`. Both the
Envoy controller and generated data-plane pods tolerate Atlantis's control-plane taints.

The initial Gateway listens on internal HTTP port 80 and accepts routes from the same namespace.
Add Vault routing only after the Vault shared-services layer defines the target Service and TLS
behavior.

## Reconciliation

The Atlantis `networking` Flux Kustomization depends on `infrastructure`, ensuring cert-manager,
Longhorn, and the remaining foundation are healthy first.

```sh
flux reconcile kustomization networking -n flux-system --with-source
```

## Verification

```sh
kubectl --context atlantis-vault get helmrelease -n envoy-gateway-system envoy-gateway
kubectl --context atlantis-vault get pods -n envoy-gateway-system
kubectl --context atlantis-vault get envoyproxy -n networking
kubectl --context atlantis-vault get gatewayclass internal
kubectl --context atlantis-vault get gateway -n networking internal
kubectl --context atlantis-vault get service -A \
  -o wide | grep 192.168.89.131
```

The Envoy Gateway Helm install runs a pre-install certificate generation Job. On Atlantis, both
`certgen.job.tolerations` and `deployment.pod.tolerations` are required because every node has the
control-plane `NoSchedule` taint.