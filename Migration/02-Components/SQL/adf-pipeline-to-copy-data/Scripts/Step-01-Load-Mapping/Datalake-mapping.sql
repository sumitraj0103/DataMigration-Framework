-- Wave 2: Data Lake Family prep script (mirrors Identity-mapping.sql for Wave 1).
--
-- Mapping needed: `acls.identity_id`, `datasets.owner_1/2/3_user_id` and
-- `datasetPermissions.identity_id` are all surrogate FKs into `actual_identity.identities`
-- (user.id is itself PK+FK to identities.id), so they are resolved using the EXISTING Wave 1
-- mapping table `mig.actual_identity_identities_mapping` - no new mapping table is needed here.
-- `datasetPermissions.dataset_id` is a natural/business key (VARCHAR id defined on `datasets`,
-- not an IDENTITY column), so it is copied through unchanged - no mapping required for it.
--
-- Load order:
--   10: datasetSizes, rawFolderMappingListOfValues (no FK remap needed)
--   (phase boundary): refresh mig.actual_identity_identities_mapping (pick up any new prd_ids)
--   20: datasets (loads from vw_actual_datalake_datasets to resolve owner_*_user_id via the
--       mapping; must run after the refresh above, and before acls/datasetPermissions since
--       datasetPermissions.dataset_id references datasets.id)
--   30: acls, datasetPermissions (resolve identity_id / owner_*_user_id via the mapping)
--
-- folderMapping moved to Wave 2.1 (needs an Environment column + Dev/Tst/Acc load) - see
-- scripts/FolderMapping-mapping.sql and
-- sql/validate-and-load/15_folderMapping_environment_table_configuration.sql. The 'acc'
-- metadata_loadToStaging row registered below is still correct/reused by Wave 2.1.

USE [DMAP]
GO

-- One-time fix: mig_stg_acc.actual_datalake_datasetSizes.path was created by PL_LoadSourceToStaging
-- (Use Case 1.0) without preserving Production's explicit COLLATE SQL_Latin1_General_CP1_CS_AS on
-- this column (actual_datalake.datasetSizes.path - case-sensitive by design, since real paths like
-- `CEAR/gold` and `CEAR/GOLD` are genuinely distinct folders, not duplicates). The staging table
-- instead defaulted to the database's own collation (SQL_Latin1_General_CP1_CI_AS, case-insensitive),
-- which both (a) made the duplicate-check script report false-positive "duplicates" for path values
-- differing only by case, and (b) would make mig.usp_LoadValidatedTableToProduction's generated
-- comparison on `path` fail at runtime with "Cannot resolve the collation conflict between
-- SQL_Latin1_General_CP1_CI_AS and SQL_Latin1_General_CP1_CS_AS in the equal to operation (468)".
-- PL_LoadSourceToStaging's GetSourceColumnDefs_Dev/_Test/_Acc activities have been patched to
-- capture COLLATION_NAME going forward (adf/pipelines/PL_LoadSourceToStaging.json), so this only
-- needs to run once against the table that already exists.
ALTER TABLE mig_stg_acc.actual_datalake_datasetSizes
ALTER COLUMN path VARCHAR(255) COLLATE SQL_Latin1_General_CP1_CS_AS NOT NULL;
GO

INSERT INTO [mig].[metadata_loadToStaging]
           ([SchemaName], [TableName], [Env], [Loadtostaging])
     VALUES
           ('actual_datalake', 'acls',                          'acc', 1),
           ('actual_datalake', 'datasets',                       'acc', 1),
           ('actual_datalake', 'datasetSizes',                   'acc', 1),
           ('meta_datalake',   'datasetPermissions',             'acc', 1),
           ('meta_datalake',   'folderMapping',                  'acc', 1),
           ('meta_datalake',   'rawFolderMappingListOfValues',   'acc', 1)
GO

-- =========================================================================
-- VIEWS - only the tables carrying an identity-surrogate FK need a vw_* view;
-- the rest load straight from the staging table since their business keys are
-- natural keys (no id remap required).
-- =========================================================================

-- Datasets: id is the dataset's own business key (not an IDENTITY), owners are identity surrogate
-- ids and must be resolved via the existing identity mapping table (NULL-safe: owners are optional).
-- path is projected with an explicit case-sensitive COLLATE (no schema/column change on either
-- Acc or Production needed): Production's actual_datalake.datasets.path uses the database's
-- default (case-insensitive) collation, which falsely treats e.g. 'CEAR/gold' and 'CEAR/GOLD' as
-- the same business key even though both already exist in Production as distinct, legitimate rows
-- (see Database-Migration-Execution.md, Wave 2, item 4). An explicit COLLATE clause has higher
-- precedence than a plain column's implicit collation, so every downstream comparison against this
-- view's path (the generic engine's business-key match/duplicate-check GROUP BY, and this family's
-- own check_datalake_family_duplicates.sql / preview_datalake_family_load.sql) becomes
-- case-sensitive automatically - Production's path column itself is read, not altered.
CREATE OR ALTER VIEW mig_stg_acc.vw_actual_datalake_datasets
AS
SELECT
    b.id,
    b.storage_account,
    b.layer,
    b.path COLLATE Latin1_General_100_CS_AS AS path,
    m1.prd_id AS owner_1_user_id,
    m2.prd_id AS owner_2_user_id,
    m3.prd_id AS owner_3_user_id,
    b.active
FROM mig_stg_acc.actual_datalake_datasets AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m1 ON m1.acc_id = b.owner_1_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS m2 ON m2.acc_id = b.owner_2_user_id
LEFT JOIN mig.actual_identity_identities_mapping AS m3 ON m3.acc_id = b.owner_3_user_id;
GO

-- Acls: id is an IDENTITY surrogate but is not referenced elsewhere as a FK, so it is not
-- part of the business key and does not need remapping - only identity_id does. path gets the
-- same explicit case-sensitive COLLATE as datasets above, as a precaution against the same
-- case-only "duplicate" risk (not yet confirmed to actually occur here, but the column/data comes
-- from the same source).
CREATE OR ALTER VIEW mig_stg_acc.vw_actual_datalake_acls
AS
SELECT
    b.storage_account,
    b.layer,
    b.path COLLATE Latin1_General_100_CS_AS AS path,
    m.prd_id AS identity_id,
    b.permission,
    b.recursive,
    b.valid_from,
    b.valid_to
FROM mig_stg_acc.actual_datalake_acls AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.acc_id = b.identity_id;
GO

-- DatasetPermissions: dataset_id passes through unchanged (natural key on datasets),
-- identity_id is resolved via the identity mapping table.
CREATE VIEW mig_stg_acc.vw_meta_datalake_datasetPermissions
AS
SELECT
    b.dataset_id,
    m.prd_id AS identity_id,
    b.permission_type,
    b.valid_from,
    b.valid_to
FROM mig_stg_acc.meta_datalake_datasetPermissions AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.acc_id = b.identity_id;
GO

-- =========================================================================
-- PRODUCTION LOAD: config-driven, not hand-written.
-- No new mapping table/refresh proc for Wave 2 - mig.usp_RefreshIdentityMapping (Wave 1) already
-- keeps mig.actual_identity_identities_mapping in sync and must run before LoadOrder=30 so the
-- vw_actual_datalake_acls / vw_meta_datalake_datasetPermissions views can resolve identity_id.
-- Register these 6 tables in mig.TableConfiguration (see 12_datalake_family_table_configuration.sql).
-- =========================================================================

-- sanity checks before go-live: confirm no duplicate business keys in staging
SELECT storage_account, layer, path, identity_id, permission, valid_from, COUNT(*)
FROM mig_stg_acc.actual_datalake_acls
GROUP BY storage_account, layer, path, identity_id, permission, valid_from
HAVING COUNT(*) > 1;

SELECT dataset_id, identity_id, permission_type, valid_from, COUNT(*)
FROM mig_stg_acc.meta_datalake_datasetPermissions
GROUP BY dataset_id, identity_id, permission_type, valid_from
HAVING COUNT(*) > 1;

-- confirm every identity_id / owner_*_user_id referenced by staging has a mapping row
-- (run after mig.usp_RefreshIdentityMapping; any rows returned are blockers for go-live)
SELECT DISTINCT b.identity_id
FROM mig_stg_acc.actual_datalake_acls AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
WHERE m.acc_id IS NULL;

SELECT DISTINCT b.identity_id
FROM mig_stg_acc.meta_datalake_datasetPermissions AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.identity_id
WHERE m.acc_id IS NULL;
