-- Use Case 1.2 (Part 2): metadata-driven validation/production-load framework. Lives only on the
-- Prd server's DMAP database (same server that hosts the mig_stg_<env> staging tables and the
-- Production target tables). Independent of Part 1 (sql/00-14, deploy.ps1) -- do not merge.
-- Idempotent: creates the schema/table only if missing.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.TableConfiguration', 'U') IS NULL
BEGIN
    CREATE TABLE mig.TableConfiguration
    (
        ConfigurationId    INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_TableConfiguration PRIMARY KEY,
        SourceSchema       SYSNAME       NOT NULL,
        SourceTable        SYSNAME       NOT NULL,
        TargetSchema       SYSNAME       NOT NULL,
        TargetTable        SYSNAME       NOT NULL,
        BusinessKeyColumns NVARCHAR(MAX) NOT NULL,
        LoadStrategy       VARCHAR(20)   NOT NULL CONSTRAINT CK_TableConfiguration_LoadStrategy
                                CHECK (LoadStrategy IN ('INSERT', 'UPDATE', 'UPSERT', 'REPLACE', 'SKIP_EXISTING', 'INSERT_IF_NOT_EXISTS')),
        ValidationRequired BIT           NOT NULL DEFAULT 1,
        IsActive           BIT           NOT NULL DEFAULT 1,
        CreatedDate        DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        ModifiedDate       DATETIME2     NULL,
        CONSTRAINT UQ_TableConfiguration UNIQUE (SourceSchema, SourceTable, TargetSchema, TargetTable)
    );
END
GO

-- Widen the CHECK constraint on tables created before SKIP_EXISTING was added.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TableConfiguration_LoadStrategy')
   AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints
        WHERE name = 'CK_TableConfiguration_LoadStrategy' AND definition LIKE '%SKIP_EXISTING%'
   )
BEGIN
    ALTER TABLE mig.TableConfiguration DROP CONSTRAINT CK_TableConfiguration_LoadStrategy;
    ALTER TABLE mig.TableConfiguration ADD CONSTRAINT CK_TableConfiguration_LoadStrategy
        CHECK (LoadStrategy IN ('INSERT', 'UPDATE', 'UPSERT', 'REPLACE', 'SKIP_EXISTING', 'INSERT_IF_NOT_EXISTS'));
END
GO

-- Widen the CHECK constraint on tables created before INSERT_IF_NOT_EXISTS was added.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_TableConfiguration_LoadStrategy')
   AND NOT EXISTS (
        SELECT 1 FROM sys.check_constraints
        WHERE name = 'CK_TableConfiguration_LoadStrategy' AND definition LIKE '%INSERT_IF_NOT_EXISTS%'
   )
BEGIN
    ALTER TABLE mig.TableConfiguration DROP CONSTRAINT CK_TableConfiguration_LoadStrategy;
    ALTER TABLE mig.TableConfiguration ADD CONSTRAINT CK_TableConfiguration_LoadStrategy
        CHECK (LoadStrategy IN ('INSERT', 'UPDATE', 'UPSERT', 'REPLACE', 'SKIP_EXISTING', 'INSERT_IF_NOT_EXISTS'));
END
GO

-- LoadOrder: lets FK-dependent tables (e.g. identities -> users/groups/serviceprincipal -> membersingroup)
-- be loaded in the correct sequence by PL_ValidateAndLoadAllToProduction. Tables with no dependency
-- can all share the same LoadOrder; ties are broken by ConfigurationId.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('mig.TableConfiguration') AND name = 'LoadOrder')
BEGIN
    ALTER TABLE mig.TableConfiguration ADD LoadOrder INT NOT NULL CONSTRAINT DF_TableConfiguration_LoadOrder DEFAULT 100;
END
GO

-- IdentityInsertMode: AUTO (default) excludes any target IDENTITY column from the generated insert
-- so Production assigns its own new id (e.g. actual_identity.identities); COPY inserts the source
-- value explicitly, toggling SET IDENTITY_INSERT ON/OFF around the statement.
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('mig.TableConfiguration') AND name = 'IdentityInsertMode')
BEGIN
    ALTER TABLE mig.TableConfiguration ADD IdentityInsertMode VARCHAR(10) NOT NULL
        CONSTRAINT DF_TableConfiguration_IdentityInsertMode DEFAULT 'AUTO'
        CONSTRAINT CK_TableConfiguration_IdentityInsertMode CHECK (IdentityInsertMode IN ('AUTO', 'COPY'));
END
GO
