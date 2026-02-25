-- ============================================================================
-- Performance Indexes for Linux Broker Database
-- Idempotent: safe to run multiple times.
-- ============================================================================

-- VirtualMachines: VmStatus — used by checkout, scaling logic, and status queries
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VirtualMachines_VmStatus' AND object_id = OBJECT_ID('dbo.VirtualMachines'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_VirtualMachines_VmStatus
    ON dbo.VirtualMachines (VmStatus)
    INCLUDE (PowerState, NetworkStatus);
    PRINT 'Index IX_VirtualMachines_VmStatus created.';
END
ELSE
    PRINT 'Index IX_VirtualMachines_VmStatus already exists. Skipping.';
GO

-- VirtualMachines: Username — used by checkout (user lookup) and session queries
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VirtualMachines_Username' AND object_id = OBJECT_ID('dbo.VirtualMachines'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_VirtualMachines_Username
    ON dbo.VirtualMachines (Username)
    INCLUDE (VmStatus, AvdHost);
    PRINT 'Index IX_VirtualMachines_Username created.';
END
ELSE
    PRINT 'Index IX_VirtualMachines_Username already exists. Skipping.';
GO

-- VirtualMachines: Hostname — used by ReleaseVm and VM lookups
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VirtualMachines_Hostname' AND object_id = OBJECT_ID('dbo.VirtualMachines'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_VirtualMachines_Hostname
    ON dbo.VirtualMachines (Hostname);
    PRINT 'Index IX_VirtualMachines_Hostname created.';
END
ELSE
    PRINT 'Index IX_VirtualMachines_Hostname already exists. Skipping.';
GO

-- VirtualMachines: AvdHost — used by checkout and session filtering
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VirtualMachines_AvdHost' AND object_id = OBJECT_ID('dbo.VirtualMachines'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_VirtualMachines_AvdHost
    ON dbo.VirtualMachines (AvdHost);
    PRINT 'Index IX_VirtualMachines_AvdHost created.';
END
ELSE
    PRINT 'Index IX_VirtualMachines_AvdHost already exists. Skipping.';
GO

-- VmScalingActivityLog: CheckTimestamp — used by activity log date-range queries
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_VmScalingActivityLog_CheckTimestamp' AND object_id = OBJECT_ID('dbo.VmScalingActivityLog'))
BEGIN
    CREATE NONCLUSTERED INDEX IX_VmScalingActivityLog_CheckTimestamp
    ON dbo.VmScalingActivityLog (CheckTimestamp DESC)
    INCLUDE (ActionTaken, Outcome);
    PRINT 'Index IX_VmScalingActivityLog_CheckTimestamp created.';
END
ELSE
    PRINT 'Index IX_VmScalingActivityLog_CheckTimestamp already exists. Skipping.';
GO

PRINT '--- Index deployment complete. ---';
GO
