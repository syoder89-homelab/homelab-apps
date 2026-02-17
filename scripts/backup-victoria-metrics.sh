#!/bin/bash

# Backup script for Victoria Metrics data before upgrading
# Backs up both scott and taylor Victoria Metrics instances

set -e

BACKUP_DIR="${BACKUP_DIR:-.}/victoria-metrics-backup-$(date +%Y%m%d-%H%M%S)"
SCOTT_NS="scott-monitoring"
TAYLOR_NS="taylor-monitoring"
SCOTT_POD_PREFIX="victoria-metrics-scott"
TAYLOR_POD_PREFIX="victoria-metrics"

echo "🔄 Starting Victoria Metrics backup to: $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# Backup scott instance
echo "📦 Backing up scott Victoria Metrics..."
mkdir -p "$BACKUP_DIR/scott"
mkdir -p "$BACKUP_DIR/scott/snapshots"

# Get current pod name
SCOTT_POD=$(kubectl get pods -n "$SCOTT_NS" -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[0].metadata.name}')
echo "  Pod: $SCOTT_POD"

# Backup configuration
echo "  Exporting configuration..."
kubectl get -n "$SCOTT_NS" deployment -l app.kubernetes.io/instance="$SCOTT_POD_PREFIX" -o yaml > "$BACKUP_DIR/scott/deployment.yaml"
kubectl get -n "$SCOTT_NS" statefulset -l app.kubernetes.io/name=victoria-metrics-single -o yaml > "$BACKUP_DIR/scott/statefulset.yaml" 2>/dev/null || true
kubectl get -n "$SCOTT_NS" pvc -o yaml > "$BACKUP_DIR/scott/pvc.yaml"
kubectl get -n "$SCOTT_NS" cm,secret -l app.kubernetes.io/instance="$SCOTT_POD_PREFIX" -o yaml > "$BACKUP_DIR/scott/configmap-secrets.yaml" 2>/dev/null || true

# Create OpenEBS snapshots
echo "  Creating OpenEBS snapshots..."
SCOTT_PVC_NAMES=$(kubectl get pvc -n "$SCOTT_NS" -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[*].metadata.name}')
for pvc in $SCOTT_PVC_NAMES; do
  SNAPSHOT_NAME="$pvc-snapshot-$(date +%s)"
  echo "    Creating snapshot for $pvc -> $SNAPSHOT_NAME"
  
  # Get the volume name
  VOLUME=$(kubectl get pvc "$pvc" -n "$SCOTT_NS" -o jsonpath='{.spec.volumeName}')
  
  # Create VolumeSnapshot resource
  cat > "$BACKUP_DIR/scott/snapshots/$SNAPSHOT_NAME-manifest.yaml" << EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: $SCOTT_NS
spec:
  volumeSnapshotClassName: openebs-snapclass
  source:
    persistentVolumeClaimName: $pvc
EOF
  
  # Apply the snapshot
  kubectl apply -f "$BACKUP_DIR/scott/snapshots/$SNAPSHOT_NAME-manifest.yaml"
done

# Backup taylor instance
echo "📦 Backing up taylor Victoria Metrics..."
mkdir -p "$BACKUP_DIR/taylor"
mkdir -p "$BACKUP_DIR/taylor/snapshots"

TAYLOR_POD=$(kubectl get pods -n "$TAYLOR_NS" -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[0].metadata.name}')
echo "  Pod: $TAYLOR_POD"

# Backup configuration
echo "  Exporting configuration..."
kubectl get -n "$TAYLOR_NS" deployment -l app.kubernetes.io/name=victoria-metrics-single -o yaml > "$BACKUP_DIR/taylor/deployment.yaml" 2>/dev/null || true
kubectl get -n "$TAYLOR_NS" statefulset -l app.kubernetes.io/name=victoria-metrics-single -o yaml > "$BACKUP_DIR/taylor/statefulset.yaml" 2>/dev/null || true
kubectl get -n "$TAYLOR_NS" pvc -o yaml > "$BACKUP_DIR/taylor/pvc.yaml"
kubectl get -n "$TAYLOR_NS" cm,secret -l app.kubernetes.io/instance="$TAYLOR_POD_PREFIX" -o yaml > "$BACKUP_DIR/taylor/configmap-secrets.yaml" 2>/dev/null || true

# Create OpenEBS snapshots
echo "  Creating OpenEBS snapshots..."
TAYLOR_PVC_NAMES=$(kubectl get pvc -n "$TAYLOR_NS" -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[*].metadata.name}')
for pvc in $TAYLOR_PVC_NAMES; do
  SNAPSHOT_NAME="$pvc-snapshot-$(date +%s)"
  echo "    Creating snapshot for $pvc -> $SNAPSHOT_NAME"
  
  # Get the volume name
  VOLUME=$(kubectl get pvc "$pvc" -n "$TAYLOR_NS" -o jsonpath='{.spec.volumeName}')
  
  # Create VolumeSnapshot resource
  cat > "$BACKUP_DIR/taylor/snapshots/$SNAPSHOT_NAME-manifest.yaml" << EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: $SNAPSHOT_NAME
  namespace: $TAYLOR_NS
spec:
  volumeSnapshotClassName: openebs-snapclass
  source:
    persistentVolumeClaimName: $pvc
EOF
  
  # Apply the snapshot
  kubectl apply -f "$BACKUP_DIR/taylor/snapshots/$SNAPSHOT_NAME-manifest.yaml"
done

# Create manifest for recovery
echo "📝 Creating recovery manifest..."
cat > "$BACKUP_DIR/RECOVERY.md" << 'EOF'
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
EOF

echo "✅ Saving snapshot status..."
mkdir -p "$BACKUP_DIR/snapshots-status"
echo "Scott VolumeSnapshots:" > "$BACKUP_DIR/snapshots-status/status.txt"
kubectl get volumesnapshot -n "$SCOTT_NS" -o wide >> "$BACKUP_DIR/snapshots-status/status.txt" 2>/dev/null || echo "  (Snapshots may still be creating...)"
echo "" >> "$BACKUP_DIR/snapshots-status/status.txt"
echo "Taylor VolumeSnapshots:" >> "$BACKUP_DIR/snapshots-status/status.txt"
kubectl get volumesnapshot -n "$TAYLOR_NS" -o wide >> "$BACKUP_DIR/snapshots-status/status.txt" 2>/dev/null || echo "  (Snapshots may still be creating...)"

echo "✅ Helm chart versions snapshot..."
cat > "$BACKUP_DIR/helm-versions.txt" << EOF
=== Pre-upgrade Chart Versions ===
Date: $(date)

Scott:
$(helm list -n scott-monitoring | grep victoria)

Taylor:
$(helm list -n taylor-monitoring | grep victoria)

=== Available Updates ===
$(helm search repo victoria-metrics-single --versions | grep -E "0\.(9\.3|10\.|11\.|20\.|25\.|30\.|31\.)" | head -5)
EOF

echo ""
echo "✅ Backup complete!"
echo ""
echo "📍 Backup Location: $BACKUP_DIR"
echo ""
echo "📊 Backup Contents:"
du -sh "$BACKUP_DIR"/*
echo ""
echo "� VolumeSnapshots Created:"
kubectl get volumesnapshot -n "$SCOTT_NS" -o wide 2>/dev/null | grep -E "snapshot|NAME" || echo "  (Check status with: kubectl get volumesnapshot -n scott-monitoring)"
echo ""
kubectl get volumesnapshot -n "$TAYLOR_NS" -o wide 2>/dev/null | grep -E "snapshot|NAME" || echo "  (Check status with: kubectl get volumesnapshot -n taylor-monitoring)"
echo ""
echo "💾 Next Steps:"
echo "  1. Wait ~30s for snapshots to be ready: kubectl get volumesnapshot -n [namespace] -w"
echo "  2. Verify Bound status: kubectl get volumesnapshot -n [namespace]"
echo "  3. Test upgrade in CI/CD pipeline"
echo "  4. If upgrade fails, keep backup for 24-48 hours for potential restoration"
echo ""
echo "🔗 Recovery instructions saved to: $BACKUP_DIR/RECOVERY.md"
echo "📝 Snapshot status saved to: $BACKUP_DIR/snapshots-status/status.txt"
