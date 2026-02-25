# Routing Rules

## Signal → Agent Mapping

| Signal / Keywords | Route To | Reason |
|-------------------|----------|--------|
| Architecture, design, scope, review, decisions | Ripley | Lead oversees architecture and code review |
| Frontend, portal, UI, management portal, React, components, dashboard | Lambert | Frontend Dev owns the Service Management Portal |
| API, broker, endpoint, Azure Functions, session, checkout, release, scaling logic | Dallas | Backend Dev owns the Broker API and Azure Functions |
| Bicep, deployment, infrastructure, Azure config, ARM, managed identity, Key Vault, networking, security groups | Parker | Infra/DevOps owns IaC and deployment scripts |
| SQL, database, queries, stored procedures, Azure SQL, tables, schema, data | Ash | Data Engineer owns SQL queries and database implementation |
| Tests, testing, QA, quality, edge cases, validation, coverage | Kane | Tester owns test creation and quality assurance |
| PowerShell, Connect-LinuxBroker, broker agent, custom script extensions | Dallas + Parker | Backend logic + infrastructure deployment |
| Linux host, XRDP, xpra, session release agent, cron | Dallas + Parker | Backend session management + Linux config |
| Scaling rules, auto-scaling, VM power state | Dallas + Ash | Backend scaling logic + database scaling tables |
| Full stack changes, multi-component | Ripley (triage) | Lead decomposes and assigns |

## Default

If no signal matches, route to **Ripley** for triage.
