# Victoria Metrics Upgrade - Quick Reference (0.9.3 → 0.31.0)

## Pre-Upgrade Checklist ✓

```bash
# 1. Backup data (DONE)
export BACKUP_DIR="./victoria-metrics-backup-20260217-170105"

# 2. Validate system health
./scripts/pre-upgrade-check.sh

# 3. Verify backup contents
ls -lah "$BACKUP_DIR"
```

**Status:** All checks passed ✓

---

## Backup Location

📦 **Backup:** `./victoria-metrics-backup-20260217-170105/`

**Contains:**
- ✓ Scott deployment/PVC configs
- ✓ Taylor deployment/PVC configs  
- ✓ OpenEBS snapshot metadata
- ✓ Recovery instructions
- ✓ Helm version snapshot

**Size:** 108KB (metadata only)

---

## Upgrade Procedure

### Phase 1: Test Environment (Via CI/CD)

```bash
# Trigger test environment deployment
# Through your CI/CD pipeline → test-monitoring namespace

# Monitor:
kubectl logs -f $(kubectl get pod -n test-monitoring \
  -l app.kubernetes.io/name=victoria-metrics-single \
  -o jsonpath='{.items[0].metadata.name}') -n test-monitoring

# Verify metrics:
kubectl port-forward -n test-monitoring svc/victoria-metrics 8428:8428 &
curl http://localhost:8428/api/v1/query?query=up
```

### Phase 2: Production Upgrade (After Test Success)

#### Option A: Direct Helm Upgrade

```bash
# Scott
cd applications/victoria-metrics-scott
helm dependency update
helm upgrade victoria-metrics-scott . \
  -n scott-monitoring \
  --wait --timeout=10m

# Taylor
cd ../victoria-metrics-taylor
helm dependency update
helm upgrade victoria-metrics . \
  -n taylor-monitoring \
  --wait --timeout=10m
```

#### Option B: Via CI/CD Pipeline

```bash
# 1. Commit Chart.yaml with new version
# 2. Push to main branch
# 3. Pipeline will test then promote to production
# 4. Monitor: kubectl get stages -n homelab-apps

# Watch promotion
kubectl get stages -n homelab-apps -w
```

### Phase 3: Verify Upgrade

```bash
./scripts/post-upgrade-check.sh
```

---

## Emergency Rollback

### Quick Rollback (99% success rate)

```bash
# Rollback both instances
helm rollback victoria-metrics-scott -n scott-monitoring
helm rollback victoria-metrics -n taylor-monitoring

# Verify
./scripts/post-upgrade-check.sh
```

### Check Current Releases

```bash
helm list -n scott-monitoring
helm list -n taylor-monitoring

# See available releases
helm history victoria-metrics-scott -n scott-monitoring
helm history victoria-metrics -n taylor-monitoring
```

---

## Monitoring During Upgrade

### Real-time Pod Status

```bash
# Scott
kubectl get pods -n scott-monitoring -l app.kubernetes.io/name=victoria-metrics-single -w

# Taylor
kubectl get pods -n taylor-monitoring -l app.kubernetes.io/name=victoria-metrics-single -w
```

### Pod Logs

```bash
# Scott
kubectl logs -f <pod-name> -n scott-monitoring

# Taylor
kubectl logs -f <pod-name> -n taylor-monitoring
```

### API Check (After pod is ready)

```bash
# Port-forward
kubectl port-forward -n scott-monitoring svc/victoria-metrics 8428:8428 &

# Test endpoints
curl http://localhost:8428/api/v1/labels       # Should return {"status":"success",...}
curl http://localhost:8428/api/v1/query?query=up  # Check metrics are flowing
```

---

## Rollback Scenarios

### Scenario 1: Pod CrashLoopBackOff

```bash
# Check logs for errors
kubectl logs <pod-name> -n scott-monitoring

# Rollback immediately
helm rollback victoria-metrics-scott -n scott-monitoring
```

### Scenario 2: API Not Responding

```bash
# Check pod status
kubectl describe pod <pod-name> -n scott-monitoring

# Verify storage mounting
kubectl exec <pod-name> -n scott-monitoring -- ls -la /storage

# Rollback if storage issues
helm rollback victoria-metrics-scott -n scott-monitoring
```

### Scenario 3: Data Inaccessible

```bash
# Check PVC status
kubectl get pvc -n scott-monitoring

# Check events
kubectl get events -n scott-monitoring -w

# Scale down, test PVC separately
kubectl scale deployment victoria-metrics-scott --replicas=0 -n scott-monitoring

# Recover from backup
kubectl apply -f "$BACKUP_DIR/scott/pvc.yaml" -n scott-monitoring

# Full rollback
helm rollback victoria-metrics-scott -n scott-monitoring
```

---

## Chart Versions

**Before Upgrade:**
- Victoria Metrics Single: **0.9.3**

**Target Upgrade:**
- Victoria Metrics Single: **0.31.0**

**Available Versions:**
```
0.31.0 → v1.136.0 (Latest)
0.30.0 → v1.135.0
0.29.0 → v1.134.0
```

---

## Key Information

| Item | Scott | Taylor |
|------|-------|--------|
| Namespace | `scott-monitoring` | `taylor-monitoring` |
| Storage Class | `openebs-storage` | `openebs-storage` |
| PVC Size | 16Gi | 16Gi |
| Pod Running Since | 38d | 131d |
| Data Size | ~14Gi | ~15Gi |
| Backup Size | 48KB | 48KB |

---

## Timeline

- **Pre-upgrade checks:** 5 min
- **Helm upgrade:** 5-10 min per instance
- **Pod startup:** 2-5 min
- **API warmup:** 1-2 min
- **Verification:** 2-5 min
- **Total per instance:** ~20 min

---

## Support Commands

```bash
# Show current state
kubectl get pods -A | grep victoria
kubectl get pvc -A | grep victoria

# Check deployment status
kubectl rollout status deployment/victoria-metrics-scott -n scott-monitoring

# View events
kubectl get events -n scott-monitoring --sort-by='.lastTimestamp' | tail -10

# Pod info
kubectl describe pod <pod-name> -n scott-monitoring

# Storage info
kubectl describe pvc -n scott-monitoring | grep -A 10 "victoria"
```

---

## Emergency Contacts

- Backup Location: `./victoria-metrics-backup-20260217-170105/`
- Recovery Guide: `./victoria-metrics-backup-20260217-170105/RECOVERY.md`
- Full Upgrade Guide: `./VICTORIA_METRICS_UPGRADE.md`
- Helm Release History: `helm history [release] -n [namespace]`

---

**Backup Created:** February 17, 2026 @ 17:01:05 UTC  
**Ready for Upgrade:** ✓ YES
