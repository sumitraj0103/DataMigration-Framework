-- Read-only dry run: shows exactly what the request & other family (Wave 4, Acc-only)
-- mig.TableConfiguration rows would insert/update into Production, without writing anything.
-- Safe to run anytime; no INSERT/UPDATE statements in this file.
-- Run after mig.usp_RefreshIdentityMapping so requested_by_user_id/processed_by_user_id/
-- owner_*_user_id resolve correctly, and after the prerequisite schema changes (requests/tasks
-- environment columns, tasks.source_id, datasetDataOwnerRequests.id -> IDENTITY) are deployed - see
-- "# Wave 4: Request & Other Family Migration Plan" in Database-Migration-Execution.md.

-- =========================================================================
-- 1) requests rows that can't resolve requested_by_user_id/processed_by_user_id yet (blocked)
-- =========================================================================
SELECT
    b.id, b.task_trace_uuid,
    b.requested_by_user_id AS acc_requested_by_user_id, rbu.prd_id AS requested_by_user_id_resolved,
    b.processed_by_user_id AS acc_processed_by_user_id, pbu.prd_id AS processed_by_user_id_resolved
FROM mig_stg_acc.meta_request_requests AS b
LEFT JOIN mig.actual_identity_identities_mapping AS rbu ON rbu.acc_id = b.requested_by_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS pbu ON pbu.acc_id = b.processed_by_user_id
WHERE rbu.prd_id IS NULL
   OR (b.processed_by_user_id IS NOT NULL AND pbu.prd_id IS NULL);

-- =========================================================================
-- 2) requests rows that would be inserted/updated (UPSERT, business key = task_trace_uuid)
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM meta_request.requests AS p WHERE p.task_trace_uuid = v.task_trace_uuid) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM meta_request.requests AS p
            WHERE p.task_trace_uuid = v.task_trace_uuid
              AND (p.status <> v.status
                OR  ISNULL(p.processed_by_user_id,-1) <> ISNULL(v.processed_by_user_id,-1)
                OR  ISNULL(p.processed_at,'1900-01-01') <> ISNULL(v.processed_at,'1900-01-01')
                OR  ISNULL(p.reason_completed,'') <> ISNULL(v.reason_completed,'')
                OR  ISNULL(p.completed_at,'1900-01-01') <> ISNULL(v.completed_at,'1900-01-01')
                OR  ISNULL(p.failed_reason,'') <> ISNULL(v.failed_reason,'')
                OR  ISNULL(p.failed_at,'1900-01-01') <> ISNULL(v.failed_at,'1900-01-01'))
        ) THEN 'WILL BE UPDATED'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_meta_request_requests AS v
ORDER BY LoadStatus, v.task_trace_uuid;

-- =========================================================================
-- 3) Per-child-table blocked row counts (requests.id unresolved via the bridge) - any non-zero
--    value is a go-live blocker for that specific table (the referenced request hasn't loaded to
--    Production yet, or its task_trace_uuid doesn't match for some other reason)
-- =========================================================================
SELECT 'aclActionRequests' AS table_name, COUNT(*) AS blocked_unresolved_request_id FROM mig_stg_acc.meta_request_aclActionRequests b LEFT JOIN mig_stg_acc.vw_meta_request_requests_bridge rb ON rb.acc_id = b.id WHERE rb.prd_id IS NULL
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

-- =========================================================================
-- 4) Per-child-table insert counts (rows not already in Production, matched on the resolved id)
-- =========================================================================
SELECT 'aclActionRequests' AS table_name, COUNT(*) AS will_insert FROM mig_stg_acc.vw_meta_request_aclActionRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.aclActionRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'aclCopyRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_aclCopyRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.aclCopyRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'aclReapplyRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_aclReapplyRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.aclReapplyRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'dataCopyPrdLikeEnvRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_dataCopyPrdLikeEnvRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.dataCopyPrdLikeEnvRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'dataCopyRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_dataCopyRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.dataCopyRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'dataDeletionRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_dataDeletionRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.dataDeletionRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'datasetAccessRemovalRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_datasetAccessRemovalRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.datasetAccessRemovalRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'datasetAccessRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_datasetAccessRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.datasetAccessRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'dynamicRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_dynamicRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.dynamicRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'environmentProdLikeRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_environmentProdLikeRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.environmentProdLikeRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'foldermappingCreateRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_foldermappingCreateRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.foldermappingCreateRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'folderMappingRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_folderMappingRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.folderMappingRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'idmcGroupMembershipRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_idmcGroupMembershipRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.idmcGroupMembershipRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'idmcGroupRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_idmcGroupRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.idmcGroupRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'manual_upload_requests', COUNT(*) FROM mig_stg_acc.vw_meta_request_manual_upload_requests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.manual_upload_requests p WHERE p.id = v.id)
UNION ALL
SELECT 'removeSolutionInTechnologyRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_removeSolutionInTechnologyRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.removeSolutionInTechnologyRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'roleAssignmentRequests', COUNT(*) FROM mig_stg_acc.vw_meta_request_roleAssignmentRequests v WHERE NOT EXISTS (SELECT 1 FROM meta_request.roleAssignmentRequests p WHERE p.id = v.id)
UNION ALL
SELECT 'requestResolutionNotes', COUNT(*) FROM mig_stg_acc.vw_meta_request_requestResolutionNotes v WHERE NOT EXISTS (SELECT 1 FROM meta_request.requestResolutionNotes p WHERE p.request_id = v.request_id);

-- =========================================================================
-- 5) datasetDataOwnerRequests: blocked (owner_1_user_id unresolved) and insert/update preview
--    (business key = layer,path)
-- =========================================================================
SELECT
    b.layer, b.path,
    b.owner_1_user_id AS acc_owner_1_user_id, o1.prd_id AS owner_1_user_id_resolved
FROM mig_stg_acc.meta_request_datasetDataOwnerRequests AS b
LEFT JOIN mig.actual_identity_identities_mapping AS o1 ON o1.acc_id = b.owner_1_user_id
WHERE o1.prd_id IS NULL;

SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM meta_request.datasetDataOwnerRequests AS p WHERE p.layer = v.layer AND p.path = v.path) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM meta_request.datasetDataOwnerRequests AS p
            WHERE p.layer = v.layer AND p.path = v.path
              AND (p.owner_1_user_id <> v.owner_1_user_id
                OR  ISNULL(p.owner_2_user_id,-1) <> ISNULL(v.owner_2_user_id,-1)
                OR  ISNULL(p.owner_3_user_id,-1) <> ISNULL(v.owner_3_user_id,-1))
        ) THEN 'WILL BE UPDATED'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_meta_request_datasetDataOwnerRequests AS v
ORDER BY LoadStatus, v.layer, v.path;

-- =========================================================================
-- 6) tasks: insert/update preview (business key = environment,source_id) - this is the query that
--    would run daily once TR_MasterLoadAndValidate_Daily is started
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM meta_other.tasks AS p WHERE p.environment = v.environment AND p.source_id = v.source_id) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM meta_other.tasks AS p
            WHERE p.environment = v.environment AND p.source_id = v.source_id
              AND (p.status <> v.status
                OR  ISNULL(p.started_at,'1900-01-01') <> ISNULL(v.started_at,'1900-01-01')
                OR  ISNULL(p.failed_at,'1900-01-01') <> ISNULL(v.failed_at,'1900-01-01')
                OR  ISNULL(p.completed_at,'1900-01-01') <> ISNULL(v.completed_at,'1900-01-01'))
        ) THEN 'WILL BE UPDATED'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_meta_other_tasks AS v
ORDER BY LoadStatus, v.source_id;

-- =========================================================================
-- 7) Overall row-count summary, for a quick before-you-run check
-- =========================================================================
SELECT 'requests_blocked_unresolved_user_id', COUNT(*) FROM mig_stg_acc.meta_request_requests AS b
    LEFT JOIN mig.actual_identity_identities_mapping AS rbu ON rbu.acc_id = b.requested_by_user_id
    LEFT JOIN mig.actual_identity_identities_mapping AS pbu ON pbu.acc_id = b.processed_by_user_id
    WHERE rbu.prd_id IS NULL OR (b.processed_by_user_id IS NOT NULL AND pbu.prd_id IS NULL)
UNION ALL
SELECT 'requests_insert', COUNT(*) FROM mig_stg_acc.vw_meta_request_requests AS v
    WHERE NOT EXISTS (SELECT 1 FROM meta_request.requests AS p WHERE p.task_trace_uuid = v.task_trace_uuid)
UNION ALL
SELECT 'datasetDataOwnerRequests_insert', COUNT(*) FROM mig_stg_acc.vw_meta_request_datasetDataOwnerRequests AS v
    WHERE NOT EXISTS (SELECT 1 FROM meta_request.datasetDataOwnerRequests AS p WHERE p.layer = v.layer AND p.path = v.path)
UNION ALL
SELECT 'tasks_insert', COUNT(*) FROM mig_stg_acc.vw_meta_other_tasks AS v
    WHERE NOT EXISTS (SELECT 1 FROM meta_other.tasks AS p WHERE p.environment = v.environment AND p.source_id = v.source_id);
