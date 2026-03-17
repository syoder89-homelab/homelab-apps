#!/bin/bash
#
# Update the ArgoCD GKE cluster secret in 1Password.
#
# Pulls cluster_endpoint and cluster_ca_certificate from GKE terraform outputs
# and creates/updates the 1Password item used by the OnePasswordItem manifest.
#
# Prerequisites:
#   - op CLI authenticated (op signin)
#   - terraform state accessible in homelab-infra/terraform/gke
#
# Usage:
#   ./scripts/update-gke-cluster-secret.sh [--gke-tf-dir PATH]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults — assume homelab-infra is a sibling of homelab-apps
GKE_TF_DIR="${SCRIPT_DIR}/../../homelab-infra/terraform/gke"
VAULT="homelab"
ITEM_TITLE="argocd-gke-staging-cluster"
CLUSTER_NAME="gke-staging"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gke-tf-dir)
      GKE_TF_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--gke-tf-dir PATH]"
      echo ""
      echo "Fetches GKE cluster info from terraform outputs and creates/updates"
      echo "the 1Password item '${ITEM_TITLE}' in the '${VAULT}' vault."
      echo ""
      echo "Options:"
      echo "  --gke-tf-dir PATH  Path to homelab-infra/terraform/gke (default: sibling repo)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Resolve to absolute path
GKE_TF_DIR="$(cd "$GKE_TF_DIR" && pwd)"

# --- Validate prerequisites ---

for cmd in op terraform jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: '$cmd' is required but not found in PATH" >&2
    exit 1
  fi
done

if [[ ! -f "${GKE_TF_DIR}/main.tf" ]]; then
  echo "Error: GKE terraform directory not found at ${GKE_TF_DIR}" >&2
  echo "Use --gke-tf-dir to specify the correct path" >&2
  exit 1
fi

# --- Fetch terraform outputs ---

echo "Fetching terraform outputs from ${GKE_TF_DIR}..."

ENDPOINT=$(terraform -chdir="$GKE_TF_DIR" output -raw cluster_endpoint)
CA_CERT=$(terraform -chdir="$GKE_TF_DIR" output -raw cluster_ca_certificate)

if [[ -z "$ENDPOINT" || -z "$CA_CERT" ]]; then
  echo "Error: Failed to read terraform outputs (cluster_endpoint, cluster_ca_certificate)" >&2
  echo "Make sure 'terraform init' has been run in ${GKE_TF_DIR}" >&2
  exit 1
fi

SERVER="https://${ENDPOINT}"

echo "  Cluster endpoint: ${SERVER}"
echo "  CA certificate:   (${#CA_CERT} chars, base64)"

# --- Build ArgoCD config JSON ---

CONFIG=$(jq -n \
  --arg ca_data "$CA_CERT" \
  '{
    execProviderConfig: {
      command: "argocd-k8s-auth",
      args: ["gcp"],
      apiVersion: "client.authentication.k8s.io/v1beta1",
      env: {
        "GOOGLE_APPLICATION_CREDENTIALS": "/var/run/secrets/gcp/credential-config.json"
      }
    },
    tlsClientConfig: {
      insecure: false,
      caData: $ca_data
    }
  }')

# --- Create or update 1Password item ---

echo "Updating 1Password item '${ITEM_TITLE}' in vault '${VAULT}'..."

if op item get "$ITEM_TITLE" --vault="$VAULT" &>/dev/null; then
  op item edit "$ITEM_TITLE" \
    --vault="$VAULT" \
    "server=${SERVER}" \
    "name=${CLUSTER_NAME}" \
    "config=${CONFIG}"
  echo "Updated existing item."
else
  op item create \
    --category="Secure Note" \
    --vault="$VAULT" \
    --title="$ITEM_TITLE" \
    "server=${SERVER}" \
    "name=${CLUSTER_NAME}" \
    "config=${CONFIG}"
  echo "Created new item."
fi

echo ""
echo "Done. The 1Password Connect operator will sync this to the"
echo "gke-staging-cluster Secret in the argocd namespace."
