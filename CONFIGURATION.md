# Configuration Guide — Linux Broker for AVD Access

This document maps out the complete configuration journey: what needs to be set, where, in what order, and what depends on what.

## Configuration Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    CONFIGURATION FLOW                       │
│                                                             │
│  1. Azure AD App Registration  ──┐                          │
│  2. Infrastructure (Bicep)     ──┼──▶ Produces IDs/URLs     │
│  3. Database Schema (SQL)      ──┘                          │
│                                    │                        │
│                                    ▼                        │
│  4. API App Service Settings  ◀── Uses IDs/URLs             │
│  5. Azure Functions Settings  ◀── Uses API URL + Client ID  │
│  6. AVD Host Script Extension ◀── Uses API URL + Client ID  │
│  7. Linux Host Script Ext.    ◀── Uses API URL + Client ID  │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

Before configuring anything, you need:

- An Azure subscription with Owner or Contributor access
- Azure CLI installed and authenticated (`az login`)
- PowerShell 7+ with Az module
- Access to create Azure AD App Registrations

---

## Phase 1: Azure AD App Registration

**What:** Create the API and Frontend app registrations in Azure AD.

**How:** Run the app registration script or create manually in Azure Portal.

**Produces:**
| Output | Used By |
|--------|---------|
| `CLIENT_ID` (API App Registration) | API, Functions, Broker Agent, Session Release Agent |
| `TENANT_ID` | API |
| `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET` | API (Portal auth) |
| `AVD_HOST_GROUP_ID` | API |
| `LINUX_HOST_GROUP_ID` | API |

**File:** `app-registration-config.json` is produced by the registration script.

> **⚠ Dependency:** CLIENT_ID is needed by almost every component. Complete this first.

---

## Phase 2: Infrastructure Deployment (Bicep)

**What:** Deploy Azure resources — App Service, Function App, SQL Server, Key Vault, networking.

**How:** Run `deploy/Deploy-LinuxBroker.ps1` or deploy Bicep templates directly.

**Produces:**
| Output | Used By |
|--------|---------|
| App Service URL | Functions (`API_URL`), Broker Agent, Session Release Agent |
| SQL Server hostname | API (`DB_SERVER`) |
| Database name | API (`DB_DATABASE`) |
| Key Vault URI | API (`VAULT_URL`) |
| Storage Account connection string | Functions (`AzureWebJobsStorage`) |
| App Insights connection string | API, Functions |

**Config file:** `vm-deployment-config.json` (copy from `vm-deployment-config.example.json`).

> **⚠ Dependency:** Bicep must complete before configuring App Service settings.

---

## Phase 3: Database Schema

**What:** Create tables, stored procedures, and seed data in Azure SQL.

**How:** Execute SQL scripts in `sql_queries/` in numbered order against the deployed database.

**Requires:**
- `DB_SERVER` (from Phase 2)
- `DB_DATABASE` (from Phase 2)
- `DB_USERNAME` and DB password (set during Bicep deployment)

> **⚠ Dependency:** Database must be deployed (Phase 2) and schema created before the API can start.

---

## Phase 4: API App Service Configuration

**What:** Set all 17 environment variables on the App Service.

**Where:** Azure Portal → App Service → Configuration → Application Settings,
or via Azure CLI:
```bash
az webapp config appsettings set --name <app-name> --resource-group <rg> --settings \
  TENANT_ID="..." \
  CLIENT_ID="..." \
  # ... see .env.template for full list
```

**Required Variables (all must be set):**

| Variable | Source | Description |
|----------|--------|-------------|
| `TENANT_ID` | Phase 1 | Azure AD Tenant ID |
| `CLIENT_ID` | Phase 1 | API App Registration Client ID |
| `MICROSOFT_PROVIDER_AUTHENTICATION_SECRET` | Phase 1 | App registration secret |
| `VM_SUBSCRIPTION_ID` | Your Azure subscription | Subscription with Linux VMs |
| `VM_RESOURCE_GROUP` | Phase 2 | Resource group with Linux VMs |
| `AVD_HOST_GROUP_ID` | Phase 1 | Security group for AVD hosts |
| `LINUX_HOST_GROUP_ID` | Phase 1 | Security group for Linux hosts |
| `LINUX_HOST_ADMIN_LOGIN_NAME` | Your choice | Admin username on Linux VMs |
| `GRAPH_API_ENDPOINT` | Static | `https://graph.microsoft.com/.default` |
| `DOMAIN_NAME` | Azure AD | Your Azure AD domain |
| `VAULT_URL` | Phase 2 | Key Vault URI |
| `KEY_NAME` | Phase 2 | Secret name for SSH PEM key |
| `DB_SERVER` | Phase 2 | SQL Server hostname |
| `DB_DATABASE` | Phase 2 | Database name |
| `DB_USERNAME` | Phase 2 | SQL admin username |
| `DB_PASSWORD_NAME` | Phase 2 | Secret name for DB password in Key Vault |
| `NFS_SHARE` | Your infrastructure | NFS share for user profiles |

**Validation:** The API now validates all required environment variables at startup. If any are missing, it logs exactly which ones and exits cleanly — check the App Service log stream.

> **⚠ Dependency:** Phases 1, 2, and 3 must be complete.

---

## Phase 5: Azure Functions Configuration

**What:** Set environment variables on the Function App.

**Where:** Azure Portal → Function App → Configuration → Application Settings.

| Variable | Source | Description |
|----------|--------|-------------|
| `API_CLIENT_ID` | Phase 1 | Same CLIENT_ID as the API |
| `API_URL` | Phase 2 | Full base URL of the API (e.g., `https://your-app.azurewebsites.net/api`) |

**Also required (typically auto-configured):**
- `FUNCTIONS_WORKER_RUNTIME` = `python`
- `FUNCTIONS_EXTENSION_VERSION` = `~4`
- `AzureWebJobsStorage` (connection string)
- `AzureWebJobsFeatureFlags` = `EnableWorkerIndexing`

> **⚠ Dependency:** API must be deployed and accessible (Phase 4).

---

## Phase 6: AVD Session Host Configuration

**What:** Run the custom script extension on each AVD session host to install the Broker Agent.

**How:** The Bicep template runs `Configure-AVD-Host.ps1` as a custom script extension, passing:

```powershell
Configure-AVD-Host.ps1 -LinuxBrokerApiBaseUrl "https://your-app.azurewebsites.net/api" `
                        -LinuxBrokerApiClientId "your-api-client-id"
```

This script:
1. Downloads `Connect-LinuxBroker.ps1` from GitHub
2. Replaces the API URL and Client ID placeholders
3. Installs dependencies (CredentialManager, Azure CLI, SSH extension)

**Values injected:**
| Placeholder in Connect-LinuxBroker.ps1 | Replaced With |
|-----------------------------------------|---------------|
| `https://your_linuxbroker_api_base_url/api` | `-LinuxBrokerApiBaseUrl` parameter value |
| `your_linuxbroker_api_client_id` | `-LinuxBrokerApiClientId` parameter value |

> **⚠ Dependency:** API must be deployed and accessible (Phase 4). App registration must exist (Phase 1).

---

## Phase 7: Linux Host Configuration

**What:** Run the custom script extension on each Linux VM to install the Session Release Agent.

**How:** The Bicep template runs the appropriate `Configure-*-Host.sh` script as a custom script extension.

For **RHEL 7/8/9**:
```bash
Configure-RHEL9-Host.sh <ORG_ID> <ACTIVATION_KEY> <API_CLIENT_ID> <API_URL>
```

For **Ubuntu 24**:
```bash
Configure-Ubuntu24_desktop-Host.sh <API_CLIENT_ID> <API_URL>
```

**Values injected into `release-session.sh`:**
| Placeholder | Replaced With |
|-------------|---------------|
| `YOUR_LINUX_BROKER_API_CLIENT_ID` | API Client ID argument |
| `YOUR_LINUX_BROKER_API_URL` | API base URL argument |

**RHEL-specific:**
| Variable | Description |
|----------|-------------|
| `ORG_ID` | RHEL Subscription Manager Org ID |
| `ACTIVATION_KEY` | RHEL Subscription Manager activation key |

> **⚠ Dependency:** API must be deployed (Phase 4). For RHEL, subscription manager credentials are required.

---

## Quick Reference: Where Each Value Comes From

| Value | Created In | Used By |
|-------|-----------|---------|
| `CLIENT_ID` / `API_CLIENT_ID` | Azure AD App Registration | API, Functions, AVD Hosts, Linux Hosts |
| `TENANT_ID` | Azure AD | API |
| `API_URL` / API Base URL | Bicep deployment output | Functions, AVD Hosts, Linux Hosts |
| `DB_SERVER`, `DB_DATABASE` | Bicep deployment output | API |
| `VAULT_URL` | Bicep deployment output | API |
| `AVD_HOST_GROUP_ID` | Azure AD Security Group | API |
| `LINUX_HOST_GROUP_ID` | Azure AD Security Group | API |
| `ORG_ID`, `ACTIVATION_KEY` | RHEL subscription | Linux Hosts (RHEL only) |
| `NFS_SHARE` | Your NFS infrastructure | API, Linux Hosts |

---

## Troubleshooting

### API won't start — missing environment variables
The API validates all required environment variables at startup. Check the App Service log stream for a message listing exactly which variables are missing.

### Broker Agent can't connect
1. Verify the API URL was injected correctly: check `C:\Temp\Connect-LinuxBroker.ps1` on the AVD host
2. Verify the API Client ID was injected correctly (look for `api://` URI in the script)
3. Check the AVD host's managed identity has the `AVDHost` app role assigned

### Session Release Agent can't authenticate
1. Check `/usr/local/bin/release-session.sh` on the Linux VM — verify `api://` URI has the real Client ID
2. Check the API base URL in the same script
3. Verify the Linux VM's managed identity has the `LinuxHost` app role assigned
4. Test token acquisition: `curl -s -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=api://<CLIENT_ID>"`

### Functions not triggering
1. Verify `API_URL` and `API_CLIENT_ID` in Function App settings
2. Check the Function App's managed identity has the `ScheduledTask` app role
3. Review Function App logs in Application Insights

---

## See Also

- [`.env.template`](.env.template) — Complete list of environment variables with descriptions
- [`api/env.example`](api/env.example) — API-specific example (subset)
- [`task/local.settings.json-example`](task/local.settings.json-example) — Functions local dev settings
- [`vm-deployment-config.example.json`](vm-deployment-config.example.json) — VM deployment config
- [`deploy/QUICKSTART.md`](deploy/QUICKSTART.md) — Deployment quickstart guide
