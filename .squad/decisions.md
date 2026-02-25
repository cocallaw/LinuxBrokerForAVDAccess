# Decisions

_Team decisions are recorded here. Append-only._
### 2025-02-25: SQL Deployment Idempotency & Automation
**By:** Ash (Data Engineer)
**What:** All SQL scripts made idempotent; added performance indexes, Deploy-Database.ps1 wrapper, and deployment verification queries. Removed hardcoded `USE linuxbroker;` from table scripts — database context is now always set by the connection/caller.
**Why:** Scripts previously failed on re-run (CREATE without IF NOT EXISTS). No automated deployment existed. Missing indexes on frequently queried columns (VmStatus, Username, Hostname) impacted query performance. VmUsers table (024) was undocumented.
**Impact:** Parker should update Deploy-LinuxBroker.ps1 to call Deploy-Database.ps1 for the database deployment step. Dallas should be aware that procedures now use CREATE OR ALTER (no behavioral change to pymssql callers).
### 2026-02-25T18:24:02Z: User directive
**By:** Corey Callaway (via Copilot)
**What:** Do not worry about local dev setup or Docker containers at this time — skip those improvements.
**Why:** User request — captured for team memory
### 2026-02-25: Deployment Configuration Improvements
**By:** Dallas (Backend Dev)
**Status:** Implemented

**What:**
1. Created `.env.template` at repo root — centralizes all environment variable documentation across API, Functions, Broker Agent, and Session Release Agent components.
2. Added startup validation to `api/config.py` — the API now validates all 16 required environment variables at startup and exits with a clear error if any are missing.
3. Parameterized hardcoded values in custom script extension scripts — `ORG_ID`, `ACTIVATION_KEY`, `API_CLIENT_ID`, and `API_URL` now accept arguments instead of requiring manual editing. `Configure-AVD-Host.ps1` now takes `-LinuxBrokerApiClientId` in addition to `-LinuxBrokerApiBaseUrl`.
4. Created `CONFIGURATION.md` — documents the complete 7-phase configuration flow with dependencies.

**Why:**
- Deployers were hitting cryptic errors because env vars were undocumented and unvalidated
- Hardcoded values in scripts required manual editing after deployment — error-prone and not traceable
- No single document mapped the configuration dependency chain

**Impact:**
- **Parker:** `Configure-AVD-Host.ps1` now requires an additional `-LinuxBrokerApiClientId` parameter. Bicep custom script extension calls need updating to pass this value.
- **Parker:** Linux host custom script extensions now accept positional args for ORG_ID, ACTIVATION_KEY, API_CLIENT_ID, API_URL. Bicep should pass these instead of relying on hardcoded defaults.
- **Lambert:** The `.env.template` covers the full stack. Frontend env vars can be added to it for a single reference point.
- **All:** `CONFIGURATION.md` is the canonical deployment configuration reference.

**Backward compatibility:** All changes are backward-compatible. Scripts fall back to existing placeholder defaults if new arguments are not provided.
### 2025: Deployment validation test suite
**By:** Kane (Tester)
**What:** Created three deployment validation scripts:
- `deploy/Test-DeploymentReadiness.ps1` — pre-deployment checks with structured pass/fail table
- `deploy/Test-PostDeployment.ps1` — post-deployment health checks against live Azure resources
- `sql_queries/test_schema.sql` — database schema completeness validation
**Why:** Team review identified lack of deployment validation tooling. These scripts catch missing prerequisites before deployment and verify health afterward, reducing failed deployments and troubleshooting time.
**Convention:** Both PowerShell scripts output a standardized pass/fail table and exit with code 1 on failures, making them suitable for CI/CD integration.
### Decision: Frontend Deployment Improvements
**By:** Lambert (Frontend Dev)
**Date:** 2025-07-25
**Status:** Implemented

#### What Changed
1. **Dependencies bumped:** Flask 2.2.2→3.1.1, requests 2.26.0→2.32.3, Werkzeug unpinned to >=3.1.0.
2. **Startup env validation:** app.py validates 6 required env vars before creating the Flask app. Missing vars cause a clear error + sys.exit(1).
3. **`.env.template` added:** Documents all env vars with descriptions, GUID placeholders, and generation tips.
4. **`/health` endpoint added:** Returns JSON `{status, version, api_reachable}`. Unauthenticated — designed for Azure health probes.

#### Why
- Flask 2.2.2 and requests 2.26.0 had known CVEs and were 2-3 years outdated.
- Deployers had no feedback when env vars were misconfigured — app would start but crash on first request.
- No way to verify portal health post-deployment without logging in.

#### Impact
- **Parker (Infra):** Can wire `/health` into App Service health check configuration in Bicep.
- **Dallas (Backend):** The portal now pings `{API_URL}/health` — consider adding a `/health` endpoint to the API if one doesn't exist.
- **All:** `.env.template` serves as the canonical list of frontend env vars.

#### Files Modified
- `front_end/requirements.txt` — version bumps
- `front_end/app.py` — env validation + health endpoint
- `front_end/env.example` — typo fix ("Linbux" → "Linux")
- `front_end/.env.template` — new file
### 2026-02-25: Deployment reliability improvements
**By:** Parker (Infra/DevOps)
**What:**
1. All PowerShell scripts now set `$ErrorActionPreference = 'Stop'` — errors halt execution instead of silently continuing.
2. `Deploy-LinuxBroker.ps1` has idempotency: checks for existing successful Bicep deployments and SQL firewall rules before creating them.
3. `Deploy-LinuxBroker.ps1` now runs `Test-DeploymentHealth` after deployment — validates API, frontend, Key Vault, SQL Server, and Function App are responding/provisioned.
4. `deploy_infrastructure/` has a README explaining its relationship to `deploy/` and a deprecation notice on `Assign-AppRoleToFunctionApp.ps1`.

**Why:** Improves deployment reliability, supports re-runs without side effects, and gives operators immediate feedback on deployment health. Consolidates documentation to reduce confusion between the two deploy directories.

**Impact:** Dallas/Ash/Lambert — if you reference deploy_infrastructure/ scripts in docs, note they are supplementary to deploy/. The main workflow is deploy/ only.
### 2026-02-25: Bicep Templates Updated for Parameterized Script Extensions
**By:** Parker (Infra/DevOps)
**Status:** Implemented

**What Changed**
1. **AVD custom script extension** now passes `-LinuxBrokerApiClientId` alongside `-LinuxBrokerApiBaseUrl` to `Configure-AVD-Host.ps1`.
2. **Linux custom script extensions** now pass positional arguments to all host configuration scripts:
   - RHEL 7/8/9: `ORG_ID`, `ACTIVATION_KEY`, `API_CLIENT_ID`, `API_URL` (4 args)
   - Ubuntu 24: `API_CLIENT_ID`, `API_URL` (2 args)
3. **Frontend App Service** now has `healthCheckPath: '/health'` configured — Azure health probes will use Lambert's `/health` endpoint.
4. **Python 3.11** runtime confirmed compatible with Flask 3.1.1 (no change needed).
5. All new Bicep parameters have `@description` decorators and safe empty-string defaults for backward compatibility.

**Why**
- Dallas parameterized hardcoded placeholder values in custom script extensions — Bicep needed to pass those values through.
- Lambert added a `/health` endpoint to the frontend — Bicep should configure Azure's built-in health monitoring to use it.
- Without these Bicep changes, deployers would still need to manually edit scripts post-deployment.

**Impact**
- **Dallas:** AVD and Linux host scripts will now receive real configuration values from Bicep during deployment. No more manual editing of deployed scripts.
- **Lambert:** Frontend health probes are now active — Azure will auto-restart unhealthy instances using `/health`.
- **All:** Deployers need to provide `linuxBrokerApiClientId` when deploying AVD or Linux VMs. RHEL deployers also need `rhelOrgId` and `rhelActivationKey`.

**Files Modified**
- `bicep/main.bicep` — added `linuxBrokerApiClientId`, `rhelOrgId`, `rhelActivationKey` params
- `bicep/main.bicepparam` — example values for new params
- `bicep/infrastructure/main.bicep` — `healthCheckPath: '/health'` on frontend
- `bicep/AVD/main.bicep` — `linuxBrokerApiClientId` param + updated commandToExecute
- `bicep/AVD/main.bicepparam` — example value for API client ID
- `bicep/Linux/main.bicep` — 4 new params + updated imageConfigs command strings
- `bicep/Linux/main.bicepparam` — example values for new params

**Key Pattern:** Ubuntu scripts take 2 positional args (API_CLIENT_ID, API_URL) while RHEL scripts take 4 (ORG_ID, ACTIVATION_KEY, API_CLIENT_ID, API_URL). Order matters!
### 2026-02-25: Deployment Documentation Structure
**By:** Dallas (Backend Dev)
**Status:** Implemented

**What**
Created `DEPLOYMENT.md` as the canonical end-to-end deployment guide. Updated `README.md` to replace the verbose "Getting Started" section with a concise "Deployment" section linking to DEPLOYMENT.md.

**Why**
- Documentation was fragmented across README.md, CONFIGURATION.md, sql_queries/README.md, deploy/QUICKSTART.md, and deploy_infrastructure/README.md. No single guide walked a user through the complete process.
- README.md had a "Getting Started" section that covered infrastructure but skipped database deployment, environment configuration, and post-deployment validation.
- New team scripts (Test-DeploymentReadiness.ps1, Test-PostDeployment.ps1, Deploy-Database.ps1, Test-DeploymentHealth) weren't surfaced in the main documentation flow.
- README.md referenced `DEPLOYMENT_IMPROVEMENTS.md` and `CONTRIBUTING.md` which didn't exist.

**What Changed**
1. **`DEPLOYMENT.md` (new):** 10-step deployment guide covering pre-flight checks → clone → prerequisites → app registrations → infrastructure → database → env vars → security groups → validation. Includes troubleshooting and a progress checklist.
2. **`README.md` (updated):** "Getting Started" replaced with "Deployment" section — quick-start snippet + table linking to DEPLOYMENT.md, CONFIGURATION.md, sql_queries/README.md, and deploy/QUICKSTART.md. Fixed broken references to nonexistent files.

**Impact**
- **All agents:** DEPLOYMENT.md is the canonical "how to deploy" reference. If you add deployment steps, add them there.
- **Parker:** deploy/ vs deploy_infrastructure/ distinction is documented in DEPLOYMENT.md.
- **Kane:** Test-DeploymentReadiness.ps1 and Test-PostDeployment.ps1 are now prominently featured in Steps 0 and 9.
- **Ash:** Deploy-Database.ps1 is Step 5 in the guide.
- **Lambert:** Frontend env config is covered in Step 6d.

**Key Pattern:** DEPLOYMENT.md follows the 7-phase configuration flow without duplicating CONFIGURATION.md content. All 17 referenced file paths verified to exist.
