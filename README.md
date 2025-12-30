# homelab-apps

A Kubernetes-based home lab infrastructure-as-code repository for deploying and managing containerized applications using Helm charts, ArgoCD, and Kargo. This project provides umbrella Helm charts and configurations for multiple home lab services across different environments.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Applications](#applications)
- [Getting Started](#getting-started)
- [Configuration](#configuration)
- [Deployment](#deployment)
- [Development](#development)
- [Contributing](#contributing)
- [Generators Documentation](#generators-documentation)

## Overview

This repository manages a comprehensive home lab Kubernetes cluster with:

- **Multiple Applications**: Services like Frigate (video NVR), InfluxDB, Grafana, Home Assistant, Mosquitto (MQTT), and Victoria Metrics
- **Multiple Environments**: Support for different deployment environments (prod, test, dev)
- **GitOps Workflow**: Integration with ArgoCD for continuous deployment and Kargo for progressive delivery
- **Helm-based Deployment**: Umbrella charts for easy application management

## Architecture

### Technology Stack

- **Kubernetes**: Container orchestration platform
- **Helm**: Package manager for Kubernetes applications
- **ArgoCD**: GitOps continuous deployment tool
- **Kargo**: Progressive delivery platform for safer deployments
- **YAML-based Configuration**: Version-controlled infrastructure definitions

### Components

```
homelab-apps/
├── bootstrap/          # Initial cluster setup and bootstrapping
├── applications/       # Application definitions (umbrella charts)
├── charts/            # Helm chart generators
├── config/            # Global and environment-specific configurations
└── README.md          # This file
```

## Project Structure

### `bootstrap/`

Contains initialization scripts and manifests for setting up the Kubernetes cluster:

- **`argocd/`**: ArgoCD setup and application definitions
  - `setup.sh`: Script to initialize ArgoCD
  - `manifests/`: ArgoCD Application and AppProject definitions
  
- **`kargo/`**: Kargo setup for progressive deployment
  - `setup.sh`: Script to initialize Kargo
  - `manifests/`: Kargo Project, Stages, Tasks, and Warehouse definitions

### `applications/`

Umbrella Helm charts for each home lab application:

- `frigate/`: Video NVR system for camera management
- `grafana-scott/`: Grafana monitoring instance
- `grafana-taylor/`: Grafana monitoring instance
- `influxdb-scott/`: Time-series database instance
- `victoria-metrics-scott/`: Metrics storage instance
- `victoria-metrics-taylor/`: Metrics storage instance
- `mosquitto/`: MQTT message broker
- `mosquitto-taylor/`: MQTT message broker instance
- `kargo-config/`: Kargo configuration and integration
- `home-assistant/`: Home automation platform

Each application follows the structure:
```
application-name/
├── Chart.yaml              # Helm chart metadata
├── values.yaml             # Default Helm values
├── charts/                 # Dependent chart repositories
├── config/
│   ├── env-types/          # Application-specific environment type configs (optional)
│   ├── envs/               # Environment-specific configurations
│   └── global/             # Application-level global configurations
├── templates/              # Kubernetes manifests and secrets
└── files/                  # Static configuration files
```

### `charts/`

Helm chart generators and utilities:

- **`application-generator/`**: Generates ArgoCD Applications from chart definitions
- **`config-generator/`**: Generates configuration and values templates

### `config/`

Global and environment-specific configuration:

- **`env-types/`**: Environment type definitions (e.g., `prod/` for production-type settings)
- **`global/`**: Repository-wide global settings
- **`envs/`**: Environment configurations (e.g., `prod/`, `test/`)

## Applications

| Application | Purpose |
|---|---|
| **Frigate** | Video NVR and camera management |
| **Grafana** | Metrics visualization and dashboards |
| **InfluxDB** | Time-series database for metrics |
| **Victoria Metrics** | Metrics storage and querying |
| **Home Assistant** | Home automation platform |
| **Mosquitto** | MQTT message broker |
| **Kargo Config** | Progressive delivery configuration |

## Getting Started

### Prerequisites

- Kubernetes cluster (v1.24+)
- `kubectl` configured to access your cluster
- `helm` CLI (v3.10+)
- Git access to this repository

### Initial Cluster Setup

1. **Bootstrap ArgoCD**:
   ```bash
   cd bootstrap/argocd
   ./setup.sh
   ```

2. **Bootstrap Kargo** (optional, for progressive delivery):
   ```bash
   cd bootstrap/kargo
   ./setup.sh
   ```

3. **Verify deployments**:
   ```bash
   kubectl get all -A
   ```

## Configuration

### Repository-Level vs Application-Level Configuration

The configuration hierarchy is divided into two levels, each serving a specific purpose:

**Repository-Level Configuration** (`config/`):
- Provides common configurations shared across all applications
- Use cases: common labels, tags, monitoring configurations, global policies
- Structure: `env-types/`, `global/`, `envs/`
- Applied to every application in the repository

**Application-Level Configuration** (`applications/[app-name]/config/`):
- Provides application-specific overrides and customizations
- Use cases: application-specific environment variables, secrets, feature flags
- Structure: `env-types/` (optional), `global/`, `envs/`
- Applied only to the specific application

### Environments and Kargo Stages

Configurations are organized by **environment type** (e.g., `prod`, `dev`, `test`) and **environment** (specific deployments). For each environment, a corresponding Kargo stage is created for every application, enabling progressive delivery and promotion workflows.

The configuration hierarchy follows this order (later overrides earlier):
1. **Repository-level `global/`**: Shared settings for all apps and all environments
2. **Repository-level `env-types/[type]/`**: Shared settings for a specific environment type
3. **Repository-level `envs/[env]/`**: Shared settings for a specific environment
4. **Application-level `global/`**: Application-specific settings for all environments
5. **Application-level `env-types/[type]/`** (optional): Application-specific overrides for a specific environment type
6. **Application-level `envs/[env]/`** (optional): Application-specific overrides for a specific environment

For example, with a production environment and an ephemeral test environment:

```
Repository level (shared across all apps):
config/
├── env-types/
│   └── prod/                 # Prod env-type: common labels, tags, monitoring
├── global/                   # Global: repository-wide settings
└── envs/
    └── prod/                 # Prod env: production-specific shared configs

Application level (app-specific overrides):
applications/grafana-scott/config/
├── env-types/
│   ├── prod/                 # Grafana-specific prod settings
│   └── test/                 # Grafana-specific test settings
├── global/                   # Grafana-specific global settings
└── envs/
    └── prod/                 # Grafana-specific prod environment settings
```

### Ephemeral Environments

Environments can be marked as ephemeral using the `isEphemeral` flag in the environment configuration. Ephemeral environments have different deployment behavior—they are temporary environments typically created from pull requests or short-lived test branches. The `test` environment is currently configured as ephemeral and creates temporary Kargo stages for testing before merging to main.

### Application Configuration

Each application supports multiple configuration levels:

1. **Default Values** (`values.yaml`): Base configuration
2. **Global Config** (`config/global/*.yaml`): Applied to all environments
3. **Environment Config** (`config/envs/[env-name]/*.yaml`): Environment-specific overrides
4. **Templates** (`templates/*.yaml`): Kubernetes manifests and secrets

### Configuration Templating

Configuration files support Helm templating, allowing you to use variables, conditionals, and other Helm functions. This enables dynamic configuration based on the environment, environment type, or other values.

**Template Syntax**: Use standard Helm template syntax in YAML files:
```yaml
# Example: Using environment and environment type variables
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.appName }}-config
  namespace: {{ .Values.namespace }}
spec:
  config.yaml: |
    environment: {{ .Values.envName }}
    environment_type: {{ .Values.envType }}
    {{- if eq .Values.envType "prod" }}
    replicas: 3
    {{- else }}
    replicas: 1
    {{- end }}
```

**Available Template Variables**:
- `.Values.envName`: Name of the current environment (e.g., `prod`, `test`)
- `.Values.envType`: Type of the current environment (e.g., `prod`, `test`)
- Any other values defined in your configuration files (merged hierarchically)

The `config-generator` chart processes all configuration files through Helm's templating engine, allowing for flexible, dynamic configurations across your environments.

### Adding Custom Values

To customize an application:

1. **For repository-wide settings** (apply to all apps):
   - Edit `config/global/` for settings shared by all apps
   - Edit `config/env-types/[type]/` for environment-type-wide settings
   - Edit `config/envs/[env]/` for environment-specific shared settings

2. **For application-specific settings**:
   - Edit `applications/[app-name]/values.yaml` for application defaults
   - Add settings in `applications/[app-name]/config/global/` for app-wide overrides
   - Add settings in `applications/[app-name]/config/env-types/[type]/` for app-specific environment type overrides
   - Add settings in `applications/[app-name]/config/envs/[env]/` for app-specific environment overrides

3. **Deploy changes**:
   - Use Kargo to gradually roll out changes across environments
   - Review the configuration cascade to understand which settings will take precedence

## Deployment

Deployments are GitOps-driven using ArgoCD and Kargo. Changes are automatically deployed from Git, and promotions between environments are managed through Kargo stages.

## Development

### Adding a New Application

1. **Create application directory**:
   ```bash
   mkdir -p applications/new-app/{config,templates,charts}
   ```

2. **Create Chart.yaml**:
   ```yaml
   apiVersion: v2
   name: new-app
   description: Description of the application
   type: application
   version: "0.0.1"
   appVersion: "1.0.0"
   ```

3. **Create values.yaml** with default values

4. **Add configuration templates** in `templates/`

5. **Define environment-specific configs** in `config/envs/[env-name]/`

### Updating Application Versions

To update a dependency:

1. Edit the `dependencies` section in `Chart.yaml`
2. Run `helm dependency update` in the application directory
3. Test changes in a staging environment
4. Use Kargo to promote to production

### Secrets Management

Sensitive data (API keys, passwords, credentials) are stored in:
- `templates/*-credentials.yaml`
- `templates/*-secret.yaml`
- `config/envs/[env-name]/*-secret.yaml`

These should be managed with appropriate secret management tools (e.g., Sealed Secrets, External Secrets Operator).

## Contributing

### Guidelines

- Follow the existing directory structure and naming conventions
- Update documentation when making changes
- Test changes in staging before promoting to production
- Use Kargo for staged, progressive rollouts
- Keep secrets out of Git (use secret management tools)

### Making Changes

1. Create a feature branch
2. Make changes to application configs or charts
3. Test with `helm lint` and `helm template`
4. Submit a pull request
5. ArgoCD will automatically sync approved changes

## Troubleshooting

### Check Application Status

```bash
# View application health
kubectl get all -n [namespace]

# Check pod logs
kubectl logs -n [namespace] deployment/[deployment-name]

# Describe resources
kubectl describe deployment [deployment-name] -n [namespace]
```

### View ArgoCD Details

```bash
# Port-forward to ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Check application status
argocd app list
```

### Verify Kargo Promotions

```bash
# Watch stage status
kubectl get stages -n kargo -w

# Check promotion status
kubectl get promotions -n kargo
```

## Directory Reference

| Path | Purpose |
|------|---------|
| `applications/` | Application umbrella charts and configurations |
| `bootstrap/` | Initial cluster setup scripts and manifests |
| `charts/` | Reusable Helm chart generators |
| `config/` | Global and environment-specific settings |
| `.gitignore` | Git ignore rules (secrets, temporary files) |
| `README.md` | This documentation |
| `GENERATORS.md` | Detailed documentation for chart generators |

## Generators Documentation

For detailed information about the `application-generator` and `config-generator` charts, see [GENERATORS.md](GENERATORS.md). This documentation covers:

- **Application Generator**: Automatically discovers applications and generates ArgoCD Applications and Kargo Stages
- **Config Generator**: Renders templated configuration files with hierarchical merging and Helm template support
- **Workflow Integration**: How the two generators work together to create a complete GitOps pipeline
- **Customization Guide**: How to add new environments and application-specific configurations

## License

[Add your license information here]

## Contact

For questions or support, contact: [Add contact information]

---

**Last Updated**: December 2025
**Kubernetes Version**: v1.24+
**Helm Version**: v3.10+

