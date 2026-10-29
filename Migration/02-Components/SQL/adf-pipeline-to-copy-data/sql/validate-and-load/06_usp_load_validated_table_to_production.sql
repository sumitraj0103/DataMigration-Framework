-- Use Case 1.2 (Part 2): loads a validated source/staging table into its configured Production
-- target, blocking the load unless the referenced ValidationRun PASSED for this exact ConfigurationId
-- + BatchId. Assumes mig.TableConfiguration/ValidationRun/LoadRun (01/02/04) already exist.

CREATE OR ALTER PROCEDURE mig.usp_LoadValidatedTableToProduction
    @ConfigurationId INT,
    @ValidationRunId BIGINT,
    @BatchId         UNIQUEIDENTIFIER,
    @LoadRunId       BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SourceSchema SYSNAME, @SourceTable SYSNAME, @TargetSchema SYSNAME, @TargetTable SYSNAME,
            @BusinessKeyColumns NVARCHAR(MAX), @LoadStrategy VARCHAR(20), @IsActive BIT, @IdentityInsertMode VARCHAR(10);
    DECLARE @VRConfigurationId INT, @VRBatchId UNIQUEIDENTIFIER, @VRStatus VARCHAR(20);
    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @RecordsRead BIGINT = 0, @RecordsInserted BIGINT = 0, @RecordsUpdated BIGINT = 0;

    SET @LoadRunId = NULL;

    -- 1-2. Read + validate configuration exists and is active
    SELECT
        @SourceSchema = SourceSchema, @SourceTable = SourceTable,
        @TargetSchema = TargetSchema, @TargetTable = TargetTable,
        @BusinessKeyColumns = BusinessKeyColumns, @LoadStrategy = LoadStrategy, @IsActive = IsActive,
        @IdentityInsertMode = IdentityInsertMode
    FROM mig.TableConfiguration
    WHERE ConfigurationId = @ConfigurationId;

    IF @SourceSchema IS NULL
        THROW 51010, 'ConfigurationId not found in mig.TableConfiguration.', 1;
    IF @IsActive = 0
        THROW 51011, 'Configuration is not active (IsActive = 0).', 1;

    -- 3-6. Validate the ValidationRun exists, matches this config/batch, and PASSED
    SELECT @VRConfigurationId = ConfigurationId, @VRBatchId = BatchId, @VRStatus = ValidationStatus
    FROM mig.ValidationRun
    WHERE ValidationRunId = @ValidationRunId;

    IF @VRConfigurationId IS NULL
        THROW 51012, 'ValidationRunId not found.', 1;
    IF @VRConfigurationId <> @ConfigurationId
        THROW 51013, 'ValidationRunId does not belong to the requested ConfigurationId.', 1;
    IF @VRBatchId <> @BatchId
        THROW 51014, 'BatchId does not match the ValidationRun (stale validation).', 1;

    IF @VRStatus <> 'PASSED'
    BEGIN
        -- audit the blocked attempt, then refuse to load
        INSERT INTO mig.LoadRun (ValidationRunId, ConfigurationId, BatchId, LoadStatus, ErrorMessage, CompletedAt)
        VALUES (@ValidationRunId, @ConfigurationId, @BatchId, 'BLOCKED',
                'Production load blocked because validation status was ' + @VRStatus + ', not PASSED.', SYSUTCDATETIME());
        THROW 51015, 'Production load blocked because validation failed.', 1;
    END

    -- 8. Validate the source/target tables still exist (source may be a table or a view)
    IF OBJECT_ID(QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable), 'U') IS NULL
       AND OBJECT_ID(QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable), 'V') IS NULL
        THROW 51016, 'Source table does not exist.', 1;
    IF OBJECT_ID(QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable), 'U') IS NULL
        THROW 51017, 'Target table does not exist.', 1;

    INSERT INTO mig.LoadRun (ValidationRunId, ConfigurationId, BatchId, LoadStatus)
    VALUES (@ValidationRunId, @ConfigurationId, @BatchId, 'RUNNING');
    SET @LoadRunId = SCOPE_IDENTITY();

    BEGIN TRY
        -- target's IDENTITY column (if any); AUTO excludes it so Production assigns a new id,
        -- COPY inserts the source value explicitly under SET IDENTITY_INSERT ON
        DECLARE @TargetIdentityColumn SYSNAME;
        SELECT @TargetIdentityColumn = c.name
        FROM sys.identity_columns c
        WHERE c.object_id = OBJECT_ID(QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable));

        DECLARE @IdentityInsertOn NVARCHAR(MAX) = '', @IdentityInsertOff NVARCHAR(MAX) = '';
        IF @TargetIdentityColumn IS NOT NULL AND @IdentityInsertMode = 'COPY'
        BEGIN
            SET @IdentityInsertOn  = N'SET IDENTITY_INSERT ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' ON; ';
            SET @IdentityInsertOff = N'SET IDENTITY_INSERT ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' OFF; ';
        END

        -- columns common to both source and target, in source ordinal order; excludes the target
        -- identity column unless IdentityInsertMode = COPY
        DECLARE @ColumnList NVARCHAR(MAX);       -- [Col1], [Col2]
        DECLARE @SourceValuesList NVARCHAR(MAX);  -- s.[Col1], s.[Col2]
        SELECT
            @ColumnList = STRING_AGG(QUOTENAME(c.COLUMN_NAME), ', ') WITHIN GROUP (ORDER BY c.ORDINAL_POSITION),
            @SourceValuesList = STRING_AGG('s.' + QUOTENAME(c.COLUMN_NAME), ', ') WITHIN GROUP (ORDER BY c.ORDINAL_POSITION)
        FROM INFORMATION_SCHEMA.COLUMNS c
        WHERE c.TABLE_SCHEMA = @SourceSchema AND c.TABLE_NAME = @SourceTable
          AND EXISTS (
                SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS t
                WHERE t.TABLE_SCHEMA = @TargetSchema AND t.TABLE_NAME = @TargetTable
                  AND t.COLUMN_NAME = c.COLUMN_NAME
          )
          AND (@IdentityInsertMode = 'COPY' OR @TargetIdentityColumn IS NULL OR c.COLUMN_NAME <> @TargetIdentityColumn);

        IF @ColumnList IS NULL
            THROW 51018, 'No matching columns found between source and target tables.', 1;

        -- business key join predicate, used by UPDATE/UPSERT/REPLACE
        DECLARE @KeyEqualJoin NVARCHAR(MAX);
        SELECT @KeyEqualJoin = STRING_AGG('t.' + QUOTENAME(LTRIM(RTRIM(value))) + ' = s.' + QUOTENAME(LTRIM(RTRIM(value))), ' AND ')
        FROM STRING_SPLIT(@BusinessKeyColumns, ',');

        -- non-key columns, used for the UPDATE SET clause (an IDENTITY column can never be updated,
        -- so it is always excluded here regardless of IdentityInsertMode)
        DECLARE @SetClause NVARCHAR(MAX);
        SELECT @SetClause = STRING_AGG('t.' + QUOTENAME(c.COLUMN_NAME) + ' = s.' + QUOTENAME(c.COLUMN_NAME), ', ')
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
          )
          AND (@TargetIdentityColumn IS NULL OR c.COLUMN_NAME <> @TargetIdentityColumn);

        -- NULL-safe "has anything actually changed" predicate for non-key columns, used to skip
        -- no-op UPDATEs in MERGE/UPSERT so RecordsUpdated reflects real changes only
        DECLARE @ChangedPredicate NVARCHAR(MAX);
        SELECT @ChangedPredicate = STRING_AGG(
            'EXISTS (SELECT t.' + QUOTENAME(c.COLUMN_NAME) + ' EXCEPT SELECT s.' + QUOTENAME(c.COLUMN_NAME) + ')',
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
          )
          AND (@TargetIdentityColumn IS NULL OR c.COLUMN_NAME <> @TargetIdentityColumn);

        BEGIN TRANSACTION;

        SET @Sql = N'SELECT @cnt = COUNT(*) FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + ';';
        EXEC sp_executesql @Sql, N'@cnt BIGINT OUTPUT', @cnt = @RecordsRead OUTPUT;

        IF @LoadStrategy = 'INSERT'
        BEGIN
            SET @Sql = @IdentityInsertOn + N'INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) +
                       N' (' + @ColumnList + N')
                       SELECT ' + @ColumnList + N'
                       FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s;
                       SET @ins = @@ROWCOUNT;' + @IdentityInsertOff;
            EXEC sp_executesql @Sql, N'@ins INT OUTPUT', @ins = @RecordsInserted OUTPUT;
        END
        ELSE IF @LoadStrategy = 'UPDATE'
        BEGIN
            IF @SetClause IS NULL
                THROW 51019, 'No non-key columns available to UPDATE.', 1;
            SET @Sql = N'UPDATE t SET ' + @SetClause + N'
                       FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                       INNER JOIN ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                          ON ' + @KeyEqualJoin + N';
                       SET @upd = @@ROWCOUNT;';
            EXEC sp_executesql @Sql, N'@upd INT OUTPUT', @upd = @RecordsUpdated OUTPUT;
        END
        ELSE IF @LoadStrategy = 'UPSERT'
        BEGIN
            CREATE TABLE #MergeOutput (Action NVARCHAR(10));
            SET @Sql = @IdentityInsertOn + N'MERGE ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                       USING ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                          ON ' + @KeyEqualJoin +
                       -- only UPDATE when a non-key column actually differs; no-op matches are left alone
                       (CASE WHEN @ChangedPredicate IS NOT NULL THEN N'
                       WHEN MATCHED AND (' + @ChangedPredicate + N') THEN UPDATE SET ' + ISNULL(@SetClause, '')
                       ELSE N'' END) + N'
                       WHEN NOT MATCHED BY TARGET THEN INSERT (' + @ColumnList + N') VALUES (' + @SourceValuesList + N')
                       OUTPUT $action INTO #MergeOutput;' + @IdentityInsertOff;
            EXEC sp_executesql @Sql;
            SELECT
                @RecordsUpdated = SUM(CASE WHEN Action = 'UPDATE' THEN 1 ELSE 0 END),
                @RecordsInserted = SUM(CASE WHEN Action = 'INSERT' THEN 1 ELSE 0 END)
            FROM #MergeOutput;
            SET @RecordsUpdated = ISNULL(@RecordsUpdated, 0);
            SET @RecordsInserted = ISNULL(@RecordsInserted, 0);
            DROP TABLE #MergeOutput;
        END
        ELSE IF @LoadStrategy = 'SKIP_EXISTING'
        BEGIN
            -- insert only staging rows whose business key is not already present in target;
            -- existing target rows are left untouched (the "skip the copy" case)
            SET @Sql = @IdentityInsertOn + N'INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) +
                       N' (' + @ColumnList + N')
                       SELECT ' + @ColumnList + N'
                       FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                       WHERE NOT EXISTS (
                           SELECT 1 FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                           WHERE ' + @KeyEqualJoin + N'
                       );
                       SET @ins = @@ROWCOUNT;' + @IdentityInsertOff;
            EXEC sp_executesql @Sql, N'@ins INT OUTPUT', @ins = @RecordsInserted OUTPUT;
        END
        ELSE IF @LoadStrategy = 'REPLACE'
        BEGIN
            -- delete target rows matching a business key present in staging, then insert all staging rows
            SET @Sql = @IdentityInsertOn + N'DELETE t FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                       WHERE EXISTS (
                           SELECT 1 FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                           WHERE ' + @KeyEqualJoin + N'
                       );
                       INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) +
                       N' (' + @ColumnList + N')
                       SELECT ' + @ColumnList + N'
                       FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s;
                       SET @ins = @@ROWCOUNT;' + @IdentityInsertOff;
            EXEC sp_executesql @Sql, N'@ins INT OUTPUT', @ins = @RecordsInserted OUTPUT;
        END
        ELSE IF @LoadStrategy = 'INSERT_IF_NOT_EXISTS'
        BEGIN
            -- safety net: usp_ValidateTableForProductionLoad should already have failed the batch if
            -- an existing business key's non-key values differ from staging; re-check here so a direct
            -- call to this proc can never silently overwrite/skip a real conflict
            IF @ChangedPredicate IS NOT NULL
            BEGIN
                DECLARE @ConflictCount INT;
                SET @Sql = N'SELECT @cnt = COUNT(*)
                           FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                           INNER JOIN ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                              ON ' + @KeyEqualJoin + N'
                           WHERE ' + @ChangedPredicate + N';';
                EXEC sp_executesql @Sql, N'@cnt INT OUTPUT', @cnt = @ConflictCount OUTPUT;
                IF @ConflictCount > 0
                    THROW 51021, 'INSERT_IF_NOT_EXISTS load blocked: one or more business keys already exist in the Production target with different non-key column values.', 1;
            END

            -- insert only staging rows whose business key is not already present in target;
            -- existing target rows whose values already match are left untouched (no-op, not an error)
            SET @Sql = @IdentityInsertOn + N'INSERT INTO ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) +
                       N' (' + @ColumnList + N')
                       SELECT ' + @ColumnList + N'
                       FROM ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable) + N' AS s
                       WHERE NOT EXISTS (
                           SELECT 1 FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N' AS t
                           WHERE ' + @KeyEqualJoin + N'
                       );
                       SET @ins = @@ROWCOUNT;' + @IdentityInsertOff;
            EXEC sp_executesql @Sql, N'@ins INT OUTPUT', @ins = @RecordsInserted OUTPUT;
        END
        ELSE
            THROW 51020, 'Unsupported LoadStrategy.', 1;

        -- Data quality check: after the load, the target table must not contain duplicate
        -- records based on the configured business key(s). This query only touches the TARGET
        -- table (no source/view reference), so - unlike @KeyEqualJoin above, which naturally
        -- inherits any explicit COLLATE a source view projects (e.g.
        -- mig_stg_acc.vw_actual_datalake_datasets.path's case-sensitive COLLATE, see
        -- Database-Migration-Execution.md, Wave 2, item 4) - it would otherwise compare using the
        -- target column's own plain/default collation and could misreport two legitimately
        -- distinct rows (differing only by a case the source view treats as significant) as
        -- duplicates. To stay consistent with the rest of this engine without requiring any schema
        -- change, auto-detect per business-key column whether the SOURCE (table or view) declares a
        -- different collation than the TARGET, and apply that collation here too when it does.
        DECLARE @KeyColumnList NVARCHAR(MAX);
        DECLARE @DupKeyCount INT;
        SELECT @KeyColumnList = STRING_AGG(
            CASE
                WHEN src.COLLATION_NAME IS NOT NULL AND src.COLLATION_NAME <> tgt.COLLATION_NAME
                    THEN QUOTENAME(tgt.COLUMN_NAME) + N' COLLATE ' + src.COLLATION_NAME
                ELSE QUOTENAME(tgt.COLUMN_NAME)
            END, ', ')
        FROM STRING_SPLIT(@BusinessKeyColumns, ',') k
        JOIN INFORMATION_SCHEMA.COLUMNS tgt
            ON tgt.TABLE_SCHEMA = @TargetSchema AND tgt.TABLE_NAME = @TargetTable
           AND tgt.COLUMN_NAME = LTRIM(RTRIM(k.value))
        LEFT JOIN INFORMATION_SCHEMA.COLUMNS src
            ON src.TABLE_SCHEMA = @SourceSchema AND src.TABLE_NAME = @SourceTable
           AND src.COLUMN_NAME = LTRIM(RTRIM(k.value));

        SET @Sql = N'
            SELECT @cnt = COUNT(*)
            FROM (
                SELECT ' + @KeyColumnList + N'
                FROM ' + QUOTENAME(@TargetSchema) + '.' + QUOTENAME(@TargetTable) + N'
                GROUP BY ' + @KeyColumnList + N'
                HAVING COUNT(*) > 1
            ) AS dup;';
        EXEC sp_executesql @Sql, N'@cnt INT OUTPUT', @cnt = @DupKeyCount OUTPUT;

        IF @DupKeyCount > 0
            THROW 51022, 'Data quality check failed: duplicate business key(s) found in the Production target table after load.', 1;

        COMMIT TRANSACTION;

        UPDATE mig.LoadRun
        SET LoadStatus = 'SUCCESS',
            RecordsRead = @RecordsRead,
            RecordsInserted = ISNULL(@RecordsInserted, 0),
            RecordsUpdated = ISNULL(@RecordsUpdated, 0),
            CompletedAt = SYSUTCDATETIME()
        WHERE LoadRunId = @LoadRunId;

        SELECT
            @LoadRunId AS LoadRunId,
            'SUCCESS' AS LoadStatus,
            @RecordsRead AS RecordsRead,
            ISNULL(@RecordsInserted, 0) AS RecordsInserted,
            ISNULL(@RecordsUpdated, 0) AS RecordsUpdated;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        UPDATE mig.LoadRun
        SET LoadStatus = 'ERROR',
            ErrorMessage = ERROR_MESSAGE(),
            CompletedAt = SYSUTCDATETIME()
        WHERE LoadRunId = @LoadRunId;

        THROW;
    END CATCH
END
GO
