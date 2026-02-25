# Dallas — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Learnings

### Deployment Architecture (2025-02-25)
- **API Configuration:** 17 environment variables scattered across config.py with no startup validation; no .env support; Key Vault integration via managed identity is solid but error messaging is poor
- **Azure Functions:** Only 2 env vars (API_CLIENT_ID, API_URL); uses ManagedIdentityCredential correctly; timer schedules hardcoded in decorators (no flexibility for ops); no retry logic for API calls
- **Broker Agent (PowerShell):** API URL hardcoded in script line 13; custom script extension wrapper exists but doesn't parameterize URL; relies on post-deployment manual editing
- **Session Release Agent:** 4 distribution-specific scripts (RHEL 7/8/9, Ubuntu) = maintenance debt; GitHub URLs hardcoded; no centralized config injection pattern
- **Database Deployment:** 24 SQL scripts in sql_queries/ with no automation; deployers must manually execute in order; no schema version tracking
- **Deployment Orchestration:** Bicep templates good, but Deploy-LinuxBroker.ps1 doesn't orchestrate SQL, app config, RBAC, or agent setup; requires 9+ manual steps post-infrastructure
- **Secrets:** DB password retrieved from Key Vault at runtime ✅; API registration secret stored as env var (required for Portal auth); no Key Vault policy validation in deployment
- **Dependencies:** Minimal and well-curated; no bloat detected
- **Local Dev:** Impossible without Cloud resources (Key Vault, SQL DB); no docker-compose provided

### Deployment Pain Points (Key Findings)
1. **17+ environment variables** with no validation layer or centralized template
2. **Hardcoded API URLs** in Broker Agent script (requires manual editing)
3. **Manual SQL deployment** with no automation or schema versioning
4. **Tight API coupling** in Functions (no offline capability, no retries)
5. **Timer schedules in Functions** hardcoded in decorators (requires code redeploy to adjust)
6. **Four similar Session Release Agent scripts** instead of one adaptive script with distro detection
7. **No post-deployment validation** to confirm config is correct

### Recommended Improvements (Priority)
**High:**
- Create `.env.template` at repo root with all required vars + descriptions
- Add env var validation to API on startup (fail early, clear errors)
- Automate SQL schema deployment with migration tracking
- Parameterize Broker Agent API URL (add `-ApiUrl` parameter)

**Medium:**
- Move Function timer schedules to environment variables
- Add retry logic with exponential backoff to Function API calls
- Create deployment validation script (env vars, Key Vault policies, DB schema, Function config)
- Consolidate Linux host config scripts (2 instead of 4)
- Add local dev docker-compose with SQL Server, Key Vault emulator, Function emulator

**Low:**
- Add schema version tracking to database
- Document deployment checklist step-by-step
- Add troubleshooting section to QUICKSTART.md

### Key File Paths (Dallas Scope)
- **API:** api/app.py (35.9 KB, 30+ endpoints), api/config.py (23 lines, 17 env vars), api/env.example
- **Functions:** task/function_app.py (189 lines, 3 timer triggers), task/requirements.txt, task/host.json, task/local.settings.json-example
- **Broker Agent:** avd_host/broker/Connect-LinuxBroker.ps1 (169 lines, hardcoded API URL at line 13)
- **Session Release:** linux_host/session_release_buffer/ (4 distro scripts), linux_host/create-user.sh
- **Custom Extensions:** custom_script_extensions/Configure-*.ps1 and Configure-*.sh (5 scripts, 637 lines total)
- **Deployment:** deploy/Deploy-LinuxBroker.ps1, deploy/Check-Prerequisites.ps1, deploy/QUICKSTART.md
- **Database:** sql_queries/ (24 numbered scripts, no automation wrapper)

---

## Cross-Agent Learnings (2026-02-25)

### Team Findings on Deployment Experience Review

**Ripley (Architecture/Lead)** found:
- Configuration scattered across 8+ files with unclear dependencies
- Hardcoded placeholder values in custom script extensions require parameterization
- Database schema deployment is manual with no validation
- Multi-step deployment requires strict ordering but this isn't enforced
- Need unified configuration wizard and post-deployment validation

**Parker (Infra/DevOps)** found:
- Two deployment directories (deploy/ and deploy_infrastructure/) causing confusion
- Deploy-LinuxBroker.ps1 monolithic (884 lines); hard to refactor
- No idempotency — script assumes fresh state
- Database schema deployment stubbed out, not implemented
- PowerShell missing ErrorActionPreference = "Stop"
- No deployment manifest created

**Lambert (Frontend)** found:
- 10+ environment variables with no validation script
- Flask-Session using filesystem storage (not cloud-scalable)
- Outdated dependencies: Flask 2.2.2 (18 months old), requests 2.26.0 (45 months old)
- No local development environment setup
- No Python tests or linting in CI/CD

**Ash (Database)** found:
- SQL scripts not idempotent — CREATE statements fail on re-deployment
- No schema version tracking mechanism
- Missing performance indexes on frequently queried columns (Username, VmStatus, Hostname)
- VmUsers table added but not documented in README
- No pre-flight connectivity check before running SQL scripts

### Key Cross-Team Patterns
1. **Configuration chaos** — 17+ env vars across API/Functions/Frontend with no centralized validation
2. **Manual deployment steps** — SQL, app config, RBAC all separate steps
3. **Hardcoded values** — API URLs in scripts, timer schedules in code, distro-specific scripts
4. **No idempotency** — SQL, PowerShell, all components assume fresh state
5. **Missing validation** — No way to verify deployment succeeded or identify configuration errors

### Dallas-Specific Coordination Needs
1. **With Parker:** Implement database schema deployment automation in Deploy-LinuxBroker.ps1
2. **With Ash:** Coordinate on idempotency changes to SQL scripts for pymssql compatibility
3. **With Lambert:** Coordinated .env.template and validation across API/Frontend
4. **Team:** Create deployment validation script that checks all backend components

### Deployment Improvements Implemented (2026-02-25)

**1. `.env.template` created at repo root**
- Documents all environment variables across API (17 vars), Functions (2 vars), Broker Agent, and Session Release Agent
- Grouped by component with descriptions, example values, and deployment order notes
- Comments explain each variable's purpose and where it comes from

**2. API startup validation in `api/config.py`**
- `validate_environment()` function checks all 16 required env vars at import time
- Missing vars produce a clear error listing each one by name + description
- Exits with sys.exit(1) instead of letting the app crash later with cryptic DB/auth errors
- NFS_SHARE intentionally excluded from required list (optional feature)

**3. Parameterized hardcoded values across scripts**
- `Connect-LinuxBroker.ps1`: Added `-ApiBaseUrl` and `-ApiClientId` parameters; placeholders now have deployment comments
- `Configure-AVD-Host.ps1`: Added `-LinuxBrokerApiClientId` parameter; now injects both URL and Client ID
- `Configure-RHEL7-Host.sh`, `Configure-RHEL8-Host.sh`, `Configure-RHEL9-Host.sh`: ORG_ID, ACTIVATION_KEY, API_CLIENT_ID, API_URL now accept positional args with fallback defaults
- `Configure-Ubuntu24_desktop-Host.sh`: API_CLIENT_ID and API_URL accept positional args

**4. `CONFIGURATION.md` created at repo root**
- Maps the complete 7-phase configuration flow with dependency arrows
- Documents every variable, where it comes from, and which component uses it
- Includes troubleshooting section for common deployment issues
- Cross-references .env.template, env.example, local.settings.json-example

**Key Patterns:**
- Placeholders in scripts use the pattern `<-- REQUIRED:` comments for deployer visibility
- `${N:-default}` pattern in bash scripts allows positional arg override while keeping backward compatibility
- PowerShell scripts use optional parameters with empty string defaults for same backward compatibility
- API validation runs at import time via `config.py` — no changes to `app.py` needed

### Cross-Agent Updates (2026-02-25)
- **Parker:** Bicep custom script extensions need to pass new `-LinuxBrokerApiClientId` parameter to Configure-AVD-Host.ps1. Linux host extensions now accept positional args instead of relying on hardcoded defaults.
- **Ash:** Coordinate on idempotency changes to SQL scripts for pymssql compatibility. Procedures now use `CREATE OR ALTER` (no behavioral change to pymssql callers).
- **Lambert:** `.env.template` now covers the full stack including frontend vars. All components reference this single file for env var documentation.

### Deployment Documentation (2025-07-25)

**Created `DEPLOYMENT.md`** — the single end-to-end deployment guide for the solution.

**Key decisions:**
- Created a dedicated `DEPLOYMENT.md` rather than expanding README.md, because README was already 300+ lines with architecture, RBAC, and workflow documentation. Deployment guide is ~300 lines on its own — cramming it into README would make both harder to navigate.
- Replaced README.md's "Getting Started" section with a concise "Deployment" section that links to DEPLOYMENT.md with a quick-start snippet.
- Fixed broken README references to `DEPLOYMENT_IMPROVEMENTS.md` (never existed) and `CONTRIBUTING.md` (doesn't exist — pointed to CODE_OF_CONDUCT.md and SUPPORT.md instead).
- DEPLOYMENT.md references only files that actually exist — all 17 file references verified.
- The guide follows the 7-phase configuration flow from CONFIGURATION.md but adds the orchestration scripts (Check-Prerequisites, Test-DeploymentReadiness, Deploy-LinuxBroker, Deploy-Database, Test-PostDeployment) as concrete steps.
- Deliberately does NOT duplicate content from CONFIGURATION.md or sql_queries/README.md — links to them instead.

**Key file paths:**
- `DEPLOYMENT.md` — end-to-end deployment guide (new)
- `README.md` — updated Deployment section with link to DEPLOYMENT.md
- `CONFIGURATION.md` — environment variable reference (existing, unchanged)
- `sql_queries/README.md` — database setup reference (existing, unchanged)
