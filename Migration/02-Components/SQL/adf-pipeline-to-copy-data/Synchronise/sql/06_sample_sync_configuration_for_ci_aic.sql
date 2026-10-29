-- Sample mig.SyncConfiguration rows for the dbo.CI_AIC test table (Prd server only; mig schema
-- only exists on Prd). UPSERT_ALL: one row per lower environment, since TargetEnvironment is part
-- of the configuration. Run 05_test_table_ci_aic.sql against Dev/Tst/Acc/Prd first so the table
-- exists everywhere.

INSERT INTO mig.SyncConfiguration
    (SourceSchema, SourceTable, TargetSchema, TargetTable, TargetEnvironment, SyncStrategy, EnvironmentColumn, BusinessKeyColumns, IsActive)
SELECT 'dbo', 'CI_AIC', 'dbo', 'CI_AIC', env.TargetEnvironment, 'UPSERT_ALL', NULL, 'InstanceName', 1
FROM (VALUES ('dev'), ('tst'), ('acc')) AS env(TargetEnvironment)
WHERE NOT EXISTS (
    SELECT 1 FROM mig.SyncConfiguration
    WHERE SourceSchema = 'dbo' AND SourceTable = 'CI_AIC' AND TargetSchema = 'dbo' AND TargetTable = 'CI_AIC' AND TargetEnvironment = env.TargetEnvironment
);
GO
