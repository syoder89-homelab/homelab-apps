# Add a New Environment

Scaffold a new environment across the application-generator config and directory hierarchy.

## Input

`$ARGUMENTS` should contain the environment name and optionally the environment type.

Examples:
- `staging` — creates a new environment named "staging" (will ask for env type)
- `staging prod` — creates "staging" with envType "prod"
- `dev` — creates a new "dev" environment

## Steps

### 1. Read Current Environments

Read `charts/application-generator/values.yaml` to understand the existing environment definitions and their structure. Show the user what currently exists.

### 2. Gather Configuration

Determine from the user (or arguments):
- **Environment name** (required): e.g., `staging`, `dev`
- **Environment type** (`envType`): e.g., `prod`, `test`, `dev` — this controls which `env-types/` config directories apply
- **Is ephemeral** (`isEphemeral`): `true` for temporary/PR-based environments, `false` for permanent
- **Promotion source**: Does it accept direct promotions (`sources.direct: true`) or promote from another stage (`sources.stages`)?
- **Create PRs** (`asPR`): Whether promotions create pull requests for review
- **Branch prefix** (`targetBranchPrefix`): Git branch prefix (convention: `env/{envName}`)

If not all details are provided, suggest sensible defaults based on the envType:
- `prod`-type: `isEphemeral: false`, promotes from a test stage, `asPR: true`
- `test`-type: `isEphemeral: true`, direct promotions, `asPR: true`
- Other: `isEphemeral: false`, direct promotions, `asPR: false`

### 3. Update `charts/application-generator/values.yaml`

Add the new environment entry under `envs:`. Follow the exact YAML structure of existing entries:

```yaml
envs:
  # ... existing envs ...
  {new-env}:
    sources:
      direct: true  # or stages: [...]
    asPR: {true|false}
    isEphemeral: {true|false}
    targetBranchPrefix: env/{new-env}
    envType: {env-type}
```

### 4. Create Repository-Level Config Directories

Create these directories (with a `.gitkeep` file in each so Git tracks them):

```
config/envs/{new-env}/
```

If this is a new envType that doesn't already have a directory:
```
config/env-types/{new-env-type}/
```

### 5. Optionally Create Application-Level Config Directories

Ask the user if they want environment-specific config directories created for existing applications. If yes, for each application in `applications/*/`:

```
applications/{app}/config/envs/{new-env}/
```

### 6. Validate

```bash
helm lint charts/application-generator
```

### 7. Summary

Print what was created:
- The environment entry added to `application-generator/values.yaml`
- The config directories created
- Reminder that the application-generator will automatically create ArgoCD Applications and Kargo Stages for each application × this new environment on next sync

## Important Notes

- Do NOT manually create ArgoCD Application or Kargo Stage manifests — the `application-generator` auto-generates them.
- Environment names should be lowercase kebab-case.
- The `targetBranchPrefix` convention is `env/{envName}`.
- The `envType` is used by the `config-generator` to select `env-types/` config directories, so it should match an existing or new env-type directory.
- Use 2-space indentation in all YAML files.
- Existing environments are `prod` (non-ephemeral, promotes from test, `asPR: true`) and `test` (ephemeral, direct, `asPR: true`).
