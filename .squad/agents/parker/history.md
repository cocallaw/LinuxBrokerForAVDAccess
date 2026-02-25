# Parker — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Current Focus: GitHub Actions Deployment Automation

Ripley (2026-02-25) recommended OIDC federated credentials + 4-workflow GitHub Actions structure. Parker will own workflow implementation.

**Recommendation:** ✅ PROCEED
- **Automation Rate:** 80% (Bicep, Database, Config, Validation)
- **Timeline:** 2–3 weeks for production-ready workflows
- **Risk Level:** 🟢 LOW
- **Authentication:** OIDC federated credentials (no static secrets)
- **Workflow Structure:** 4 separate files (app-registrations, infrastructure, vms, cleanup)

**Secrets Required (9 total):**
- AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID (OIDC)
- LINUX_BROKER_API_CLIENT_ID, API_AUTH_SECRET, SQL_ADMIN_PASSWORD (config)
- RHEL_ORG_ID, RHEL_ACTIVATION_KEY (RHEL VMs, optional)
- AZURE_RESOURCE_GROUP (resource naming)

**Next Steps for Parker:**
1. Set up OIDC federated identity in Azure Portal (~10 min)
2. Create `deploy-app-registrations.yml` workflow (manual gated)
3. Create `deploy-infrastructure.yml` workflow (main automation: Bicep + DB + config + validation)
4. Create `deploy-vms.yml` and `cleanup.yml` workflows (optional)
5. Document secret rotation procedures in SECURITY.md

**Full Analysis:** `.squad/decisions.md` (GitHub Actions Deployment Automation section)

---

## Deployment Improvements Implemented (2026-02-25)
- **ErrorActionPreference:** Added `$ErrorActionPreference = 'Stop'` to all 7 PowerShell scripts
- **Idempotency:** Deploy-LinuxBroker.ps1 checks for existing deployments/firewall rules before creating
- **Post-deployment validation:** Added `Test-DeploymentHealth` function checking API, frontend, Key Vault, SQL, Function App
- **Deploy directory consolidation:** Added README explaining deploy/ vs deploy_infrastructure/ relationship
- **Key pattern:** `$ErrorActionPreference = 'Stop'` must be placed AFTER `param()` block

### Bicep Template Updates (2025-07-25)
- **AVD module:** Added `linuxBrokerApiClientId` parameter + updated custom script extension
- **Linux module:** Added 4 params (rhelOrgId, rhelActivationKey, linuxBrokerApiClientId, linuxBrokerApiUrl)
- **Infrastructure module:** Added `healthCheckPath: '/health'` to frontend App Service
- **Python runtime:** Confirmed `PYTHON|3.11` compatible with Flask 3.1.1
- **All .bicepparam files updated** with example values for new parameters
- **Key pattern:** Ubuntu scripts take 2 positional args (API_CLIENT_ID, API_URL); RHEL take 4 (ORG_ID, ACTIVATION_KEY, API_CLIENT_ID, API_URL)

---

## Cross-Agent Updates (2026-02-25)
- **Dallas:** `Configure-AVD-Host.ps1` now requires `-LinuxBrokerApiClientId` parameter; Bicep custom script extensions updated
- **Ash:** Should update Deploy-LinuxBroker.ps1 to call Deploy-Database.ps1 for database deployment
- **Lambert:** Can wire `/health` endpoint into App Service health check (frontend now provides this)
- **Ripley:** Recommended OIDC + 4-workflow structure for GitHub Actions deployment — Parker will likely build this

---

## Historical Context
For archived 2025-02-25 deployment architecture review, see `.squad/agents/parker/_archive/2025-02-25-deployment-architecture-review.md`

### Team Findings on Deployment Experience (Archived 2026-02-25)
**Consolidated findings from cross-agent review:**
- Configuration scattered across 8+ files with unclear dependencies
- Hardcoded placeholder values in custom script extensions
- Database schema deployment manual with no validation
- Multi-step deployment requires strict ordering but not enforced
- 17+ env vars across components with no validation
- SQL scripts not idempotent (fail on re-deployment)
- Missing performance indexes on frequently queried columns
- Outdated dependencies (Flask 2.2.2, requests 2.26.0)
- No post-deployment validation tooling

**Unified Recommendations Across All Agents:**
1. Consolidate deploy directories
2. Create master orchestration script
3. Implement idempotent database schema deployment
4. Parameterize custom script extensions
5. Create post-deployment validation script
6. Add ErrorActionPreference to all PowerShell
7. Migrate frontend sessions to Redis
8. Update outdated dependencies
