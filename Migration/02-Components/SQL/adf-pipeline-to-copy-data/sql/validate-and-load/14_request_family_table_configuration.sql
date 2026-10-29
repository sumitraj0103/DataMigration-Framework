-- Registers the request & other family (Wave 4) in mig.TableConfiguration so
-- PL_ValidateAndLoadAllToProduction loads them, in FK order, via the generic
-- mig.usp_LoadValidatedTableToProduction engine.
-- Scope: Acc-only (see "# Wave 4: Request & Other Family Migration Plan" in
-- Database-Migration-Execution.md). The six `uc*` tables are excluded - out of scope for this wave.
--
-- All sources are the mig_stg_acc.vw_* views (scripts/Request-mapping.sql), which resolve
-- requested_by_user_id/processed_by_user_id/owner_*_user_id (existing Wave 1 identity mapping) and
-- id/request_id for the 17 child tables + requestResolutionNotes (new Acc-only requests-id bridge,
-- matched on task_trace_uuid against Production's already-loaded requests this same wave).
-- identity_entra_id/group_entra_id already pass through unchanged (Wave 1 business key).
--
-- IdentityInsertMode = 'AUTO' for every row here: requests.id, datasetDataOwnerRequests.id and
-- tasks.id are all (or become, per the prerequisite schema changes) IDENTITY columns that
-- Production generates fresh; the 17 child tables' own id/request_id columns are plain (non-
-- identity) ints whose value the view already resolves to the correct Production requests.id via
-- the bridge, so AUTO vs COPY makes no difference for them (no identity column exists to exclude).
--
-- LoadOrder = 60 / 70 (new values, after Wave 3's 40/50): requests, datasetDataOwnerRequests and
-- tasks (60, independent of each other) must load before the 17 child/detail tables +
-- requestResolutionNotes (70), since those resolve against Production's just-loaded requests via
-- the bridge. Both tiers fall in PL_ValidateAndLoadAllToProduction's existing `LoadOrder > 10`
-- phase (after the identity mapping refresh needed for requested_by_user_id/owner_*_user_id); no
-- new refresh step is required.
--
-- LoadStrategy: UPSERT for requests/datasetDataOwnerRequests/tasks (their status/owner/lifecycle
-- fields can change after creation - see design doc item 7); SKIP_EXISTING for the 17 child/detail
-- tables + requestResolutionNotes (set once at request-creation time, never updated afterwards).
--
-- `tasks` runs on the EXISTING daily schedule (adf/triggers/TR_MasterLoadAndValidate_Daily,
-- currently IsActive/runtimeState = Stopped) - no new scheduling work needed, just start that
-- trigger once this wave goes live.
--
-- IsActive = 0 on first insert AND on every re-run of this script (WHEN MATCHED also forces 0,
-- mirroring 12_datalake_family_table_configuration.sql's / 13_solution_family_table_configuration.sql's
-- pattern): several Go/No-Go items are still open (see the Go/No-Go table in
-- Database-Migration-Execution.md - prerequisite schema changes must be deployed first, the
-- app-level follow-up for new requests'/tasks' `environment` column is still unresolved, and the
-- datasetDataOwnerRequests.id question in item 10 is unresolved), so re-running this registration
-- script must not silently activate the family. Once every remaining Go/No-Go item is resolved, run
-- the commented-out activation statement at the bottom of this file to flip every row above to
-- IsActive = 1 in one step, rather than relying on this MERGE to do it implicitly.
--
-- OPEN ITEM (item 10 in the plan doc): the datasetDataOwnerRequests row below assumes id is an
-- independent surrogate (IdentityInsertMode = 'AUTO', BusinessKeyColumns = 'layer,path',
-- LoadOrder = 60). If the team confirms id actually represents the owning requests.id instead (see
-- the validation query in item 10), replace that row with:
--   ('mig_stg_acc', 'vw_meta_request_datasetDataOwnerRequests', 'meta_request', 'datasetDataOwnerRequests', 'id', 'UPSERT', 70, 'AUTO'),
-- (BusinessKeyColumns = 'id', LoadOrder = 70) and swap in the alternate, bridge-based view from
-- scripts/Request-mapping.sql.

-- =========================================================================
-- PREREQUISITE GUARD: refuse to register the load if meta_request.requests.environment and/or
-- meta_other.tasks.environment/source_id don't already exist in Production (see
-- scripts/Request-mapping.sql for the same check - this script's registration and that script's
-- load setup must never run independently of each other's guard). SET NOEXEC ON skips every later
-- batch in this file regardless of client (SSMS/sqlcmd/Invoke-Sqlcmd); NOEXEC OFF further down
-- resets the session once the guard passes.
-- =========================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('meta_request.requests') AND name = 'environment'
) OR NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('meta_other.tasks') AND name = 'environment'
) OR NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('meta_other.tasks') AND name = 'source_id'
)
BEGIN
    RAISERROR('Prerequisite missing: meta_request.requests.environment and/or meta_other.tasks.environment/source_id do not exist in Production yet. Apply the separate schema-change (ADD environment VARCHAR(10) NOT NULL to both tables, ADD source_id INT NOT NULL to tasks, backfilled per environment, enforced NOT NULL) across Dev/Tst/Acc/Prd before registering this TableConfiguration. See Database-Migration-Execution.md, Wave 4, item 1.', 16, 1);
    SET NOEXEC ON;
END
GO

MERGE mig.TableConfiguration AS t
USING (VALUES
    ('mig_stg_acc', 'vw_meta_request_requests',                            'meta_request', 'requests',                           'task_trace_uuid', 'UPSERT',       60, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_datasetDataOwnerRequests',            'meta_request', 'datasetDataOwnerRequests',           'layer,path',       'UPSERT',       60, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_other_tasks',                                 'meta_other',   'tasks',                              'environment,source_id', 'UPSERT', 60, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_aclActionRequests',                   'meta_request', 'aclActionRequests',                  'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_aclCopyRequests',                     'meta_request', 'aclCopyRequests',                    'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_aclReapplyRequests',                  'meta_request', 'aclReapplyRequests',                 'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_dataCopyPrdLikeEnvRequests',          'meta_request', 'dataCopyPrdLikeEnvRequests',         'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_dataCopyRequests',                    'meta_request', 'dataCopyRequests',                   'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_dataDeletionRequests',                'meta_request', 'dataDeletionRequests',               'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_datasetAccessRemovalRequests',        'meta_request', 'datasetAccessRemovalRequests',       'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_datasetAccessRequests',               'meta_request', 'datasetAccessRequests',              'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_dynamicRequests',                     'meta_request', 'dynamicRequests',                    'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_environmentProdLikeRequests',         'meta_request', 'environmentProdLikeRequests',        'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_foldermappingCreateRequests',         'meta_request', 'foldermappingCreateRequests',        'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_folderMappingRequests',               'meta_request', 'folderMappingRequests',              'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_idmcGroupMembershipRequests',         'meta_request', 'idmcGroupMembershipRequests',        'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_idmcGroupRequests',                   'meta_request', 'idmcGroupRequests',                  'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_manual_upload_requests',              'meta_request', 'manual_upload_requests',             'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_removeSolutionInTechnologyRequests',  'meta_request', 'removeSolutionInTechnologyRequests', 'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_roleAssignmentRequests',              'meta_request', 'roleAssignmentRequests',             'id',               'SKIP_EXISTING', 70, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_request_requestResolutionNotes',              'meta_request', 'requestResolutionNotes',             'request_id',       'SKIP_EXISTING', 70, 'AUTO')
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

-- Reset session state in case the prerequisite guard above tripped NOEXEC ON for this run.
SET NOEXEC OFF;
GO

-- =========================================================================
-- ACTIVATION (DO NOT RUN YET) - once the team confirms every remaining Go/No-Go item above
-- (prerequisite schema changes deployed, app-level `environment`/`source_id` follow-up, and the
-- datasetDataOwnerRequests.id question in item 10), run this to go live with every Wave 4 row
-- registered above. Left commented out deliberately so re-running this whole file never
-- accidentally activates the family before those items clear.
-- =========================================================================
-- UPDATE mig.TableConfiguration
-- SET IsActive = 1, ModifiedDate = SYSUTCDATETIME()
-- WHERE (SourceSchema, SourceTable, TargetSchema, TargetTable) IN (
--     ('mig_stg_acc', 'vw_meta_request_requests',                           'meta_request', 'requests'),
--     ('mig_stg_acc', 'vw_meta_request_datasetDataOwnerRequests',           'meta_request', 'datasetDataOwnerRequests'),
--     ('mig_stg_acc', 'vw_meta_other_tasks',                                'meta_other',   'tasks'),
--     ('mig_stg_acc', 'vw_meta_request_aclActionRequests',                  'meta_request', 'aclActionRequests'),
--     ('mig_stg_acc', 'vw_meta_request_aclCopyRequests',                    'meta_request', 'aclCopyRequests'),
--     ('mig_stg_acc', 'vw_meta_request_aclReapplyRequests',                 'meta_request', 'aclReapplyRequests'),
--     ('mig_stg_acc', 'vw_meta_request_dataCopyPrdLikeEnvRequests',         'meta_request', 'dataCopyPrdLikeEnvRequests'),
--     ('mig_stg_acc', 'vw_meta_request_dataCopyRequests',                   'meta_request', 'dataCopyRequests'),
--     ('mig_stg_acc', 'vw_meta_request_dataDeletionRequests',               'meta_request', 'dataDeletionRequests'),
--     ('mig_stg_acc', 'vw_meta_request_datasetAccessRemovalRequests',       'meta_request', 'datasetAccessRemovalRequests'),
--     ('mig_stg_acc', 'vw_meta_request_datasetAccessRequests',              'meta_request', 'datasetAccessRequests'),
--     ('mig_stg_acc', 'vw_meta_request_dynamicRequests',                    'meta_request', 'dynamicRequests'),
--     ('mig_stg_acc', 'vw_meta_request_environmentProdLikeRequests',        'meta_request', 'environmentProdLikeRequests'),
--     ('mig_stg_acc', 'vw_meta_request_foldermappingCreateRequests',        'meta_request', 'foldermappingCreateRequests'),
--     ('mig_stg_acc', 'vw_meta_request_folderMappingRequests',              'meta_request', 'folderMappingRequests'),
--     ('mig_stg_acc', 'vw_meta_request_idmcGroupMembershipRequests',        'meta_request', 'idmcGroupMembershipRequests'),
--     ('mig_stg_acc', 'vw_meta_request_idmcGroupRequests',                  'meta_request', 'idmcGroupRequests'),
--     ('mig_stg_acc', 'vw_meta_request_manual_upload_requests',             'meta_request', 'manual_upload_requests'),
--     ('mig_stg_acc', 'vw_meta_request_removeSolutionInTechnologyRequests', 'meta_request', 'removeSolutionInTechnologyRequests'),
--     ('mig_stg_acc', 'vw_meta_request_roleAssignmentRequests',             'meta_request', 'roleAssignmentRequests'),
--     ('mig_stg_acc', 'vw_meta_request_requestResolutionNotes',             'meta_request', 'requestResolutionNotes')
-- );
-- GO
