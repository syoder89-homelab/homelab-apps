# Add a New Application

Scaffold a new application in this repository with all required files and directories.

## Input

The user must provide `$ARGUMENTS` containing at minimum the application name.

Parse the arguments to extract:
- **App name** (required) — kebab-case, e.g., `prometheus-scott`
- **Upstream chart name** — the Helm chart to depend on (if not provided, ask the user)
- **Upstream chart repository URL** — the Helm repo URL (if not provided, ask the user)
- **Chart version** — the version to pin (if not provided, look it up with `helm search repo`)
- **Namespace** — Kubernetes namespace (if not provided, infer from naming convention: `{owner}-{category}` for owner-suffixed apps, or the app name itself)

If the arguments are ambiguous or missing required info, ask the user before proceeding.

## Steps

### 1. Look Up the Latest Chart Version (if not provided)

```bash
helm repo add temp-scaffold <repository-url> 2>/dev/null
helm repo update temp-scaffold 2>/dev/null
helm search repo temp-scaffold/<chart-name> --versions -o json | head -20
helm repo remove temp-scaffold 2>/dev/null
```

Use the latest stable version from the results.

### 2. Create `applications/{app-name}/Chart.yaml`

Follow the exact pattern used by existing apps:

```yaml
apiVersion: v2
name: {app-name}
description: An Umbrella Helm chart for deploying {description}
type: application
version: "0.0.1"
appVersion: "{chart-version}"
dependencies:
  - name: {upstream-chart-name}
    version: "{chart-version}"
    repository: "{repository-url}"
```

Add optional custom fields only if needed:
- `namespace: {namespace}` — if namespace differs from app name
- `releaseName: {release-name}` — if release name differs from app name

Look at existing apps with similar naming patterns for guidance. Apps suffixed with an owner name (e.g., `grafana-scott`) typically need both `namespace` and sometimes `releaseName`.

### 3. Create `applications/{app-name}/values.yaml`

Create an empty file (or with minimal comments). Default overrides for the upstream chart go here.

### 4. Create Config Directory Structure

```
applications/{app-name}/config/
  envs/
    prod/
```

Create the `config/envs/prod/` directory. Only create `config/global/` or `config/env-types/` directories if the user specifically requests them or provides config that belongs there.

### 5. Create Templates Directory (if needed)

Only create `applications/{app-name}/templates/` if the user mentions needing secrets or custom Kubernetes resources. If created, follow naming conventions:
- Secrets: `{name}-credentials.yaml` or `{name}-secret.yaml`

### 6. Validate

Run:
```bash
helm lint applications/{app-name}
```

If the lint fails due to missing dependency, that's expected — the dependency will be fetched during the Kargo promotion process.

### 7. Summary

Print a summary of what was created and any next steps the user should take, such as:
- Adding values overrides in `values.yaml`
- Adding environment-specific config in `config/envs/prod/`
- Adding secrets templates if needed
- The application-generator will auto-discover it on next sync

## Important Notes

- Every application MUST have a `Chart.yaml` — this is how auto-discovery works.
- Do NOT create ArgoCD Application or Kargo Stage manifests — the `application-generator` handles that automatically.
- Use `version: "0.0.1"` for the umbrella chart version (this is convention).
- Quote string values in Chart.yaml fields.
- Use 2-space indentation in all YAML files.
- Look at existing similar applications for reference patterns before creating files.
