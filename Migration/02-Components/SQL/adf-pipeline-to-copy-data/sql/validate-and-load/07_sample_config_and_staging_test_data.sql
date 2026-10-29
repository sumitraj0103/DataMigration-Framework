-- Use Case 1.2 (Part 2): sample mig.TableConfiguration row + matching staging test data, wired to
-- the existing actual_identity.servicePrincipals table on Prd (seeded by Part 1's
-- sql/12_actual_identity_service_principals.sql) as the Production target. Reuses the mig_stg_dev
-- naming convention from Part 1's PL_LoadSourceToStaging so this can be exercised standalone,
-- without requiring the ADF pipeline to have run first.
-- Idempotent: creates the schema/table only if missing, seeds only when empty.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig_stg_dev')
    EXEC('CREATE SCHEMA mig_stg_dev');
GO

IF OBJECT_ID('mig_stg_dev.actual_identity_servicePrincipals', 'U') IS NULL
BEGIN
    CREATE TABLE mig_stg_dev.actual_identity_servicePrincipals
    (
        id    INT           NULL,
        email NVARCHAR(256) NULL,
        upn   NVARCHAR(113) NULL
    );
END
GO

-- Clean rows with ids that do not already exist in actual_identity.servicePrincipals, so a first
-- run demonstrates a successful INSERT load. See the deploy/test guide for how to introduce a
-- duplicate/NULL row to exercise the validation failure paths.
IF NOT EXISTS (SELECT 1 FROM mig_stg_dev.actual_identity_servicePrincipals)
BEGIN
    INSERT INTO mig_stg_dev.actual_identity_servicePrincipals (id, email, upn)
    VALUES
        (501, 'test.user501@dllgroup.com', 'TestUser501@delagelanden.com'),
        (502, 'test.user502@dllgroup.com', 'TestUser502@delagelanden.com'),
        (503, 'test.user503@dllgroup.com', 'TestUser503@delagelanden.com');
END
GO

IF NOT EXISTS (
    SELECT 1 FROM mig.TableConfiguration
    WHERE SourceSchema = 'mig_stg_dev' AND SourceTable = 'actual_identity_servicePrincipals'
      AND TargetSchema = 'actual_identity' AND TargetTable = 'servicePrincipals'
)
BEGIN
    INSERT INTO mig.TableConfiguration
        (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, ValidationRequired, IsActive)
    VALUES
        ('mig_stg_dev', 'actual_identity_servicePrincipals', 'actual_identity', 'servicePrincipals', 'id', 'INSERT', 1, 1);
END
GO
