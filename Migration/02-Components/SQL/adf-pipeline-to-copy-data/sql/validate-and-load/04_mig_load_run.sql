-- Use Case 1.2 (Part 2): audit trail of every Production load execution (one row per
-- usp_LoadValidatedTableToProduction call, including blocked attempts).
-- Idempotent: creates the schema/table only if missing.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.LoadRun', 'U') IS NULL
BEGIN
    CREATE TABLE mig.LoadRun
    (
        LoadRunId       BIGINT      NOT NULL IDENTITY(1,1) CONSTRAINT PK_LoadRun PRIMARY KEY,
        ValidationRunId BIGINT      NOT NULL CONSTRAINT FK_LoadRun_ValidationRun
                              REFERENCES mig.ValidationRun (ValidationRunId),
        ConfigurationId INT         NOT NULL CONSTRAINT FK_LoadRun_TableConfiguration
                              REFERENCES mig.TableConfiguration (ConfigurationId),
        BatchId         UNIQUEIDENTIFIER NOT NULL,
        LoadStatus      VARCHAR(20) NOT NULL CONSTRAINT CK_LoadRun_Status
                              CHECK (LoadStatus IN ('RUNNING', 'SUCCESS', 'FAILED', 'ERROR', 'BLOCKED')),
        RecordsRead     BIGINT      NOT NULL DEFAULT 0,
        RecordsInserted BIGINT      NOT NULL DEFAULT 0,
        RecordsUpdated  BIGINT      NOT NULL DEFAULT 0,
        RecordsFailed   BIGINT      NOT NULL DEFAULT 0,
        StartedAt       DATETIME2   NOT NULL DEFAULT SYSUTCDATETIME(),
        CompletedAt     DATETIME2   NULL,
        ErrorMessage    NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_LoadRun_ConfigurationId ON mig.LoadRun (ConfigurationId);
    CREATE INDEX IX_LoadRun_BatchId ON mig.LoadRun (BatchId);
END
GO
