-- Simple duplicate-check: finds rows that are duplicates across ALL columns
-- (i.e. entire row repeats, not just the business key).
SELECT [Instance Name]
      ,[AIC Classification]
      ,[Short Description]
      ,[Service Owner Name]
      ,[Linked Application Owner]
      ,[Product Owner]
      ,[InsertDate]
      ,COUNT(*) AS DuplicateCount
FROM [dbo].[CI_AIC]
GROUP BY [Instance Name]
        ,[AIC Classification]
        ,[Short Description]
        ,[Service Owner Name]
        ,[Linked Application Owner]
        ,[Product Owner]
        ,[InsertDate]
HAVING COUNT(*) > 1;
GO

-- Generic duplicate-check: pass a table name and a comma-separated list of business key
-- column(s), and this returns every business key combination that occurs more than once,
-- along with the duplicate row count and the row data itself (via a JOIN back to the table).
-- Works for CI_AIC or any other table -- just change @SchemaName/@TableName/@BusinessKeyColumns.

DECLARE @SchemaName          SYSNAME       = 'dbo';
DECLARE @TableName            SYSNAME       = 'CI_AIC';
DECLARE @BusinessKeyColumns   NVARCHAR(MAX) = '[Instance Name]';  -- comma-separated, e.g. '[Col1],[Col2]'

DECLARE @FullTableName NVARCHAR(261) = QUOTENAME(@SchemaName) + N'.' + QUOTENAME(@TableName);

-- 1) Business key combinations that appear more than once, with their duplicate count.
DECLARE @Sql NVARCHAR(MAX) = N'
SELECT ' + @BusinessKeyColumns + N',
       COUNT(*) AS DuplicateCount
FROM ' + @FullTableName + N'
GROUP BY ' + @BusinessKeyColumns + N'
HAVING COUNT(*) > 1
ORDER BY DuplicateCount DESC;';

EXEC sys.sp_executesql @Sql;

-- 2) All the actual rows behind those duplicate business keys (full row detail, easier to eyeball).
DECLARE @SqlDetail NVARCHAR(MAX) = N'
;WITH Dupes AS (
    SELECT ' + @BusinessKeyColumns + N',
           COUNT(*) OVER (PARTITION BY ' + @BusinessKeyColumns + N') AS DuplicateCount
    FROM ' + @FullTableName + N'
)
SELECT t.*
FROM ' + @FullTableName + N' t
INNER JOIN Dupes d
    ON ' + (
        SELECT STRING_AGG(CAST('t.' + value + ' = d.' + value AS NVARCHAR(MAX)), ' AND ')
        FROM STRING_SPLIT(@BusinessKeyColumns, ',')
    ) + N'
WHERE d.DuplicateCount > 1
ORDER BY ' + @BusinessKeyColumns + N';';

EXEC sys.sp_executesql @SqlDetail;
