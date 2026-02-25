### Decision: Deployment Documentation Structure
**By:** Dallas (Backend Dev)
**Date:** 2025-07-25
**Status:** Implemented

#### What
Created `DEPLOYMENT.md` as the canonical end-to-end deployment guide. Updated `README.md` to replace the verbose "Getting Started" section with a concise "Deployment" section linking to DEPLOYMENT.md.

#### Why
- Documentation was fragmented across README.md, CONFIGURATION.md, sql_queries/README.md, deploy/QUICKSTART.md, and deploy_infrastructure/README.md. No single guide walked a user through the complete process.
- README.md had a "Getting Started" section that covered infrastructure but skipped database deployment, environment configuration, and post-deployment validation.
- New team scripts (Test-DeploymentReadiness.ps1, Test-PostDeployment.ps1, Deploy-Database.ps1, Test-DeploymentHealth) weren't surfaced in the main documentation flow.
- README.md referenced `DEPLOYMENT_IMPROVEMENTS.md` and `CONTRIBUTING.md` which didn't exist.

#### What Changed
1. **`DEPLOYMENT.md` (new):** 10-step deployment guide covering pre-flight checks → clone → prerequisites → app registrations → infrastructure → database → env vars → security groups → validation. Includes troubleshooting and a progress checklist.
2. **`README.md` (updated):** "Getting Started" replaced with "Deployment" section — quick-start snippet + table linking to DEPLOYMENT.md, CONFIGURATION.md, sql_queries/README.md, and deploy/QUICKSTART.md. Fixed broken references to nonexistent files.

#### Impact
- **All agents:** DEPLOYMENT.md is the canonical "how to deploy" reference. If you add deployment steps, add them there.
- **Parker:** deploy/ vs deploy_infrastructure/ distinction is documented in DEPLOYMENT.md.
- **Kane:** Test-DeploymentReadiness.ps1 and Test-PostDeployment.ps1 are now prominently featured in Steps 0 and 9.
- **Ash:** Deploy-Database.ps1 is Step 5 in the guide.
- **Lambert:** Frontend env config is covered in Step 6d.
