# Deployment Guide — Linux Broker for AVD Access

This is the end-to-end guide for deploying the Linux Broker for AVD Access solution. Follow each step in order — later steps depend on outputs from earlier ones.

> **Quick reference:** For environment variable details, see [CONFIGURATION.md](CONFIGURATION.md).
> For database schema details, see [sql_queries/README.md](sql_queries/README.md).

---

## Prerequisites

### Azure Requirements

- **Azure subscription** with Owner or Contributor + User Access Administrator access
- **Azure AD permissions** to create App Registrations and Security Groups
- **Resource providers** enabled: `Microsoft.Sql`, `Microsoft.Web`, `Microsoft.KeyVault`, `Microsoft.DesktopVirtualization`

### Tools

| Tool | Minimum Version | Install |
|------|----------------|---------|
| PowerShell | 7+ | [Install PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell) |
| Azure CLI | 2.50+ | [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Az PowerShell Module | Latest | `Install-Module -Name Az -Force` |
| Git | Any | [Install Git](https://git-scm.com/downloads) |
| sqlcmd (optional) | Any | Only if deploying database manually |

### Information to Gather

Before starting, collect the following:

| Item | Where to Find It |
|------|------------------|
| Azure Subscription ID | Azure Portal → Subscriptions |
| Azure AD Tenant ID | Azure Portal → Azure Active Directory → Overview |
| Target Resource Group name | Choose a name (e.g., `rg-linuxbroker-prod`) |
| Target Azure Region | Choose a region (e.g., `eastus`) |
| RHEL Org ID & Activation Key | Red Hat Customer Portal (only if using RHEL hosts) |
| NFS Share path | Your NFS infrastructure (for user profile storage) |

---

## Step 0: Pre-Deployment Readiness Check

Run the pre-flight validation script to verify your environment is ready:

```powershell
.\deploy\Test-DeploymentReadiness.ps1 -SubscriptionId "<subscription-id>" `
                                       -ResourceGroupName "<resource-group>"
```

This checks:
- Azure CLI and PowerShell module versions
- Azure subscription access and permissions
- Required resource provider registrations
- Existing resource group state

Fix any failures before proceeding. The script outputs a pass/fail table showing exactly what needs attention.

---

## Step 1: Clone the Repository

```powershell
git clone https://github.com/microsoft/LinuxBrokerForAVDAccess.git
cd LinuxBrokerForAVDAccess
```

---

## Step 2: Check Prerequisites

```powershell
.\deploy\Check-Prerequisites.ps1
```

This verifies that required tools (Azure CLI, PowerShell modules) are installed and you are authenticated.

---

## Step 3: Set Up Azure AD App Registrations

```powershell
.\deploy\Setup-AppRegistrations.ps1 -TenantId "<tenant-id>"
```

This creates:
- **API App Registration** — produces `CLIENT_ID`, `TENANT_ID`, and the authentication secret
- **App Roles** — `AVDHost`, `LinuxHost`, `ScheduledTask`, `User`, `FullAccess`
- **Security Groups** — `LinuxBroker-AVDHost-VMs`, `LinuxBroker-LinuxHost-VMs`

The script outputs `app-registration-config.json` with the values you'll need in later steps.

> **Save these values.** The `CLIENT_ID` is used by almost every component.

---

## Step 4: Deploy Infrastructure

### Option A: Automated (Recommended)

**Core infrastructure only:**
```powershell
.\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId "<subscription-id>" `
                                 -ResourceGroupName "<resource-group>" `
                                 -Location "<region>"
```

**With VMs** (using a configuration file):
```powershell
# Copy and customize the example config
Copy-Item ".\vm-deployment-config.example.json" ".\my-vm-config.json"
# Edit my-vm-config.json with your settings

.\deploy\Deploy-LinuxBroker.ps1 -SubscriptionId "<subscription-id>" `
                                 -ResourceGroupName "<resource-group>" `
                                 -Location "<region>" `
                                 -VMConfigPath ".\my-vm-config.json"
```

See `configs/` for additional VM configuration examples:
- `configs/linux-only-deployment.json` — Linux VMs only
- `configs/avd-only-deployment.json` — AVD hosts only
- `configs/full-deployment.json` — Production example with both

The script is **idempotent** — safe to re-run. It checks for existing deployments and skips completed steps.

### Option B: Bicep Direct

```bash
az deployment group create \
  --resource-group <resource-group> \
  --template-file bicep/main.bicep \
  --parameters @bicep/main.bicepparam
```

### What Gets Created

| Resource | Purpose |
|----------|---------|
| App Service (API) | Broker API |
| App Service (Frontend) | Service Management Portal |
| Azure SQL Database | VM and scaling data |
| Function App | Automated scaling tasks |
| Key Vault | SSH keys and DB password |
| Application Insights | Logging and monitoring |
| Managed Identities | Component authentication |

> **Note the outputs.** You'll need the App Service URL, SQL Server hostname, database name, and Key Vault URI for the next steps.

---

## Step 5: Deploy Database Schema

Use the automated database deployment script:

```powershell
# SQL Authentication
cd sql_queries
.\Deploy-Database.ps1 -ServerName "<server>.database.windows.net" `
                       -DatabaseName "linuxbroker" `
                       -Username "<sql-admin>" `
                       -Password "<password>"

# Or Azure AD Authentication
.\Deploy-Database.ps1 -ServerName "<server>.database.windows.net" `
                       -DatabaseName "linuxbroker" `
                       -UseAzureAD
cd ..
```

This deploys all tables, 19 stored procedures, and performance indexes in the correct order. Each script is **idempotent** — safe to run multiple times.

> Optionally, validate the schema afterward:
> ```bash
> sqlcmd -S <server> -d <database> -U <user> -P <pass> -i sql_queries/test_schema.sql
> ```

For manual deployment or troubleshooting, see [sql_queries/README.md](sql_queries/README.md).

---

## Step 6: Configure Environment Variables

### 6a: Copy and Fill Environment Templates

```powershell
# API and backend components
Copy-Item ".env.template" ".env"

# Frontend portal
Copy-Item "front_end/.env.template" "front_end/.env"
```

Fill in the values using outputs from Steps 3–5. See [CONFIGURATION.md](CONFIGURATION.md) for the complete variable reference with sources and dependencies.

### 6b: API App Service Settings

Set all 17 required environment variables on the API App Service. You can do this via the Azure Portal (App Service → Configuration → Application Settings) or via CLI:

```bash
az webapp config appsettings set --name <api-app-name> --resource-group <rg> --settings \
  TENANT_ID="<from Step 3>" \
  CLIENT_ID="<from Step 3>" \
  MICROSOFT_PROVIDER_AUTHENTICATION_SECRET="<from Step 3>" \
  VM_SUBSCRIPTION_ID="<your subscription id>" \
  VM_RESOURCE_GROUP="<resource group with Linux VMs>" \
  AVD_HOST_GROUP_ID="<from Step 3>" \
  LINUX_HOST_GROUP_ID="<from Step 3>" \
  LINUX_HOST_ADMIN_LOGIN_NAME="<admin username on Linux VMs>" \
  GRAPH_API_ENDPOINT="https://graph.microsoft.com/.default" \
  DOMAIN_NAME="<your Azure AD domain>" \
  VAULT_URL="<from Step 4>" \
  KEY_NAME="<SSH PEM key secret name>" \
  DB_SERVER="<from Step 4>" \
  DB_DATABASE="<from Step 4>" \
  DB_USERNAME="<SQL admin username>" \
  DB_PASSWORD_NAME="<DB password secret name in Key Vault>"
```

The API validates all required variables at startup. If any are missing, it logs exactly which ones and exits — check the App Service log stream.

### 6c: Azure Functions Settings

```bash
az functionapp config appsettings set --name <func-app-name> --resource-group <rg> --settings \
  API_CLIENT_ID="<CLIENT_ID from Step 3>" \
  API_URL="https://<api-app-name>.azurewebsites.net/api"
```

### 6d: Frontend Portal Settings

Set the 6 required variables from `front_end/.env.template` on the frontend App Service. The frontend also validates at startup and will exit with a clear error if variables are missing.

---

## Step 7: Update Environment Variables Script

After all app registrations and deployments are complete, run the environment update script to ensure everything is synchronized:

```powershell
.\deploy\Update-EnvironmentVariables.ps1 -SubscriptionId "<subscription-id>" `
                                          -ResourceGroupName "<resource-group>"
```

---

## Step 8: Add VMs to Security Groups

If you deployed VMs, add their managed identities to the correct security groups:

```powershell
.\deploy\Add-VMsToSecurityGroups.ps1
```

This ensures:
- AVD host managed identities → `LinuxBroker-AVDHost-VMs` security group → `AVDHost` API role
- Linux VM managed identities → `LinuxBroker-LinuxHost-VMs` security group → `LinuxHost` API role

---

## Step 9: Post-Deployment Validation

### Automated Validation

`Deploy-LinuxBroker.ps1` automatically runs `Test-DeploymentHealth` at the end of deployment, which checks:
- API endpoint responding
- Frontend portal responding
- Key Vault accessible
- SQL Server reachable
- Function App provisioned

For a more thorough check, run the post-deployment smoke tests:

```powershell
.\deploy\Test-PostDeployment.ps1 -SubscriptionId "<subscription-id>" `
                                  -ResourceGroupName "<resource-group>"
```

### Manual Verification

1. **API Health Check:**
   ```bash
   curl https://<api-app-name>.azurewebsites.net/api/health
   ```

2. **Frontend Portal:**
   Navigate to `https://<frontend-app-name>.azurewebsites.net` and log in with Azure AD.

3. **Frontend Health Check:**
   ```bash
   curl https://<frontend-app-name>.azurewebsites.net/health
   ```
   Returns `{status, version, api_reachable}` — verify `api_reachable` is `true`.

4. **Database Connectivity:**
   From the portal, check that the VMs page loads (confirms API → SQL connection).

5. **Function App:**
   Check Application Insights for timer trigger executions (runs on schedule).

6. **VM Checkout Test** (if VMs deployed):
   From an AVD host, run `Connect-LinuxBroker.ps1` — should successfully check out a Linux VM.

---

## Deployment Directory Structure

| Directory | Purpose | When to Use |
|-----------|---------|-------------|
| `deploy/` | **Primary.** Full deployment lifecycle — prerequisites, infrastructure, apps, validation, cleanup. | ✅ Always use this |
| `deploy_infrastructure/` | **Supplementary.** Standalone utility scripts for specific tasks (e.g., manual permission fixes). | ⚠️ Only for targeted fixes |

The scripts in `deploy_infrastructure/` are maintained for edge cases. Their functionality is handled automatically by `deploy/Deploy-LinuxBroker.ps1`. See [deploy_infrastructure/README.md](deploy_infrastructure/README.md) for details.

---

## Deployment Summary Checklist

Use this checklist to track your progress:

- [ ] Pre-deployment readiness check passed (`Test-DeploymentReadiness.ps1`)
- [ ] Prerequisites verified (`Check-Prerequisites.ps1`)
- [ ] App registrations created (`Setup-AppRegistrations.ps1`)
- [ ] Infrastructure deployed (`Deploy-LinuxBroker.ps1`)
- [ ] Database schema deployed (`Deploy-Database.ps1`)
- [ ] API environment variables configured
- [ ] Functions environment variables configured
- [ ] Frontend environment variables configured
- [ ] Environment variables synchronized (`Update-EnvironmentVariables.ps1`)
- [ ] VMs added to security groups (if applicable)
- [ ] Post-deployment validation passed (`Test-PostDeployment.ps1`)
- [ ] Frontend portal accessible and API reachable

---

## Troubleshooting

### API Won't Start — Missing Environment Variables

The API validates all 16 required environment variables at startup. Check the App Service log stream for a message listing exactly which variables are missing. See [CONFIGURATION.md](CONFIGURATION.md) Phase 4 for the complete list.

### Database Deployment Fails

| Symptom | Resolution |
|---------|------------|
| Connection refused | Add your client IP to the Azure SQL Server firewall rules |
| Permission denied | Ensure your user has `db_ddladmin` and `db_datawriter` roles |
| `sqlcmd` not found | Install via `apt install mssql-tools` (Linux) or download from Microsoft |

See [sql_queries/README.md](sql_queries/README.md) for additional database troubleshooting.

### Broker Agent Can't Connect

1. Check `C:\Temp\Connect-LinuxBroker.ps1` on the AVD host — verify the API URL was injected
2. Verify the API Client ID (`api://` URI) in the script
3. Confirm the AVD host's managed identity has the `AVDHost` app role assigned
4. Confirm the managed identity is in the `LinuxBroker-AVDHost-VMs` security group

### Session Release Agent Can't Authenticate

1. Check `/usr/local/bin/release-session.sh` on the Linux VM — verify `api://` URI and API URL
2. Confirm the VM's managed identity has the `LinuxHost` app role assigned
3. Test token acquisition:
   ```bash
   curl -s -H "Metadata:true" \
     "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=api://<CLIENT_ID>"
   ```

### Functions Not Triggering

1. Verify `API_URL` and `API_CLIENT_ID` in Function App settings
2. Confirm the Function App's managed identity has the `ScheduledTask` app role
3. Review Function App logs in Application Insights

### Frontend Portal Shows "API Unreachable"

1. Hit the `/health` endpoint — check if `api_reachable` is `false`
2. Verify `API_URL` in the frontend App Service settings points to the correct API
3. Ensure the API App Service is running and responding on `/api/health`

### Deployment Script Fails Mid-Run

`Deploy-LinuxBroker.ps1` is idempotent — simply re-run it. It skips already-completed steps (existing Bicep deployments, firewall rules, etc.) and picks up where it left off.

---

## Related Documentation

| Document | What It Covers |
|----------|---------------|
| [CONFIGURATION.md](CONFIGURATION.md) | Complete environment variable reference — all 7 phases, dependencies, sources |
| [sql_queries/README.md](sql_queries/README.md) | Database schema, stored procedures, manual deployment, verification queries |
| [.env.template](.env.template) | Environment variable template for API, Functions, and host scripts |
| [front_end/.env.template](front_end/.env.template) | Frontend portal environment variables |
| [deploy_infrastructure/README.md](deploy_infrastructure/README.md) | Supplementary deployment scripts |
| [vm-deployment-config.example.json](vm-deployment-config.example.json) | VM deployment configuration example |
| [README.md](README.md) | Architecture overview, RBAC model, workflows |
