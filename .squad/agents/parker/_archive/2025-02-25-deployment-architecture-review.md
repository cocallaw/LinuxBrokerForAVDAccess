# Parker — Archived: Deployment Architecture Review (2025-02-25)

## Key Findings

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
