-- Audit trail for PL_LoadSourceToStaging (Use Case 1.0/1.1, "Load to Staging" phase): one row per
-- staging load execution. BatchId is populated with the master pipeline's BatchId
-- (mig.MasterRun.BatchId) when invoked via PL_MasterLoadAndValidate -> PL_LoadAllToStaging, and is
-- NULL for a standalone PL_LoadSourceToStaging run. Idempotent: creates the schema/table only if
-- missing.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.StagingLoadRun', 'U') IS NULL
BEGIN
    CREATE TABLE mig.StagingLoadRun
    (
        StagingLoadRunId  BIGINT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_StagingLoadRun PRIMARY KEY,
        BatchId           UNIQUEIDENTIFIER NULL,
        SourceEnvironment VARCHAR(10)      NOT NULL,
        SourceSchema      SYSNAME          NOT NULL,
        SourceTable       SYSNAME          NOT NULL,
        TargetSchema      SYSNAME          NOT NULL,
        TargetTable       SYSNAME          NOT NULL,
        SourceRowCount    BIGINT           NULL,
        StagingRowCount   BIGINT           NULL,
        LoadStatus        VARCHAR(20)      NOT NULL CONSTRAINT CK_StagingLoadRun_Status
                                CHECK (LoadStatus IN ('RUNNING', 'SUCCESS', 'FAILED', 'ERROR')),
        StartedAt         DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        CompletedAt       DATETIME2        NULL,
        ErrorMessage      NVARCHAR(MAX)    NULL
    );

    CREATE INDEX IX_StagingLoadRun_BatchId ON mig.StagingLoadRun (BatchId);
END
GO
