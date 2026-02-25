-- test_schema.sql
-- Validates that the Linux Broker database schema is correctly deployed.
-- Run against the linuxbroker database after deploying all SQL scripts.
-- Usage: sqlcmd -S <server> -d linuxbroker -i sql_queries/test_schema.sql

USE linuxbroker;
GO

SET NOCOUNT ON;
GO

-- ============================================================
-- Temp table to collect results
-- ============================================================
CREATE TABLE #SchemaResults (
    ObjectType  NVARCHAR(30),
    ObjectName  NVARCHAR(128),
    Status      NVARCHAR(10),  -- PASS / FAIL
    Detail      NVARCHAR(256)
);

-- ============================================================
-- 1. EXPECTED TABLES
-- ============================================================
DECLARE @ExpectedTables TABLE (TableName NVARCHAR(128));
INSERT INTO @ExpectedTables VALUES
    ('VirtualMachines'),
    ('VmScalingRules'),
    ('VmScalingActivityLog'),
    ('VmUsers'),
    ('VirtualMachinesHistory'),
    ('VmScalingRulesHistory');

INSERT INTO #SchemaResults (ObjectType, ObjectName, Status, Detail)
SELECT
    'Table',
    et.TableName,
    CASE WHEN t.TABLE_NAME IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN t.TABLE_NAME IS NOT NULL THEN 'Exists' ELSE 'MISSING — run the corresponding CREATE TABLE script' END
FROM @ExpectedTables et
LEFT JOIN INFORMATION_SCHEMA.TABLES t
    ON t.TABLE_NAME = et.TableName
    AND t.TABLE_SCHEMA = 'dbo'
    AND t.TABLE_TYPE = 'BASE TABLE';

-- ============================================================
-- 2. EXPECTED STORED PROCEDURES
-- ============================================================
DECLARE @ExpectedProcs TABLE (ProcName NVARCHAR(128));
INSERT INTO @ExpectedProcs VALUES
    ('CheckoutVm'),
    ('DeleteVm'),
    ('AddVm'),
    ('GetVmDetails'),
    ('ReturnVm'),
    ('GetScalingRules'),
    ('UpdateScalingRule'),
    ('TriggerScalingLogic'),
    ('GetScalingActivityLog'),
    ('GetVms'),
    ('CreateScalingRule'),
    ('ReleaseVm'),
    ('UpdateVmAttributes'),
    ('ReturnReleasedVms'),
    ('DeleteScalingRule'),
    ('GetVmHistory'),
    ('GetVmScalingRulesHistory'),
    ('GetScalingRuleDetails'),
    ('GetDeletedVirtualMachines');

INSERT INTO #SchemaResults (ObjectType, ObjectName, Status, Detail)
SELECT
    'Procedure',
    ep.ProcName,
    CASE WHEN r.ROUTINE_NAME IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN r.ROUTINE_NAME IS NOT NULL THEN 'Exists' ELSE 'MISSING — run the corresponding CREATE PROCEDURE script' END
FROM @ExpectedProcs ep
LEFT JOIN INFORMATION_SCHEMA.ROUTINES r
    ON r.ROUTINE_NAME = ep.ProcName
    AND r.ROUTINE_SCHEMA = 'dbo'
    AND r.ROUTINE_TYPE = 'PROCEDURE';

-- ============================================================
-- 3. KEY COLUMNS (spot-check critical columns exist)
-- ============================================================
DECLARE @ExpectedColumns TABLE (TableName NVARCHAR(128), ColumnName NVARCHAR(128));
INSERT INTO @ExpectedColumns VALUES
    ('VirtualMachines', 'VMID'),
    ('VirtualMachines', 'Hostname'),
    ('VirtualMachines', 'IPAddress'),
    ('VirtualMachines', 'VmStatus'),
    ('VirtualMachines', 'Username'),
    ('VirtualMachines', 'AvdHost'),
    ('VmScalingRules', 'RuleID'),
    ('VmScalingRules', 'MinVMs'),
    ('VmScalingRules', 'MaxVMs'),
    ('VmScalingRules', 'ScaleUpRatio'),
    ('VmScalingRules', 'ScaleDownRatio'),
    ('VmScalingActivityLog', 'ActivityID'),
    ('VmUsers', 'uid'),
    ('VmUsers', 'username');

INSERT INTO #SchemaResults (ObjectType, ObjectName, Status, Detail)
SELECT
    'Column',
    ec.TableName + '.' + ec.ColumnName,
    CASE WHEN c.COLUMN_NAME IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN c.COLUMN_NAME IS NOT NULL THEN 'Exists' ELSE 'MISSING — column not found in table' END
FROM @ExpectedColumns ec
LEFT JOIN INFORMATION_SCHEMA.COLUMNS c
    ON c.TABLE_NAME = ec.TableName
    AND c.COLUMN_NAME = ec.ColumnName
    AND c.TABLE_SCHEMA = 'dbo';

-- ============================================================
-- 4. INDEXES (check primary keys exist)
-- ============================================================
DECLARE @ExpectedPKs TABLE (TableName NVARCHAR(128));
INSERT INTO @ExpectedPKs VALUES
    ('VirtualMachines'),
    ('VmScalingRules'),
    ('VmScalingActivityLog'),
    ('VmUsers');

INSERT INTO #SchemaResults (ObjectType, ObjectName, Status, Detail)
SELECT
    'Primary Key',
    epk.TableName,
    CASE WHEN i.name IS NOT NULL THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN i.name IS NOT NULL THEN 'PK: ' + i.name ELSE 'MISSING — no primary key on table' END
FROM @ExpectedPKs epk
LEFT JOIN sys.tables st ON st.name = epk.TableName AND SCHEMA_NAME(st.schema_id) = 'dbo'
LEFT JOIN sys.indexes i ON i.object_id = st.object_id AND i.is_primary_key = 1;

-- ============================================================
-- 5. SYSTEM VERSIONING (temporal tables)
-- ============================================================
INSERT INTO #SchemaResults (ObjectType, ObjectName, Status, Detail)
SELECT
    'Temporal',
    t.name,
    CASE WHEN t.temporal_type = 2 THEN 'PASS' ELSE 'FAIL' END,
    CASE WHEN t.temporal_type = 2
        THEN 'System-versioned — history table: ' + ISNULL(ht.name, 'unknown')
        ELSE 'NOT system-versioned — expected temporal table'
    END
FROM sys.tables t
LEFT JOIN sys.tables ht ON ht.object_id = t.history_table_id
WHERE t.name IN ('VirtualMachines', 'VmScalingRules')
    AND SCHEMA_NAME(t.schema_id) = 'dbo';

-- ============================================================
-- 6. CHECK CONSTRAINTS
-- ============================================================
DECLARE @ExpectedChecks TABLE (TableName NVARCHAR(128), Description NVARCHAR(128));
INSERT INTO @ExpectedChecks VALUES
    ('VirtualMachines', 'PowerState IN check'),
    ('VirtualMachines', 'NetworkStatus IN check'),
    ('VirtualMachines', 'VmStatus IN check');

INSERT INTO #SchemaResults (ObjectType, ObjectName, Status, Detail)
SELECT DISTINCT
    'Constraint',
    ec.TableName + ': ' + ec.Description,
    CASE WHEN cc.name IS NOT NULL THEN 'PASS' ELSE 'WARN' END,
    CASE WHEN cc.name IS NOT NULL THEN 'Exists: ' + cc.name ELSE 'Not found — check constraints may use different names' END
FROM @ExpectedChecks ec
LEFT JOIN sys.tables st ON st.name = ec.TableName AND SCHEMA_NAME(st.schema_id) = 'dbo'
LEFT JOIN sys.check_constraints cc ON cc.parent_object_id = st.object_id;

-- ============================================================
-- REPORT
-- ============================================================
PRINT '================================================================';
PRINT '  LINUX BROKER — DATABASE SCHEMA VALIDATION REPORT';
PRINT '================================================================';
PRINT '';

-- Summary counts
DECLARE @PassCount INT, @FailCount INT, @WarnCount INT, @Total INT;
SELECT @PassCount = COUNT(*) FROM #SchemaResults WHERE Status = 'PASS';
SELECT @FailCount = COUNT(*) FROM #SchemaResults WHERE Status = 'FAIL';
SELECT @WarnCount = COUNT(*) FROM #SchemaResults WHERE Status = 'WARN';
SELECT @Total = COUNT(*) FROM #SchemaResults;

-- Print results
SELECT
    ObjectType  AS [Type],
    ObjectName  AS [Object],
    Status,
    Detail
FROM #SchemaResults
ORDER BY
    CASE Status WHEN 'FAIL' THEN 0 WHEN 'WARN' THEN 1 ELSE 2 END,
    ObjectType,
    ObjectName;

PRINT '';
PRINT '================================================================';
PRINT '  SUMMARY: ' + CAST(@PassCount AS VARCHAR) + ' passed, '
    + CAST(@FailCount AS VARCHAR) + ' failed, '
    + CAST(@WarnCount AS VARCHAR) + ' warnings out of '
    + CAST(@Total AS VARCHAR) + ' checks';
PRINT '================================================================';

IF @FailCount > 0
BEGIN
    PRINT '';
    PRINT '❌ SCHEMA VALIDATION FAILED — deploy missing objects using sql_queries/ scripts.';
    PRINT '   Run scripts in numeric order: 001, 002, 003, ... 024';
END
ELSE
BEGIN
    PRINT '';
    PRINT '✅ SCHEMA VALIDATION PASSED — all expected objects are present.';
END

-- Cleanup
DROP TABLE #SchemaResults;
GO
