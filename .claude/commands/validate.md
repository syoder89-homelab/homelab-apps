# Validate Charts

Lint and template-render Helm charts to catch errors before committing.

## Input

`$ARGUMENTS` is optional:
- If provided, validate only the specified application(s) (e.g., `grafana-scott`)
- If empty, validate ALL applications and generator charts

## Steps

### 1. Determine Scope

If `$ARGUMENTS` is provided, validate only matching apps under `applications/`.
If empty, collect all directories that contain a `Chart.yaml`:
- `applications/*/Chart.yaml`
- `charts/application-generator/Chart.yaml`
- `charts/config-generator/Chart.yaml`

### 2. Lint Each Chart

For each chart, run:
```bash
helm lint <chart-path> 2>&1
```

Capture the output. Track pass/fail for each chart.

Note: Lint warnings about missing dependencies are expected for application umbrella charts — the dependencies are resolved during the Kargo promotion process, not locally. Do NOT treat these as failures.

### 3. Template Render (applications only)

For each application chart, attempt a template render:
```bash
helm template <app-name> <chart-path> 2>&1
```

If the app has environment-specific values files, also try rendering with them:
```bash
helm template <app-name> <chart-path> -f <chart-path>/config/envs/prod/values.yaml 2>&1
```

Template render failures due to missing chart dependencies are expected — note them but don't count as errors.

### 4. Check for Common Issues

Scan for these problems across all application YAML files:
- **Unquoted version strings** in `Chart.yaml` (`version` and `appVersion` should be quoted)
- **Missing `Chart.yaml`** in any `applications/*/` directory
- **Mismatched versions**: `appVersion` in Chart.yaml not matching `dependencies[].version`

### 5. Report Results

Print a summary:

```
# Validation Report — <date>

## Results
✓ <app-name>: lint passed, template passed
✓ <app-name>: lint passed, template skipped (missing deps)
✗ <app-name>: lint failed — <error summary>

## Summary
- X charts validated
- Y passed
- Z failed
- N warnings

## Issues Found
(list any issues from step 4)
```

### 6. Exit Status

If any charts have real failures (not dependency-related warnings), clearly indicate which ones need attention and what the errors are.

## Important Notes

- Lint warnings about missing dependency charts (e.g., `Chart.lock is out of sync`) are normal — these deps are pulled during Kargo promotion.
- Template failures from missing subcharts are expected — these are umbrella charts that depend on deployment-time chart fetching.
- The generator charts (`application-generator`, `config-generator`) should lint cleanly since they have no external dependencies.
- Use 2>&1 to capture both stdout and stderr from helm commands.
