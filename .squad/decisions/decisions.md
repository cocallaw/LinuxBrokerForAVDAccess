# Squad Decisions

**Project:** Linux Broker for AVD Access  
**Last Updated:** 2026-02-25  
**Status:** Active Decisions

---

## Decision: Prioritize Deployment UX Over Feature Additions

**ID:** DEPLOY-2026-001  
**Date:** 2026-02-25  
**Owner:** Ripley (with input from Parker, Dallas, Lambert, Ash)  
**Status:** ACCEPTED  
**Priority:** P0

### Rationale
After comprehensive deployment experience reviews across all team members:
- Current architecture requires management of **6+ separate configuration files/steps**
- Configuration complexity creates **high user friction and support burden**
- **8+ configuration touch points** with unclear dependencies
- **Manual ordering** of multi-step deployment creates fragile state
- **Post-deployment validation missing** — users can't tell if deployment succeeded

Fixing configuration management and validation would dramatically improve adoption, reduce support tickets, and enable self-service deployment.

### Affected Components
- Deployment pipeline
- Bicep templates  
- PowerShell scripts
- Frontend/Backend configuration
- Database schema deployment
- Documentation

### Implementation Timeline
**Phase 1:** Unified Configuration Management + Hardcoded Placeholder Fix (1-2 sprints)  
**Phase 2:** Post-Deployment Validation + Database Schema Automation (1-2 sprints)  
**Phase 3:** Multi-Step Orchestration + Documentation Consolidation (1 sprint)  

### Success Criteria
1. First-time deployment completes without manual file editing
2. Deployment validation script catches 90%+ of configuration issues
3. Users can re-run deployment safely (idempotency)
4. Database schema deploys automatically as part of orchestration
5. Documentation consolidates to single Getting Started guide

---

## Decision: Consolidate Deployment Directories

**ID:** DEPLOY-2026-002  
**Date:** 2026-02-25  
**Owner:** Parker  
**Status:** ACCEPTED  
**Priority:** P1

### Issue
Two deployment directories (`deploy/` and `deploy_infrastructure/`) with overlapping purpose cause user confusion:
- `deploy/` contains 6 scripts (2,409 lines total)
- `deploy_infrastructure/` contains 1 utility script
- Users don't know which directory to work from

### Decision
Consolidate into single `deploy/` directory with clear subfolders if organization is needed.

### Implementation
Move `deploy_infrastructure/Assign-AppRoleToFunctionApp.ps1` to `deploy/` and delete `deploy_infrastructure/` directory.

---

## Decision: Implement Idempotent Database Scripts

**ID:** DEPLOY-2026-003  
**Date:** 2026-02-25  
**Owner:** Ash  
**Status:** ACCEPTED  
**Priority:** P0

### Issue
All SQL CREATE scripts fail on re-deployment:
- Blocks safe re-runs
- Prevents CI/CD patterns
- Makes debugging harder

### Decision
Convert all `CREATE` statements to idempotent patterns:
- Use `CREATE IF NOT EXISTS` for tables
- Use `DROP IF EXISTS ... CREATE` for stored procedures
- Add seed verification for VmScalingRules

### Success Criteria
- Fresh deployment succeeds
- Re-deployment succeeds without modification
- Schema version tracking implemented

---

## Decision: Create Unified Configuration Wizard

**ID:** DEPLOY-2026-004  
**Date:** 2026-02-25  
**Owner:** Ripley + Parker  
**Status:** ACCEPTED  
**Priority:** P0

### Issue
Users must manage 6+ separate configuration files/steps with no validation:
- `vm-deployment-config.example.json`
- `app-registration-config.json`
- Multiple `.env` files
- Hardcoded placeholders in scripts

### Decision
Create interactive **deployment wizard** (`deploy/Interactive-Setup.ps1`) that:
- Prompts for Azure subscription, region, resource groups
- Generates all configs in one pass
- Validates each input before saving
- Outputs checklist of created resources
- Stores all configs in `./.linuxbroker-deployment/` directory

### Benefits
- Single entry point for deployment
- Input validation prevents configuration errors
- Generated configs can be version-controlled
- Clear visibility of deployment state

---

## Decision: Automate Post-Deployment Validation

**ID:** DEPLOY-2026-005  
**Date:** 2026-02-25  
**Owner:** Ripley + Parker  
**Status:** ACCEPTED  
**Priority:** P1

### Issue
Deployment script ends with vague checklist of "next steps"; users can't verify if deployment actually works:
- No health endpoint checking
- No database connectivity validation
- No Function App authentication testing
- No VM-to-API communication validation
- No clear recovery path on failure

### Decision
Create **post-deployment validation script** (`deploy/Validate-Deployment.ps1`) that:
- Calls API health endpoint
- Checks database connectivity
- Validates Function App can authenticate
- Tests VM-to-API communication (if VMs deployed)
- Provides clear error messages with remediation steps

### Success Criteria
- Deployment success/failure determined programmatically
- Clear error messages point to root causes
- Troubleshooting guide linked to error messages

---

## Decision: Parameterize Custom Script Extensions

**ID:** DEPLOY-2026-006  
**Date:** 2026-02-25  
**Owner:** Parker + Dallas  
**Status:** ACCEPTED  
**Priority:** P0

### Issue
Custom script extensions have placeholder values that must be manually edited:
- `YOUR_LINUXBROKER_API_CLIENT_ID="my_actual_client_id"`
- `YOUR_LINUXBROKER_API_URL="my.actual.linuxbroker.api.url"`
- `orgId="ORG_ID"` and `activationKey="ACTIVATION_KEY"`

Bicep passes values but scripts don't read them reliably.

### Decision
Refactor custom script extensions to accept parameters from Bicep:
- Use cloud-init or ARM template parameter passing
- Make RHEL registration optional with clear fallback
- Add validation in scripts to verify API connectivity before marking VM ready

### Success Criteria
- Custom script extensions accept all required values as parameters
- No manual editing required post-deployment
- VM configuration validated automatically

---

## Decision: Create Master Orchestration Script

**ID:** DEPLOY-2026-007  
**Date:** 2026-02-25  
**Owner:** Ripley  
**Status:** ACCEPTED  
**Priority:** P1

### Issue
Multi-step deployment dependencies not enforced:
- Users can run steps out of order
- No clear checkpoint system
- Difficult to resume from failure

### Decision
Create **master orchestration script** (`deploy/Deploy-Complete.ps1`) that:
- Enforces step ordering
- Validates each step succeeded before proceeding
- Allows resuming from failure point
- Clearly documents which steps are optional
- Saves deployment manifest after each step

### Success Criteria
- Deployment follows enforced order
- Can resume from failure without re-running earlier steps
- Manifest shows what was deployed and when

---

## Decision: Add Environment Variable Validation

**ID:** DEPLOY-2026-008  
**Date:** 2026-02-25  
**Owner:** Dallas + Lambert  
**Status:** ACCEPTED  
**Priority:** P0

### Issue
17+ environment variables scattered across configs with no validation:
- No check that required vars exist
- Errors surface at runtime
- Configuration example files outdated

### Decision
1. Create `.env.template` at repo root with ALL required env vars
2. Add validation layer to API startup:
   - Check required vars exist
   - Print validation report
   - Fail early with clear error message
3. Add validation script to deployment workflow
4. Update env.example files to be current and complete

### Success Criteria
- Deployment fails fast with clear error if config incomplete
- All required env vars documented in .env.template
- Example files match actual code requirements

---

## Decision: Automate SQL Schema Deployment

**ID:** DEPLOY-2026-009  
**Date:** 2026-02-25  
**Owner:** Ash + Dallas  
**Status:** ACCEPTED  
**Priority:** P0

### Issue
Database schema deployment is manual:
- 24 SQL scripts must be run in specific order
- No automation in deployment script
- No validation that schema exists before API starts

### Decision
Add database initialization step to deployment script:
- Create SQL connection from PowerShell
- Execute all SQL scripts in correct order
- Validate connection before attempting migration
- Return success/failure to deployment log
- Add schema version tracking

### Success Criteria
- Database schema deploys automatically during orchestration
- Schema version tracked
- API validates required tables/procedures exist on startup

---

## Decision: Consolidate Linux Host Configuration Scripts

**ID:** DEPLOY-2026-010  
**Date:** 2026-02-25  
**Owner:** Dallas  
**Status:** PROPOSED  
**Priority:** P2

### Issue
Four separate distribution-specific scripts (RHEL 7/8/9, Ubuntu 24) create maintenance debt.

### Proposed Decision
Consolidate into two scripts (RHEL and Ubuntu) with distro detection, instead of maintaining four separate versions.

### Status
Proposed — pending schedule and priority review.

---

## Decision: Migrate Frontend Session Storage to Redis

**ID:** DEPLOY-2026-011  
**Date:** 2026-02-25  
**Owner:** Lambert + Parker  
**Status:** ACCEPTED  
**Priority:** P1

### Issue
Flask-Session stores sessions as files (filesystem):
- Sessions lost on app restart
- Not scalable for multi-instance deployments
- High-latency file I/O in containerized environment
- No persistence across deployments

### Decision
Migrate to Azure Cache for Redis (managed service):
- Update Flask-Session config to use Redis backend
- Add Redis connection to Bicep template
- Configure managed identity access
- Test multi-instance deployments

### Success Criteria
- Sessions persist across app restarts
- Multi-instance deployments work without sticky sessions
- Session latency improves

---

## Decision: Update Outdated Dependencies

**ID:** DEPLOY-2026-012  
**Date:** 2026-02-25  
**Owner:** Lambert  
**Status:** ACCEPTED  
**Priority:** P1

### Issue
Frontend dependencies are outdated with known vulnerabilities:
- Flask 2.2.2 (Oct 2022, 18 months old)
- requests 2.26.0 (Aug 2021, 45 months old)

### Decision
- Pin Flask to 3.0.x series (security updates, backward compatible)
- Update requests to 2.31.x (LTS, security fixes)
- Run `pip audit` in CI/CD to detect vulnerabilities

### Success Criteria
- No known CVEs in dependencies
- CI/CD includes dependency vulnerability scanning

---

## Cross-Cutting Themes

### Configuration as Code
Need to move from manual env var setup to infrastructure-as-code:
- Use Bicep to define all App Service environment variables
- Validate configuration in PowerShell before deployment
- Generate .env files from Bicep outputs

### Idempotency
Enable safe re-runs and self-healing:
- PowerShell scripts check for existing resources
- SQL scripts use IF NOT EXISTS patterns
- Bicep templates support updates, not just creation

### Validation & Observability
Catch issues early:
- Pre-flight configuration validation
- Post-deployment health checks
- Centralized error logging and reporting
- Troubleshooting guides linked to error codes

### Documentation Consolidation
Reduce fragmentation:
- Single Getting Started guide
- Step-by-step deployment checklist
- Troubleshooting section for common issues
- Configuration reference guide

---

## Decision Review Calendar

- **Next Review:** 2026-03-25
- **Quarterly Review:** 2026-05-25
- **Owners:** Ripley (Architecture), Parker (Infra), Dallas (Backend), Lambert (Frontend), Ash (Data)
