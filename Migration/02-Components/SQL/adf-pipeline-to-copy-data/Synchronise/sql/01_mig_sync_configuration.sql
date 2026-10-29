-- Strategy 2 (Prod -> Lower Environment Synchronization): metadata table describing which
-- Production tables get synced down into the lower environments, and how. Lives on the Prd
-- server's DMAP database, same `mig` schema used by Strategy 1 (sql/validate-and-load). Kept in
-- a separate script/folder from Strategy 1 so the two efforts aren't mixed. Idempotent.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

-- SyncStrategy values:
--   UPSERT_ALL           - all Production rows are UPSERTed (inserted or updated) into
--                           TargetEnvironment, matched on BusinessKeyColumns. No environment
--                           filtering; EnvironmentColumn is not used.
--   INSERT_ALL           - all Production rows are INSERTed into TargetEnvironment, matched on
--                           BusinessKeyColumns; rows whose business key already exists in the
--                           target are skipped (never updated). EnvironmentColumn is not used.
--   UPSERT_ENV_SPECIFIC  - only Production rows whose EnvironmentColumn matches TargetEnvironment
--                           are UPSERTed (inserted or updated) into TargetEnvironment, matched on
--                           BusinessKeyColumns.
--   INSERT_ENV_SPECIFIC  - only Production rows whose EnvironmentColumn matches TargetEnvironment
--                           are considered, and only INSERTed if the business key doesn't already
--                           exist in the target (existing rows are skipped, never updated).
IF OBJECT_ID('mig.SyncConfiguration', 'U') IS NULL
BEGIN
    CREATE TABLE mig.SyncConfiguration
    (
        SyncConfigurationId INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_SyncConfiguration PRIMARY KEY,
        SourceSchema        SYSNAME       NOT NULL,  -- Production schema
        SourceTable         SYSNAME       NOT NULL,  -- Production table
        TargetSchema        SYSNAME       NOT NULL,  -- schema in the lower environment
        TargetTable         SYSNAME       NOT NULL,  -- table in the lower environment
        TargetEnvironment   VARCHAR(10)   COLLATE Latin1_General_100_CS_AS NOT NULL CONSTRAINT CK_SyncConfiguration_TargetEnvironment
                               CHECK (TargetEnvironment IN ('dev', 'tst', 'acc')),
        SyncStrategy        VARCHAR(30)   NOT NULL CONSTRAINT CK_SyncConfiguration_SyncStrategy
                               CHECK (SyncStrategy IN ('UPSERT_ALL', 'INSERT_ALL', 'UPSERT_ENV_SPECIFIC', 'INSERT_ENV_SPECIFIC')),
        EnvironmentColumn   SYSNAME       NULL,       -- required when SyncStrategy is *_ENV_SPECIFIC
        BusinessKeyColumns  NVARCHAR(MAX) NOT NULL,   -- comma-separated UPSERT/INSERT match key column(s)
        IsActive            BIT           NOT NULL DEFAULT 1,
        CreatedDate         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        ModifiedDate        DATETIME2     NULL,
        CONSTRAINT UQ_SyncConfiguration UNIQUE (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment),
        CONSTRAINT CK_SyncConfiguration_EnvColumn
            CHECK (SyncStrategy NOT IN ('UPSERT_ENV_SPECIFIC', 'INSERT_ENV_SPECIFIC') OR EnvironmentColumn IS NOT NULL)
    );
END
GO

-- Migration for tables created before TargetEnvironment/SyncStrategy existed, and for tables
-- created with the older IsEnvironmentSpecific + 3-value SyncStrategy model. Every step is
-- individually guarded so this is safe to re-run from any partially-applied state.
IF COL_LENGTH('mig.SyncConfiguration', 'TargetEnvironment') IS NULL
BEGIN
    ALTER TABLE mig.SyncConfiguration ADD TargetEnvironment VARCHAR(10) COLLATE Latin1_General_100_CS_AS NULL;
    EXEC('UPDATE mig.SyncConfiguration SET TargetEnvironment = ''dev'' WHERE TargetEnvironment IS NULL');
    ALTER TABLE mig.SyncConfiguration ALTER COLUMN TargetEnvironment VARCHAR(10) COLLATE Latin1_General_100_CS_AS NOT NULL;
END
GO

-- TargetEnvironment is compared case-sensitively (ADF Switch cases are case-sensitive), so make
-- sure the column's collation is case-sensitive even if it was added under the old default
-- collation. Any CHECK/UNIQUE constraint referencing the column must be dropped first, since
-- ALTER COLUMN fails while dependent objects exist; they're recreated further below.
IF COL_LENGTH('mig.SyncConfiguration', 'TargetEnvironment') IS NOT NULL
   AND (SELECT collation_name FROM sys.columns WHERE object_id = OBJECT_ID('mig.SyncConfiguration') AND name = 'TargetEnvironment') NOT LIKE '%_CS_%'
BEGIN
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_TargetEnvironment')
        ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT CK_SyncConfiguration_TargetEnvironment;
    IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_SyncConfiguration')
        ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT UQ_SyncConfiguration;
    ALTER TABLE mig.SyncConfiguration ALTER COLUMN TargetEnvironment VARCHAR(10) COLLATE Latin1_General_100_CS_AS NOT NULL;
END
GO

-- Rename legacy 'Dev'/'Test'/'Acc' values to the lowercase 'dev'/'tst'/'acc' model.
IF COL_LENGTH('mig.SyncConfiguration', 'TargetEnvironment') IS NOT NULL
BEGIN
    EXEC('UPDATE mig.SyncConfiguration SET TargetEnvironment = ''dev'' WHERE TargetEnvironment = ''Dev''');
    EXEC('UPDATE mig.SyncConfiguration SET TargetEnvironment = ''tst'' WHERE TargetEnvironment = ''Test''');
    EXEC('UPDATE mig.SyncConfiguration SET TargetEnvironment = ''acc'' WHERE TargetEnvironment = ''Acc''');
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_TargetEnvironment'
           AND definition NOT LIKE '%tst%')
BEGIN
    ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT CK_SyncConfiguration_TargetEnvironment;
END
GO

IF COL_LENGTH('mig.SyncConfiguration', 'TargetEnvironment') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_TargetEnvironment')
BEGIN
    ALTER TABLE mig.SyncConfiguration ADD CONSTRAINT CK_SyncConfiguration_TargetEnvironment CHECK (TargetEnvironment IN ('dev', 'tst', 'acc'));
END
GO

IF COL_LENGTH('mig.SyncConfiguration', 'TargetEnvironment') IS NOT NULL
   AND EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_SyncConfiguration')
   AND NOT EXISTS (
        SELECT 1 FROM sys.indexes i
        JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
        JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
        WHERE i.name = 'UQ_SyncConfiguration' AND c.name = 'TargetEnvironment'
   )
BEGIN
    ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT UQ_SyncConfiguration;
END
GO

IF COL_LENGTH('mig.SyncConfiguration', 'TargetEnvironment') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_SyncConfiguration')
BEGIN
    ALTER TABLE mig.SyncConfiguration ADD CONSTRAINT UQ_SyncConfiguration UNIQUE (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment);
END
GO

IF COL_LENGTH('mig.SyncConfiguration', 'SyncStrategy') IS NULL
BEGIN
    ALTER TABLE mig.SyncConfiguration ADD SyncStrategy VARCHAR(30) NULL;
    EXEC('UPDATE mig.SyncConfiguration SET SyncStrategy = ''UPSERT_ALL'' WHERE SyncStrategy IS NULL');
    ALTER TABLE mig.SyncConfiguration ALTER COLUMN SyncStrategy VARCHAR(30) NOT NULL;
END
GO

-- Rename rows created under the older 3-value SyncStrategy model to the new 4-value model.
-- Drop the old 3-value SyncStrategy CHECK constraint BEFORE renaming values below, otherwise the
-- rename UPDATEs (which write the new 4-value names) violate the still-active old constraint.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_SyncStrategy'
           AND definition NOT LIKE '%INSERT_ALL%')
BEGIN
    ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT CK_SyncConfiguration_SyncStrategy;
END
GO

-- Always attempt the renames (idempotent no-op if no matching rows), regardless of whether the
-- old CK_SyncConfiguration_StrategyMatchesEnvSpecific constraint is still present, since a prior
-- partial run may have already dropped it without every row having been renamed.
IF COL_LENGTH('mig.SyncConfiguration', 'SyncStrategy') IS NOT NULL
BEGIN
    EXEC('UPDATE mig.SyncConfiguration SET SyncStrategy = ''UPSERT_ENV_SPECIFIC'' WHERE SyncStrategy = ''UPSERT_MATCHED_ENV''');
    EXEC('UPDATE mig.SyncConfiguration SET SyncStrategy = ''INSERT_ENV_SPECIFIC'' WHERE SyncStrategy = ''INSERT_ONLY_MATCHED_ENV''');
END
GO

IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_StrategyMatchesEnvSpecific')
BEGIN
    ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT CK_SyncConfiguration_StrategyMatchesEnvSpecific;
END
GO

-- Catch-all: normalize any leftover/unrecognized SyncStrategy value so the new CHECK constraint
-- below can be added without violating existing data.
IF COL_LENGTH('mig.SyncConfiguration', 'SyncStrategy') IS NOT NULL
BEGIN
    EXEC('UPDATE mig.SyncConfiguration SET SyncStrategy = ''UPSERT_ALL'' WHERE SyncStrategy NOT IN (''UPSERT_ALL'', ''INSERT_ALL'', ''UPSERT_ENV_SPECIFIC'', ''INSERT_ENV_SPECIFIC'')');
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_SyncStrategy')
BEGIN
    ALTER TABLE mig.SyncConfiguration ADD CONSTRAINT CK_SyncConfiguration_SyncStrategy
        CHECK (SyncStrategy IN ('UPSERT_ALL', 'INSERT_ALL', 'UPSERT_ENV_SPECIFIC', 'INSERT_ENV_SPECIFIC'));
END
GO

-- Drop the retired IsEnvironmentSpecific column (superseded by SyncStrategy's *_ENV_SPECIFIC suffix).
IF COL_LENGTH('mig.SyncConfiguration', 'IsEnvironmentSpecific') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_EnvColumn')
        ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT CK_SyncConfiguration_EnvColumn;
    DECLARE @DefName SYSNAME = (
        SELECT dc.name FROM sys.default_constraints dc
        JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
        WHERE dc.parent_object_id = OBJECT_ID('mig.SyncConfiguration') AND c.name = 'IsEnvironmentSpecific'
    );
    IF @DefName IS NOT NULL
        EXEC('ALTER TABLE mig.SyncConfiguration DROP CONSTRAINT ' + @DefName);
    ALTER TABLE mig.SyncConfiguration DROP COLUMN IsEnvironmentSpecific;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_SyncConfiguration_EnvColumn')
BEGIN
    ALTER TABLE mig.SyncConfiguration ADD CONSTRAINT CK_SyncConfiguration_EnvColumn
        CHECK (SyncStrategy NOT IN ('UPSERT_ENV_SPECIFIC', 'INSERT_ENV_SPECIFIC') OR EnvironmentColumn IS NOT NULL);
END
GO
