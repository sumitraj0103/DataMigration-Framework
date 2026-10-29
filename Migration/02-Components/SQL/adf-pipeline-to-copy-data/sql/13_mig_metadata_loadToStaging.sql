-- Use Case 1.1: metadata-driven table list for PL_LoadAllToStaging. Lives only in the Prd server's
-- DMAP database (the pipeline reads it via LS_ProdSqlMig). Loadtostaging = 1 means "include this table in the
-- next PL_LoadAllToStaging run"; set it to 0 to skip a table without deleting its row.
-- Idempotent: creates the schema/table only if missing, and only seeds the test row when empty.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.metadata_loadToStaging', 'U') IS NULL
BEGIN
    CREATE TABLE mig.metadata_loadToStaging
    (
        Id             INT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_metadata_loadToStaging PRIMARY KEY,
        SchemaName     NVARCHAR(128) NOT NULL,
        TableName      NVARCHAR(128) NOT NULL,
        Env            NVARCHAR(20)  NOT NULL,
        Loadtostaging  BIT           NOT NULL DEFAULT 0,
        CONSTRAINT UQ_metadata_loadToStaging UNIQUE (SchemaName, TableName, Env)
    );
END
GO

IF NOT EXISTS (SELECT 1 FROM mig.metadata_loadToStaging)
BEGIN
    INSERT INTO mig.metadata_loadToStaging (SchemaName, TableName, Env, Loadtostaging)
    VALUES ('actual_identity', 'servicePrincipals', 'Dev', 1);
END
GO
