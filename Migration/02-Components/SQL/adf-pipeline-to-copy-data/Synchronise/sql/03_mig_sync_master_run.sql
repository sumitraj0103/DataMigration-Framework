-- Strategy 2 (Prod -> Lower Environment Synchronization): audit table for
-- PL_SyncAllProdToLowerEnvironments master runs, mirroring mig.MasterRun from Strategy 1. Lives on
-- the Prd server's DMAP database, `mig` schema. Idempotent.

IF OBJECT_ID('mig.SyncMasterRun', 'U') IS NULL
BEGIN
    CREATE TABLE mig.SyncMasterRun
    (
        SyncMasterRunId BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_SyncMasterRun PRIMARY KEY,
        BatchId         UNIQUEIDENTIFIER NOT NULL,
        RunStatus       VARCHAR(20)   NOT NULL CONSTRAINT CK_SyncMasterRun_Status
                             CHECK (RunStatus IN ('RUNNING', 'SUCCESS', 'FAILED')),
        ErrorMessage    NVARCHAR(MAX) NULL,
        StartedAt       DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        CompletedAt     DATETIME2     NULL
    );
END
GO
