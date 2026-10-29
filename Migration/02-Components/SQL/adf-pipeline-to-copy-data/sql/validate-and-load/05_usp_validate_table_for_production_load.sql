-- Use Case 1.2 (Part 2): validates a source/staging table against its configured business key(s)
-- before a Production load is allowed. Assumes mig.TableConfiguration/ValidationRun/ValidationError
-- (01-03) already exist. Metadata-driven, reusable for any table registered in mig.TableConfiguration.

CREATE OR ALTER PROCEDURE mig.usp_ValidateTableForProductionLoad
    @ConfigurationId  INT,
    @BatchId          UNIQUEIDENTIFIER,
    @ValidationRunId  BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SourceSchema SYSNAME, @SourceTable SYSNAME, @TargetSchema SYSNAME, @TargetTable SYSNAME,
            @BusinessKeyColumns NVARCHAR(MAX), @LoadStrategy VARCHAR(20), @IsActive BIT;
    DECLARE @KeyColumnList NVARCHAR(MAX);   -- [Col1], [Col2]
    DECLARE @KeyEqualJoin  NVARCHAR(MAX);   -- t.[Col1] = s.[Col1] AND ...
    DECLARE @KeyConcatExpr NVARCHAR(MAX);   -- '' + 'Col1=' + CONVERT(...,s.[Col1]) + ';' + 'Col2=' + ...
    DECLARE @Sql           NVARCHAR(MAX);
    DECLARE @ErrorCount    INT = 0;

    SET @ValidationRunId = NULL;

    BEGIN TRY
        -- 1-2. Read + validate configuration exists and is active
        SELECT
            @SourceSchema = SourceSchema, @SourceTable = SourceTable,
            @TargetSchema = TargetSchema, @TargetTable = TargetTable,
            @BusinessKeyColumns = BusinessKeyColumns, @LoadStrategy = LoadStrategy, @IsActive = IsActive
        FROM mig.TableConfiguration
        WHERE ConfigurationId = @ConfigurationId;

        IF @SourceSchema IS NULL
            THROW 51000, 'ConfigurationId not found in mig.TableConfiguration.', 1;
        IF @IsActive = 0
            THROW 51001, 'Configuration is not active (IsActive = 0).', 1;

        -- Create the ValidationRun (RUNNING) as early as possible - once ConfigurationId/BatchId
        -- are known - so that any failure below (bad config, missing tables/columns, etc.) is
        -- still captured as an ERROR row on this ValidationRun instead of being lost entirely.
        INSERT INTO mig.ValidationRun (ConfigurationId, BatchId, ValidationStatus)
        VALUES (@ConfigurationId, @BatchId, 'RUNNING');
        SET @ValidationRunId = SCOPE_IDENTITY();

        -- 3. Validate source/target tables exist (source may be a table or a view)
        IF OBJECT_ID(QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable), 'U') IS NULL
           AND OBJECT_ID(QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable), 'V') IS NULL
            THROW 51002, 'Source table does not exist.', 1;
        IF OBJECT_ID(QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable), 'U') IS NULL
            THROW 51003, 'Target table does not exist.', 1;

        -- 4. Validate the configured business key columns exist on the source table
        IF EXISTS (
            SELECT 1 FROM STRING_SPLIT(@BusinessKeyColumns, ',') k
            WHERE NOT EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS c
                WHERE c.TABLE_SCHEMA = @SourceSchema AND c.TABLE_NAME = @SourceTable
                  AND c.COLUMN_NAME = LTRIM(RTRIM(k.value))
            )
        )
            THROW 51004, 'One or more BusinessKeyColumns do not exist on the source table.', 1;

        SELECT
            @KeyColumnList = STRING_AGG(QUOTENAME(LTRIM(RTRIM(value))), ', '),
            @KeyEqualJoin  = STRING_AGG('t.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND '),
            @KeyConcatExpr = STRING_AGG('''' + LTRIM(RTRIM(value)) + '='' + ISNULL(CONVERT(NVARCHAR(4000), s.' + QUOTENAME(LTRIM(RTRIM(value))) + '), ''NULL'')', ' + '';'' + ')
        FROM STRING_SPLIT(@BusinessKeyColumns, ',');

        IF @KeyColumnList IS NULL
            THROW 51005, 'BusinessKeyColumns metadata is empty or invalid.', 1;

        -- 7. Duplicate business keys within the source/staging table
        SET @Sql = N'
            ;WITH Dup AS (
                SELECT *, COUNT(*) OVER (PARTITION BY ' + @KeyColumnList + N') AS __KeyCount
                FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
            )
            INSERT INTO mig.ValidationError (ValidationRunId, ErrorType, BusinessKeyValue, ErrorMessage)
            SELECT DISTINCT @vrid, ''DUPLICATE_BUSINESS_KEY'', ' + @KeyConcatExpr + N',
                   ''Duplicate business key found in staging table.''
            FROM Dup AS s
            WHERE __KeyCount > 1;';
        EXEC sp_executesql @Sql, N'@vrid BIGINT', @vrid = @ValidationRunId;

        -- 8. NULL business key values
        DECLARE @NullCheckExpr NVARCHAR(MAX);
        SELECT @NullCheckExpr = STRING_AGG('s.' + QUOTENAME(LTRIM(RTRIM(value))) + ' IS NULL', ' OR ')
        FROM STRING_SPLIT(@BusinessKeyColumns, ',');

        SET @Sql = N'
            INSERT INTO mig.ValidationError (ValidationRunId, ErrorType, BusinessKeyValue, ErrorMessage)
            SELECT @vrid, ''NULL_BUSINESS_KEY'', ' + @KeyConcatExpr + N',
                   ''NULL business key value found in staging table.''
            FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
            WHERE ' + @NullCheckExpr + N';';
        EXEC sp_executesql @Sql, N'@vrid BIGINT', @vrid = @ValidationRunId;

        -- 9. Business keys that already exist in the Production target (INSERT strategy only -
        --    for UPDATE/UPSERT/SKIP_EXISTING an existing target key is expected, not an error)
        IF @LoadStrategy = 'INSERT'
        BEGIN
            SET @Sql = N'
                INSERT INTO mig.ValidationError (ValidationRunId, ErrorType, BusinessKeyValue, ErrorMessage)
                SELECT @vrid, ''EXISTS_IN_TARGET'', ' + @KeyConcatExpr + N',
                       ''Business key already exists in the Production target table.''
                FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                WHERE EXISTS (
                    SELECT 1 FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                    WHERE ' + @KeyEqualJoin + N'
                );';
            EXEC sp_executesql @Sql, N'@vrid BIGINT', @vrid = @ValidationRunId;
        END

        -- 9b. INSERT_IF_NOT_EXISTS strategy: an existing business key is only an error when the
        --     non-key column values differ from staging (a true conflict); an existing key whose
        --     values already match staging is not an error (it's simply left alone at load time).
        IF @LoadStrategy = 'INSERT_IF_NOT_EXISTS'
        BEGIN
            DECLARE @NonKeyDiffPredicate NVARCHAR(MAX);
            SELECT @NonKeyDiffPredicate = STRING_AGG(
                'EXISTS (SELECT t.' + QUOTENAME(c.COLUMN_NAME) + ' EXCEPT SELECT s.' + QUOTENAME(c.COLUMN_NAME) + ')'
                + ' OR EXISTS (SELECT s.' + QUOTENAME(c.COLUMN_NAME) + ' EXCEPT SELECT t.' + QUOTENAME(c.COLUMN_NAME) + ')',
                ' OR '
            )
            FROM INFORMATION_SCHEMA.COLUMNS c
            WHERE c.TABLE_SCHEMA = @SourceSchema AND c.TABLE_NAME = @SourceTable
              AND EXISTS (
                    SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS t
                    WHERE t.TABLE_SCHEMA = @TargetSchema AND t.TABLE_NAME = @TargetTable
                      AND t.COLUMN_NAME = c.COLUMN_NAME
              )
              AND NOT EXISTS (
                    SELECT 1 FROM STRING_SPLIT(@BusinessKeyColumns, ',') k
                    WHERE LTRIM(RTRIM(k.value)) = c.COLUMN_NAME
              );

            IF @NonKeyDiffPredicate IS NOT NULL
            BEGIN
                SET @Sql = N'
                    INSERT INTO mig.ValidationError (ValidationRunId, ErrorType, BusinessKeyValue, ErrorMessage)
                    SELECT @vrid, ''BUSINESS_KEY_VALUE_MISMATCH'', ' + @KeyConcatExpr + N',
                           ''Business key already exists in the Production target table with different non-key column values.''
                    FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                    INNER JOIN ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                       ON ' + @KeyEqualJoin + N'
                    WHERE ' + @NonKeyDiffPredicate + N';';
                EXEC sp_executesql @Sql, N'@vrid BIGINT', @vrid = @ValidationRunId;
            END
        END

        -- 10-13. Count errors, set final status, update the ValidationRun
        SELECT @ErrorCount = COUNT(*) FROM mig.ValidationError WHERE ValidationRunId = @ValidationRunId;

        UPDATE mig.ValidationRun
        SET ValidationStatus = CASE WHEN @ErrorCount = 0 THEN 'PASSED' ELSE 'FAILED' END,
            ErrorCount = @ErrorCount,
            CompletedAt = SYSUTCDATETIME()
        WHERE ValidationRunId = @ValidationRunId;

        -- 14. Summary for the caller
        SELECT
            @ValidationRunId AS ValidationRunId,
            CASE WHEN @ErrorCount = 0 THEN 'PASSED' ELSE 'FAILED' END AS ValidationStatus,
            @ErrorCount AS ErrorCount;
    END TRY
    BEGIN CATCH
        IF @ValidationRunId IS NOT NULL
        BEGIN
            UPDATE mig.ValidationRun
            SET ValidationStatus = 'ERROR',
                ErrorMessage = ERROR_MESSAGE(),
                CompletedAt = SYSUTCDATETIME()
            WHERE ValidationRunId = @ValidationRunId;
        END;
        THROW;
    END CATCH
END
GO
