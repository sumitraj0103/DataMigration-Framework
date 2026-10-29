-- Test table for Strategy 2 (Prod -> Lower Environment Synchronization): dbo.CI_AIC, matching the
-- shape shown in the screenshot (InstanceName/AICClassification/ShortDescription/ServiceOwnerName/
-- LinkedApplicationOwner/ProductOwner/InsertDate), seeded with dummy rows for sync testing.
-- Idempotent: creates the table only if missing, and only seeds dummy rows when empty, so it is
-- safe to run against the DMAP database on the Dev/tst/Acc/Prd SQL servers alike.

IF OBJECT_ID('dbo.CI_AIC', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.CI_AIC
    (
        InstanceName          VARCHAR(128)  NOT NULL CONSTRAINT PK_CI_AIC PRIMARY KEY,
        AICClassification     INT           NULL,
        ShortDescription      NVARCHAR(1024) NULL,
        ServiceOwnerName      VARCHAR(128)  NULL,
        LinkedApplicationOwner VARCHAR(128) NULL,
        ProductOwner          VARCHAR(128)  NULL,
        InsertDate            DATE          NULL
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.CI_AIC)
BEGIN
    INSERT INTO dbo.CI_AIC (InstanceName, AICClassification, ShortDescription, ServiceOwnerName, LinkedApplicationOwner, ProductOwner, InsertDate)
    VALUES
        ('CI-AIC-001', 1, 'Core banking instance',        'Alice Owner',   'Bob Linked',     'Carol Product', '2026-01-05'),
        ('CI-AIC-002', 2, 'Reporting service instance',   'Dave Owner',    'Erin Linked',    'Frank Product', '2026-02-10'),
        ('CI-AIC-003', 1, 'Customer portal instance',     'Grace Owner',   'Heidi Linked',   'Ivan Product',  '2026-03-15'),
        ('CI-AIC-004', 3, 'Batch processing instance',    'Judy Owner',    'Karl Linked',    'Liam Product',  '2026-04-20'),
        ('CI-AIC-005', 2, 'Data warehouse instance',       'Mallory Owner', 'Niaj Linked',    'Olivia Product', '2026-05-25');
END
GO
