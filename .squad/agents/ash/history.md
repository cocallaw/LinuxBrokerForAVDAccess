# Ash — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Learnings

### Database Architecture & Schema (Feb 2025)
- **Tables**: 4 core tables (VirtualMachines, VmScalingRules, VmScalingActivityLog, VmUsers)
- **Temporal Tables**: VirtualMachines and VmScalingRules use SQL Server temporal versioning (SYSTEM_VERSIONING) for audit trails and history
- **Stored Procedures**: 19 procedures providing VM checkout/return, scaling management, and status tracking
- **Error Handling**: Procedures use transaction management (BEGIN/COMMIT/ROLLBACK) and TRY/CATCH blocks for atomicity
- **Constraints**: CHECK constraints on scaling rules (MinVMs < MaxVMs, ScaleUpRatio > ScaleDownRatio) and power states
- **No Indexes**: Temporal tables and procedures lack explicit non-clustered indexes for frequently queried columns (Hostname, Username, VmStatus)
- **Authentication**: API uses pymssql with credentials from Key Vault; connection pool refreshes credentials hourly
- **Deployment Automation**: PowerShell script (Deploy-LinuxBroker.ps1) handles sequential SQL execution with fallback from SQL Auth → AAD → Azure CLI methods

### Deployment Experience Gaps (Identified - Feb 2025)
1. **Idempotency**: Most SQL scripts use CREATE (not CREATE IF NOT EXISTS or ALTER), risking re-deployment failures
2. **No Migration Framework**: No version control or rollback mechanism for schema changes
3. **Manual Ordering**: Relies on file naming convention (001_, 002_...) for execution order; no validation
4. **Deployment Documentation**: README.md step-by-step is thorough but lacks troubleshooting for common failures
5. **Missing vmusers Table**: File 024_create_table-vmusers.sql added recently but not documented in README.md
6. **No Seeding Script**: Scaling rules require manual INSERT; deployment doesn't validate initial state
7. **Performance Gaps**: No indexes on frequently accessed columns (Username, VmStatus, Hostname) in VirtualMachines
8. **Connection String Inconsistency**: Bicep uses "Active Directory Default" auth; deploy script uses SQL Auth + AAD Integrated fallback
9. **Firewall Management**: Deploy script creates firewall rules but doesn't validate database connectivity before script execution
10. **Error Suppression**: Deploy script treats warnings as success; some errors might be masked

---

## Cross-Agent Learnings (2026-02-25)

### Team Findings on Deployment Experience Review

**Ripley (Architecture/Lead)** found:
- Configuration scattered across 8+ files with unclear dependencies
- Hardcoded placeholder values in custom script extensions
- Database schema deployment is manual with no validation before API starts
- Multi-step deployment requires strict ordering but isn't enforced
- Recommended unified configuration wizard and post-deployment validation

**Parker (Infra/DevOps)** found:
- Two deployment directories causing confusion (deploy/ vs. deploy_infrastructure/)
- Deploy-LinuxBroker.ps1 is monolithic (884 lines)
- No idempotency — script assumes fresh state
- Database schema deployment is stubbed out, not implemented
- PowerShell scripts missing ErrorActionPreference = "Stop"

**Dallas (Backend)** found:
- API has 17 environment variables with no startup validation
- Hardcoded API URLs in Broker Agent script require manual editing
- Function timer schedules hardcoded in decorators (no flexibility)
- Four distribution-specific Session Release Agent scripts = maintenance debt
- 24 SQL scripts with no automation in deployment orchestration

**Lambert (Frontend)** found:
- 10+ environment variables with no validation script
- Flask-Session using filesystem storage (not cloud-scalable)
- Outdated dependencies: Flask 2.2.2 (18 months old), requests 2.26.0 (45 months old)
- No local development environment setup
- No Python tests or linting in CI/CD

### Key Cross-Team Patterns
1. **Configuration Scattered:** 17+ env vars across API/Functions/Frontend with no centralized validation
2. **Manual Multi-Step Dependencies:** SQL, app config, RBAC all separate steps
3. **Hardcoded Values Everywhere:** API URLs, timer schedules, distro-specific scripts
4. **No Idempotency:** SQL scripts, PowerShell, all components assume fresh state
5. **Missing Validation:** No way to verify deployment succeeded

### Ash-Specific Coordination Needs
1. **With Parker:** Implement automated SQL schema deployment in Deploy-LinuxBroker.ps1
2. **With Dallas:** Coordinate on idempotency changes for pymssql compatibility
3. **Team:** Create deployment validation script that verifies database schema exists and is current version
4. **Sequencing:** Database must initialize before API can start (deployment order critical)

### Deployment Improvements Implemented (Feb 2025)

1. **Idempotency**: All 24 SQL scripts are now safe to re-run:
   - 4 table scripts use `IF OBJECT_ID(...) IS NULL` guards
   - 19 stored procedures use `CREATE OR ALTER PROCEDURE` (Azure SQL native)
   - Removed hardcoded `USE linuxbroker;` — database context set by connection
   - Seed data in 001 only inserts if table is empty, with verification query

2. **Performance Indexes** (`025_add_indexes.sql`):
   - VirtualMachines: VmStatus (+ includes), Username (+ includes), Hostname, AvdHost
   - VmScalingActivityLog: CheckTimestamp DESC (+ includes)
   - All wrapped with `IF NOT EXISTS` on `sys.indexes`

3. **Deployment Automation**:
   - `Deploy-Database.ps1` — PowerShell wrapper executing all scripts in dependency order with connectivity test, per-script status, summary report, and error halting
   - `deploy_database.sql` — master reference documenting execution order + post-deployment verification queries
   - Supports SQL Auth and Azure AD auth

4. **README.md** rewritten: documents all 4 tables (including VmUsers), 19 procedures, index script, automated and manual deployment, verification queries, idempotency explanation, troubleshooting table

5. **Key Patterns**:
   - Azure SQL supports `CREATE OR ALTER PROCEDURE` natively — no need for DROP/CREATE or IF EXISTS wrappers
   - Azure SQL does NOT support `:r` (SQLCMD file includes) — must use external orchestration (PowerShell)
   - `$ErrorActionPreference = "Stop"` is critical in deployment scripts

### Cross-Agent Updates (2026-02-25)
- **Parker:** Should update Deploy-LinuxBroker.ps1 to call Deploy-Database.ps1 for the database deployment step. Database must initialize before API can start.
- **Dallas:** Procedures now use `CREATE OR ALTER PROCEDURE` (no behavioral change to pymssql callers). Coordinate on idempotency changes for compatibility.
- **All:** Database deployment now fully automated with verification queries. Team should monitor first production deployment for schema migration success.
