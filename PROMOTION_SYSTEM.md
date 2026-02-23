# Promotion System

This document describes the progressive delivery promotion system used in the homelab-apps repository. The system uses **Kargo** for staged promotions and **ArgoCD** for GitOps deployment.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Promotion Flow](#promotion-flow)
  - [Test Stage (Ephemeral)](#test-stage-ephemeral)
  - [Prod Stage (Non-Ephemeral)](#prod-stage-non-ephemeral)
- [Components](#components)
  - [Warehouses](#warehouses)
  - [Stages](#stages)
  - [PromotionTasks](#promotiontasks)
  - [ArgoCD Applications & ApplicationSets](#argocd-applications--applicationsets)
- [Race Condition Fix](#race-condition-fix)
- [Verification Strategy](#verification-strategy)
- [Adding App-Specific Health Checks](#adding-app-specific-health-checks)
- [Troubleshooting](#troubleshooting)

## Overview

The promotion system implements a **test → prod** pipeline for each application:

```
main branch commit
       │
       ▼
   Warehouse          (detects changes per-app via path filters)
       │
       ▼
   Test Stage          (ephemeral: deploys to test-{namespace} via PR)
       │  ✓ verified
       ▼
   Prod Stage          (non-ephemeral: deploys to {namespace} via PR for review)
```

- **Test** is an ephemeral environment that deploys to a separate namespace (`test-{namespace}`) using PR-based ArgoCD ApplicationSets. The test deployment exists only during the promotion window.
- **Prod** is a persistent environment that deploys to the app's primary namespace. Promotions create PRs for human review before merging.

## Architecture

### Key Design Decisions

1. **Resource efficiency**: Test uses ephemeral PR-based deployments so no persistent test infrastructure is required.
2. **Namespace isolation**: Test deployments use `test-{namespace}` to avoid conflicts with prod.
3. **Automated verification**: The test stage auto-verifies via ArgoCD health checks and auto-merges the PR when passing. No manual intervention needed for test.
4. **Human gate for prod**: Prod promotions create PRs that require manual merge.

### Environment Configuration

Defined in `charts/application-generator/values.yaml`:

```yaml
envs:
  prod:
    sources:
      stages:
      - test-{{ .app.name }}    # Promote FROM test stage
    asPR: true                  # Create PR for human review
    isEphemeral: false          # Persistent ArgoCD Application
    targetBranchPrefix: env/prod
    envType: prod
  test:
    sources:
      direct: true              # Accept direct promotions from warehouse
    asPR: true                  # Create PR (used by ApplicationSet PR generator)
    isEphemeral: true           # PR-based ApplicationSet (temporary)
    targetBranchPrefix: env/test
    envType: test
```

## Promotion Flow

### Test Stage (Ephemeral)

When a commit is pushed to `main` that modifies an application's directory:

```
1. Warehouse detects change    ─── Watches main branch, filters by application path
       │
2. Test Stage auto-promotes    ─── autoPromotionEnabled: true
       │
3. prepare-workdir             ─── Clones main → ./src, creates target branch → ./out
       │
4. copy config                 ─── Copies repo config + app config into config-generator
       │
5. helm-template (config)      ─── Renders environment-specific values.yaml via config-generator
       │
6. helm-template (app)         ─── Renders K8s manifests with test-{namespace} naming
       │
7. push-manifests              ─── Commits rendered manifests, opens PR to env/test/{app}
       │                            (waitForPR: false — does NOT block on PR merge)
       │
8. argocd-update               ─── Waits for ArgoCD ApplicationSet to detect the PR,
       │                            create the ephemeral Application, sync, and report healthy
       │                            retry: errorThreshold=10, timeout=10m
       │
9. git-merge-pr                ─── Auto-merges the PR after verification passes
       │                            This triggers ApplicationSet cleanup of the ephemeral app
       │
10. Promotion Complete         ─── Freight marked as verified in test stage
       │
11. Prod stage can promote     ─── Sources from test-{app} stage
```

**Key points:**
- The test Application only exists while the PR is open (between steps 7-9)
- The PR is automatically merged after ArgoCD confirms the app is healthy
- No manual intervention is needed for the test stage
- Namespace: `test-{appNamespace}` (e.g., `test-frigate`, `test-scott-monitoring`)
- Release name: `test-{appName}` (e.g., `test-frigate`, `test-grafana-scott`)

### Prod Stage (Non-Ephemeral)

After the test stage verifies freight:

```
1. Prod Stage auto-promotes    ─── Sources from test-{app} stage, autoPromotionEnabled: true
       │
2. prepare-workdir             ─── Clones main → ./src, creates target branch → ./out
       │
3. copy config + helm-template ─── Same as test, but with envType=prod, envName=prod
       │
4. push-manifests              ─── Commits rendered manifests, opens PR to env/prod/{app}
       │                            (waitForPR: true — blocks until PR is merged)
       │
5. Human reviews and merges PR ─── PR targets the env/prod/{app} branch
       │
6. argocd-update               ─── Points the prod ArgoCD Application at the merge commit
       │
7. Promotion Complete          ─── Prod Application syncs and deploys
```

**Key points:**
- The prod Application is persistent (tracks the `env/prod/{app}` branch)
- PRs require human review and merge (the `git-wait-for-pr` step blocks)
- Namespace: `{appNamespace}` (the primary namespace, e.g., `frigate`, `scott-monitoring`)
- Release name: `{appName}` (e.g., `frigate`, `grafana-scott`)

## Components

### Warehouses

One warehouse per application, defined by auto-discovery from `applications/*/Chart.yaml`:

```yaml
apiVersion: kargo.akuity.io/v1alpha1
kind: Warehouse
metadata:
  name: {appName}
  namespace: homelab-apps
spec:
  subscriptions:
  - git:
      branch: main
      repoURL: https://github.com/syoder89-homelab/homelab-apps.git
      includePaths:
      - applications/{appName}     # Only triggers on changes to this app
```

There is also a special `application-generator` warehouse that watches for changes to `applications/*/Chart.yaml` and `charts/application-generator/**`.

### Stages

**Non-ephemeral stages** (`stage.yaml`) — for prod:
- Create a Kargo Stage with promotion steps that push directly to a branch (or create a PR)
- Reference an ArgoCD Application by name (`{env}-{app}`)
- The Application is persistent

**Ephemeral stages** (`stage-ephemeral.yaml`) — for test:
- Create a Kargo Stage with promotion steps that open a PR
- Reference an ArgoCD Application created by the PR-based ApplicationSet (`pr-{N}-{env}-{app}`)
- The Application is temporary — exists only while the PR is open

### PromotionTasks

Reusable tasks defined in `bootstrap/kargo/manifests/tasks.yaml`:

| Task | Purpose |
|------|---------|
| `prepare-workdir` | Clones the repo and sets up source/output working directories |
| `push-manifests` | Commits rendered manifests and optionally opens a PR |
| `verify-deployment` | Optional HTTP health check against a deployed application |

#### verify-deployment Task

Optional HTTP health check. Add between `argocd-update` and `git-merge-pr` for additional verification:

```yaml
- task:
    name: verify-deployment
  vars:
  - name: healthURL
    value: "http://test-frigate.test-frigate.svc.cluster.local:5000/api/health"
  - name: timeout
    value: "5m"
```

Configuration:
- `healthURL` (required): URL to check
- `expectedStatus` (default: `200`): Expected HTTP status code
- `timeout` (default: `5m`): How long to retry before failing
- `retries` (default: `10`): Maximum consecutive failures before giving up

### ArgoCD Applications & ApplicationSets

**Non-ephemeral** (`application.yaml`):
```yaml
# Persistent Application tracking a branch
name: prod-{appName}
source:
  path: deploy/
  targetRevision: env/prod/{appName}
syncPolicy:
  automated: { prune: true, selfHeal: true }
```

**Ephemeral** (`applicationset.yaml`):
```yaml
# ApplicationSet with PR generator — creates/deletes apps based on PR lifecycle
name: ephemeral-test-{appName}
generators:
- pullRequest:
    github:
      owner: syoder89-homelab
      repo: homelab-apps
    filters:
    - targetBranchMatch: "^env/test/{appName}$"
    requeueAfterSeconds: 60
template:
  metadata:
    name: pr-{number}-test-{appName}
  spec:
    destination:
      namespace: test-{appNamespace}
    source:
      targetRevision: "{head_sha}"     # Tracks PR head commit
```

## Race Condition Fix

### The Problem (Before Fix)

The original flow had `git-wait-for-pr` as the final step, which waited for someone to manually close the PR:

```
argocd-update → git-wait-for-pr (manual) → promotion complete
```

This created two race conditions:

1. **ApplicationSet polling delay**: After `push-manifests` opens the PR, the ApplicationSet polls GitHub every 60 seconds. `argocd-update` could run before the Application exists, causing failures.

2. **Early PR close**: If the user closed the PR while `argocd-update` was still running, the ApplicationSet would delete the Application, causing `argocd-update` to fail. Even if `argocd-update` had already completed, the ongoing health checks registered by `argocd-update` would immediately discover the Application was deleted, potentially affecting Stage health reporting.

### The Fix

Replace `git-wait-for-pr` with automated verification and PR auto-merge:

```
argocd-update (retry: 10, timeout: 10m) → git-merge-pr → promotion complete
```

**How this eliminates both race conditions:**

1. **ApplicationSet delay**: The `argocd-update` step now has `errorThreshold: 10` and `timeout: 10m`, giving the ApplicationSet plenty of time to detect the PR and create the Application (only needs 60 seconds max).

2. **Early PR close**: The PR is only merged programmatically AFTER `argocd-update` confirms the Application is synced and healthy. There is no manual step where someone could close the PR prematurely.

**Why `git-merge-pr` instead of closing?** Kargo handles git credentials natively for merge operations, so there's no need for raw GitHub API calls or PAT secret management in the step config. The `env/test/{appName}` branch accumulates merged manifests, but this is harmless — each new test promotion overwrites it.

### What Changed

| File | Change |
|------|--------|
| `charts/application-generator/templates/stage-ephemeral.yaml` | Replaced `git-wait-for-pr` with `git-merge-pr` step; increased `argocd-update` retry/timeout |
| `bootstrap/kargo/manifests/tasks.yaml` | Added `verify-deployment` PromotionTask |

## Verification Strategy

The verification strategy has three layers:

### Layer 1: ArgoCD Sync + Health (Always Active)

The `argocd-update` step waits for:
- ArgoCD Application to sync to the desired commit
- All resources to report as `Healthy` (pod readiness probes pass, services have endpoints, etc.)
- The 10-minute timeout handles slow image pulls and initializations

This catches:
- Manifest errors (invalid YAML, missing resources)
- Image pull failures
- Pods that fail to start
- Readiness probe failures

### Layer 2: HTTP Health Check (Optional)

For applications with health endpoints, add the `verify-deployment` task between `argocd-update` and `git-merge-pr`. This catches:
- Application-level failures not visible to Kubernetes readiness probes
- Dependency issues (database not reachable, config errors)
- Startup race conditions within the application

### Layer 3: Soak Time (Future Enhancement)

For catching delayed failures (e.g., memory leaks, CrashLoopBackOff after initial success), consider:
- Using `requiredSoakTime` on prod's `requestedFreight` to require freight to be verified in test for a minimum duration before promoting to prod
- Adding Stage-level verification with `AnalysisTemplate` (requires Argo Rollouts)

## Adding App-Specific Health Checks

To add HTTP health checks for a specific application, modify its ephemeral stage template. Since the stage-ephemeral.yaml is a generator that creates stages for ALL apps, you have two options:

### Option 1: Add to Chart.yaml (Recommended)

Add a custom `healthCheck` field to the application's `Chart.yaml`:

```yaml
# applications/frigate/Chart.yaml
apiVersion: v2
name: frigate
healthCheck:
  url: "http://test-frigate.test-frigate.svc.cluster.local:5000/api/health"
  timeout: "3m"
```

Then update `stage-ephemeral.yaml` to conditionally include the verify-deployment task (between `argocd-update` and `git-merge-pr`):

```yaml
{{- if $app.healthCheck }}
      - task:
          name: verify-deployment
        if: {{`${{ outputs.promotion.prNumber != "" }}`}}
        vars:
        - name: healthURL
          value: "{{ $app.healthCheck.url }}"
        - name: timeout
          value: "{{ $app.healthCheck.timeout | default "5m" }}"
{{- end }}
```

### Option 2: Per-Environment Config

Add health check configuration to the application's environment config:

```yaml
# applications/frigate/config/env-types/test/healthcheck.yaml
healthCheck:
  enabled: true
  url: "http://test-{{ .Values.appName }}.test-{{ .Values.appName }}.svc.cluster.local:5000/api/health"
```

## Troubleshooting

### Common Issues

#### Promotion stuck at argocd-update

The `argocd-update` step is waiting for the ApplicationSet to detect the PR and create the Application.

**Diagnosis:**
```bash
# Check if the PR was created
kubectl get promotions -n homelab-apps

# Check ApplicationSet status
kubectl get applicationsets -n argocd

# Check if the Application was created
kubectl get applications -n argocd | grep "pr-.*-test-"
```

**Fix:** This should resolve automatically within 60 seconds (the ApplicationSet poll interval). The step has a 10-minute timeout. If it consistently times out, check:
- GitHub PAT permissions (needs repo access)
- ApplicationSet controller logs
- Network connectivity to GitHub API

#### git-merge-pr step fails

The PR may have merge conflicts or the GitHub credentials may be misconfigured.

**Diagnosis:**
```bash
# Check Kargo promotion status for error details
kubectl describe promotion <promotion-name> -n homelab-apps

# Verify git credentials secret
kubectl get secret kargo-github-pat -n homelab-apps
```

**Fix:** Kargo uses its configured git credentials (same ones used for `git-push` and `git-open-pr`) for merge operations. If merge fails due to conflicts, check whether the `env/test/{appName}` branch has diverged unexpectedly. You can delete the branch and let the next promotion recreate it.

#### Test namespace not cleaned up

After the PR is merged, the ApplicationSet should delete the Application and ArgoCD should prune the namespace. If resources remain:

```bash
# Check if the Application was deleted
kubectl get applications -n argocd | grep test

# Force cleanup
kubectl delete namespace test-{appName}
```

#### Prod not promoting after test succeeds

Check that the test freight is verified:

```bash
# Check freight verification status
kubectl get freight -n homelab-apps

# Check prod stage
kubectl get stages -n homelab-apps
```

The prod stage sources from `test-{appName}`. If the test promotion completed but freight isn't marked verified, check the Kargo controller logs.

### Viewing Promotion Logs

```bash
# List recent promotions
kubectl get promotions -n homelab-apps --sort-by=.metadata.creationTimestamp

# Describe a specific promotion for step details
kubectl describe promotion <promotion-name> -n homelab-apps

# Watch stages
kubectl get stages -n homelab-apps -w
```
