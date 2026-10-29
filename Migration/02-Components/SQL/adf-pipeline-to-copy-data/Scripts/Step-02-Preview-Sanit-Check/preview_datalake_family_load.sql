-- Read-only dry run: shows exactly what the data lake family (Wave 2) mig.TableConfiguration
-- rows would insert/update into Production, without writing anything.
-- Safe to run anytime; no INSERT/UPDATE statements in this file.
-- Run after mig.usp_RefreshIdentityMapping so identity_id/owner_*_user_id resolve correctly.

-- =========================================================================
-- 1) Datasets - business key: storage_account,layer,path,active (id stays OUT of the key - see
--    Database-Migration-Execution.md, Wave 2, item 4). No explicit COLLATE needed on path here -
--    mig_stg_acc.vw_actual_datalake_datasets (v, scripts/Datalake-mapping.sql) already projects it
--    with an explicit case-sensitive COLLATE, which wins precedence over actual_datalake.datasets'
--    (p) plain/implicit collation, so this comparison is case-sensitive automatically.
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (
            SELECT 1 FROM actual_datalake.datasets AS p
            WHERE p.storage_account = v.storage_account
              AND p.layer = v.layer
              AND p.path = v.path
              AND p.active = v.active
        ) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM actual_datalake.datasets AS p
            WHERE p.storage_account = v.storage_account
              AND p.layer = v.layer
              AND p.path = v.path
              AND p.active = v.active
              AND (ISNULL(p.owner_1_user_id,-1) <> ISNULL(v.owner_1_user_id,-1)
                OR  ISNULL(p.owner_2_user_id,-1) <> ISNULL(v.owner_2_user_id,-1)
                OR  ISNULL(p.owner_3_user_id,-1) <> ISNULL(v.owner_3_user_id,-1)
                OR  p.id <> v.id)
        ) THEN 'WILL BE UPDATED (note: this also overwrites id - see Go/No-Go, item 4)'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_actual_datalake_datasets AS v
ORDER BY LoadStatus, v.storage_account, v.layer, v.path;

-- =========================================================================
-- 2) Datasets whose owner_*_user_id can't resolve yet (identity not mapped to a prd_id)
--    - these rows load with NULL owners until the identity mapping is refreshed
-- =========================================================================
SELECT
    b.id, b.storage_account, b.layer,
    b.owner_1_user_id AS acc_owner_1, m1.prd_id AS owner_1_resolved,
    b.owner_2_user_id AS acc_owner_2, m2.prd_id AS owner_2_resolved,
    b.owner_3_user_id AS acc_owner_3, m3.prd_id AS owner_3_resolved
FROM mig_stg_acc.actual_datalake_datasets AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m1 ON m1.acc_id = b.owner_1_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS m2 ON m2.acc_id = b.owner_2_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS m3 ON m3.acc_id = b.owner_3_user_id
WHERE (b.owner_1_user_id IS NOT NULL AND m1.prd_id IS NULL)
   OR (b.owner_2_user_id IS NOT NULL AND m2.prd_id IS NULL)
   OR (b.owner_3_user_id IS NOT NULL AND m3.prd_id IS NULL);

-- =========================================================================
-- 3) DatasetSizes that would be inserted (SKIP_EXISTING, business key = storage_account,layer,path,blob_inventory_date)
-- =========================================================================
SELECT s.*
FROM mig_stg_acc.actual_datalake_datasetSizes AS s
WHERE NOT EXISTS (
    SELECT 1 FROM actual_datalake.datasetSizes AS p
    WHERE p.storage_account = s.storage_account AND p.layer = s.layer
      AND p.path = s.path AND p.blob_inventory_date = s.blob_inventory_date
);

-- =========================================================================
-- 4) FolderMapping / RawFolderMappingListOfValues that would be inserted (SKIP_EXISTING)
-- =========================================================================
SELECT s.*
FROM mig_stg_acc.meta_datalake_folderMapping AS s
WHERE NOT EXISTS (
    SELECT 1 FROM meta_datalake.folderMapping AS p
    WHERE p.source_system = s.source_system AND p.source_container = s.source_container
      AND p.source_folder = s.source_folder AND p.file_name = s.file_name
      AND p.target_folder = s.target_folder
);

SELECT s.*
FROM mig_stg_acc.meta_datalake_rawFolderMappingListOfValues AS s
WHERE NOT EXISTS (
    SELECT 1 FROM meta_datalake.rawFolderMappingListOfValues AS p
    WHERE p.region = s.region AND p.entity = s.entity
);

-- =========================================================================
-- 5) Acls that can't resolve identity_id yet (blocked until identity mapping is refreshed)
-- =========================================================================
SELECT
    b.storage_account, b.layer, b.path, b.identity_id AS acc_identity_id, b.permission, b.valid_from
FROM mig_stg_acc.actual_datalake_acls AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
WHERE m.prd_id IS NULL;

-- =========================================================================
-- 6) Acls that would be inserted/updated (UPSERT, business key = storage_account,layer,path,identity_id,permission,valid_from)
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (
            SELECT 1 FROM actual_datalake.acls AS p
            WHERE p.storage_account = v.storage_account AND p.layer = v.layer AND p.path = v.path
              AND p.identity_id = v.identity_id AND p.permission = v.permission AND p.valid_from = v.valid_from
        ) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM actual_datalake.acls AS p
            WHERE p.storage_account = v.storage_account AND p.layer = v.layer AND p.path = v.path
              AND p.identity_id = v.identity_id AND p.permission = v.permission AND p.valid_from = v.valid_from
              AND (p.recursive <> v.recursive OR ISNULL(p.valid_to,'1900-01-01') <> ISNULL(v.valid_to,'1900-01-01'))
        ) THEN 'WILL BE UPDATED'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_actual_datalake_acls AS v
ORDER BY LoadStatus, v.storage_account, v.layer, v.path;

-- =========================================================================
-- 7) DatasetPermissions that can't resolve identity_id yet (blocked until identity mapping is refreshed)
-- =========================================================================
SELECT
    b.dataset_id, b.identity_id AS acc_identity_id, b.permission_type, b.valid_from
FROM mig_stg_acc.meta_datalake_datasetPermissions AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
WHERE m.prd_id IS NULL;

-- =========================================================================
-- 8) DatasetPermissions that reference a dataset_id not yet in Production (blocked until datasets load first)
-- =========================================================================
SELECT DISTINCT b.dataset_id
FROM mig_stg_acc.meta_datalake_datasetPermissions AS b
WHERE NOT EXISTS (SELECT 1 FROM actual_datalake.datasets AS p WHERE p.id = b.dataset_id)
  AND NOT EXISTS (SELECT 1 FROM mig_stg_acc.actual_datalake_datasets AS s WHERE s.id = b.dataset_id);

-- =========================================================================
-- 9) DatasetPermissions that would be inserted/updated (UPSERT, business key = dataset_id,identity_id,permission_type,valid_from)
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (
            SELECT 1 FROM meta_datalake.datasetPermissions AS p
            WHERE p.dataset_id = v.dataset_id AND p.identity_id = v.identity_id
              AND p.permission_type = v.permission_type AND p.valid_from = v.valid_from
        ) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM meta_datalake.datasetPermissions AS p
            WHERE p.dataset_id = v.dataset_id AND p.identity_id = v.identity_id
              AND p.permission_type = v.permission_type AND p.valid_from = v.valid_from
              AND ISNULL(p.valid_to,'1900-01-01') <> ISNULL(v.valid_to,'1900-01-01')
        ) THEN 'WILL BE UPDATED'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_meta_datalake_datasetPermissions AS v
ORDER BY LoadStatus, v.dataset_id;

-- =========================================================================
-- 10) Row-count summary of all of the above, for a quick before-you-run check
-- =========================================================================
SELECT 'datasets_insert', COUNT(*) FROM mig_stg_acc.vw_actual_datalake_datasets AS v
    WHERE NOT EXISTS (
        SELECT 1 FROM actual_datalake.datasets AS p
        WHERE p.storage_account = v.storage_account
          AND p.layer = v.layer
          AND p.path = v.path
          AND p.active = v.active
    )
UNION ALL
SELECT 'datasetSizes_insert', COUNT(*) FROM mig_stg_acc.actual_datalake_datasetSizes AS s
    WHERE NOT EXISTS (
        SELECT 1 FROM actual_datalake.datasetSizes AS p
        WHERE p.storage_account = s.storage_account AND p.layer = s.layer
          AND p.path = s.path AND p.blob_inventory_date = s.blob_inventory_date)
UNION ALL
SELECT 'folderMapping_insert', COUNT(*) FROM mig_stg_acc.meta_datalake_folderMapping AS s
    WHERE NOT EXISTS (
        SELECT 1 FROM meta_datalake.folderMapping AS p
        WHERE p.source_system = s.source_system AND p.source_container = s.source_container
          AND p.source_folder = s.source_folder AND p.file_name = s.file_name AND p.target_folder = s.target_folder)
UNION ALL
SELECT 'rawFolderMappingListOfValues_insert', COUNT(*) FROM mig_stg_acc.meta_datalake_rawFolderMappingListOfValues AS s
    WHERE NOT EXISTS (SELECT 1 FROM meta_datalake.rawFolderMappingListOfValues AS p WHERE p.region = s.region AND p.entity = s.entity)
UNION ALL
SELECT 'acls_blocked_unmapped_identity', COUNT(*) FROM mig_stg_acc.actual_datalake_acls AS b
    LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
    WHERE m.prd_id IS NULL
UNION ALL
SELECT 'acls_insert', COUNT(*) FROM mig_stg_acc.vw_actual_datalake_acls AS v
    WHERE NOT EXISTS (
        SELECT 1 FROM actual_datalake.acls AS p
        WHERE p.storage_account = v.storage_account AND p.layer = v.layer AND p.path = v.path
          AND p.identity_id = v.identity_id AND p.permission = v.permission AND p.valid_from = v.valid_from)
UNION ALL
SELECT 'datasetPermissions_blocked_unmapped_identity', COUNT(*) FROM mig_stg_acc.meta_datalake_datasetPermissions AS b
    LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
    WHERE m.prd_id IS NULL
UNION ALL
SELECT 'datasetPermissions_insert', COUNT(*) FROM mig_stg_acc.vw_meta_datalake_datasetPermissions AS v
    WHERE NOT EXISTS (
        SELECT 1 FROM meta_datalake.datasetPermissions AS p
        WHERE p.dataset_id = v.dataset_id AND p.identity_id = v.identity_id
          AND p.permission_type = v.permission_type AND p.valid_from = v.valid_from);
