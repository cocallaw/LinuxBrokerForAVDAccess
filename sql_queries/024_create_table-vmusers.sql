-- Create VmUsers table (idempotent)
IF OBJECT_ID('dbo.VmUsers', 'U') IS NULL
BEGIN
    CREATE TABLE VmUsers (
        uid INTEGER PRIMARY KEY,
        username VARCHAR(255) UNIQUE NOT NULL,
        CreateDate DATETIME DEFAULT(GETDATE())
    );

    PRINT 'Table VmUsers created successfully.';
END
ELSE
    PRINT 'Table VmUsers already exists. Skipping creation.';
GO
