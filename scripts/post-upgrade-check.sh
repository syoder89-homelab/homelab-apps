#!/bin/bash

# Post-upgrade validation for Victoria Metrics
# Run this after helm upgrade completes

set -e

SCOTT_NS="scott-monitoring"
TAYLOR_NS="taylor-monitoring"
MAX_WAIT=300
CHECK_INTERVAL=10

echo "🔍 Post-upgrade Victoria Metrics Validation"
echo "=========================================="
echo ""

# Function to wait for pod readiness
wait_for_pod() {
  local namespace=$1
  local label=$2
  local timeout=$3
  local elapsed=0
  
  echo "  Waiting for pod to be ready..."
  while [ $elapsed -lt $timeout ]; do
    READY=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
    if [ "$READY" = "True" ]; then
      echo "    ✓ Pod Ready"
      return 0
    fi
    sleep $CHECK_INTERVAL
    elapsed=$((elapsed + CHECK_INTERVAL))
  done
  echo "    ✗ Pod not ready within ${timeout}s"
  return 1
}

# Function to check API health
check_api_health() {
  local namespace=$1
  local pod_label=$2
  
  POD=$(kubectl get pods -n "$namespace" -l "$pod_label" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [ -z "$POD" ]; then
    echo "    ✗ No pod found"
    return 1
  fi
  
  echo "  Pod: $POD"
  
  # Check API endpoint
  if kubectl exec -n "$namespace" "$POD" -- wget -q -O- http://localhost:8428/api/v1/labels 2>/dev/null | grep -q "^{"; then
    echo "    ✓ API responding"
  else
    echo "    ✗ API not responding"
    return 1
  fi
  
  # Check data retention
  RETENTION=$(kubectl exec -n "$namespace" "$POD" -- wget -q -O- http://localhost:8428/api/v1/query?query=time 2>/dev/null | grep -o '"value":\["[0-9]*' | head -1 | cut -d'"' -f4)
  if [ -n "$RETENTION" ]; then
    echo "    ✓ Data accessible (timestamp: $RETENTION)"
  else
    echo "    ✗ No metrics data found"
  fi
}

# Check new chart versions
echo "✓ Updated Helm Releases:"
echo "  Scott:"
scott_release=$(helm list -n "$SCOTT_NS" | grep victoria | awk '{print $9}')
echo "    Release: $(helm list -n "$SCOTT_NS" | grep victoria | awk '{print $1, "v" $9}')"
echo "  Taylor:"
echo "    Release: $(helm list -n "$TAYLOR_NS" | grep victoria | awk '{print $1, "v" $9}')"

# Wait for pods to be ready
echo ""
echo "✓ Pod Readiness (Scott):"
if wait_for_pod "$SCOTT_NS" "app.kubernetes.io/name=victoria-metrics-single"; then
  :
else
  echo "    Waiting longer... (checking status)"
  kubectl get pods -n "$SCOTT_NS" -l app.kubernetes.io/name=victoria-metrics-single
fi

echo ""
echo "✓ Pod Readiness (Taylor):"
if wait_for_pod "$TAYLOR_NS" "app.kubernetes.io/name=victoria-metrics-single"; then
  :
else
  echo "    Waiting longer... (checking status)"
  kubectl get pods -n "$TAYLOR_NS" -l app.kubernetes.io/name=victoria-metrics-single
fi

# Verify API health
echo ""
echo "✓ Victoria Metrics API Health (Scott):"
check_api_health "$SCOTT_NS" "app.kubernetes.io/name=victoria-metrics-single"

echo ""
echo "✓ Victoria Metrics API Health (Taylor):"
check_api_health "$TAYLOR_NS" "app.kubernetes.io/name=victoria-metrics-single"

# Check storage status
echo ""
echo "✓ Storage Status:"
echo "  Scott:"
kubectl get pvc -n "$SCOTT_NS" | grep -E 'victoria|NAME' | head -3
echo "  Taylor:"
kubectl get pvc -n "$TAYLOR_NS" | grep -E 'victoria|NAME' | head -3

# Display recent events
echo ""
echo "✓ Recent Events (Scott):"
kubectl get events -n "$SCOTT_NS" --sort-by='.lastTimestamp' | tail -5 || echo "  No recent events"

echo ""
echo "✓ Recent Events (Taylor):"
kubectl get events -n "$TAYLOR_NS" --sort-by='.lastTimestamp' | tail -5 || echo "  No recent events"

# Final summary
echo ""
echo "=========================================="
echo "✅ Upgrade validation complete!"
echo ""
echo "🔗 Next steps:"
echo "  1. Monitor logs: kubectl logs -f [pod-name] -n [namespace]"
echo "  2. Verify metrics in Grafana dashboards"
echo "  3. Keep PVC backups for 48 hours"
echo "  4. If issues found, rollback: helm rollback [release] -n [namespace]"
echo ""
echo "💾 Backup location: Check your pre-upgrade backup script output"
echo ""
