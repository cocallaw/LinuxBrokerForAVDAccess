-- Create VmScalingRules table (idempotent)
IF OBJECT_ID('dbo.VmScalingRules', 'U') IS NULL
BEGIN
    CREATE TABLE VmScalingRules (
        RuleID INT IDENTITY(1,1) PRIMARY KEY,
        MinVMs INT NOT NULL,
        MaxVMs INT NOT NULL,
        ScaleUpRatio DECIMAL(5,2) NOT NULL, -- Percentage (e.g., 70.00 for 70%)
        ScaleUpIncrement INT NOT NULL,
        ScaleDownRatio DECIMAL(5,2) NOT NULL, -- Percentage (e.g., 30.00 for 30%)
        ScaleDownIncrement INT NOT NULL,
        LastChecked DATETIME DEFAULT NULL,
        SysStartTime DATETIME2 GENERATED ALWAYS AS ROW START HIDDEN,
        SysEndTime DATETIME2 GENERATED ALWAYS AS ROW END HIDDEN,
        PERIOD FOR SYSTEM_TIME (SysStartTime, SysEndTime),
        CHECK (MinVMs < MaxVMs),  -- Ensures MinVMs is less than MaxVMs
        CHECK (ScaleUpRatio > ScaleDownRatio)  -- Ensures ScaleUpRatio is greater than ScaleDownRatio
    )
    WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = dbo.VmScalingRulesHistory));

    PRINT 'Table VmScalingRules created successfully.';
END
ELSE
    PRINT 'Table VmScalingRules already exists. Skipping creation.';
GO

-- Seed default scaling rule if table is empty
IF NOT EXISTS (SELECT 1 FROM dbo.VmScalingRules)
BEGIN
    INSERT INTO VmScalingRules (MinVMs, MaxVMs, ScaleUpRatio, ScaleUpIncrement, ScaleDownRatio, ScaleDownIncrement)
    VALUES (2, 10, 70.00, 2, 30.00, 1);

    PRINT 'Default scaling rule seeded successfully.';
END
ELSE
    PRINT 'Scaling rules already exist. Skipping seed data.';
GO

-- Verify seed data
SELECT
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS: VmScalingRules contains ' + CAST(COUNT(*) AS VARCHAR) + ' rule(s).'
        ELSE 'FAIL: VmScalingRules is empty — seed data was not inserted.'
    END AS SeedValidation
FROM dbo.VmScalingRules;
GO
