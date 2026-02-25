# Lambert — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Learnings

### Frontend Architecture & Stack
- **Framework:** Flask 2.2.2 (Python web framework)
- **Runtime:** Python 3.11 on Azure App Service (Linux)
- **Session Storage:** Filesystem-based (Flask-Session)
- **Authentication:** Azure AD (MSAL) using ConfidentialClientApplication with client credentials
- **Static Hosting:** Bootstrap 5.3.0 CDN + local static files (no build process)
- **Server:** Gunicorn (production WSGI server)
- **Deployment:** ZIP file deployment to Azure App Service via PowerShell script

### Code Organization
- **Routes:** Modular route files (route_authentication.py, route_vm_management.py, route_scaling_management.py, route_user.py)
- **Templates:** Jinja2 templates organized by feature (vm/, scaling/, base layout)
- **Static Assets:** Bootstrap CSS and favicon only
- **Configuration:** Environment variables via config.py (12 vars: CLIENT_ID, TENANT_ID, API_URL, etc.)

### Deployment Process
**Current Deployment Flow:**
1. PowerShell script (Deploy-LinuxBroker.ps1) compresses front_end/* to frontend.zip
2. ZIP deployed via `az webapp deploy` to App Service
3. App Service builds on deployment (SCM_DO_BUILD_DURING_DEPLOYMENT=true)
4. Environment variables injected via Bicep (infrastructure/main.bicep)
5. API_URL set to dynamically generated API App Service URL

### Configuration & Environment
- **env.example** provides 10 required fields (Flask key, Azure AD credentials, API URL, Application Insights)
- **config.py** reads 6 environment variables directly from os.environ
- **Bicep Template:** Sets APP_SERVICE_PLAN_SKU to P1v3, Python 3.11, alwaysOn=true
- **API Connection:** Simple hardcoded requests library calls to API_URL endpoints

### Key Findings

#### ✅ Strengths
1. **Simple & Maintainable:** ~1,000 lines of Python code across 5 files; easy to understand
2. **Secure Configuration:** All secrets in env.example; no hardcoded credentials
3. **Standard Stack:** Flask + Jinja2 is industry standard, well-documented
4. **Modular Routes:** Feature-based separation of concerns
5. **HTTPS Enforced:** App Service configured with httpsOnly=true in Bicep
6. **Managed Identity:** App Service has SystemAssigned identity for future use

#### ⚠️ Deployment Experience Issues
1. **Manual Environment Variable Setup:** Deployer must populate 10+ env vars manually; no validation script
   - No pre-deployment validation of config completeness
   - No example of working env.example → actual deployment
   - env.example lists "Linbux Broker API" (typo)

2. **Session Storage on Filesystem:** Flask-Session stores user sessions as files in /tmp
   - Not scalable for multi-instance deployments (sticky sessions required)
   - High-latency file I/O in containerized environment
   - Sessions lost on app restart

3. **No Local Development Story:** 
   - No requirements.txt for local dev (has front_end/requirements.txt but unclear if compatible with all OSes)
   - No run-local.sh or Makefile for `make dev`
   - No Docker setup for consistent local environment
   - Developers must manually set env vars locally

4. **Dependencies Not Current:**
   - Flask 2.2.2 (Oct 2022) - 18+ months old; latest is 3.1.x
   - Werkzeug 2.2.2 pinned to match Flask 2.2.2
   - requests 2.26.0 (Aug 2021) - ancient, 3+ years old
   - msal 1.31.0 (recent, good)
   - cryptography 43.0.3 (recent, good)

5. **API Error Handling:** All API calls use generic try/catch with user flash message; no retry logic
   - Network timeouts not handled
   - 401/403 responses not distinguished (might redirect to login)

6. **No Build Automation:**
   - No linting (flake8, pylint)
   - No unit tests visible
   - No pre-commit hooks
   - CI/CD pipeline (squad-ci.yml) only runs Node.js tests, not Python frontend

7. **Static Assets:** Bootstrap CDN for CSS + inline <style> tags for custom CSS
   - No asset versioning for cache busting
   - No minification or bundling

8. **Database/State:**
   - No database migrations or schema versioning
   - SQL scripts must be run manually before frontend deployment

### Deployment Steps Identified
**Current Manual Steps:**
1. Create Azure Resources (RG, App Service Plan, App Service)
2. Manually set 10+ environment variables in App Service
3. Run SQL migration scripts
4. Compress front_end/* and deploy via PowerShell script
5. Verify health via browser login

**Improvements Needed:**
- Add validation script for env vars before deployment
- Containerize frontend (Dockerfile) for consistent builds
- Extract CSS to separate file with versioning
- Upgrade dependencies (Flask, requests) for security
- Add local dev setup (docker-compose or .devcontainer)
- Add pre-deployment checklist documentation
- Implement Redis for session storage
- Add linting and tests to CI/CD

### Key Files & Paths
- **App Entry:** front_end/app.py (61 lines, clean structure)
- **Configuration:** front_end/config.py (9 lines, simple env reader)
- **Auth Logic:** front_end/route_authentication.py (81 lines, Azure AD + MSAL)
- **VM Management:** front_end/route_vm_management.py (280 lines)
- **Scaling Management:** front_end/route_scaling_management.py (338 lines)
- **Templates:** front_end/templates/ (852 lines total, organized by feature)
- **Deployment Script:** deploy/Deploy-LinuxBroker.ps1 (line 679 for frontend)
- **Infrastructure:** bicep/infrastructure/main.bicep (line 151 for frontend App Service)

---

## Cross-Agent Learnings (2026-02-25)

### Team Findings on Deployment Experience Review

**Ripley (Architecture/Lead)** found:
- Configuration scattered across 8+ files with unclear dependencies
- Hardcoded placeholder values in custom script extensions
- Database schema deployment is manual with no validation
- Multi-step deployment requires strict ordering but isn't enforced
- Recommended unified configuration wizard and post-deployment validation

**Parker (Infra/DevOps)** found:
- Two deployment directories confusing users (deploy/ vs. deploy_infrastructure/)
- Deploy-LinuxBroker.ps1 is monolithic (884 lines), hard to modify
- No idempotency — script assumes fresh state
- Database schema deployment stubbed out
- Missing deployment manifest/log for troubleshooting

**Dallas (Backend)** found:
- API has 17 environment variables with no startup validation
- Hardcoded API URLs in Broker Agent script require manual editing
- Function timer schedules hardcoded in decorators (requires code redeploy)
- Four distribution-specific Session Release Agent scripts = maintenance
- 24 SQL scripts with no automation in deployment

**Ash (Database)** found:
- SQL scripts not idempotent — all CREATE statements fail on re-deployment
- No schema version tracking
- Missing performance indexes on frequently queried columns
- VmUsers table added but not documented
- No pre-flight connectivity validation

### Key Cross-Team Patterns
1. **Configuration Scattered:** 17+ env vars (API/Functions/Frontend) with no centralized validation
2. **Manual Dependencies:** SQL, app config, RBAC all separate steps post-infrastructure
3. **Hardcoded Values:** API URLs, timer schedules, distro-specific scripts
4. **No Idempotency:** All components assume fresh state; re-runs fail
5. **Missing Validation:** Users can't tell if deployment succeeded

### Frontend-Specific Coordination
1. **With Dallas:** Coordinated .env.template and environment validation (17 API vars + 10 frontend vars)
2. **With Parker:** Redis migration for session storage (managed by Parker's Bicep)
3. **Team:** Create deployment validation script to verify config before first login
4. **Dependencies:** Flask and requests upgrades needed (security CVEs)

### Deployment Improvements (Implemented)
1. **Dependencies Updated:** Flask 2.2.2→3.1.1, Werkzeug pinned→>=3.1.0, requests 2.26.0→2.32.3. Dry-run verified all resolve cleanly with existing deps (msal, Flask-Session, pyjwt, cryptography).
2. **Environment Validation:** app.py now validates 6 required env vars at startup and exits with clear error listing missing vars. Validation runs before Flask app is created.
3. **`.env.template` Created:** Comprehensive template with descriptions, example GUID formats, and generation tips (e.g. `python3 -c "import secrets; print(secrets.token_hex(32))"`). Also fixed "Linbux" typo in env.example.
4. **Health Check Endpoint:** `/health` returns JSON with status, version, and api_reachable flag (pings API's /health with 5s timeout). Unauthenticated — suitable for Azure App Service health probes and post-deployment validation.
5. **Key Design Decisions:**
   - Flask 3.x chosen over staying on 2.x: app only uses stable APIs (routes, templates, session, flash) — no deprecated features in use. Verified compatibility with `ast.parse` and dry-run pip install.
   - Health endpoint deliberately unauthenticated to allow Azure health probes and monitoring tools.
   - `requests` imported as `req_lib` in app.py to avoid shadowing the `requests` module already imported in route files.
   - Env validation happens at module load (before `app = Flask(...)`) so gunicorn workers fail fast with clear messaging.

### Cross-Agent Updates (2026-02-25)
- **Parker:** Can wire `/health` endpoint into App Service health check configuration in Bicep. Frontend provides JSON response with api_reachable status for monitoring.
- **Dallas:** Portal now pings `{API_URL}/health` endpoint. Consider adding `/health` endpoint to the API if one doesn't exist. `.env.template` now serves as canonical list of all frontend env vars.
- **All:** Dependency updates completed — no local dev Docker setup required per user preference.
