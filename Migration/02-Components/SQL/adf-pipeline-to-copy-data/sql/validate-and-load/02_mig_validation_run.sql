-- Use Case 1.2 (Part 2): stores the result of every validation execution. One row per
-- usp_ValidateTableForProductionLoad run -- never overwritten, always a new row.
-- Idempotent: creates the schema/table only if missing.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.ValidationRun', 'U') IS NULL
BEGIN
    CREATE TABLE mig.ValidationRun
    (
        ValidationRunId  BIGINT      NOT NULL IDENTITY(1,1) CONSTRAINT PK_ValidationRun PRIMARY KEY,
        ConfigurationId  INT         NOT NULL CONSTRAINT FK_ValidationRun_TableConfiguration
                              REFERENCES mig.TableConfiguration (ConfigurationId),
        BatchId          UNIQUEIDENTIFIER NOT NULL,
        ValidationStatus VARCHAR(20) NOT NULL CONSTRAINT CK_ValidationRun_Status
                              CHECK (ValidationStatus IN ('RUNNING', 'PASSED', 'FAILED', 'ERROR')),
        ErrorCount       INT         NOT NULL DEFAULT 0,
        StartedAt        DATETIME2   NOT NULL DEFAULT SYSUTCDATETIME(),
        CompletedAt      DATETIME2   NULL,
        ErrorMessage     NVARCHAR(MAX) NULL
    );

    CREATE INDEX IX_ValidationRun_ConfigurationId ON mig.ValidationRun (ConfigurationId);
    CREATE INDEX IX_ValidationRun_BatchId ON mig.ValidationRun (BatchId);
END
GO
