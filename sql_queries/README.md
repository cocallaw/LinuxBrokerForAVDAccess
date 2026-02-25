## Database Setup and SQL Procedures

The `sql_queries` directory contains all SQL scripts to set up the Azure SQL Database for the Linux Broker for AVD Access solution. All scripts are **idempotent** — safe to run multiple times without errors.

### Tables

| Table | Script | Description |
|-------|--------|-------------|
| **VmScalingRules** | `001_create_table-vm_scaling_rules.sql` | Scaling rules with temporal versioning (history table: `VmScalingRulesHistory`). Includes seed data. |
| **VmScalingActivityLog** | `002_create_table-vm_scaling_activity_log.sql` | Audit log of scaling actions (scale up, scale down, no action). |
| **VirtualMachines** | `003_create_table-virtual_machines.sql` | VM inventory with temporal versioning (history table: `VirtualMachinesHistory`). Tracks hostname, IP, power state, network status, VM status, user, and AVD host. |
| **VmUsers** | `024_create_table-vmusers.sql` | User registry (uid, username) for VM access. |

### Stored Procedures (19 total)

| Script | Procedure | Purpose |
|--------|-----------|---------|
| `005` | CheckoutVm | Checks out an available VM to a user/AVD host |
| `006` | DeleteVm | Removes a VM record |
| `007` | AddVm | Registers a new VM |
| `008` | GetVmDetails | Retrieves details for a specific VM |
| `009` | ReturnVm | Returns a VM to the available pool |
| `010` | GetScalingRules | Lists all scaling rules |
| `011` | UpdateScalingRule | Updates an existing scaling rule |
| `012` | TriggerScalingLogic | Evaluates utilization and scales up/down |
| `013` | GetScalingActivityLog | Queries scaling activity with date filters |
| `014` | GetVms | Lists all VMs |
| `015` | CreateScalingRule | Creates a new scaling rule |
| `016` | ReleaseVm | Marks a VM as released (by hostname) |
| `017` | UpdateVmAttributes | Updates power state, network, or VM status |
| `018` | ReturnReleasedVms | Auto-returns VMs released >30 minutes |
| `019` | DeleteScalingRule | Deletes a scaling rule |
| `020` | GetVmHistory | Queries temporal history of VM changes |
| `021` | GetVmScalingRulesHistory | Queries temporal history of scaling rules |
| `022` | GetScalingRuleDetails | Gets details for a specific rule |
| `023` | GetDeletedVirtualMachines | Finds VMs deleted from the main table |

### Performance Indexes

Script `025_add_indexes.sql` creates non-clustered indexes on frequently queried columns:

- **VirtualMachines**: `VmStatus`, `Username`, `Hostname`, `AvdHost`
- **VmScalingActivityLog**: `CheckTimestamp` (descending)

### Prerequisites

- **Azure SQL Database** — an existing instance (any tier)
- **SQL Client** — `sqlcmd`, Azure Data Studio, or SSMS
- **Permissions** — ability to create tables, procedures, and indexes
- **Network** — firewall rule allowing your client IP to reach the Azure SQL server

### Automated Deployment (Recommended)

Use the included PowerShell script to deploy all scripts in the correct order:

```powershell
# SQL Authentication
.\Deploy-Database.ps1 -ServerName "myserver.database.windows.net" `
                      -DatabaseName "linuxbroker" `
                      -Username "sqladmin" `
                      -Password "YourPassword"

# Azure AD Authentication
.\Deploy-Database.ps1 -ServerName "myserver.database.windows.net" `
                      -DatabaseName "linuxbroker" `
                      -UseAzureAD
```

The script will:
1. Test database connectivity before deploying
2. Execute all scripts in dependency order
3. Print per-script pass/fail status
4. Report a summary with total succeeded/failed count

### Manual Deployment

If deploying manually, execute scripts in this exact order:

#### Step 1 — Tables

```bash
sqlcmd -S <server> -d <database> -U <user> -P <pass> -i 001_create_table-vm_scaling_rules.sql
sqlcmd -S <server> -d <database> -U <user> -P <pass> -i 002_create_table-vm_scaling_activity_log.sql
sqlcmd -S <server> -d <database> -U <user> -P <pass> -i 003_create_table-virtual_machines.sql
sqlcmd -S <server> -d <database> -U <user> -P <pass> -i 024_create_table-vmusers.sql
```

#### Step 2 — Stored Procedures

```bash
# Run scripts 005 through 023 in numeric order
sqlcmd -S <server> -d <database> -U <user> -P <pass> -i 005_create_procedure-CheckoutVm.sql
# ... continue through 023
```

#### Step 3 — Performance Indexes

```bash
sqlcmd -S <server> -d <database> -U <user> -P <pass> -i 025_add_indexes.sql
```

### Post-Deployment Verification

```sql
-- Verify tables
SELECT name FROM sys.tables
WHERE name IN ('VmScalingRules', 'VmScalingActivityLog', 'VirtualMachines', 'VmUsers');

-- Verify procedures (expect 19)
SELECT COUNT(*) AS ProcedureCount FROM sys.procedures;

-- Verify indexes
SELECT i.name, t.name AS TableName
FROM sys.indexes i JOIN sys.tables t ON i.object_id = t.object_id
WHERE i.name LIKE 'IX_%';

-- Verify seed data
SELECT COUNT(*) AS ScalingRuleCount FROM VmScalingRules;
```

You can also run `deploy_database.sql` in your SQL client — it contains all verification queries.

### Idempotency

All scripts are designed for safe re-execution:

- **Tables**: Wrapped with `IF OBJECT_ID(...) IS NULL` — skips creation if the table already exists
- **Stored Procedures**: Use `CREATE OR ALTER PROCEDURE` — creates or updates in place
- **Indexes**: Check `sys.indexes` before creating — skips if the index exists
- **Seed Data**: Only inserts if the table is empty

### Granting Permissions

After deployment, grant execute permissions to application identities:

```sql
-- For managed identity or SQL user
GRANT EXECUTE ON SCHEMA::dbo TO [your-app-identity];
```

### Troubleshooting

| Issue | Resolution |
|-------|------------|
| Connection refused | Add your client IP to the Azure SQL firewall rules |
| Permission denied | Ensure your user has `db_ddladmin` and `db_datawriter` roles |
| Table already exists (old scripts) | Update to the latest idempotent scripts from this directory |
| `sqlcmd` not found | Install via `apt install mssql-tools` (Linux) or download from Microsoft |
| Temporal table errors | Temporal tables require Azure SQL or SQL Server 2016+. Not supported on SQL Express |