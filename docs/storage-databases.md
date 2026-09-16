# Phase 4: Longhorn and CloudNative-PG

This document explains how workloads consume storage and PostgreSQL after the
Longhorn and CloudNative-PG operators are installed and become `Ready` through
Flux. It does not install either operator yet; operator installation should be added
under `apps/base/storage/` and `apps/base/databases/` with environment overlays.

## Longhorn volumes

### Request persistent storage from a workload

A workload should request storage with a `PersistentVolumeClaim` using the Longhorn
StorageClass. The PVC belongs in the same namespace as the consuming Deployment or
StatefulSet:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
  namespace: app
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: 10Gi
```

Then mount the claim in a Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: app
    spec:
      containers:
        - name: app
          image: example/app:1.0.0
          volumeMounts:
            - name: app-data
              mountPath: /var/lib/app
      volumes:
        - name: app-data
          persistentVolumeClaim:
            claimName: app-data
```

The PVC and Deployment should normally be committed together in the application
base or environment overlay. Do not create a Longhorn volume manually in the UI for a
normal application; let Kubernetes create it from the PVC.

### Verify a volume

```sh
kubectl -n app get pvc app-data
kubectl -n app describe pvc app-data
kubectl -n app get pv
kubectl -n longhorn-system get volumes
```

Expected PVC state is `Bound`. If it remains `Pending`, inspect the PVC events and
Longhorn manager/CSI pods:

```sh
kubectl -n app describe pvc app-data
kubectl -n longhorn-system get pods
kubectl -n longhorn-system get events --sort-by=.lastTimestamp
```

### StatefulSet pattern

For a StatefulSet, use `volumeClaimTemplates` so each replica receives its own
volume. Do not share a `ReadWriteOnce` claim between replicas:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: longhorn
      resources:
        requests:
          storage: 20Gi
```

### Operational rules

- Use `ReadWriteOnce` unless the workload specifically requires another access mode.
- Keep application data in PVCs, not `emptyDir`.
- Back up important volumes; Longhorn replication is not a backup.
- Do not reduce a PVC size. Plan expansion and confirm the filesystem supports it.
- Drain and node replacement operations must be checked against Longhorn replica
  health before removing a worker node.
- Use separate StorageClasses or Longhorn recurring jobs later for backup policies,
  retention, and snapshot schedules.

## CloudNative-PG clusters

### Create a PostgreSQL cluster

After the CNPG operator is installed, create a `Cluster` resource in the application
namespace. This example creates a small non-prod PostgreSQL cluster with one
instance and persistent storage:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: app-postgres
  namespace: app
spec:
  instances: 1
  primaryUpdateStrategy: unsupervised
  storage:
    storageClass: longhorn
    size: 10Gi
  bootstrap:
    initdb:
      database: app
      owner: app
      secret:
        name: app-postgres-credentials
  monitoring:
    enablePodMonitor: true
```

Create the credentials Secret separately and keep its values in the configured secret
management system rather than committing plaintext credentials:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-postgres-credentials
  namespace: app
type: kubernetes.io/basic-auth
stringData:
  username: app
  password: replace-me
```

For production, use multiple instances and a deliberate update strategy:

```yaml
spec:
  instances: 3
  primaryUpdateStrategy: automated
  storage:
    storageClass: longhorn
    size: 50Gi
```

CNPG creates the primary/replica Services and a Secret containing the generated
connection credentials. Inspect the resulting objects:

```sh
kubectl -n app get cluster app-postgres
kubectl -n app get pods -l cnpg.io/cluster=app-postgres
kubectl -n app get svc -l cnpg.io/cluster=app-postgres
kubectl -n app get secret app-postgres-credentials
```

### Connect from an application

Use the CNPG read-write Service for normal application traffic. Keep the Service name
and database name in an application Secret or ConfigMap rather than hardcoding them in
an image:

```text
host: app-postgres-rw.app.svc.cluster.local
port: 5432
database: app
```

### Operational rules

- Keep each tenant/application database in its own namespace or naming boundary.
- Use one CNPG `Cluster` per logical database service, not one cluster for unrelated
  applications by default.
- Enable `PodMonitor` only after the monitoring stack is installed and labels/selectors
  are agreed.
- Use scheduled backups and WAL archiving before calling a production database
  protected.
- Test restore procedures; replicas provide availability, not a complete backup.
- Do not delete a `Cluster` resource casually: deletion can remove database pods and
  their PVCs depending on the configured policy.
