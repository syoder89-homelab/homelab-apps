# AI Agent Guide

This file provides context for AI coding agents working in this repository.

## Repository Overview

This is a **Kubernetes infrastructure-as-code** repository for a home lab. It deploys and manages containerized applications using **Helm charts**, **ArgoCD** (GitOps), and **Kargo** (progressive delivery). The repository does NOT contain application source code — it contains only deployment configuration, Helm charts, and infrastructure definitions.

## Technology Stack

- **Kubernetes** (v1.24+): Container orchestration
- **Helm** (v3.10+): Chart-based Kubernetes package management
- **ArgoCD**: GitOps continuous deployment (syncs Git → cluster)
- **Kargo**: Progressive delivery (staged promotions between environments)
- **YAML**: All configuration is YAML-based

## Key Architecture Concepts

### Umbrella Charts

Each application in `applications/` is an **umbrella Helm chart** — a thin wrapper around an upstream community chart (declared as a dependency in `Chart.yaml`). The umbrella chart adds:
- Environment-specific configuration (`config/`)
- Kubernetes secrets and custom resources (`templates/`)
- Override values (`values.yaml`)

### Two Generator Charts

The `charts/` directory contains two critical generator charts:

1. **`application-generator`**: Auto-discovers applications from `applications/*/Chart.yaml` and generates ArgoCD Applications, ApplicationSets, Kargo Stages, and Warehouses for each app × environment combination.

2. **`config-generator`**: Aggregates and renders templated YAML configs from a hierarchical directory structure. It merges configs in priority order (later overrides earlier):
   - Repository global → env-type → environment
   - Application global → env-type → environment

Both generators use a recursive `better-tpl` helper that processes Helm templates within templates.

### Environments

Defined in `charts/application-generator/values.yaml`:
- **prod**: Non-ephemeral, promotes from test stages, creates PRs (`asPR: true`)
- **test**: Ephemeral, direct promotions, creates PRs, PR-based ApplicationSets

### Configuration Hierarchy

Configuration merges in this order (later wins):
1. `config/global/` — repo-wide defaults
2. `config/env-types/{type}/` — environment-type settings (e.g., prod)
3. `config/envs/{env}/` — environment-specific settings
4. `applications/{app}/config/global/` — app defaults
5. `applications/{app}/config/env-types/{type}/` — app env-type overrides
6. `applications/{app}/config/envs/{env}/` — app environment overrides

### Template Variables

In config YAML files, these Helm template variables are available:
- `.Values.envName` — environment name (e.g., `prod`, `test`)
- `.Values.envType` — environment type (e.g., `prod`, `test`)
- `.Values.appName` — application name (e.g., `frigate`, `grafana-scott`)
- Any custom keys from merged config files

### Custom Chart.yaml Fields

Application `Chart.yaml` files use custom fields consumed by the application-generator:
- `namespace`: Target Kubernetes namespace (defaults to app name)
- `releaseName`: Helm release name (defaults to app name)

## Directory Structure

```
applications/          # Umbrella Helm charts (one per deployed app)
  {app-name}/
    Chart.yaml         # Chart metadata + upstream dependency
    values.yaml        # Default Helm values
    config/            # Hierarchical config (envs/, env-types/, global/)
    templates/         # K8s secrets, configmaps, custom resources
    charts/            # Downloaded dependency charts (gitignored or committed)
    files/             # Static config files mounted into containers

bootstrap/             # One-time cluster setup scripts
  argocd/              # ArgoCD bootstrap (setup.sh + manifests)
  kargo/               # Kargo bootstrap (setup.sh + manifests)

charts/                # Reusable Helm chart generators
  application-generator/  # Generates ArgoCD/Kargo resources
  config-generator/       # Renders hierarchical templated configs

config/                # Repository-level configuration
  global/              # Applied to all apps and environments
  env-types/           # Per environment-type settings
  envs/                # Per environment settings

scripts/               # Operational scripts (backup, upgrade checks)
```

## Conventions & Patterns

### Naming
- Application directories use kebab-case: `grafana-scott`, `victoria-metrics-taylor`
- Multi-instance apps are suffixed with the instance owner: `{app}-{owner}`
- Generated ArgoCD resource names follow `{env}-{app}` pattern (e.g., `prod-frigate`)
- Namespaces follow `{owner}-{category}` pattern (e.g., `scott-monitoring`)

### File Patterns
- Secrets go in `templates/*-credentials.yaml` or `templates/*-secret.yaml`
- Config files use standard Helm template syntax (`{{ .Values.x }}`)
- All YAML files in `config/` directories may contain Helm templates

### Chart Structure
- Every application MUST have a `Chart.yaml` (this is how auto-discovery works)
- `values.yaml` contains default overrides for the upstream chart
- Dependencies are declared in `Chart.yaml` under `dependencies:`

### Git Workflow
- `main` branch is the source of truth
- Kargo promotes changes via branches prefixed with `env/{envName}/{appName}`
- Prod promotions create PRs for review (`asPR: true`)
- Test environments are ephemeral and use PR-based ApplicationSets
- **All commits MUST be GPG-signed.** Never use `--no-gpg-sign`, `-c commit.gpgsign=false`, or any other mechanism to bypass commit signing. If signing fails (e.g., 1Password agent not running), stop and ask the user to fix it — do not work around it.

## Common Tasks

### Adding a New Application
1. Create `applications/{app-name}/Chart.yaml` with upstream dependency
2. Create `applications/{app-name}/values.yaml` with default overrides
3. Add environment configs in `applications/{app-name}/config/envs/{env}/`
4. Add templates/secrets in `applications/{app-name}/templates/` if needed
5. The application-generator will auto-discover it from `Chart.yaml`

### Adding a New Environment
1. Add entry to `charts/application-generator/values.yaml` under `envs:`
2. Create `config/env-types/{type}/` and `config/envs/{env}/` directories
3. Optionally add app-level overrides in `applications/*/config/envs/{env}/`

### Updating an Application Version
1. Edit `dependencies[].version` in `applications/{app}/Chart.yaml`
2. Update `appVersion` in `Chart.yaml` to match
3. Commit and let Kargo promote through environments

### Validating Changes
```bash
# Lint a chart
helm lint applications/{app-name}

# Render templates locally
helm template applications/{app-name}

# Render with specific values
helm template applications/{app-name} -f applications/{app-name}/config/envs/prod/values.yaml
```

## Important Warnings

- **All commits MUST be GPG-signed.** Never bypass or disable commit signing under any circumstances. If signing fails, stop and ask the user to resolve the issue.
- **Never commit secrets in plaintext** — use Sealed Secrets or External Secrets Operator
- **Do not manually edit generated manifests** — they are produced by the generator pipeline
- The `config-generator` paths reference `config/platform/` and `config/application/` — these are mapped during the Kargo promotion process (copied from repo `config/` and `applications/{app}/config/`)
- Helm template syntax in YAML config files is intentional and processed by `config-generator`
- The `better-tpl` helper recursively renders templates, so templated values can reference other templated values

## Reference Documentation

- [README.md](README.md) — Full project documentation
- [GENERATORS.md](GENERATORS.md) — Detailed generator chart documentation
- [VICTORIA_METRICS_UPGRADE.md](VICTORIA_METRICS_UPGRADE.md) — Victoria Metrics upgrade guide
- [SNAPSHOT_RECOVERY_GUIDE.md](SNAPSHOT_RECOVERY_GUIDE.md) — Snapshot recovery procedures
