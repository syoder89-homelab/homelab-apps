# Update an Application Version

Update a specific application's Helm chart dependency to a new version.

## Input

`$ARGUMENTS` should contain the application name and optionally a target version.

Examples:
- `grafana-scott` — update to the latest available version
- `grafana-scott 10.6.0` — update to a specific version
- `grafana` — update all grafana instances (grafana-scott, grafana-taylor)

## Steps

### 1. Identify Target Application(s)

Read `applications/*/Chart.yaml` to find matching apps. If the argument matches a prefix shared by multiple apps (e.g., `grafana` matches `grafana-scott` and `grafana-taylor`), include all of them and confirm with the user.

For each app, extract:
- Current `appVersion`
- Current `dependencies[].version`
- `dependencies[].name` (upstream chart name)
- `dependencies[].repository` (Helm repo URL)

Also determine if this is a **local/vendored chart** (`repository: "file://..."`) or a **remote chart**.

### 2. Determine Target Version

If the user provided a specific version, use that.

**For remote charts**, look up the latest stable version:
```bash
helm repo add temp-update <repository-url> 2>/dev/null
helm repo update temp-update 2>/dev/null
helm search repo temp-update/<chart-name> --versions -o json | head -20
helm repo remove temp-update 2>/dev/null
```

**For local/vendored charts** (`repository: "file://..."`), look up the latest container image instead:
- Read the vendored chart's `values.yaml` to find `image.repository` (e.g., `ghcr.io/blakeblackshear/frigate`).
- For GitHub Container Registry images (`ghcr.io/{owner}/{repo}`):
  ```bash
  curl -s "https://api.github.com/repos/{owner}/{repo}/releases?per_page=10"
  ```
  Find the latest stable release (`prerelease: false`). Strip leading `v` from the tag name.
- For Docker Hub images, use:
  ```bash
  curl -s "https://hub.docker.com/v2/repositories/{owner}/{repo}/tags?page_size=20&ordering=last_updated"
  ```
- Find the currently-deployed tag by checking overrides in order: `applications/{app}/config/envs/*/values.yaml` → `applications/{app}/values.yaml` → vendored chart `values.yaml`.

Parse the output to find the latest version. Show the user the current vs. target version and confirm before making changes.

### 3. Apply the Update

**For remote charts**, update both fields in `applications/{app}/Chart.yaml`:
- `appVersion: "{new-version}"`
- `dependencies[].version: "{new-version}"`

These two values should always match for apps with upstream dependencies.

**For local/vendored charts**, update the image tag in the appropriate config file:
- Find where the image tag is currently overridden. Check `applications/{app}/config/envs/*/values.yaml` and `applications/{app}/values.yaml`.
- Update the `image.tag` value in the existing override file (preserving the nested YAML key structure under the chart name, e.g., `frigate.image.tag`).
- If no override exists yet, add one in the appropriate environment config file (`applications/{app}/config/envs/prod/values.yaml`).
- Also update `appVersion` in the umbrella `Chart.yaml` to reflect the new image version.

### 4. Check for Breaking Changes

If the update is a **major version** change (first number differs), warn the user:
- "This is a major version update. Check the upstream chart's changelog for breaking changes."
- Provide the Helm repository URL for reference.

### 5. Validate

```bash
helm lint applications/{app-name}
```

### 6. Summary

Print what was changed:
```
Updated {app-name}:
  appVersion: {old} → {new}
  dependencies[].version: {old} → {new}
```

If multiple instances were updated, list them all.

Remind the user:
- Commit the change to `main` and Kargo will promote through environments
- For multi-instance apps, all instances sharing the same upstream chart should typically be updated together

## Important Notes

- Only modify `appVersion` and `dependencies[].version` for remote charts — do not change `version` (umbrella chart version).
- For remote charts, `appVersion` and `dependencies[].version` should always be kept in sync.
- Quote the version strings in YAML.
- For local/vendored charts, update the `image.tag` in the environment config override file and `appVersion` in Chart.yaml.
- The image tag override must be nested under the dependency chart name key (e.g., `frigate:` → `image:` → `tag:`) to properly override the vendored chart defaults.
- When comparing or displaying image tags, strip leading `v` prefixes (GitHub releases use `v0.16.4`, image tags use `0.16.4`).
- Skip `kargo-config` and other apps without `dependencies` sections.
