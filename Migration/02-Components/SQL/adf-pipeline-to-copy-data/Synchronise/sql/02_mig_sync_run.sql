-- Strategy 2 (Prod -> Lower Environment Synchronization): audit table, one row per
-- PL_SyncProdToLowerEnvironment execution. Lives on the Prd server's DMAP database, `mig` schema.
-- Assumes mig.SyncConfiguration (01) already exists. Idempotent.

IF OBJECT_ID('mig.SyncRun', 'U') IS NULL
BEGIN
    CREATE TABLE mig.SyncRun
    (
        SyncRunId          BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_SyncRun PRIMARY KEY,
        SyncConfigurationId INT          NOT NULL CONSTRAINT FK_SyncRun_SyncConfiguration
                                REFERENCES mig.SyncConfiguration (SyncConfigurationId),
        TargetEnvironment  VARCHAR(20)   NOT NULL,  -- Dev / Test / Acc
        BatchId            UNIQUEIDENTIFIER NOT NULL,
        SyncStatus         VARCHAR(20)   NOT NULL CONSTRAINT CK_SyncRun_Status
                                CHECK (SyncStatus IN ('RUNNING', 'SUCCESS', 'ERROR')),
        RecordsRead        BIGINT        NULL,
        RecordsWritten     BIGINT        NULL,
        ErrorMessage       NVARCHAR(MAX) NULL,
        StartedAt          DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME(),
        CompletedAt        DATETIME2     NULL
    );
END
GO
