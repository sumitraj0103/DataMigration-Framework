-- Use Case 1.2 (Part 2): individual validation failures for a ValidationRun (duplicate business
-- keys, NULL business keys, keys already present in the Production target, etc.).
-- Idempotent: creates the schema/table only if missing.

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mig')
    EXEC('CREATE SCHEMA mig');
GO

IF OBJECT_ID('mig.ValidationError', 'U') IS NULL
BEGIN
    CREATE TABLE mig.ValidationError
    (
        ValidationErrorId BIGINT        NOT NULL IDENTITY(1,1) CONSTRAINT PK_ValidationError PRIMARY KEY,
        ValidationRunId   BIGINT        NOT NULL CONSTRAINT FK_ValidationError_ValidationRun
                                REFERENCES mig.ValidationRun (ValidationRunId),
        ErrorType         VARCHAR(100)  NOT NULL,
        BusinessKeyValue  NVARCHAR(MAX) NULL,
        ErrorMessage      NVARCHAR(MAX) NOT NULL,
        CreatedAt         DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
    );

    CREATE INDEX IX_ValidationError_ValidationRunId ON mig.ValidationError (ValidationRunId);
END
GO
