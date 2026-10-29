-- Wave 4: Request & Other Family prep script (mirrors Solution-mapping.sql / Identity-mapping.sql /
-- Datalake-mapping.sql). See "# Wave 4: Request & Other Family Migration Plan" in
-- Database-Migration-Execution.md for the full design discussion and Go/No-Go items; this script
-- implements that plan.
--
-- Scope: Acc-only (dev/tst deferred to a later wave - see Database-Migration-Execution.md). The six
-- `uc*` tables are out of scope for this wave. `meta_other.tasks` is included but runs on the
-- existing daily schedule (`TR_MasterLoadAndValidate_Daily`), not a one-off backfill.
--
-- PREREQUISITE SCHEMA CHANGES (proposed, NOT applied by this script - run through the normal
-- DACPAC/DB deployment process first, in all four environments where noted). Scope of this file is
-- LOAD ONLY, same principle as Wave 2.1's folderMapping: the schema changes below are a separate,
-- out-of-scope prerequisite, and this script's own guard (below) enforces that Production already
-- has them before anything here runs:
--   1. meta_request.requests:              ADD environment VARCHAR(10) NOT NULL (all 4 envs)
--   2. meta_other.tasks:                   ADD environment VARCHAR(10) NOT NULL,
--                                           ADD source_id INT NOT NULL (all 4 envs)
--   3. meta_request.datasetDataOwnerRequests.id: change to IDENTITY (all 4 envs)
-- Rollout: add nullable -> backfill per-environment literal -> enforce NOT NULL (see item 1 in the
-- design doc). This script assumes all three changes are already deployed everywhere it targets.
--
-- Mapping needed:
--   - `requests.requested_by_user_id`/`processed_by_user_id` and
--     `datasetDataOwnerRequests.owner_1/2/3_user_id` are surrogate FKs into `actual_identity.users`,
--     resolved via the EXISTING `mig.actual_identity_identities_mapping` table (already has
--     dev_id/tst_id/acc_id/prd_id side by side, keyed by entra_id) - no new mapping needed.
--   - `requests.id` is IDENTITY and is the shared PK of 17 child/detail tables (their own `id`, also
--     their PK, e.g. aclActionRequests.id) plus `requestResolutionNotes.request_id` - resolved live
--     via a natural-key bridge view below (no persisted mapping table), matched on
--     `task_trace_uuid` (confirmed globally unique - zero duplicates within any environment, zero
--     collisions across all four), against PRODUCTION's own `requests` (not a staged bridge, since
--     `requests` loads earlier in this same wave - same reasoning as Wave 3's
--     solutionInTechnologies -> solutionRoles).
--   - `identity_entra_id`/`group_entra_id` are already entra_id values (the Wave 1 business key for
--     actual_identity.identities, identical across all environments) - pass through unchanged.
--   - `datasetDataOwnerRequests` has no FK to requests.id and no natural key beyond
--     `(layer,path)` (agreed business key) - its `id` becomes IDENTITY (prerequisite change above)
--     and is never migrated/copied, Production generates it fresh.
--   - `meta_other.tasks` has no FK in or out and no natural key at all - the prerequisite
--     `environment`/`source_id` columns are what make its daily UPSERT safe.
--
-- Load order:
--   (pipeline-level) refresh mig.actual_identity_identities_mapping (pick up any new prd_ids
--     needed for requested_by_user_id/processed_by_user_id/owner_*_user_id) - already done by
--     Wave 1/2's refresh step.
--   60: requests, datasetDataOwnerRequests, tasks (independent of each other and of the 17 child
--       tables below)
--   70: the 17 request child/detail tables + requestResolutionNotes (must run after 60, since they
--       resolve id/request_id against Production's just-loaded requests via the bridge)

USE [DMAP]
GO

-- =========================================================================
-- PREREQUISITE GUARD: per Database-Migration-Execution.md ("Wave 4: Request & Other Family
-- Migration Plan", item 1 - Scope: load only), the three columns below are a SEPARATE
-- schema-change activity (DACPAC/deployment, rolled out across all four environments), owned
-- outside this load-setup script:
--   - meta_request.requests.environment VARCHAR(10) NOT NULL
--   - meta_other.tasks.environment VARCHAR(10) NOT NULL
--   - meta_other.tasks.source_id INT NOT NULL
-- This script only ever registers the load (metadata_loadToStaging rows + staging/bridge views) -
-- it never creates or alters these columns. Checking Production's copies is used here as the
-- representative "all clear" signal for the whole Dev/Tst/Acc/Prd rollout, since Production is the
-- last environment to receive the change in the agreed rollout order (same convention as
-- scripts/FolderMapping-mapping.sql's guard for Wave 2.1). If any of the three columns aren't
-- there yet, stop here rather than registering a load that would fail (or silently load with an
-- incomplete business key) once it runs. SET NOEXEC ON causes every later batch in this file to be
-- skipped (not just this one), regardless of which client (SSMS/sqlcmd/Invoke-Sqlcmd) runs it;
-- NOEXEC OFF at the bottom of this file resets the session once the guard has passed.
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
    RAISERROR('Prerequisite missing: meta_request.requests.environment and/or meta_other.tasks.environment/source_id do not exist in Production yet. Apply the separate schema-change (ADD environment VARCHAR(10) NOT NULL to both tables, ADD source_id INT NOT NULL to tasks, backfilled per environment, enforced NOT NULL) across Dev/Tst/Acc/Prd before running this load-setup script. See Database-Migration-Execution.md, Wave 4, item 1.', 16, 1);
    SET NOEXEC ON;
END
GO

INSERT INTO [mig].[metadata_loadToStaging]
           ([SchemaName], [TableName], [Env], [Loadtostaging])
     VALUES
           ('meta_request', 'requests',                             'acc', 1),
           ('meta_request', 'aclActionRequests',                     'acc', 1),
           ('meta_request', 'aclCopyRequests',                       'acc', 1),
           ('meta_request', 'aclReapplyRequests',                    'acc', 1),
           ('meta_request', 'dataCopyPrdLikeEnvRequests',            'acc', 1),
           ('meta_request', 'dataCopyRequests',                      'acc', 1),
           ('meta_request', 'dataDeletionRequests',                  'acc', 1),
           ('meta_request', 'datasetAccessRemovalRequests',          'acc', 1),
           ('meta_request', 'datasetAccessRequests',                 'acc', 1),
           ('meta_request', 'dynamicRequests',                       'acc', 1),
           ('meta_request', 'environmentProdLikeRequests',           'acc', 1),
           ('meta_request', 'foldermappingCreateRequests',           'acc', 1),
           ('meta_request', 'folderMappingRequests',                 'acc', 1),
           ('meta_request', 'idmcGroupMembershipRequests',           'acc', 1),
           ('meta_request', 'idmcGroupRequests',                     'acc', 1),
           ('meta_request', 'manual_upload_requests',                'acc', 1),
           ('meta_request', 'removeSolutionInTechnologyRequests',    'acc', 1),
           ('meta_request', 'roleAssignmentRequests',                'acc', 1),
           ('meta_request', 'requestResolutionNotes',                'acc', 1),
           ('meta_request', 'datasetDataOwnerRequests',              'acc', 1),
           ('meta_other',   'tasks',                                 'acc', 1)
GO

-- =========================================================================
-- BRIDGE VIEW - resolves Acc's surrogate requests.id to the matching Production id via
-- task_trace_uuid (confirmed globally unique). Live join against PRODUCTION's requests (not a
-- staged bridge), same reasoning as Wave 3's solutionInTechnologies -> solutionRoles: requests
-- loads earlier in this same wave (LoadOrder 60), so by the time the LoadOrder-70 child tables run,
-- Production's requests already has the rows this bridge needs.
-- =========================================================================
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_requests_bridge
AS
SELECT
    b.id   AS acc_id,
    p.id   AS prd_id
FROM mig_stg_acc.meta_request_requests AS b
INNER JOIN meta_request.requests AS p
    ON p.task_trace_uuid = b.task_trace_uuid;
GO

-- =========================================================================
-- PRODUCTION-LOAD VIEWS - these are what mig.TableConfiguration points at
-- (sql/validate-and-load/14_request_family_table_configuration.sql).
-- =========================================================================

-- requests: requested_by_user_id/processed_by_user_id resolved via the existing Wave 1 identity
-- mapping; environment is a literal 'acc' (this wave's source); everything else passes through
-- unchanged. id is excluded here - IdentityInsertMode = 'AUTO' means Production generates it fresh,
-- and that's exactly the id the bridge above then resolves for every child table.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_requests
AS
SELECT
    b.request_type,
    b.status,
    b.task_trace_uuid,
    b.itsm_ticket_id,
    b.itsm_system,
    b.itsm_ticket_url,
    b.itsm_assignment_group,
    b.reason_requested,
    rbu.prd_id      AS requested_by_user_id,
    b.created_at,
    b.reason_processed,
    pbu.prd_id      AS processed_by_user_id,
    b.processed_at,
    b.reason_completed,
    b.completed_at,
    b.failed_reason,
    b.failed_at,
    b.automated,
    'acc'           AS environment
FROM mig_stg_acc.meta_request_requests AS b
INNER JOIN mig.actual_identity_identities_mapping AS rbu
    ON rbu.acc_id = b.requested_by_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS pbu
    ON pbu.acc_id = b.processed_by_user_id;
GO

-- aclActionRequests: id via the bridge; identity_entra_id already an entra_id, passes through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_aclActionRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path,
    b.identity_entra_id,
    b.action_type,
    b.permissions,
    b.recursive
FROM mig_stg_acc.meta_request_aclActionRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- aclCopyRequests: id via the bridge; no entra_id/user columns on this table.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_aclCopyRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path,
    b.destination_layer,
    b.destination_path
FROM mig_stg_acc.meta_request_aclCopyRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- aclReapplyRequests: id via the bridge; identity_entra_id passes through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_aclReapplyRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path,
    b.identity_entra_id
FROM mig_stg_acc.meta_request_aclReapplyRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- dataCopyPrdLikeEnvRequests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_dataCopyPrdLikeEnvRequests
AS
SELECT
    rb.prd_id AS id,
    b.ci_code,
    b.source_resource_group,
    b.source_storage_account,
    b.source_layer,
    b.source_path,
    b.destination_resource_group,
    b.destination_storage_account,
    b.destination_layer,
    b.destination_path
FROM mig_stg_acc.meta_request_dataCopyPrdLikeEnvRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- dataCopyRequests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_dataCopyRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path,
    b.destination_storage_account,
    b.destination_layer,
    b.destination_path
FROM mig_stg_acc.meta_request_dataCopyRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- dataDeletionRequests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_dataDeletionRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path
FROM mig_stg_acc.meta_request_dataDeletionRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- datasetAccessRemovalRequests: id via the bridge; group_entra_id already an entra_id, passes
-- through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_datasetAccessRemovalRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path,
    b.group_entra_id
FROM mig_stg_acc.meta_request_datasetAccessRemovalRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- datasetAccessRequests: id via the bridge; group_entra_id already an entra_id, passes through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_datasetAccessRequests
AS
SELECT
    rb.prd_id AS id,
    b.storage_account,
    b.layer,
    b.path,
    b.group_entra_id
FROM mig_stg_acc.meta_request_datasetAccessRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- dynamicRequests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_dynamicRequests
AS
SELECT
    rb.prd_id AS id,
    b.dynamic_request_type,
    b.request_params
FROM mig_stg_acc.meta_request_dynamicRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- environmentProdLikeRequests: id via the bridge; `environment` here is this table's OWN,
-- unrelated data column (target env of the request), not the migration-provenance column added to
-- requests/tasks - passes through unchanged, see design doc item 5.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_environmentProdLikeRequests
AS
SELECT
    rb.prd_id AS id,
    b.ci,
    b.environment
FROM mig_stg_acc.meta_request_environmentProdLikeRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- foldermappingCreateRequests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_foldermappingCreateRequests
AS
SELECT
    rb.prd_id AS id,
    b.source_system,
    b.source_container,
    b.source_folder,
    b.file_name,
    b.target_folder,
    b.data_owner_email
FROM mig_stg_acc.meta_request_foldermappingCreateRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- folderMappingRequests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_folderMappingRequests
AS
SELECT
    rb.prd_id AS id,
    b.original_foldermapping_ids,
    b.batch_data,
    b.ci
FROM mig_stg_acc.meta_request_folderMappingRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- idmcGroupMembershipRequests: id via the bridge; `environment` here is this table's OWN,
-- unrelated data column (target env of the request) - passes through unchanged, see item 5.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_idmcGroupMembershipRequests
AS
SELECT
    rb.prd_id AS id,
    b.idmc_group_name,
    b.environment,
    b.user_email,
    b.action
FROM mig_stg_acc.meta_request_idmcGroupMembershipRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- idmcGroupRequests: id via the bridge; `environment` here is this table's OWN, unrelated data
-- column (target env of the request) - passes through unchanged, see item 5.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_idmcGroupRequests
AS
SELECT
    rb.prd_id AS id,
    b.ci,
    b.environment,
    b.group_name,
    b.role_names
FROM mig_stg_acc.meta_request_idmcGroupRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- manual_upload_requests: id via the bridge; all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_manual_upload_requests
AS
SELECT
    rb.prd_id AS id,
    b.ci,
    b.ritm_number,
    b.target_folder,
    b.sharepoint_folder_link
FROM mig_stg_acc.meta_request_manual_upload_requests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- removeSolutionInTechnologyRequests: id via the bridge; `environment` here is this table's OWN,
-- unrelated data column (target env of the request) - passes through unchanged, see item 5.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_removeSolutionInTechnologyRequests
AS
SELECT
    rb.prd_id AS id,
    b.technology_name,
    b.solution,
    b.environment,
    b.solution_in_technology_name
FROM mig_stg_acc.meta_request_removeSolutionInTechnologyRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- roleAssignmentRequests: id via the bridge; group_entra_id already an entra_id, passes through;
-- `environment` here is this table's OWN, unrelated data column (target env of the role
-- assignment) - passes through unchanged, see item 5.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_roleAssignmentRequests
AS
SELECT
    rb.prd_id AS id,
    b.group_entra_id,
    b.technology_name,
    b.solution_in_technology_name,
    b.environment,
    b.role
FROM mig_stg_acc.meta_request_roleAssignmentRequests AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.id;
GO

-- requestResolutionNotes: request_id via the bridge (PK is request_id, not id, but same pattern);
-- all other columns plain data, pass through.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_requestResolutionNotes
AS
SELECT
    rb.prd_id AS request_id,
    b.itsm_ticket_id,
    b.ritm_sys_id,
    b.resolution_notes,
    b.resolution_note_field,
    b.resolved_at,
    b.closed_at,
    b.source_updated_at,
    b.captured_at
FROM mig_stg_acc.meta_request_requestResolutionNotes AS b
INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
    ON rb.acc_id = b.request_id;
GO

-- datasetDataOwnerRequests: NOT linked to requests.id (confirmed, no FK) - id is excluded here
-- entirely (becomes IDENTITY per the prerequisite schema change, Production generates it fresh).
-- owner_1/2/3_user_id resolved via the existing Wave 1 identity mapping, same as
-- requests.requested_by_user_id/processed_by_user_id above. owner_2/3_user_id are nullable, so
-- those joins are LEFT; owner_1_user_id is NOT NULL on the target, so that join is INNER.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_datasetDataOwnerRequests
AS
SELECT
    b.layer,
    b.path,
    o1.prd_id AS owner_1_user_id,
    o2.prd_id AS owner_2_user_id,
    o3.prd_id AS owner_3_user_id
FROM mig_stg_acc.meta_request_datasetDataOwnerRequests AS b
INNER JOIN mig.actual_identity_identities_mapping AS o1
    ON o1.acc_id = b.owner_1_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS o2
    ON o2.acc_id = b.owner_2_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS o3
    ON o3.acc_id = b.owner_3_user_id;
GO

-- ALTERNATE - NOT APPLIED. Only switch to this (and drop the view above) if the team confirms
-- item 10 in Database-Migration-Execution.md's Wave 4 plan: that datasetDataOwnerRequests.id is
-- actually meant to equal its owning requests.id (no FK is declared today, but the values may
-- still be deliberately shared, same one-row-per-request pattern as the 17 child tables). If so,
-- datasetDataOwnerRequests.id must NOT become IDENTITY (keep it a plain int, like the 17 siblings)
-- and must resolve through the same bridge those 17 use, instead of being excluded/auto-generated:
--
-- CREATE OR ALTER VIEW mig_stg_acc.vw_meta_request_datasetDataOwnerRequests
-- AS
-- SELECT
--     rb.prd_id AS id,
--     b.layer,
--     b.path,
--     o1.prd_id AS owner_1_user_id,
--     o2.prd_id AS owner_2_user_id,
--     o3.prd_id AS owner_3_user_id
-- FROM mig_stg_acc.meta_request_datasetDataOwnerRequests AS b
-- INNER JOIN mig_stg_acc.vw_meta_request_requests_bridge AS rb
--     ON rb.acc_id = b.id
-- INNER JOIN mig.actual_identity_identities_mapping AS o1
--     ON o1.acc_id = b.owner_1_user_id
-- LEFT JOIN mig.actual_identity_identities_mapping AS o2
--     ON o2.acc_id = b.owner_2_user_id
-- LEFT JOIN mig.actual_identity_identities_mapping AS o3
--     ON o3.acc_id = b.owner_3_user_id;
-- GO
--
-- In that case also update mig.TableConfiguration (see
-- sql/validate-and-load/14_request_family_table_configuration.sql): BusinessKeyColumns = 'id',
-- LoadOrder = 70 (it now depends on requests loading first, same as the 17 children).

-- tasks: no FK in or out, no natural key - environment is a literal 'acc' (this wave's only
-- source), source_id captures Acc's own tasks.id verbatim so (environment,source_id) can dedupe on
-- every daily run. id is excluded here (target stays IDENTITY, unchanged), Production generates it
-- fresh exactly like it already does today for its own native rows.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_other_tasks
AS
SELECT
    b.status,
    b.steps,
    b.created_at,
    b.started_at,
    b.failed_at,
    b.completed_at,
    'acc'   AS environment,
    b.id    AS source_id
FROM mig_stg_acc.meta_other_tasks AS b;
GO

-- =========================================================================
-- PRODUCTION LOAD: config-driven, not hand-written.
-- No new persisted mapping table/refresh proc for Wave 4 - mig.usp_RefreshIdentityMapping
-- (Wave 1) already keeps mig.actual_identity_identities_mapping in sync for
-- requested_by_user_id/processed_by_user_id/owner_*_user_id, and the request bridge above is a
-- live view, not a persisted table. Register these in mig.TableConfiguration (see
-- sql/validate-and-load/14_request_family_table_configuration.sql).
-- =========================================================================

-- sanity checks before go-live: confirm no duplicate business keys in staging
SELECT task_trace_uuid, COUNT(*)
FROM mig_stg_acc.meta_request_requests
GROUP BY task_trace_uuid
HAVING COUNT(*) > 1;

SELECT layer, path, COUNT(*)
FROM mig_stg_acc.meta_request_datasetDataOwnerRequests
GROUP BY layer, path
HAVING COUNT(*) > 1;

-- confirm every requested_by_user_id / processed_by_user_id / owner_*_user_id referenced by
-- staging resolves via the identity mapping (any rows returned are blockers for go-live)
SELECT DISTINCT b.requested_by_user_id
FROM mig_stg_acc.meta_request_requests AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.requested_by_user_id
WHERE m.prd_id IS NULL;

SELECT DISTINCT b.processed_by_user_id
FROM mig_stg_acc.meta_request_requests AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.processed_by_user_id
WHERE b.processed_by_user_id IS NOT NULL AND m.prd_id IS NULL;

SELECT DISTINCT b.owner_1_user_id
FROM mig_stg_acc.meta_request_datasetDataOwnerRequests AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.owner_1_user_id
WHERE m.prd_id IS NULL;

-- confirm every requests.id referenced by each child/detail table resolves via the bridge (any
-- rows returned are blockers for go-live for that specific child table)
SELECT 'aclActionRequests' AS table_name, COUNT(*) AS unresolved FROM mig_stg_acc.meta_request_aclActionRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'aclCopyRequests', COUNT(*) FROM mig_stg_acc.meta_request_aclCopyRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'aclReapplyRequests', COUNT(*) FROM mig_stg_acc.meta_request_aclReapplyRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'dataCopyPrdLikeEnvRequests', COUNT(*) FROM mig_stg_acc.meta_request_dataCopyPrdLikeEnvRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'dataCopyRequests', COUNT(*) FROM mig_stg_acc.meta_request_dataCopyRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'dataDeletionRequests', COUNT(*) FROM mig_stg_acc.meta_request_dataDeletionRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'datasetAccessRemovalRequests', COUNT(*) FROM mig_stg_acc.meta_request_datasetAccessRemovalRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'datasetAccessRequests', COUNT(*) FROM mig_stg_acc.meta_request_datasetAccessRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'dynamicRequests', COUNT(*) FROM mig_stg_acc.meta_request_dynamicRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'environmentProdLikeRequests', COUNT(*) FROM mig_stg_acc.meta_request_environmentProdLikeRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'foldermappingCreateRequests', COUNT(*) FROM mig_stg_acc.meta_request_foldermappingCreateRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'folderMappingRequests', COUNT(*) FROM mig_stg_acc.meta_request_folderMappingRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'idmcGroupMembershipRequests', COUNT(*) FROM mig_stg_acc.meta_request_idmcGroupMembershipRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'idmcGroupRequests', COUNT(*) FROM mig_stg_acc.meta_request_idmcGroupRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'manual_upload_requests', COUNT(*) FROM mig_stg_acc.meta_request_manual_upload_requests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'removeSolutionInTechnologyRequests', COUNT(*) FROM mig_stg_acc.meta_request_removeSolutionInTechnologyRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'roleAssignmentRequests', COUNT(*) FROM mig_stg_acc.meta_request_roleAssignmentRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
UNION ALL
SELECT 'requestResolutionNotes', COUNT(*) FROM mig_stg_acc.meta_request_requestResolutionNotes b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.request_id WHERE rb.prd_id IS NULL;
GO

-- Reset session state in case the prerequisite guard above tripped NOEXEC ON for this run.
SET NOEXEC OFF;
GO
