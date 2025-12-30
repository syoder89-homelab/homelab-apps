# Helm Chart Generators

This document provides detailed documentation for the two key Helm chart generators in the homelab-apps repository:
1. **Application Generator** - Creates ArgoCD Applications and Kargo Stages
2. **Config Generator** - Renders templated configuration files

## Table of Contents

- [Application Generator](#application-generator)
- [Config Generator](#config-generator)
- [How They Work Together](#how-they-work-together)

## Application Generator

The `application-generator` chart is responsible for automatically generating ArgoCD Applications and Kargo Stages for each application and environment combination.

### Purpose

- **Discover applications** from the `applications/*/Chart.yaml` files
- **Generate ArgoCD Applications** to deploy applications to environments
- **Generate Kargo Stages** to manage progressive delivery and promotion workflows
- **Handle ephemeral environments** with special ApplicationSets for pull request testing

### Chart Structure

```
charts/application-generator/
├── Chart.yaml           # Chart metadata
├── values.yaml          # Environment and configuration definitions
└── templates/
    ├── _helpers.tpl     # Template helpers
    ├── application.yaml # Non-ephemeral ArgoCD Applications
    ├── applicationset.yaml # Ephemeral ArgoCD ApplicationSets (PR-based)
    ├── stage.yaml       # Non-ephemeral Kargo Stages
    ├── stage-ephemeral.yaml # Ephemeral Kargo Stages
    └── warehouse.yaml   # Kargo Warehouses for freight discovery
```

### Configuration (values.yaml)

The `values.yaml` file defines environments and their properties:

```yaml
envs:
  prod:
    sources:
      # Define sources for this stage
      stages:
        - test-{{ .app.name }}  # Promote from test stage
    asPR: false              # Don't create PRs for non-ephemeral
    isEphemeral: false       # Not an ephemeral environment
    targetBranchPrefix: env/prod  # Branch prefix for promotions
    envType: prod            # Environment type (used by config-generator)
  
  test:
    sources:
      direct: true           # Accept direct promotions
    asPR: true               # Create PRs for this environment
    isEphemeral: true        # Ephemeral, temporary environment
    targetBranchPrefix: env/test
    envType: test
```

#### Environment Configuration Fields

| Field | Type | Description |
|-------|------|-------------|
| `sources` | object | Freight sources for this stage (direct or from other stages) |
| `sources.direct` | boolean | Accept direct promotions (changes from specific branches) |
| `sources.stages` | array | Accept promotions from specific Kargo stages |
| `asPR` | boolean | Create pull requests for promotions (useful for review workflows) |
| `isEphemeral` | boolean | Whether this is a temporary/test environment |
| `targetBranchPrefix` | string | Git branch prefix for promotions (e.g., `env/prod/app-name`) |
| `envType` | string | Environment type, passed to config-generator for template rendering |

### Generated Resources

#### 1. ArgoCD Applications (application.yaml)

For non-ephemeral environments, the generator creates ArgoCD Application resources:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prod-frigate
  namespace: argocd
spec:
  destination:
    name: in-cluster
    namespace: frigate
  project: apps
  source:
    path: deploy/frigate
    repoURL: https://github.com/syoder89-homelab/homelab-apps
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

**Generated Application Names**: `{envName}-{appName}` (e.g., `prod-frigate`, `test-grafana-scott`)

#### 2. ArgoCD ApplicationSets (applicationset.yaml)

For ephemeral environments, the generator creates ApplicationSets with pull request generators:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: ephemeral-test-frigate
  namespace: argocd
spec:
  generators:
    - pullRequest:
        github:
          owner: syoder89-homelab
          repo: homelab-apps
        filters:
          - targetBranchMatch: "^env/test/frigate$"
```

This enables **automatic ephemeral deployments** when pull requests are opened with the matching branch pattern.

#### 3. Kargo Stages (stage.yaml)

For non-ephemeral environments, the generator creates Kargo Stage resources that define promotion workflows:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: prod-frigate
  namespace: homelab-apps
spec:
  requestedFreight:
    - origin:
        kind: Warehouse
        name: frigate
      sources: {}  # Sources defined from env config
  promotionTemplate:
    spec:
      # Promotion steps (config-generation, helm-template, argocd-update, etc.)
```

**Promotion Workflow**:
1. `prepare-workdir` - Initialize workspace
2. `copy` - Copy repository config to config-generator
3. `helm-template` (config-generator) - Render templated configuration
4. `helm-template` (application) - Generate Kubernetes manifests
5. `push-manifests` - Commit generated manifests to Git
6. `argocd-update` - Update ArgoCD Application to new revision

#### 4. Ephemeral Kargo Stages (stage-ephemeral.yaml)

For ephemeral environments, similar to non-ephemeral but:
- Creates namespaced deployments (e.g., `test-{appName}`)
- May use different promotion strategies (often PR-based with ArgoCD ApplicationSets)

#### 5. Kargo Warehouses (warehouse.yaml)

Creates Warehouse resources for freight discovery:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: frigate
  namespace: homelab-apps
spec:
  subscriptions:
    - git:
        repoURL: https://github.com/syoder89-homelab/homelab-apps
          branches:
            - main
```

### Key Features

- **Multi-environment support**: Automatically generates resources for each environment
- **Flexible promotion workflows**: Define sources (direct or from other stages)
- **PR-based ephemeral testing**: Automatic deployments for pull requests
- **Configuration templating**: Passes environment variables to config-generator
- **Auto-discovery**: Scans `applications/*/Chart.yaml` to find applications
- **CRD support**: Includes custom resource definitions in generated manifests

### Template Variables

The generator uses these variables from Chart.yaml:

```yaml
# In applications/[app-name]/Chart.yaml
apiVersion: v2
name: frigate                     # Used as: {envName}-{name}
description: Frigate NVR
namespace: frigate                # Optional, defaults to app name
releaseName: frigate              # Optional, defaults to app name
type: application
version: "0.0.1"
```

## Config Generator

The `config-generator` chart renders templated configuration files by aggregating and merging YAML configurations from multiple directories, supporting Helm templating for dynamic values.

### Purpose

- **Aggregate configurations** from repository-level and application-level sources
- **Render Helm templates** in configuration files
- **Support environment-specific overrides** through hierarchical merging
- **Provide template variables** for dynamic configuration (environment name, type, etc.)

### Chart Structure

```
charts/config-generator/
├── Chart.yaml           # Chart metadata
├── values.yaml          # Configuration paths definition
└── templates/
    ├── _helpers.tpl     # Template helper functions
    └── values.yaml      # Main template that aggregates and renders configs
```

### Configuration (values.yaml)

Defines which configuration files to load and in what order:

```yaml
configPaths:
  - config/platform/global/**.yaml
  - config/platform/env-types/{{ .Values.envType }}/**.yaml
  - config/platform/envs/{{ .Values.envName }}/**.yaml
  - config/application/global/**.yaml
  - config/application/env-types/{{ .Values.envType }}/**.yaml
  - config/application/envs/{{ .Values.envName }}/**.yaml
```

The paths themselves are templated, allowing the generator to dynamically select files based on the environment type and name.

### How It Works

1. **Path Resolution**: Configuration paths are templated (e.g., `env-types/{{ .Values.envType }}/` becomes `env-types/prod/`)
2. **File Globbing**: Uses glob patterns to find matching YAML files
3. **Hierarchical Merging**: Loads files in order, with later files overriding earlier ones
4. **Template Rendering**: Processes the merged YAML through Helm's template engine
5. **Recursive Processing**: Supports templates in templates (templates can reference other templated values)

### Configuration Paths

The default configuration paths follow this merge order (later overrides earlier):

1. **Repository-level global**: `config/platform/global/`
   - Applied to all applications and environments
   - Use for: common labels, resource naming conventions

2. **Repository-level environment type**: `config/platform/env-types/{type}/`
   - Applied to all applications with this environment type
   - Use for: production-wide policies, monitoring configurations

3. **Repository-level environment**: `config/platform/envs/{env}/`
   - Applied to all applications in this environment
   - Use for: environment-specific shared settings

4. **Application-level global**: `config/application/global/`
   - Applied to the specific application across all environments
   - Use for: application-specific defaults

5. **Application-level environment type**: `config/application/env-types/{type}/`
   - Applied to the application with this environment type
   - Use for: environment-type-specific application settings

6. **Application-level environment**: `config/application/envs/{env}/`
   - Applied to the application in this environment
   - Use for: environment-specific application overrides

### Template Variables

Available during template rendering:

| Variable | Description | Example |
|----------|-------------|---------|
| `.Values.envName` | Environment name | `prod`, `test` |
| `.Values.envType` | Environment type | `prod`, `test` |
| `.Values.appName` | Application name | `frigate`, `grafana-scott` |
| Any YAML keys from config files | Accessible as `.Values.keyName` | Custom variables from your configs |

### Templating Example

```yaml
# config/application/envs/prod/settings.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.appName }}-config
  namespace: {{ .Values.appName }}
  labels:
    environment: {{ .Values.envName }}
    environment-type: {{ .Values.envType }}
spec:
  replicas: |
    {{- if eq .Values.envType "prod" }}
    3
    {{- else }}
    1
    {{- end }}
  debug: |
    {{- if eq .Values.envType "prod" }}
    false
    {{- else }}
    true
    {{- end }}
```

### Helper Functions

The `_helpers.tpl` file provides `better-tpl` for recursive template rendering:

```
better-tpl(value, context)
```

This function:
- Converts non-string values to YAML
- Detects `{{` in strings (indicates template syntax)
- Recursively renders templates (handles templates within templates)
- Stops when no more templates are found

### Integration with Application Generator

The Kargo Stage promotion template calls config-generator:

```yaml
- uses: helm-template
  config:
    releaseName: config-generator
    path: ./charts/config-generator
    outLayout: flat
    outPath: /tmp/values.yaml
    setValues:
      - key: envName
        value: prod
      - key: envType
        value: prod
      - key: appName
        value: frigate
```

This generates a `values.yaml` file that is then used as input to the application's helm-template step:

```yaml
- uses: helm-template
  config:
    path: ./applications/frigate
    valuesFiles:
      - /tmp/values.yaml  # Generated by config-generator
```

## How They Work Together

The two generators work in concert to create a complete, templated GitOps workflow:

### Workflow

1. **Application Generator discovers applications** from `applications/*/Chart.yaml`

2. **Application Generator creates Kargo Stages** for each environment and application

3. **Kargo Stage promotion process:**
   - Creates a working directory with repository content
   - Copies `config/` directories to config-generator chart
   - **Config Generator renders templated configs** based on environment/environment-type/application
   - **Helm templates the application** using generated config values
   - **Generates Kubernetes manifests** with proper overrides
   - **Commits manifests** to Git (or creates PR for ephemeral)
   - **ArgoCD syncs** the new manifests to the cluster

4. **Application Generator creates ArgoCD Applications** pointing to deployed manifests

### Data Flow

```
Repository Structure
    ↓
Application Generator (values.yaml)
    ├── Discovers: applications/*/Chart.yaml
    ├── Generates: ArgoCD Applications (non-ephemeral)
    ├── Generates: ArgoCD ApplicationSets (ephemeral)
    └── Generates: Kargo Stages/Warehouses
         ↓
    Kargo Promotion Template
         ├── Copies config files
         ├── Config Generator
         │   ├── Aggregates: config/global/
         │   ├── Aggregates: config/env-types/{type}/
         │   ├── Aggregates: config/envs/{env}/
         │   └── Renders: Helm templates → values.yaml
         │
         ├── Helm Templates Application
         │   ├── Inputs: applications/[app]/Chart.yaml
         │   ├── Inputs: generated values.yaml
         │   └── Outputs: Kubernetes manifests
         │
         ├── Commits to Git (or creates PR)
         │
         └── ArgoCD Updates
              └── Syncs manifests to cluster
```

### Environment Promotion Example

**Promoting frigate from test to prod:**

1. User initiates promotion of `test-frigate` stage in Kargo
2. Kargo executes `prod-frigate` stage promotion template:
   - Runs config-generator with `envName=prod`, `envType=prod`, `appName=frigate`
   - Loads and merges configurations in this order:
     - `config/global/` (common labels, naming)
     - `config/env-types/prod/` (production policies)
     - `config/envs/prod/` (production environment settings)
     - `applications/frigate/config/global/` (frigate defaults)
     - `applications/frigate/config/env-types/prod/` (frigate prod settings)
     - `applications/frigate/config/envs/prod/` (frigate prod overrides)
   - Renders all templates using environment variables
   - Generates production deployment manifests
   - Commits to `env/prod/frigate` branch
   - ArgoCD application `prod-frigate` syncs the new revision

### Key Benefits

- **Single source of truth**: All configuration and deployment logic in Git
- **Reusable patterns**: Common configurations applied across all applications
- **Progressive delivery**: Kargo stages manage safe promotion workflows
- **Ephemeral testing**: Pull request-based temporary deployments
- **Template flexibility**: Dynamic configuration based on environment
- **Automatic discovery**: No manual updates needed when adding applications

## Customization

### Adding a New Environment

1. Add environment to `charts/application-generator/values.yaml`:
   ```yaml
   envs:
     dev:
       sources:
         direct: true
       asPR: false
       isEphemeral: false
       targetBranchPrefix: env/dev
       envType: dev
   ```

2. Add environment-level configuration directories:
   ```
   config/env-types/dev/
   config/envs/dev/
   applications/*/config/env-types/dev/  (optional)
   applications/*/config/envs/dev/       (optional)
   ```

### Adding Application-Specific Configurations

Create application-level configuration directories:

```
applications/[app-name]/config/
├── global/              # App defaults for all environments
├── env-types/prod/      # App-specific prod environment type settings
├── env-types/test/      # App-specific test environment type settings
└── envs/prod/           # App-specific prod environment overrides
```

### Using Custom Template Variables

Pass additional variables to config-generator via Kargo promotion template, or define them in configuration files and reference them in templates.

---

**Last Updated**: December 2025
