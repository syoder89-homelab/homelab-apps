# Victoria Metrics Upgrade Guide (0.9.3 → 0.31.0)

## Overview

This guide walks through upgrading Victoria Metrics from chart version 0.9.3 to 0.31.0 (22 version jump) with:
- Full data backups
- Pre-flight validation
- CI/CD pipeline testing
- Post-upgrade verification
- Rollback procedures

## Data Backup Strategy

Your Victoria Metrics deployments use **OpenEBS persistent volumes** with 16Gi each:
- **Scott Instance**: `scott-monitoring` namespace
- **Taylor Instance**: `taylor-monitoring` namespace

### Step 1: Run Backup

```bash
# Create timestamped backup
./scripts/backup-victoria-metrics.sh

# Save the backup location!
export BACKUP_DIR=$(ls -trd ./victoria-metrics-backup-* | tail -1)
echo "Backup saved to: $BACKUP_DIR"
```

**What gets backed up:**
- Kubernetes manifests (deployments, PVCs, ConfigMaps, Secrets)
- OpenEBS volume metadata
- Helm release history
- Current chart versions

**Backup size:** ~100MB (metadata only, not actual time-series data)

### Step 2: Pre-upgrade Validation

```bash
./scripts/pre-upgrade-check.sh
```

This validates:
- ✓ Cluster connectivity
- ✓ Current pod and PVC status
- ✓ API health
- ✓ Available disk space
- ✓ Current chart versions

## Upgrade Process

### Phase 1: Test Environment (CI/CD Pipeline)

1. **Trigger upgrade in test environment:**
   ```bash
   cd applications/victoria-metrics-scott
   helm dependency update
   helm upgrade test-victoria-metrics-scott . \
     -n test-monitoring \
     --create-namespace \
     -f config/envs/test/deployment.yaml
   ```

2. **Monitor upgrade:**
   ```bash
   kubectl rollout status deployment/victoria-metrics-scott -n test-monitoring --timeout=5m
   kubectl logs -f $(kubectl get pod -n test-monitoring -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[0].metadata.name}') -n test-monitoring
   ```

3. **Verify data and functionality:**
   ```bash
   # Check metrics are present
   kubectl port-forward -n test-monitoring svc/victoria-metrics-scott 8428:8428 &
   curl http://localhost:8428/api/v1/query?query=up
   
   # Check in Grafana dashboards
   ```

### Phase 2: Production Upgrade (After Test Success)

**Only proceed if test environment upgrade was successful!**

#### Option A: Rolling Upgrade

```bash
# Scott instance
cd applications/victoria-metrics-scott
helm dependency update
helm upgrade victoria-metrics-scott . \
  -n scott-monitoring \
  -f config/envs/prod/deployment.yaml \
  --wait \
  --timeout=10m

# Taylor instance  
cd ../victoria-metrics-taylor
helm dependency update
helm upgrade victoria-metrics . \
  -n taylor-monitoring \
  -f config/envs/prod/deployment.yaml \
  --wait \
  --timeout=10m
```

#### Option B: Via CI/CD Pipeline

1. Commit changes to Chart.yaml with new version
2. Push to feature branch
3. Create PR - CI/CD will test in ephemeral environment
4. Merge to main - CI/CD will promote to prod
5. Monitor: `kubectl get stages -n homelab-apps`

### Step 3: Post-upgrade Verification

```bash
./scripts/post-upgrade-check.sh
```

This validates:
- ✓ Pods are ready
- ✓ API is responsive
- ✓ Data is accessible
- ✓ Recent events are clean

## Troubleshooting

### Pod Stuck in CrashLoopBackOff

**Cause:** Configuration incompatibility or storage mount issues

**Recovery:**
```bash
# Check logs
kubectl logs -f <pod-name> -n <namespace>

# Rollback to previous version
helm rollback victoria-metrics-scott -n scott-monitoring
kubectl rollout status deployment/victoria-metrics-scott -n scott-monitoring
```

### API Not Responding

**Cause:** Application initialization taking longer than expected

**Verify:**
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
# Inside pod: ls -la /storage
```

### Data Loss or Inaccessible

**Cause:** PVC mount path changes in new version

**Recovery:**
```bash
# 1. Stop the deployment
kubectl scale deployment victoria-metrics-scott --replicas=0 -n scott-monitoring

# 2. Verify PVC still exists
kubectl get pvc -n scott-monitoring

# 3. Check OpenEBS volumeSnapshots
kubectl get volumesnapshot -n scott-monitoring

# 4. Rollback and investigate
helm rollback victoria-metrics-scott -n scott-monitoring
```

## Rollback Procedures

### Quick Rollback (Within 5 minutes)

```bash
helm rollback victoria-metrics-scott -n scott-monitoring
helm rollback victoria-metrics -n taylor-monitoring
kubectl rollout status deployment/victoria-metrics-scott -n scott-monitoring
```

### Full Rollback (After time has passed)

If quick rollback doesn't work:

```bash
# 1. Check available releases
helm history victoria-metrics-scott -n scott-monitoring

# 2. Rollback to specific release
helm rollback victoria-metrics-scott <revision> -n scott-monitoring

# 3. Verify rollback
./scripts/post-upgrade-check.sh
```

### Manual Recovery from Backup

If Helm rollback fails:

```bash
# 1. Delete current release
helm uninstall victoria-metrics-scott -n scott-monitoring

# 2. Restore backed up values
cat $BACKUP_DIR/scott/deployment.yaml | kubectl apply -f -
cat $BACKUP_DIR/scott/pvc.yaml | kubectl apply -f -

# 3. Reinstall previous chart version
helm install victoria-metrics-scott . \
  -n scott-monitoring \
  -f $BACKUP_DIR/scott/values.yaml
```

## Important Notes

⚠️ **CRITICAL:**

1. **Always test in test environment first** - Your CI/CD pipeline supports this
2. **Keep backups for 48+ hours** - In case issues are discovered later
3. **Have rollback command ready** - `helm rollback [release]` can save your day
4. **Monitor for 1 hour post-upgrade** - Watch for delayed failures
5. **Check Grafana dashboards** - Verify metrics are flowing properly

📊 **Current Data:**
- Scott VM: 16Gi PVC
- Taylor VM: 16Gi PVC  
- Both deployed 51+ days - significant metric history to preserve!

🔄 **Upgrade Timeline (per instance):**
- Pre-upgrade checks: 5 minutes
- Helm upgrade + pod startup: 5-10 minutes
- Data verification: 2-5 minutes
- **Total: ~20 minutes per instance**

## Post-Upgrade Checklist

- [ ] Test environment upgraded successfully
- [ ] Backup created and verified at: `$BACKUP_DIR`
- [ ] Pre-upgrade checks passed with no warnings
- [ ] Production upgrade completed
- [ ] Pods are Ready (1/1)
- [ ] API responding to queries
- [ ] No CrashLoopBackOff events
- [ ] Recent events are clean
- [ ] Grafana dashboards showing metrics
- [ ] Data retention is correct
- [ ] Backup kept for 48 hours minimum

## References

- [Victoria Metrics Chart Releases](https://github.com/VictoriaMetrics/helm-charts/releases)
- [Victoria Metrics Upgrade Docs](https://docs.victoriametrics.com/helm/)
- [Helm Rollback Documentation](https://helm.sh/docs/helm/helm_rollback/)
- [OpenEBS Snapshots](https://docs.openebs.io/docs/next/snapshots.html)

## Support

If issues occur:

1. Check logs: `kubectl logs -f [pod] -n [namespace]`
2. Review events: `kubectl describe pod [pod] -n [namespace]`
3. Consult backup recovery guide: `$BACKUP_DIR/RECOVERY.md`
4. Execute rollback: `helm rollback [release] -n [namespace]`

---

**Created:** February 17, 2026  
**Upgrade: Victoria Metrics 0.9.3 → 0.31.0**  
**Target Environments:** Scott (scott-monitoring), Taylor (taylor-monitoring)
