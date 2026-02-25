-- ============================================================================
-- Linux Broker for AVD Access — Master Database Deployment Script
-- ============================================================================
--
-- PURPOSE:
--   Documents the correct execution order for all SQL scripts.
--   Azure SQL does not support :r (SQLCMD include), so use the companion
--   Deploy-Database.ps1 PowerShell script for automated execution.
--
-- EXECUTION ORDER:
--   Step 1: Tables (must be created before procedures reference them)
--     001_create_table-vm_scaling_rules.sql    — VmScalingRules + seed data
--     002_create_table-vm_scaling_activity_log.sql — VmScalingActivityLog
--     003_create_table-virtual_machines.sql     — VirtualMachines (temporal)
--     024_create_table-vmusers.sql              — VmUsers
--
--   Step 2: Stored Procedures (depend on tables from Step 1)
--     005_create_procedure-CheckoutVm.sql
--     006_create_procedure-DeleteVm.sql
--     007_create_procedure-AddVm.sql
--     008_create_procedure-GetVmDetails.sql
--     009_create_procedure-ReturnVm.sql
--     010_create_procedure-GetScalingRules.sql
--     011_create_procedure-UpdateScalingRule.sql
--     012_create_procedure-TriggerScalingLogic.sql
--     013_create_procedure-GetScalingActivityLog.sql
--     014_create_procedure-GetVms.sql
--     015_create_procedure-CreateScalingRule.sql
--     016_create_procedure-ReleaseVm.sql
--     017_create_procedure-UpdateVmAttributes.sql
--     018_create_procedure-ReturnReleasedVms.sql  (depends on ReturnVm)
--     019_create_procedure-DeleteScalingRule.sql
--     020_create_procedure-GetVmHistory.sql
--     021_create_procedure-GetVmScalingRulesHistory.sql
--     022_create_procedure-GetScalingRuleDetails.sql
--     023_create_procedure-GetDeletedVirtualMachines.sql
--
--   Step 3: Performance Indexes
--     025_add_indexes.sql
--
-- IDEMPOTENCY:
--   All scripts are safe to run multiple times. Tables use IF NOT EXISTS
--   checks, procedures use CREATE OR ALTER, indexes check sys.indexes.
--
-- AUTOMATED DEPLOYMENT:
--   Use Deploy-Database.ps1 in this directory. Example:
--     .\Deploy-Database.ps1 -ServerName "myserver.database.windows.net" `
--                           -DatabaseName "linuxbroker" `
--                           -Username "sqladmin" `
--                           -Password "***"
--
-- POST-DEPLOYMENT VERIFICATION:
--   Run the queries below to confirm deployment succeeded.
-- ============================================================================

-- Verify tables exist
SELECT 'Tables' AS CheckType, name AS ObjectName, type_desc AS ObjectType
FROM sys.tables
WHERE name IN ('VmScalingRules', 'VmScalingActivityLog', 'VirtualMachines', 'VmUsers',
               'VmScalingRulesHistory', 'VirtualMachinesHistory')
ORDER BY name;
GO

-- Verify stored procedures exist
SELECT 'Procedures' AS CheckType, name AS ObjectName, type_desc AS ObjectType
FROM sys.procedures
ORDER BY name;
GO

-- Verify indexes exist
SELECT 'Indexes' AS CheckType, i.name AS IndexName, t.name AS TableName
FROM sys.indexes i
JOIN sys.tables t ON i.object_id = t.object_id
WHERE i.name LIKE 'IX_%'
ORDER BY t.name, i.name;
GO

-- Verify seed data
SELECT
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS: VmScalingRules seeded with ' + CAST(COUNT(*) AS VARCHAR) + ' rule(s).'
        ELSE 'FAIL: VmScalingRules has no seed data.'
    END AS SeedValidation
FROM dbo.VmScalingRules;
GO

PRINT '=== Deployment verification complete. ===';
GO
