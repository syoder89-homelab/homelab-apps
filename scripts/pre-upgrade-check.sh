#!/bin/bash

# Pre-upgrade validation for Victoria Metrics
# Run this before starting the helm upgrade

set -e

SCOTT_NS="scott-monitoring"
TAYLOR_NS="taylor-monitoring"

echo "🔍 Pre-upgrade Victoria Metrics Validation"
echo "=========================================="
echo ""

# Check cluster connectivity
echo "✓ Checking cluster connectivity..."
kubectl cluster-info > /dev/null && echo "  Cluster accessible"

# Check current versions
echo ""
echo "✓ Current Helm Releases:"
echo "  Scott:"
helm list -n "$SCOTT_NS" | grep victoria || echo "    Not found"
echo "  Taylor:"
helm list -n "$TAYLOR_NS" | grep victoria || echo "    Not found"

# Check pods
echo ""
echo "✓ Current Pods:"
echo "  Scott:"
kubectl get pods -n "$SCOTT_NS" -l app.kubernetes.io/name=victoria-metrics-single --no-headers
echo "  Taylor:"
kubectl get pods -n "$TAYLOR_NS" -l app.kubernetes.io/name=victoria-metrics-single --no-headers

# Check PVCs
echo ""
echo "✓ Current PVCs:"
echo "  Scott:"
kubectl get pvc -n "$SCOTT_NS" -o wide | grep -E 'victoria|NAME'
echo "  Taylor:"
kubectl get pvc -n "$TAYLOR_NS" -o wide | grep -E 'victoria|NAME'

# Check available disk space
echo ""
echo "✓ Disk Space on Nodes:"
kubectl top nodes 2>/dev/null | head -3 || echo "  (Metrics server not available)"

# Check Victoria Metrics API accessibility
echo ""
echo "✓ Victoria Metrics API Health:"
echo "  Polling Scott instance..."
SCOTT_PVC=$(kubectl get pvc -n "$SCOTT_NS" -l app.kubernetes.io/instance=victoria-metrics-scott -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$SCOTT_POD" ]; then
  SCOTT_POD=$(kubectl get pods -n "$SCOTT_NS" -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n "$SCOTT_NS" "$SCOTT_POD" -- wget -q -O- http://localhost:8428/api/v1/query?query=up 2>/dev/null | head -c 100 && echo "    ✓ Responsive" || echo "    ✗ Check API"
fi

echo "  Polling Taylor instance..."
TAYLOR_POD=$(kubectl get pods -n "$TAYLOR_NS" -l app.kubernetes.io/name=victoria-metrics-single -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$TAYLOR_POD" ]; then
  kubectl exec -n "$TAYLOR_NS" "$TAYLOR_POD" -- wget -q -O- http://localhost:8428/api/v1/query?query=up 2>/dev/null | head -c 100 && echo "    ✓ Responsive" || echo "    ✗ Check API"
fi

# Check Chart.lock files
echo ""
echo "✓ Checking for stale dependencies:"
if [ -f "applications/victoria-metrics-scott/Chart.lock" ]; then
  echo "  Chart.lock found (will be updated during upgrade)"
fi

# List changes that would be applied
echo ""
echo "✓ Recommended next steps:"
echo "  1. Run backup: ./scripts/backup-victoria-metrics.sh"
echo "  2. Review Helm diff: helm diff upgrade victoria-metrics-scott applications/victoria-metrics-scott -n scott-monitoring"
echo "  3. Deploy via CI/CD pipeline in test environment first"
echo "  4. Verify metrics are intact post-upgrade"
echo "  5. Monitor: kubectl logs -f [pod] -n [namespace]"
echo ""
echo "⚠️  IMPORTANT:"
echo "  - Always test in non-prod environment first"
echo "  - Keep PVC backups for 48+ hours after successful upgrade"
echo "  - Have helm rollback command ready: helm rollback victoria-metrics-scott -n scott-monitoring"
echo ""
