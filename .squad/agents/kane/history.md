# Kane — History

## Project Context
- **Project:** Linux Broker for AVD Access
- **Stack:** Azure PaaS (AVD, App Service, Azure Functions, Azure SQL DB, Key Vault), PowerShell, Bicep, Node.js, SQL, Linux (XRDP, xpra)
- **User:** Corey Callaway
- **Purpose:** Broker user access to Linux VMs via Azure Virtual Desktop with session management, auto-scaling, and admin portal

## Learnings

### Deployment Testing (2025)
- Created `deploy/Test-DeploymentReadiness.ps1` — pre-deployment validation (tools, Azure access, providers, JSON configs, repo structure, env vars). Outputs a pass/fail table.
- Created `deploy/Test-PostDeployment.ps1` — post-deployment validation (API health, DB via API, Key Vault, AVD host pool, Linux VMs, SQL Server, App Service). Requires `-ApiBaseUrl`; optionally takes `-ResourceGroupName` for Azure resource checks.
- Created `sql_queries/test_schema.sql` — validates all 6 tables (incl. history tables), 19 stored procedures, key columns, primary keys, temporal versioning, and check constraints. Uses `#SchemaResults` temp table for reporting.
- Existing `deploy/Check-Prerequisites.ps1` was already present — new `Test-DeploymentReadiness.ps1` complements it with structured pass/fail output and additional checks (JSON validation, env vars, resource providers including DesktopVirtualization).
- The API is Python Flask (`api/app.py`), not Node.js — the front_end is the Node.js component.
- API routes include `/api/version` (unauthenticated), `/api/vms`, `/api/scaling/rules` etc.
- Database: Azure SQL with temporal tables (VirtualMachines, VmScalingRules have system versioning).
- Config files live in `configs/` (JSON deployment profiles) and root (`app-registration-config.json`, `vm-deployment-config.example.json`).
- User directive: no local dev setup or Docker containers.
