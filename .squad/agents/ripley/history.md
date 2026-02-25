# Ripley — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Learnings

### Deployment Architecture Review (2025-02-26)

**Key Findings:**
- Solution has solid foundational scripting with 90+ error handling checks
- **Main UX issue:** Configuration scattered across 8+ files with unclear dependencies
- **Top blocker:** Hardcoded placeholder values in Linux host custom script extensions (ORG_ID, ACTIVATION_KEY, API_CLIENT_ID)
- Database schema deployment is manual step with no validation before API startup
- Multi-step deployment requires strict ordering (Setup-AppReg → Deploy → Configure VMs) but this isn't enforced

**Top 5 Improvements (Priority Order):**
1. Unified configuration management + interactive setup wizard (P0, 1-2 sprints)
2. Fix hardcoded placeholders in custom script extensions via parameter passing (P0, 1-2 sprints)
3. Post-deployment validation script + troubleshooting guide (P1, 1-2 sprints)
4. Automated database schema deployment via SQL execution in PowerShell (P0, 1 sprint)
5. Master orchestration script enforcing step ordering + resumable checkpoints (P1, 1 sprint)

**Architecture Strengths:**
- Error handling with fallback mechanisms (90+ checks in Deploy-LinuxBroker.ps1)
- Modular Bicep templates with clear resource dependencies
- Security-conscious: managed identities, Key Vault, no hardcoded secrets in code
- Flexibility: VM deployment supports multiple configurations (AVD-only, Linux-only, full)
- Cleanup tooling available (Cleanup-LinuxBroker.ps1)

**Configuration Complexity:**
- Users must manage: API config, Frontend config, Function App config, VM config, app-registration config, Key Vault secrets, Azure AD roles
- No unified onboarding or single happy path
- Documentation split across README.md, QUICKSTART.md, sql_queries/README.md

**Deployment Decision:**
- Prioritize UX improvements over feature additions; current friction creates support burden
- Owner: Ripley (architecture oversight) with team execution

**Files to Know:**
- `deploy/Deploy-LinuxBroker.ps1` (884 lines, monolithic orchestrator)
- `custom_script_extensions/Configure-*.sh` (hardcoded values issue; RHEL 7-9, Ubuntu 24)
- `bicep/infrastructure/main.bicep` (core resource creation)
- `vm-deployment-config.example.json` (configuration template for VMs)
- `sql_queries/README.md` (manual schema deployment; needs automation)

---

## Cross-Agent Learnings (2026-02-25)

### Team Findings on Deployment Experience Review

**Parker (Infra/DevOps)** found:
- Deploy/deploy_infrastructure directories are confusing; recommend consolidation
- Deploy-LinuxBroker.ps1 is monolithic (884 lines); hard to test individual steps
- No idempotency — script assumes fresh state each run
- Database schema deployment is stubbed out, not implemented
- No deployment manifest created for troubleshooting
- PowerShell scripts missing ErrorActionPreference = "Stop"

**Dallas (Backend)** found:
- API has 17 environment variables scattered with no validation on startup
- Hardcoded API URLs in Broker Agent script require manual editing
- Function App timer schedules hardcoded in decorators (requires code redeploy)
- Four distribution-specific Session Release Agent scripts = maintenance debt
- 24 SQL scripts with no automation to run them in order
- No .env.template file for centralized configuration

**Lambert (Frontend)** found:
- 10+ environment variables with no validation script
- Flask-Session using filesystem storage (not suitable for cloud scale-out)
- Outdated dependencies: Flask 2.2.2 (18 months old), requests 2.26.0 (45 months old)
- No local development setup documented
- No Python tests or linting in CI/CD

**Ash (Database)** found:
- SQL scripts not idempotent — all CREATE statements fail on re-deployment
- No schema version tracking
- Missing performance indexes on frequently queried columns
- VmUsers table exists but not documented in deployment README
- No pre-flight connectivity check before running SQL scripts

### Key Cross-Team Patterns
1. **Configuration Scattered:** 17+ env vars across API/Functions/Frontend with no centralized validation
2. **Manual Dependencies:** SQL, app config, RBAC all manual steps post-infrastructure
3. **Hardcoded Values:** API URLs, timer schedules, distribution-specific scripts require manual editing
4. **No Idempotency:** All components assume fresh state; re-runs fail
5. **Missing Validation:** Users can't tell if deployment succeeded

### Unified Recommendations Across All Agents
1. Create `.env.template` at repo root (Dallas + Lambert ownership)
2. Add environment variable validation to all services (Dallas + Lambert)
3. Automate SQL schema deployment with idempotent scripts (Ash + Dallas)
4. Create unified configuration wizard (Ripley + Parker)
5. Create post-deployment validation script (Ripley + Parker)
6. Parameterize custom script extensions (Parker + Dallas)
7. Create master orchestration script (Ripley with support from team)
8. Consolidate deploy directories (Parker)
9. Migrate frontend sessions to Redis (Lambert + Parker)
10. Update outdated dependencies (Lambert)
