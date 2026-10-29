-- One-time migration for environments where mig.metadata_loadToStaging was already created without an Id
-- column (composite PK on SchemaName/TableName/Env, which SSMS can't grid-edit). Adds a surrogate
-- Id INT IDENTITY PK and keeps the old composite as a UNIQUE constraint. SQL Server can't ALTER a
-- column to IDENTITY in place, so this rebuilds the table and copies the existing rows across.
-- Idempotent: no-ops if Id already exists (i.e. 13_mig_metadata_loadToStaging.sql already created it fresh).

IF OBJECT_ID('mig.metadata_loadToStaging', 'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('mig.metadata_loadToStaging') AND name = 'Id')
BEGIN
    CREATE TABLE mig.metadata_loadToStaging_new
    (
        Id             INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_metadata_loadToStaging PRIMARY KEY,
        SchemaName     NVARCHAR(128) NOT NULL,
        TableName      NVARCHAR(128) NOT NULL,
        Env            NVARCHAR(20)  NOT NULL,
        Loadtostaging  BIT           NOT NULL DEFAULT 0,
        CONSTRAINT UQ_metadata_loadToStaging UNIQUE (SchemaName, TableName, Env)
    );

    INSERT INTO mig.metadata_loadToStaging_new (SchemaName, TableName, Env, Loadtostaging)
    SELECT SchemaName, TableName, Env, Loadtostaging FROM mig.metadata_loadToStaging;

    DROP TABLE mig.metadata_loadToStaging;
    EXEC sp_rename 'mig.metadata_loadToStaging_new', 'metadata_loadToStaging';
END
GO
