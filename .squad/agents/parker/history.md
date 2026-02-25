# Parker — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Learnings

### Deployment Architecture (2025-02-25)
- **Two deployment directories exist:** `deploy/` (6 scripts, 2.4K lines) and `deploy_infrastructure/` (1 script, 252 lines)
- **Main orchestrator:** `Deploy-LinuxBroker.ps1` (884 lines) handles core infra, AVD, and Linux VMs in single flow
- **Bicep structure:** Modular (infrastructure, AVD, Linux modules; 989 lines total) with good parameter passing
- **Key files:** 
  - `bicep/infrastructure/main.bicep` (304 lines) - SQL, App Service, Function App, Key Vault
  - `vm-deployment-config.example.json` - comprehensive example with inline docs
  - `deploy/Check-Prerequisites.ps1` - thorough validation of tools and permissions
- **Custom script extensions:** AVD PowerShell + Linux shell scripts for host configuration; RHEL/Ubuntu supported

### Deployment Strengths
- Good error handling with try-catch and graceful fallbacks in main script
- Clear user feedback with timestamped logging and emoji status indicators
- Modular Bicep with conditional modules for optional components (deployAVD, deployLinuxVMs)
- Configuration examples for common scenarios (avd-only, linux-only, full-deployment)
- Prerequisites checking is comprehensive (CLI tools, Azure login, permissions)

### Deployment Issues Identified
1. **Directory confusion:** split between `deploy/` and `deploy_infrastructure/` not intuitive
2. **No ErrorActionPreference:** PowerShell scripts lack global error handling preference
3. **Database schema stub:** `Deploy-LinuxBroker.ps1` mentions DB schema deployment but not implemented
4. **Not idempotent:** script assumes fresh state; no existence checks before creation
5. **Monolithic deploy script:** 884 lines with only 2 functions; hard to test or rerun parts
6. **No deployment logging:** no manifest/log file of what was deployed when
7. **Parameter defaults scattered:** in bicep, bicepparam, example config, and script
8. **Shell script error handling:** missing `set -u` and `set -o pipefail`
9. **Limited Bicep documentation:** no inline comments explaining resource configuration choices
10. **No troubleshooting guide:** users stuck when deployment fails

### Bicep Insights
- **Naming pattern:** `${projectName}-${environment}-resourcetype-${uniqueSuffix}` for global uniqueness
- **Key Vault:** auto-created with firewall allow-all rule (for Function App access)
- **App Services:** P1v3 SKU (production-tier) for both API and Frontend
- **SQL:** Standard_S1 tier with 250GB max size; public network access enabled
- **Managed Identities:** created for Function App but assignment logic in PowerShell script
- **Missing validation:** no checks that network/vnet actually exist before deploying VMs

### User Workflows Observed
- **Fast path:** 5 minutes if no VMs: `Check-Prerequisites.ps1` → `Deploy-LinuxBroker.ps1` → done
- **Full path:** includes VM config file → optional app registration → optional function app permissions
- **Recovery:** `Cleanup-LinuxBroker.ps1` for cleanup; good WhatIf support

### Key Recommendations for Improvement
**High Priority (reliability):**
- Consolidate deploy directories into single `deploy/` structure
- Add `ErrorActionPreference = "Stop"` to PowerShell scripts globally
- Implement actual database schema deployment
- Add idempotency checks (resource existence before create)

**Medium Priority (usability):**
- Refactor Deploy-LinuxBroker.ps1 into smaller functions by logical step
- Add deployment manifest/log file for troubleshooting
- Add shell script robustness (set -u, set -o pipefail)
- Create TROUBLESHOOTING.md with common failure scenarios

**Low Priority (polish):**
- Consolidate parameter defaults to Bicep only
- Add inline Bicep comments for configuration rationale
- Create deployment prerequisites checklist document

---

## Cross-Agent Learnings (2026-02-25)

### Team Findings on Deployment Experience Review

**Ripley (Architecture/Lead)** found:
- Configuration scattered across 8+ files with unclear dependencies
- Hardcoded placeholder values in custom script extensions (ORG_ID, ACTIVATION_KEY, API_CLIENT_ID)
- Database schema deployment is manual with no validation before API starts
- Multi-step deployment requires strict ordering but this isn't enforced
- Need unified configuration wizard and post-deployment validation

**Dallas (Backend)** found:
- API has 17 environment variables with no startup validation
- Hardcoded API URLs in Broker Agent script require manual editing
- Function timer schedules hardcoded in decorators (no flexibility)
- Four distribution-specific Session Release Agent scripts = maintenance debt
- 24 SQL scripts with no automation in deployment

**Lambert (Frontend)** found:
- 10+ environment variables with no validation
- Flask-Session using filesystem storage (not cloud-scalable)
- Outdated dependencies: Flask 2.2.2 (18 months old), requests 2.26.0 (45 months old)
- No local development setup or Python CI/CD

**Ash (Database)** found:
- SQL scripts not idempotent — all CREATE statements fail on re-deployment
- No schema version tracking
- Missing performance indexes on frequently queried columns
- VmUsers table added but not documented in deployment flow
- No pre-flight connectivity validation

### Key Cross-Team Patterns
1. **No unified configuration management** — env vars scattered, no validation
2. **Manual multi-step dependencies** — SQL, app config, RBAC all separate
3. **Hardcoded values everywhere** — API URLs, distro scripts, timer schedules
4. **Lacks idempotency** — SQL scripts, deployment assumptions all require fresh state
5. **Missing validation layer** — No way to verify deployment succeeded

### Unified Recommendations Requiring Parker Coordination
1. Consolidate deploy directories (Parker + team communication)
2. Create master orchestration script (Parker + Ripley)
3. Implement database schema deployment (Parker + Ash)
4. Parameterize custom script extensions (Parker + Dallas)
5. Create post-deployment validation script (Parker + Ripley)
6. Add ErrorActionPreference to all PowerShell (Parker owned)
7. Refactor monolithic Deploy-LinuxBroker.ps1 (Parker + Ripley)

### Deployment Improvements Implemented (2026-02-25)
- **ErrorActionPreference:** Added `$ErrorActionPreference = 'Stop'` to all 7 PowerShell scripts (6 in deploy/, 1 in deploy_infrastructure/). Must go after `param()` block in PowerShell.
- **Idempotency:** Deploy-LinuxBroker.ps1 now checks for existing successful deployments before running Bicep, and checks for existing SQL firewall rules before creating them. Existing deployment is skipped with a message; user can force re-deploy with a different `-DeploymentName`.
- **Post-deployment validation:** Added `Test-DeploymentHealth` function to Deploy-LinuxBroker.ps1 that checks API endpoint (HTTP), frontend endpoint, Key Vault provisioning state, SQL Server readiness, and Function App state. Prints a bordered summary table with pass/fail/warn/skip status.
- **Deploy directory consolidation:** Added `deploy_infrastructure/README.md` explaining the relationship to `deploy/`. Added deprecation notice to `Assign-AppRoleToFunctionApp.ps1` header noting that `Deploy-LinuxBroker.ps1` now handles this automatically.
- **Key pattern:** `$ErrorActionPreference = 'Stop'` must be placed AFTER `param()` block — PowerShell requires `param()` as the first executable statement.
- **User preference:** No local dev setup or Docker containers — skip those improvements.

### Cross-Agent Updates (2026-02-25)
- **Dallas:** `Configure-AVD-Host.ps1` now requires `-LinuxBrokerApiClientId` parameter. Bicep custom script extension calls need updating to pass this value. Linux host custom script extensions now accept positional args (ORG_ID, ACTIVATION_KEY, API_CLIENT_ID, API_URL).
- **Ash:** Should update Deploy-LinuxBroker.ps1 to call Deploy-Database.ps1 for the database deployment step.
- **Lambert:** Can wire `/health` endpoint into App Service health check configuration in Bicep (frontend now provides this endpoint).

### Bicep Template Updates for Parameterized Scripts (2025-07-25)
- **AVD module:** Added `linuxBrokerApiClientId` parameter (mandatory) and updated custom script extension `commandToExecute` to pass both `-LinuxBrokerApiBaseUrl` and `-LinuxBrokerApiClientId` to `Configure-AVD-Host.ps1`.
- **Linux module:** Added 4 new parameters: `rhelOrgId`, `rhelActivationKey`, `linuxBrokerApiClientId`, `linuxBrokerApiUrl`. Updated `imageConfigs` command strings to pass positional args to all RHEL (4 args) and Ubuntu (2 args) scripts.
- **Infrastructure module:** Added `healthCheckPath: '/health'` to frontend App Service `siteConfig` — Azure will now probe Lambert's health endpoint.
- **Main orchestrator:** Added `linuxBrokerApiClientId`, `rhelOrgId`, `rhelActivationKey` params and threaded them through to AVD and Linux sub-modules. Linux module also receives `linuxBrokerApiUrl` from infrastructure output.
- **Python runtime:** Confirmed `PYTHON|3.11` in all App Service configs is compatible with Flask 3.1.1 (requires Python 3.9+). No change needed.
- **All .bicepparam files updated** with example/placeholder values for new parameters. RHEL params are commented out by default since they're only needed for RHEL hosts.
- **Validation:** All Bicep templates pass `az bicep build` validation.
- **Backward compatibility:** All new params have safe defaults (empty strings). Scripts fall back to placeholder defaults if args are not provided, matching Dallas's implementation.
- **Key pattern:** Ubuntu scripts take 2 positional args (API_CLIENT_ID, API_URL) while RHEL scripts take 4 (ORG_ID, ACTIVATION_KEY, API_CLIENT_ID, API_URL). The order matters!
