-- Wave 2 sanity check: duplicate rows per table's BusinessKeyColumns (Database-Migration-Execution.md,
-- "# Wave 2: Data Lake Family Migration Plan" / mig.TableConfiguration). Run against each table's
-- actual configured source (the vw_* view where one is used), so results reflect the post
-- identity-mapping ids that will actually be compared during Validate & Load.
-- Any rows returned below are blockers: UPSERT/SKIP_EXISTING assumes the business key is unique
-- in staging, so duplicates will cause ambiguous matches or ON-clause errors in the generic
-- validate/load engine (mig.usp_LoadValidatedTableToProduction).

-- 1) datasets - business key: storage_account,layer,path,active (id stays OUT of the key - see
--    Database-Migration-Execution.md, Wave 2, item 4). The duplicates this check originally found
--    turned out to be a case-insensitive-collation bug, not a real business-key gap: the same path
--    differing only by letter case (e.g. 'CEAR/gold' vs 'CEAR/GOLD') collides under the database's
--    default collation even though Production already holds both as distinct, legitimate rows.
--    No explicit COLLATE needed here any more - mig_stg_acc.vw_actual_datalake_datasets
--    (scripts/Datalake-mapping.sql) already projects path with an explicit case-sensitive COLLATE,
--    so this GROUP BY (and the real engine's business-key match/duplicate-check against the same
--    view) is case-sensitive automatically. Any rows returned here are a genuine blocker.
SELECT storage_account, layer, path, active, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.vw_actual_datalake_datasets
GROUP BY storage_account, layer, path, active
HAVING COUNT(*) > 1;

-- 1b) datasets - informational only, NOT a blocker on its own: same as #1 but queried against the
--     RAW staging table (no view, so no forced collation) using the database's default
--     (case-insensitive) collation. Rows returned here that do NOT also appear in #1 are case-only
--     variants (e.g. 'CEAR/gold' vs 'CEAR/GOLD') - expected, and already handled transparently by
--     the view, not something to action.
SELECT storage_account, layer, path, active, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.actual_datalake_datasets
GROUP BY storage_account, layer, path, active
HAVING COUNT(*) > 1;

-- 2) datasetSizes - business key: storage_account,layer,path,blob_inventory_date
SELECT storage_account, layer, path, blob_inventory_date, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.actual_datalake_datasetSizes
GROUP BY storage_account, layer, path, blob_inventory_date
HAVING COUNT(*) > 1;

-- 3) folderMapping moved to Wave 2.1 (now Dev/Tst/Acc, business key includes Environment) -
-- see scripts/FolderMapping-mapping.sql for its duplicate checks instead.

-- 4) rawFolderMappingListOfValues - business key: region,entity
SELECT region, entity, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.meta_datalake_rawFolderMappingListOfValues
GROUP BY region, entity
HAVING COUNT(*) > 1;

-- 5) acls - business key: storage_account,layer,path,identity_id,permission,valid_from. No
--    explicit COLLATE needed - mig_stg_acc.vw_actual_datalake_acls (scripts/Datalake-mapping.sql)
--    already projects path with the same explicit case-sensitive COLLATE as datasets, as a
--    precaution against the same case-only "duplicates" risk (not yet confirmed to actually occur
--    here, but the column/data comes from the same source).
SELECT storage_account, layer, path, identity_id, permission, valid_from, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.vw_actual_datalake_acls
GROUP BY storage_account, layer, path, identity_id, permission, valid_from
HAVING COUNT(*) > 1;

-- 6) datasetPermissions - business key: dataset_id,identity_id,permission_type,valid_from
SELECT dataset_id, identity_id, permission_type, valid_from, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.vw_meta_datalake_datasetPermissions
GROUP BY dataset_id, identity_id, permission_type, valid_from
HAVING COUNT(*) > 1;

-- =========================================================================
-- Optional secondary check for acls / datasetPermissions: duplicates that only appear AFTER
-- identity mapping (i.e. not duplicated in the raw staging table, but two different Acc
-- identity_ids map to the SAME Production identity, so they collide once resolved). This is a
-- distinct risk from #5/#6 above and won't show up when checking the raw table alone. Queries the
-- RAW staging table directly (not the view), so path needs its own explicit case-sensitive
-- COLLATE here too - same reasoning as the view's projection in scripts/Datalake-mapping.sql.
-- =========================================================================
SELECT storage_account, layer, path COLLATE Latin1_General_100_CS_AS AS path, permission, valid_from, m.prd_id AS identity_id, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.actual_datalake_acls AS b
JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
GROUP BY storage_account, layer, path COLLATE Latin1_General_100_CS_AS, permission, valid_from, m.prd_id
HAVING COUNT(*) > 1;

SELECT dataset_id, permission_type, valid_from, m.prd_id AS identity_id, COUNT(*) AS DuplicateCount
FROM mig_stg_acc.meta_datalake_datasetPermissions AS b
JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
GROUP BY dataset_id, permission_type, valid_from, m.prd_id
HAVING COUNT(*) > 1;
