# GitHub Actions Deployment — One-Time Setup Guide

This guide walks you through the one-time setup required before GitHub Actions workflows can deploy the Linux Broker for AVD Access solution. Budget **~30 minutes** for the full setup.

> **This is an alternative deployment method.** You can still deploy entirely via PowerShell — see [DEPLOYMENT.md](../DEPLOYMENT.md) for the manual path.

---

## Overview

The GitHub Actions deployment uses **OIDC federated credentials** for authentication — no long-lived secrets are stored in GitHub. The architecture uses 4 separate workflows:

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy-app-registrations.yml` | Manual (`workflow_dispatch`) | Creates Azure AD app registrations and app roles |
| `deploy-infrastructure.yml` | Push to `main` / Manual | Deploys Bicep infrastructure, database schema, app configuration, and runs validation |
| `deploy-vms.yml` | Manual (`workflow_dispatch`) | Deploys AVD and/or Linux VMs |
| `cleanup.yml` | Manual (`workflow_dispatch`) | Tears down resources (for dev/test environments) |

---

## Step 1: Create an Azure AD App Registration for GitHub Actions

This app registration is used by GitHub Actions to authenticate to Azure via OIDC. It is **separate** from the Linux Broker API app registration.

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "<YOUR_SUBSCRIPTION_ID>"

# Create the app registration
az ad app create --display-name "GitHub Actions - LinuxBrokerForAVDAccess"
```

Note the `appId` from the output — this is your `AZURE_CLIENT_ID`.

### Create a Service Principal

```bash
az ad sp create --id "<AZURE_CLIENT_ID>"
```

---

## Step 2: Configure OIDC Federated Credentials

Federated credentials allow GitHub Actions to authenticate without storing secrets. You need one credential per branch/environment that will trigger workflows.

### For the `main` branch (infrastructure deployments):

```bash
az ad app federated-credential create --id "<AZURE_CLIENT_ID>" --parameters '{
  "name": "github-actions-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions - main branch deployments"
}'
```

### For the `production` environment (if using GitHub Environments):

```bash
az ad app federated-credential create --id "<AZURE_CLIENT_ID>" --parameters '{
  "name": "github-actions-production",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>:environment:production",
  "audiences": ["api://AzureADTokenExchange"],
  "description": "GitHub Actions - production environment deployments"
}'
```

> **Replace** `<YOUR_GITHUB_ORG>/<YOUR_REPO_NAME>` with your actual GitHub repository path (e.g., `microsoft/LinuxBrokerForAVDAccess`).

### Verify federated credentials:

```bash
az ad app federated-credential list --id "<AZURE_CLIENT_ID>" --query "[].{name:name, subject:subject}" -o table
```

---

## Step 3: Assign Azure RBAC Roles

The GitHub Actions service principal needs permissions to deploy resources. Assign roles at the subscription or resource group level:

### Option A: Scope to a Resource Group (recommended for production)

```bash
# Create the resource group first if it doesn't exist
az group create --name "<RESOURCE_GROUP>" --location "<REGION>"

# Assign Contributor (deploy resources)
az role assignment create \
  --assignee "<AZURE_CLIENT_ID>" \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>"

# Assign User Access Administrator (manage RBAC / managed identities)
az role assignment create \
  --assignee "<AZURE_CLIENT_ID>" \
  --role "User Access Administrator" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>/resourceGroups/<RESOURCE_GROUP>"
```

### Option B: Scope to the Subscription (simpler, broader access)

```bash
az role assignment create \
  --assignee "<AZURE_CLIENT_ID>" \
  --role "Contributor" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>"

az role assignment create \
  --assignee "<AZURE_CLIENT_ID>" \
  --role "User Access Administrator" \
  --scope "/subscriptions/<SUBSCRIPTION_ID>"
```

### Verify role assignments:

```bash
az role assignment list --assignee "<AZURE_CLIENT_ID>" --output table
```

---

## Step 4: Configure GitHub Repository Secrets

Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

Add **all 9 secrets** listed below:

| Secret Name | Description | Where to Get It |
|-------------|-------------|-----------------|
| `AZURE_CLIENT_ID` | App ID of the GitHub Actions app registration | Output from Step 1 (`az ad app create`) |
| `AZURE_TENANT_ID` | Your Azure AD tenant ID | Azure Portal → Azure Active Directory → Overview |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID | Azure Portal → Subscriptions |
| `API_CLIENT_ID` | App ID of the **Linux Broker API** app registration | Output from `deploy/Setup-AppRegistrations.ps1` or `app-registration-config.json` |
| `AUTH_SECRET` | Authentication secret for the API app registration | Generated during app registration setup (Step 5 below) |
| `SQL_PASSWORD` | Password for the Azure SQL admin account | Choose a strong password (min 12 chars, mixed case + numbers + symbols) |
| `RHEL_ORG_ID` | Red Hat subscription org ID | Red Hat Customer Portal → Subscriptions (leave empty if not using RHEL) |
| `RHEL_ACTIVATION_KEY` | Red Hat subscription activation key | Red Hat Customer Portal → Activation Keys (leave empty if not using RHEL) |
| `RESOURCE_GROUP` | Target Azure resource group name | Your chosen name (e.g., `rg-linuxbroker-prod`) |

### Using the GitHub CLI (alternative):

```bash
# Set secrets via CLI (you'll be prompted for the value)
gh secret set AZURE_CLIENT_ID
gh secret set AZURE_TENANT_ID
gh secret set AZURE_SUBSCRIPTION_ID
gh secret set API_CLIENT_ID
gh secret set AUTH_SECRET
gh secret set SQL_PASSWORD
gh secret set RHEL_ORG_ID
gh secret set RHEL_ACTIVATION_KEY
gh secret set RESOURCE_GROUP
```

---

## Step 5: Set Up App Registrations (Before First Workflow Run)

The **Linux Broker API** app registration must exist before the infrastructure workflows can deploy. You have two options:

### Option A: Run the `deploy-app-registrations.yml` workflow

1. Go to **Actions** → **Deploy App Registrations** → **Run workflow**
2. The workflow creates the API app registration, app roles, and security groups
3. Note the outputs — you'll need `API_CLIENT_ID` and `AUTH_SECRET` for the GitHub secrets above
4. Update those two secrets in GitHub after the workflow completes

### Option B: Run the manual equivalent

```powershell
.\deploy\Setup-AppRegistrations.ps1 -TenantId "<tenant-id>"
```

This creates the same resources and outputs `app-registration-config.json` with the values you need. Copy `API_CLIENT_ID` and `AUTH_SECRET` to your GitHub secrets.

> **Important:** Whichever option you choose, do it **before** running the infrastructure deployment workflow. The Bicep templates and app configuration steps depend on these app registrations existing.

---

## Step 6: Configure GitHub Environments (Recommended)

GitHub Environments add protection rules — required reviewers, wait timers, and deployment logs.

1. Go to your repository → **Settings** → **Environments** → **New environment**
2. Create an environment named **`production`**
3. Configure protection rules:
   - ✅ **Required reviewers** — Add 1–2 team members who must approve deployments
   - ✅ **Wait timer** — Set to 5 minutes (gives time to cancel accidental deployments)
   - ✅ **Deployment branches** — Restrict to `main` branch only

> The infrastructure and VM deployment workflows reference the `production` environment. Creating it with protection rules ensures deployments are reviewed before executing.

---

## Step 7: Verify the OIDC Connection

Before running a full deployment, verify that GitHub Actions can authenticate to Azure.

### Quick verification workflow

Create a test run using the GitHub CLI or the Actions UI:

1. Go to **Actions** → pick any workflow with `workflow_dispatch` → **Run workflow**
2. Check the run logs for the `azure/login` step
3. A successful login confirms OIDC is working

### Manual verification (from your local machine)

Verify the app registration and service principal are correctly configured:

```bash
# Check the app registration exists
az ad app show --id "<AZURE_CLIENT_ID>" --query "{appId:appId, displayName:displayName}" -o table

# Check the service principal exists
az ad sp show --id "<AZURE_CLIENT_ID>" --query "{appId:appId, displayName:displayName}" -o table

# Check federated credentials are configured
az ad app federated-credential list --id "<AZURE_CLIENT_ID>" -o table

# Check role assignments
az role assignment list --assignee "<AZURE_CLIENT_ID>" \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

All four commands should return results. If any fail, revisit the corresponding step above.

---

## Deployment Flow (After Setup)

Once the one-time setup is complete, the deployment flow is:

```
1. deploy-app-registrations.yml  →  One-time (or when app roles change)
         ↓
2. deploy-infrastructure.yml     →  Deploys Bicep + DB + config + validates
         ↓
3. deploy-vms.yml                →  Deploys AVD and/or Linux VMs (optional, manual)
         ↓
4. cleanup.yml                   →  Tears down resources (dev/test only)
```

The infrastructure workflow (`deploy-infrastructure.yml`) handles:
- Bicep template deployment (App Service, SQL, Key Vault, Functions, etc.)
- Database schema deployment (all tables, stored procedures, indexes)
- App Service environment variable configuration
- Post-deployment validation checks

---

## Troubleshooting

### "AADSTS70021: No matching federated identity record found"

The `subject` claim in your federated credential doesn't match. Common causes:
- Wrong repository name in the subject (check org/repo casing)
- Workflow triggered from a branch not covered by federated credentials
- Using `environment:` in the workflow but only configured `ref:refs/heads/main`

**Fix:** Add a federated credential matching the exact trigger context (see Step 2).

### "The client does not have authorization to perform action"

The service principal is missing required RBAC roles.

**Fix:** Re-run the role assignment commands from Step 3. Verify with:
```bash
az role assignment list --assignee "<AZURE_CLIENT_ID>" --output table
```

### "Secret not found" errors in workflow logs

A required GitHub secret is missing or misnamed.

**Fix:** Go to Settings → Secrets → verify all 9 secrets exist with correct names (case-sensitive).

### App registration workflow fails with "Insufficient privileges"

The GitHub Actions service principal needs **Microsoft Graph** `Application.ReadWrite.All` permission to create app registrations programmatically.

**Alternative:** Run app registration setup manually (Step 5, Option B) and just store the outputs as GitHub secrets.

---

## Security Notes

- **No long-lived secrets in GitHub.** OIDC federated credentials use short-lived tokens exchanged at runtime.
- **Least privilege.** Scope RBAC roles to the resource group, not the subscription, in production.
- **Environment protection.** Use GitHub Environments with required reviewers for production deployments.
- **Secret rotation.** `AUTH_SECRET` and `SQL_PASSWORD` should be rotated periodically. Update the GitHub secrets and redeploy.
- **Audit trail.** All deployments are logged in GitHub Actions run history with full traceability.

---

## Related Documentation

| Document | Purpose |
|----------|---------|
| [DEPLOYMENT.md](../DEPLOYMENT.md) | Manual deployment guide (PowerShell path) |
| [CONFIGURATION.md](../CONFIGURATION.md) | Environment variable reference |
| [README.md](../README.md) | Architecture overview and RBAC model |
