-- Registers the data lake family (Wave 2) in mig.TableConfiguration so PL_ValidateAndLoadAllToProduction
-- loads them, in FK order, via the generic mig.usp_LoadValidatedTableToProduction engine.
-- datasetSizes/rawFolderMappingListOfValues load directly from staging (natural business keys, no
-- FK remap). datasets/acls/datasetPermissions load from the mig_stg_acc.vw_* views
-- (scripts/Datalake-mapping.sql), which resolve owner_*_user_id/identity_id via the
-- existing mig.actual_identity_identities_mapping table from Wave 1.
-- folderMapping moved to Wave 2.1 (needs an Environment column + Dev/Tst/Acc multi-source load) -
-- see sql/validate-and-load/15_folderMapping_environment_table_configuration.sql and
-- scripts/FolderMapping-mapping.sql instead.
-- datasets uses IdentityInsertMode = 'COPY': its id is a natural/business key referenced
-- unchanged by meta_datalake.datasetPermissions.dataset_id, so the staging id must be copied
-- as-is rather than Production generating a new one. BusinessKeyColumns is
-- storage_account,layer,path,active (id stays OUT of the key - see below). The earlier duplicates
-- found via scripts/check_datalake_family_duplicates.sql on those 4 columns turned out to be a
-- case-insensitive-collation bug, not a real id gap: the same path differing only by letter case
-- (e.g. 'CEAR/gold' vs 'CEAR/GOLD') collides under the database's default collation even though
-- Production already holds both as distinct, legitimate rows. Fixed with NO schema change: the
-- vw_actual_datalake_datasets/vw_actual_datalake_acls views (scripts/Datalake-mapping.sql) project
-- path with an explicit COLLATE Latin1_General_100_CS_AS, which wins precedence over Production's
-- plain/implicit column collation, so the generic engine's dynamic t.path = s.path comparison
-- (and this file's own duplicate-check/preview scripts) is case-sensitive automatically - see
-- Database-Migration-Execution.md, Wave 2, item 4. Because id stays out of the key,
-- mig.usp_LoadValidatedTableToProduction's generated UPDATE SET clause (which always excludes
-- BusinessKeyColumns) WILL include id and overwrite an already-matched Production row's id with
-- the staging value on every UPSERT - flagged as an open Go/No-Go item, not yet resolved.
-- datasetSizes/rawFolderMappingListOfValues/datasetPermissions/acls all keep
-- IdentityInsertMode = 'AUTO': each is matched on its own composite business key, and nothing
-- else references their surrogate id (if any) as an unchanged FK, so a new row inserting should
-- let Production generate its own id rather than copying the staging value. (acls does carry a
-- surrogate id column, but it isn't exposed by vw_actual_datalake_acls, so it's excluded from the
-- insert either way; folderMapping's equivalent note now lives in Wave 2.1's config file.)
-- datasets is the one exception (see above) because
-- meta_datalake.datasetPermissions.dataset_id depends on its id being preserved unchanged.
-- LoadOrder = 20 (not 10) for datasets: PL_ValidateAndLoadAllToProduction only refreshes
-- mig.actual_identity_identities_mapping a second time between its LoadOrder<=10 and LoadOrder>10
-- phases, so any owner_*_user_id resolving to an identity newly created in this same run would
-- still be NULL if datasets ran in the LoadOrder<=10 phase. 20 keeps it in the post-refresh phase
-- while still sorting before acls/datasetPermissions (30), which reference datasets via
-- datasetPermissions.dataset_id and must load after it.

-- IsActive = 0 for every row in this script run (both WHEN MATCHED and WHEN NOT MATCHED): the
-- whole Wave 2 family is still blocked on the "API changes to support dataset load"/API_V2
-- identity-resolution dependency (Database-Migration-Execution.md, Wave 2, "Dependency" section
-- and Go/No-Go "API Dependency" row) - none of it is ready for go-live yet, so re-running this
-- registration script must not silently reactivate an already-active row. Once the team confirms
-- that dependency is resolved, flip IsActive to 1 explicitly (see the activation statement at the
-- bottom of this file) rather than relying on this script's MERGE to do it implicitly.

-- One-time cleanup: supersede the earlier config that sourced datasets straight from the raw
-- staging table instead of the view (it skipped owner_*_user_id resolution and defaulted
-- IdentityInsertMode to AUTO).
UPDATE mig.TableConfiguration
SET IsActive = 0, ModifiedDate = SYSUTCDATETIME()
WHERE SourceSchema = 'mig_stg_acc' AND SourceTable = 'actual_datalake_datasets'
  AND TargetSchema = 'actual_datalake' AND TargetTable = 'datasets';
GO

MERGE mig.TableConfiguration AS t
USING (VALUES
    ('mig_stg_acc', 'vw_actual_datalake_datasets',                'actual_datalake', 'datasets',                     'storage_account,layer,path,active', 'UPSERT',        20, 'COPY'),
    ('mig_stg_acc', 'actual_datalake_datasetSizes',               'actual_datalake', 'datasetSizes',                 'storage_account,layer,path,blob_inventory_date', 'SKIP_EXISTING', 10, 'AUTO'),
    ('mig_stg_acc', 'meta_datalake_rawFolderMappingListOfValues',  'meta_datalake',  'rawFolderMappingListOfValues', 'region,entity',                          'SKIP_EXISTING', 10, 'AUTO'),
    ('mig_stg_acc', 'vw_actual_datalake_acls',                     'actual_datalake', 'acls',                        'storage_account,layer,path,identity_id,permission,valid_from', 'UPSERT', 30, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_datalake_datasetPermissions',         'meta_datalake',  'datasetPermissions',           'dataset_id,identity_id,permission_type,valid_from', 'UPSERT', 30, 'AUTO')
) AS s (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, LoadOrder, IdentityInsertMode)
ON t.SourceSchema = s.SourceSchema AND t.SourceTable = s.SourceTable
   AND t.TargetSchema = s.TargetSchema AND t.TargetTable = s.TargetTable
WHEN MATCHED THEN
    UPDATE SET BusinessKeyColumns = s.BusinessKeyColumns, LoadStrategy = s.LoadStrategy,
               LoadOrder = s.LoadOrder, IdentityInsertMode = s.IdentityInsertMode,
               IsActive = 0, ModifiedDate = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, LoadOrder, IdentityInsertMode, ValidationRequired, IsActive)
    VALUES (s.SourceSchema, s.SourceTable, s.TargetSchema, s.TargetTable, s.BusinessKeyColumns, s.LoadStrategy, s.LoadOrder, s.IdentityInsertMode, 1, 0);
GO

-- =========================================================================
-- ACTIVATION (DO NOT RUN YET) - once the team confirms the API dependency above is resolved,
-- run this to go live with all 5 Wave 2 rows registered above. Left commented out deliberately so
-- re-running this whole file never accidentally activates the family before the dependency clears.
-- =========================================================================
-- UPDATE mig.TableConfiguration
-- SET IsActive = 1, ModifiedDate = SYSUTCDATETIME()
-- WHERE (SourceSchema, SourceTable, TargetSchema, TargetTable) IN (
--     ('mig_stg_acc', 'vw_actual_datalake_datasets',               'actual_datalake', 'datasets'),
--     ('mig_stg_acc', 'actual_datalake_datasetSizes',              'actual_datalake', 'datasetSizes'),
--     ('mig_stg_acc', 'meta_datalake_rawFolderMappingListOfValues', 'meta_datalake',  'rawFolderMappingListOfValues'),
--     ('mig_stg_acc', 'vw_actual_datalake_acls',                    'actual_datalake', 'acls'),
--     ('mig_stg_acc', 'vw_meta_datalake_datasetPermissions',        'meta_datalake',  'datasetPermissions')
-- );
-- GO
