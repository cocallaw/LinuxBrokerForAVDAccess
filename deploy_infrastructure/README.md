# deploy_infrastructure/ — Legacy & Standalone Scripts

> **⚠️ Note:** The primary deployment workflow is in [`deploy/`](../deploy/).
> The main orchestrator script `deploy/Deploy-LinuxBroker.ps1` now handles all
> infrastructure provisioning, permission assignment, and application deployment
> in a single flow.

## Relationship to `deploy/`

| Directory | Purpose | Status |
|-----------|---------|--------|
| `deploy/` | **Primary.** Full deployment lifecycle — prerequisites, infrastructure, apps, cleanup. | ✅ Active |
| `deploy_infrastructure/` | **Supplementary.** Standalone utility scripts for specific tasks (e.g., manual permission fixes). | ⚠️ Use only when needed |

## Scripts in This Directory

### `Assign-AppRoleToFunctionApp.ps1`
**Status:** Maintained for standalone use only.

Assigns the API app role to the Function App's managed identity. This functionality
is now **automatically handled** by `deploy/Deploy-LinuxBroker.ps1` during deployment.

**When to use this script directly:**
- If the automated permission step failed during deployment
- If you need to re-assign permissions without re-deploying
- If you're troubleshooting Function App ↔ API authentication

**Preferred alternative:**
```powershell
# Re-run the main deployment — it will skip already-succeeded steps
.\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId <sub-id> -ResourceGroupName <rg> -Location <location>
```

## Recommended Workflow

Use the scripts in `deploy/` for all standard operations:

```powershell
# 1. Check prerequisites
.\deploy\Check-Prerequisites.ps1

# 2. (Optional) Set up Azure AD app registrations
.\deploy\Setup-AppRegistrations.ps1 -TenantId <tenant-id>

# 3. Deploy everything
.\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId <sub-id> -ResourceGroupName <rg> -Location <location>

# 4. Update environment variables
.\deploy\Update-EnvironmentVariables.ps1 -SubscriptionId <sub-id> -ResourceGroupName <rg>
```
