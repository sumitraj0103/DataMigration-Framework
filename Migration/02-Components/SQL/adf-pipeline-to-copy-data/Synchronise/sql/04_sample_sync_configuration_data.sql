-- Strategy 2 (Prod -> Lower Environment Synchronization): sample configuration rows to exercise
-- all four SyncStrategy values. Adjust schema/table/column names to match real tables before
-- running against a real environment. One row is required per (table, TargetEnvironment) pair.

-- 1. UPSERT_ENV_SPECIFIC: upsert only rows matching the target env.
INSERT INTO mig.SyncConfiguration
    (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment, SyncStrategy, EnvironmentColumn, BusinessKeyColumns, IsActive)
SELECT 'dbo', 'EnvSpecificConfig', 'dbo', 'EnvSpecificConfig', env.TargetEnvironment, 'UPSERT_ENV_SPECIFIC', 'Environment', 'ConfigId', 1
FROM (VALUES ('dev'), ('tst'), ('acc')) AS env(TargetEnvironment)
WHERE NOT EXISTS (
    SELECT 1 FROM mig.SyncConfiguration
    WHERE SourceSchema = 'dbo' AND SourceTable = 'EnvSpecificConfig' AND TargetSchema = 'dbo' AND TargetTable = 'EnvSpecificConfig' AND TargetEnvironment = env.TargetEnvironment
);

-- 2. UPSERT_ALL: all Production rows upserted into every lower environment, no environment filtering.
INSERT INTO mig.SyncConfiguration
    (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment, SyncStrategy, EnvironmentColumn, BusinessKeyColumns, IsActive)
SELECT 'dbo', 'ReferenceData', 'dbo', 'ReferenceData', env.TargetEnvironment, 'UPSERT_ALL', NULL, 'ReferenceCode', 1
FROM (VALUES ('dev'), ('tst'), ('acc')) AS env(TargetEnvironment)
WHERE NOT EXISTS (
    SELECT 1 FROM mig.SyncConfiguration
    WHERE SourceSchema = 'dbo' AND SourceTable = 'ReferenceData' AND TargetSchema = 'dbo' AND TargetTable = 'ReferenceData' AND TargetEnvironment = env.TargetEnvironment
);

-- 3. INSERT_ENV_SPECIFIC: insert-only into Dev, matching rows only, skipping rows whose business
--    key already exists there (existing Dev rows are never overwritten). Uses a distinct example
--    table since a (SourceTable, TargetTable, TargetEnvironment) combo can only have one
--    SyncStrategy (the unique constraint doesn't include SyncStrategy).
INSERT INTO mig.SyncConfiguration
    (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment, SyncStrategy, EnvironmentColumn, BusinessKeyColumns, IsActive)
SELECT 'dbo', 'EnvSpecificInsertOnlyConfig', 'dbo', 'EnvSpecificInsertOnlyConfig', 'dev', 'INSERT_ENV_SPECIFIC', 'Environment', 'ConfigId', 0
WHERE NOT EXISTS (
    SELECT 1 FROM mig.SyncConfiguration
    WHERE SourceSchema = 'dbo' AND SourceTable = 'EnvSpecificInsertOnlyConfig' AND TargetSchema = 'dbo' AND TargetTable = 'EnvSpecificInsertOnlyConfig' AND TargetEnvironment = 'dev'
);

-- 4. INSERT_ALL: insert-only into every lower environment, no environment filtering, skipping rows
--    whose business key already exists there. Uses a distinct example table for the same reason as #3.
INSERT INTO mig.SyncConfiguration
    (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment, SyncStrategy, EnvironmentColumn, BusinessKeyColumns, IsActive)
SELECT 'dbo', 'InsertOnlyReferenceData', 'dbo', 'InsertOnlyReferenceData', env.TargetEnvironment, 'INSERT_ALL', NULL, 'ReferenceCode', 0
FROM (VALUES ('dev'), ('tst'), ('acc')) AS env(TargetEnvironment)
WHERE NOT EXISTS (
    SELECT 1 FROM mig.SyncConfiguration
    WHERE SourceSchema = 'dbo' AND SourceTable = 'InsertOnlyReferenceData' AND TargetSchema = 'dbo' AND TargetTable = 'InsertOnlyReferenceData' AND TargetEnvironment = env.TargetEnvironment
);
GO
