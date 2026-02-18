# Check for Application Updates

Check all applications in this repository for available Helm chart version updates and produce an update report.

## Instructions

1. **Read every `applications/*/Chart.yaml`** file and extract the current `appVersion` and `dependencies[].version`, `dependencies[].name`, and `dependencies[].repository` for each application.

2. **Skip applications that don't have upstream dependencies** (e.g., `kargo-config` has no `dependencies` section — it is a config-only chart).

3. **For each application with a remote Helm repository** (`https://...`), run:
   ```bash
   helm repo add <temp-name> <repository-url> 2>/dev/null; helm repo update <temp-name> 2>/dev/null
   helm search repo <temp-name>/<chart-name> --versions -o json 2>/dev/null | head -50
   ```
   Use a unique temp repo name per repository (e.g., `update-check-grafana`). Parse the JSON output to find the latest stable version available.

3b. **For applications with local/vendored charts** (`repository: "file://..."`), check for newer container images instead:
   - Read the vendored chart's `values.yaml` (e.g., `applications/{app}/charts/{chart}/values.yaml`) to find the default `image.repository` and `image.tag`.
   - Read all environment config override files (`applications/{app}/config/envs/*/values.yaml` and `applications/{app}/values.yaml`) to find any `image.tag` overrides — the highest override is the actually-deployed version.
   - Determine the image source. For GitHub Container Registry images (`ghcr.io/{owner}/{repo}`):
     ```bash
     curl -s "https://api.github.com/repos/{owner}/{repo}/releases?per_page=10"
     ```
     Parse the JSON to find the latest stable release (where `prerelease` is `false`). Strip the leading `v` from tag names when comparing (e.g., `v0.16.4` → `0.16.4`).
   - For Docker Hub images, use:
     ```bash
     curl -s "https://hub.docker.com/v2/repositories/{owner}/{repo}/tags?page_size=20&ordering=last_updated"
     ```
   - Compare the actually-deployed image tag against the latest stable release.

4. **Compare the current pinned version** in `Chart.yaml` against the latest available version. Classify each result:
   - **Up to date**: current version matches latest
   - **Patch update**: only patch version differs (e.g., `4.12.0` → `4.12.5`)
   - **Minor update**: minor version differs (e.g., `10.4.1` → `10.5.15`)
   - **Major update**: major version differs (e.g., `0.9.3` → `0.31.0`)

5. **Handle multi-instance apps** (apps sharing the same upstream chart, like `grafana-scott`/`grafana-taylor` or `victoria-metrics-scott`/`victoria-metrics-taylor`). Group them together in the report since they share a dependency.

6. **Produce a summary report** printed to stdout in this markdown format:

   ```
   # Application Update Check — <today's date>

   ## Summary
   - X applications checked
   - Y updates available (N major, N minor, N patch)
   - Z applications up to date
   - N applications skipped (local/no dependency)

   ## Chart Updates Available

   ### <App Name(s)> — <severity emoji> <Major/Minor/Patch> Update
   - **Chart**: <dependency chart name>
   - **Current Version**: <version>
   - **Latest Version**: <version>
   - **Repository**: <url>
   - **Instances**: <list of app directories using this chart>

   ## Image Updates Available (Local Charts)

   ### <App Name> — <severity emoji> <Major/Minor/Patch> Update
   - **Image**: <image repository>
   - **Chart Default Tag**: <tag from vendored chart values.yaml>
   - **Deployed Tag**: <tag from env config override, or chart default if no override>
   - **Latest Stable Release**: <tag>
   - **Latest Pre-release**: <tag> (if any)
   - **Source**: <GitHub releases URL or Docker Hub URL>

   ## Up to Date
   - <app>: <version>

   ## Skipped
   - <app>: <reason>
   ```

   Use these severity emojis: 🔴 Major, 🟡 Minor, 🟢 Patch.

7. **Clean up** the temporary helm repos:
   ```bash
   helm repo remove <temp-name> 2>/dev/null
   ```

8. **If the user provided the argument `$ARGUMENTS`**, treat it as a filter — only check the application(s) matching that name. If no argument is provided, check all applications.

## Important Notes

- Do NOT modify any files — this is a read-only check.
- Chart versions use exact pins (no semver ranges). The `dependencies[].version` and `appVersion` should always match for upstream charts.
- The `version` field in `Chart.yaml` is the umbrella chart version (usually `"0.0.1"`) — ignore it for update checking.
- If `helm search repo` fails or returns no results for a repo, note it as "Unable to check" rather than failing the entire report.
- For local charts, the **actually-deployed image tag** may differ from the vendored chart default — always check environment config overrides. The config hierarchy is: vendored chart `values.yaml` → umbrella `values.yaml` → `config/envs/{env}/values.yaml` (later wins).
- When comparing image tags, ignore pre-release versions unless the user specifically asks for them. Only consider stable releases (GitHub: `prerelease: false`).
- Strip leading `v` prefixes when comparing version strings (e.g., GitHub tag `v0.16.4` equals image tag `0.16.4`).
