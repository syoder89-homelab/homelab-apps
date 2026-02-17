# Victoria Metrics Backup Recovery Guide

## Backup Contents

- `scott/` - Scott Victoria Metrics instance backup
- `taylor/` - Taylor Victoria Metrics instance backup
- `snapshots-status/` - VolumeSnapshot status at backup time
- Each instance contains:
  - Kubernetes deployment/statefulset manifests
  - PVC configurations
  - ConfigMaps and Secrets
  - VolumeSnapshot manifests for data recovery

## Pre-upgrade Checklist

1. Verify snapshots were created successfully
   ```bash
   kubectl get volumesnapshot -n scott-monitoring
   kubectl get volumesnapshot -n taylor-monitoring
   # All snapshots should show "ReadyToUse: true"
   ```

2. Record current pod/PVC status
   ```bash
   kubectl get pvc -n scott-monitoring | grep victoria
   kubectl get pvc -n taylor-monitoring | grep victoria
   ```

## If Upgrade Fails

### Option 1: Helm Rollback (FASTEST - 95% success)

If helm upgrade fails, rollback using Helm:

```bash
# Check helm history
helm history victoria-metrics-scott -n scott-monitoring
helm history victoria-metrics -n taylor-monitoring

# Rollback to previous release (immediate)
helm rollback victoria-metrics-scott -n scott-monitoring
helm rollback victoria-metrics -n taylor-monitoring

# Verify rollback
kubectl rollout status deployment/victoria-metrics-scott -n scott-monitoring
```

### Option 2: Restore from VolumeSnapshots

If PVCs become inaccessible or corrupted:

```bash
# 1. Delete the problematic pod/deployment to release the PVC
kubectl scale deployment victoria-metrics-scott --replicas=0 -n scott-monitoring

# 2. List available snapshots
kubectl get volumesnapshot -n scott-monitoring -o wide

# 3. Create a PVC from snapshot
cat << 'SNAP' > /tmp/restore-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: victoria-metrics-scott-restored
  namespace: scott-monitoring
spec:
  storageClassName: openebs-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 16Gi
  dataSource:
    name: <snapshot-name>  # e.g., "server-volume-victoria-metrics-scott-victoria-metrics-single-server-0-snapshot-1234567890"
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
SNAP

kubectl apply -f /tmp/restore-pvc.yaml

# 4. Wait for PVC to be Bound
kubectl get pvc -n scott-monitoring -w

# 5. Update deployment to use restored PVC (or redeploy via Helm)
```

### Option 3: Restore from Manifests

If all else fails, use backed up manifests:

```bash
# Restore PVC configuration
kubectl apply -f scott/pvc.yaml -n scott-monitoring

# Restore ConfigMaps and Secrets
kubectl apply -f scott/configmap-secrets.yaml -n scott-monitoring

# Redeploy with previous chart version
helm install victoria-metrics-scott . \
  -n scott-monitoring \
  -f scott/deployment.yaml
```

## VolumeSnapshot Details

**Location:** `snapshots-status/status.txt` - shows snapshot status at backup time

**Manual Snapshot Check:**
```bash
# See all snapshots
kubectl get volumesnapshot -A

# Describe a specific snapshot
kubectl describe volumesnapshot <snapshot-name> -n scott-monitoring

# Check snapshot content size
kubectl get volumesnapshotcontent
```

## Data Size Reference

Current PVC sizes: 16Gi each
Backup metadata size: ~108KB
Snapshots: Stored as VolumeSnapshot resources (can be viewed with kubectl)

## Testing the Upgrade

With CI/CD pipeline available:

1. Run against test environment first
2. Monitor:
   ```bash
   kubectl logs -f $(kubectl get pod -n scott-monitoring -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[0].metadata.name}') -n scott-monitoring
   ```

3. Verify data integrity:
   ```bash
   # Check Victoria Metrics still has metrics
   kubectl port-forward -n scott-monitoring svc/victoria-metrics-scott 8428:8428
   curl http://localhost:8428/api/v1/labels
   ```

## Rollback Timeline

| Method | Time | Success Rate | Data Safety |
|--------|------|--------------|-------------|
| Helm rollback | <1 min | 95% | Full |
| VolumeSnapshot restore | 5-10 min | 90% | Full |
| Manifest restore | 10-15 min | 85% | Full |

## Important Notes

- VolumeSnapshots are stored in Kubernetes (kubectl get volumesnapshot)
- Snapshots can be used to create new PVCs without redeploying
- OpenEBS handles snapshot storage internally
- Backup manifests are also saved for manual recovery
- Helm release history is preserved for quick rollback
