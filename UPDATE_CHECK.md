# Homelab Applications - Update Check Report
Generated: February 17, 2026

## Summary
Found several Helm chart and container image updates available across your applications. Below is a detailed breakdown by application.

---

## 🔴 Critical Updates Available

### 1. **Victoria Metrics** (scott & taylor)
- **Current Chart Version**: 0.9.3
- **Latest Chart Version**: 0.31.0
- **Image App Version**: v1.134.0+ available
- **Status**: ⚠️ **MAJOR update available** (26 versions behind)
- **Repo**: https://victoriametrics.github.io/helm-charts/

### 2. **Frigate** (prod config)
- **Chart**: 7.0.3 (custom local chart)
- **Subchart Version**: 7.0.3
- **Current Image Tag**: 0.16.3 (in prod/values.yaml)
- **Latest Image Tag**: 0.17.0-rc2 (latest), 0.16.4 (stable)
- **Status**: ⚠️ **Patch update available** (0.16.4)
- **Note**: Image in chart defaults is 0.12.0 (very outdated)

---

## 🟡 Moderate Updates Available

### 3. **InfluxDB** (scott)
- **Current Chart Version**: 4.12.0
- **Latest Chart Version**: 4.12.5
- **Status**: ✓ **Minor patch available** (+0.0.5)
- **Repo**: https://helm.influxdata.com/

### 4. **Grafana** (scott & taylor)
- **Scott Chart Version**: 10.4.1
- **Taylor Chart Version**: 10.4.0
- **Latest Chart Version**: 10.5.15
- **Status**: ✓ **Minor update available** (+1.1 versions)
- **Repo**: https://grafana.github.io/helm-charts/

### 5. **Mosquitto** (scott & taylor)
- **Current Chart Version**: 4.8.2
- **Latest Chart Version**: 4.8.2
- **Status**: ✓ **Up to date**
- **Repo**: https://k8s-at-home.com/charts/

---

## 🟢 Unable to Check

### 6. **Home Assistant**
- **Current Chart Version**: 0.3.43
- **Repository**: http://pajikos.github.io/home-assistant-helm-chart
- **Status**: ⚠️ **Repository not found in helm repos**
- **Action Required**: Add the pajikos helm repo or check if it's available elsewhere

### 7. **Kargo Config**
- **Status**: ✓ Configuration-only chart (no updates needed)

---

## Recommendation Priority

| Priority | Application | Action |
|----------|------------|--------|
| 🔴 HIGH | Victoria Metrics | Update to 0.31.0 (major version jump) |
| 🟡 MEDIUM | Frigate | Update image to 0.16.4 (or 0.17.0 when stable) |
| 🟡 MEDIUM | Grafana | Update to latest 10.5.x |
| 🟢 LOW | InfluxDB | Update to 4.12.5 |
| ✓ UP-TO-DATE | Mosquitto | No action needed |

---

## Update Commands

To update, you can use:

```bash
# Update helm repos
helm repo update

# Search for specific versions
helm search repo victoria-metrics-single --versions
helm search repo grafana/grafana --versions
helm search repo influxdata/influxdb --versions

# Pull and review values before updating
helm pull <repo>/<chart> --version <new-version> --untar
```

---

## Notes
- Victoria Metrics has the most significant updates available
- Some applications have their own subchart overlays - ensure prod values.yaml overrides are applied
- Test updates in a test environment first, especially for critical infrastructure like Grafana and InfluxDB
