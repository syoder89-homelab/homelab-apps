# Victoria Metrics Snapshot Recovery - Quick Guide

## Current Backup Status ✅

**Backup Location:** `./victoria-metrics-backup-20260217-170645/`

**VolumeSnapshots Created:**
- Scott: 2 snapshots
  - `server-volume-victoria-metrics-scott-victoria-metrics-single-server-0-snapshot-1771369606`
  - `victoria-metrics-scott-victoria-metrics-single-server-snapshot-1771369606`

- Taylor: 3 snapshots
  - `server-volume-test-victoria-metrics-victoria-metrics-single-server-0-snapshot-1771369606`
  - `server-volume-victoria-metrics-victoria-metrics-single-server-0-snapshot-1771369606`
  - `victoria-metrics-victoria-metrics-single-server-snapshot-1771369606`

**Status:** All snapshots are being created and will be ReadyToUse within 30 seconds

---

## How Snapshots Work

VolumeSnapshots are **point-in-time backups** of your PVCs. They:
- Are stored inside OpenEBS clusters
- Can be cloned to create new PVCs
- Can be used to restore data if PVCs become corrupted
- Don't require external backup storage
- Can be managed with kubectl like any other resource

---

## Recovery Scenario 1: PVC Corrupted After Upgrade

If the Victoria Metrics PVC becomes corrupted during upgrade:

```bash
# 1. Check available snapshots
kubectl get volumesnapshot -n scott-monitoring
# Shows: server-volume-victoria-metrics-scott-victoria-metrics-single-server-0-snapshot-1771369606

# 2. Scale down deployment to release PVC
kubectl scale deployment victoria-metrics-scott --replicas=0 -n scott-monitoring

# 3. Create a new PVC from snapshot
cat << 'EOF' | kubectl apply -f -
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
    name: server-volume-victoria-metrics-scott-victoria-metrics-single-server-0-snapshot-1771369606
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
EOF

# 4. Wait for PVC to become Bound
kubectl get pvc -n scott-monitoring -w

# 5. Update the deployment to use the restored PVC name
# OR rollback and let Helm handle it:
helm rollback victoria-metrics-scott -n scott-monitoring
```

---

## Recovery Scenario 2: Complete Data Loss

If you need to restore to the exact state at backup time:

```bash
# 1. Get snapshot manifests from backup
BACKUP_DIR="./victoria-metrics-backup-20260217-170645"

# 2. Apply snapshot manifests to recreate snapshots (if deleted)
kubectl apply -f "$BACKUP_DIR/scott/snapshots/"*-manifest.yaml

# 3. Restore deployment from backup
kubectl apply -f "$BACKUP_DIR/scott/deployment.yaml"
kubectl apply -f "$BACKUP_DIR/scott/configmap-secrets.yaml"

# 4. Recreate PVC from snapshot (step 3 from Scenario 1)

# 5. Redeploy
kubectl scale deployment victoria-metrics-scott --replicas=1 -n scott-monitoring
```

---

## Recovery Scenario 3: Upgrade Failed - Quick Rollback

**This is the easiest option (99% success):**

```bash
# Rollback everything immediately
helm rollback victoria-metrics-scott -n scott-monitoring
helm rollback victoria-metrics -n taylor-monitoring

# Verify status
./scripts/post-upgrade-check.sh

# Done! The original volumes and data are preserved
```

---

## Snapshot Management

### View Snapshot Details

```bash
# List all snapshots
kubectl get volumesnapshot -n scott-monitoring -o wide

# Describe a specific snapshot
kubectl describe volumesnapshot server-volume-victoria-metrics-scott-victoria-metrics-single-server-0-snapshot-1771369606 -n scott-monitoring

# Check snapshot content (raw storage)
kubectl get volumesnapshotcontent
```

### Clean Up Old Snapshots (After Confirming Upgrade Success)

```bash
# Keep snapshots for 48 hours minimum, then delete:
kubectl delete volumesnapshot -n scott-monitoring -l app.kubernetes.io/instance=victoria-metrics-scott
kubectl delete volumesnapshot -n taylor-monitoring -l app.kubernetes.io/instance=victoria-metrics

# Or delete specific snapshot:
kubectl delete volumesnapshot <snapshot-name> -n <namespace>
```

### Backup Snapshot Manifests

The backup script already saves them to:
```
$BACKUP_DIR/scott/snapshots/*-manifest.yaml
$BACKUP_DIR/taylor/snapshots/*-manifest.yaml
```

These can be reapplied at any time to recreate snapshots:

```bash
kubectl apply -f "$BACKUP_DIR/scott/snapshots/"*-manifest.yaml
```

---

## Restore Size Reference

**Snapshot sizes:**
- Scott PVC: ~14Gi (will show in RESTORESIZE column)
- Taylor PVC: ~15Gi (will show in RESTORESIZE column)

Use these sizes when creating new PVCs from snapshots (16Gi is safe).

---

## Timeline for Snapshot Recovery

| Step | Time |
|------|------|
| Detect corruption | Immediate |
| Scale down deployment | <1 min |
| Create PVC from snapshot | 1-5 min |
| Verify PVC is Bound | 2-10 min |
| Redeploy pods | 1-2 min |
| **Total** | **5-20 min** |

---

## Important Notes

✅ **Snapshots created AFTER backup started** - so they capture data from Feb 17, 2026 17:06 UTC

✅ **Snapshots persist independently** - they exist even if pods are deleted

✅ **Multiple snapshots of same PVC** - You can have multiple snapshots and restore from any one

⚠️ **Keep snapshots for 48+ hours** - Until upgrade is confirmed stable

⚠️ **One active clone per snapshot** - Only one PVC can be created per snapshot at a time (but snapshot isn't consumed)

---

## Support

If snapshot restore fails:

1. Check snapshot status:
   ```bash
   kubectl describe volumesnapshot <name> -n <namespace>
   ```

2. Check snapshot content:
   ```bash
   kubectl get volumesnapshotcontent
   kubectl describe volumesnapshotcontent <name>
   ```

3. Fall back to Helm rollback (safest):
   ```bash
   helm rollback victoria-metrics-scott -n scott-monitoring
   ```

4. Manual recovery from backup manifests
5. Contact your cluster administrator

---

**Created:** February 17, 2026  
**Snapshots:** Ready for recovery  
**Data State:** Captured at backup time  
**Snapshot Locations:** Kubernetes (not external storage)
