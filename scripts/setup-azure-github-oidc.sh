#!/usr/bin/env bash
set -euo pipefail

# Setup Azure OIDC authentication for GitHub Actions deployments.
# Creates an Entra ID app registration, service principal, federated credential,
# and configures GitHub repository secrets/variables.
#
# Prerequisites: az CLI (logged in), gh CLI (authenticated)
#
# Usage:
#   ./scripts/setup-azure-oidc.sh <owner/repo> <azure-region> <resource-group> [environment]

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <owner/repo> <azure-region> <resource-group> [environment]"
  echo "Example: $0 vivaladan/AspireApp eastus aspireapp-rg production"
  exit 1
fi

GITHUB_REPO="$1"
LOCATION="$2"
RESOURCE_GROUP="$3"
ENVIRONMENT="${4:-production}"
APP_NAME="${GITHUB_REPO#*/}-GitHub-Deploy"

# Validate owner/repo format
[[ "$GITHUB_REPO" == */* ]] || { echo "Error: Use owner/repo format (e.g. owner/repo)"; exit 1; }

# Verify az and gh are authenticated (also checks they're installed)
az account show -o none 2>/dev/null || { echo "Error: Run 'az login' first."; exit 1; }
gh auth status &>/dev/null || { echo "Error: Run 'gh auth login' first."; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "=== Azure OIDC Setup for GitHub Actions ==="
echo ""
echo "  Subscription:   $SUBSCRIPTION_ID"
echo "  Tenant:         $TENANT_ID"
echo "  Repository:     $GITHUB_REPO"
echo "  Location:       $LOCATION"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Environment:    $ENVIRONMENT"
echo "  App Name:       $APP_NAME"
echo ""
read -rp "Proceed? (y/N) " confirm
[[ "$confirm" == [yY] ]] || { echo "Aborted."; exit 0; }

echo ""
echo "--- Creating Entra ID app registration..."
APP_ID=$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)
if [[ -z "$APP_ID" ]]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  echo "  Created app: $APP_ID"
else
  echo "  Found existing app: $APP_ID"
fi

echo "--- Creating service principal..."
az ad sp create --id "$APP_ID" --output none 2>/dev/null || true

echo "--- Creating resource group (if needed)..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none

echo "--- Assigning Owner role (scoped to resource group)..."
az role assignment create \
  --assignee "$APP_ID" \
  --role Owner \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP" \
  --output none

echo "--- Creating federated identity credentials..."
CRED_MAIN=$(cat <<EOF
{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions deploy from main branch"
}
EOF
)
az ad app federated-credential create --id "$APP_ID" --parameters "$CRED_MAIN" --output none 2>/dev/null || true

CRED_ENV=$(cat <<EOF
{
  "name": "github-actions-environment",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${GITHUB_REPO}:environment:${ENVIRONMENT}",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions deploy via ${ENVIRONMENT} environment"
}
EOF
)
az ad app federated-credential create --id "$APP_ID" --parameters "$CRED_ENV" --output none 2>/dev/null || true

echo "--- Configuring GitHub secrets and variables..."
gh secret set AZURE_CLIENT_ID --repo "$GITHUB_REPO" --body "$APP_ID"
gh secret set AZURE_TENANT_ID --repo "$GITHUB_REPO" --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --repo "$GITHUB_REPO" --body "$SUBSCRIPTION_ID"
gh variable set AZURE_LOCATION --repo "$GITHUB_REPO" --body "$LOCATION"
gh variable set AZURE_RESOURCE_GROUP --repo "$GITHUB_REPO" --body "$RESOURCE_GROUP"
gh variable set AZURE_ENVIRONMENT --repo "$GITHUB_REPO" --body "$ENVIRONMENT"

echo ""
echo "=== Setup complete ==="
echo "  App registration: $APP_NAME ($APP_ID)"
echo "  Role scope:       /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
echo "  Environment:      $ENVIRONMENT"