-- Audit trail for PL_MasterLoadAndValidate: one row per master pipeline execution, keyed by the
-- BatchId generated at the start of that run. The same BatchId is reused as
-- mig.StagingLoadRun.BatchId (Load to Staging phase) and mig.ValidationRun.BatchId /
-- mig.LoadRun.BatchId (Validate & Load to Production phase), so all three can be joined together
-- for a single master run. Idempotent: creates the schema/table only if missing.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.MasterRun', 'U') IS NULL
BEGIN
    CREATE TABLE mig.MasterRun
    (
        MasterRunId  BIGINT           NOT NULL IDENTITY(1,1) CONSTRAINT PK_MasterRun PRIMARY KEY,
        BatchId      UNIQUEIDENTIFIER NOT NULL CONSTRAINT UQ_MasterRun_BatchId UNIQUE,
        RunStatus    VARCHAR(20)      NOT NULL CONSTRAINT CK_MasterRun_Status
                            CHECK (RunStatus IN ('RUNNING', 'SUCCESS', 'FAILED', 'ERROR')),
        StartedAt    DATETIME2        NOT NULL DEFAULT SYSUTCDATETIME(),
        CompletedAt  DATETIME2        NULL,
        ErrorMessage NVARCHAR(MAX)    NULL
    );

    CREATE INDEX IX_MasterRun_BatchId ON mig.MasterRun (BatchId);
END
GO
