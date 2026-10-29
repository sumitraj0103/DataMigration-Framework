-- Test table for PL_LoadSourceToStaging / validate-and-load testing: actual_identity.users, with a
-- composite business key (id, emailid) so validate-and-load's multi-column BusinessKeyColumns path
-- can be exercised. Idempotent: creates the schema/table only if missing, and only seeds dummy rows
-- when empty, so it is safe to run against the DMAP database on the Dev/tst/Acc SQL servers alike.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'actual_identity')
    EXEC('CREATE SCHEMA actual_identity');
GO

IF OBJECT_ID('actual_identity.users', 'U') IS NULL
BEGIN
    CREATE TABLE actual_identity.users
    (
        id       INT           NOT NULL,
        emailid  NVARCHAR(256) NOT NULL,
        objectid UNIQUEIDENTIFIER NOT NULL,
        Name     NVARCHAR(200) NULL,
        CONSTRAINT PK_users PRIMARY KEY (id, emailid)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM actual_identity.users)
BEGIN
    INSERT INTO actual_identity.users (id, emailid, objectid, Name)
    VALUES
        (101, 'john.doe@dllgroup.com',   'B6E1A1A0-1111-4111-8111-000000000101', 'John Doe'),
        (102, 'jane.smith@dllgroup.com', 'B6E1A1A0-1111-4111-8111-000000000102', 'Jane Smith'),
        (103, 'raj.singh@dllgroup.com',  'B6E1A1A0-1111-4111-8111-000000000103', 'Raj Singh'),
        (104, 'mary.jones@dllgroup.com', 'B6E1A1A0-1111-4111-8111-000000000104', 'Mary Jones'),
        (105, 'alex.wong@dllgroup.com',  'B6E1A1A0-1111-4111-8111-000000000105', 'Alex Wong');
END
GO
