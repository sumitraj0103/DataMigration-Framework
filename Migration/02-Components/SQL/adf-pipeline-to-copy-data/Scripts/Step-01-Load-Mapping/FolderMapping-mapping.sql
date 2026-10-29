-- Wave 2.1: Folder Mapping Environment-Aware Migration Plan (prep script).
--
-- Scope: meta_datalake.folderMapping ONLY. rawFolderMappingListOfValues is NOT touched here -
-- it keeps loading per Wave 2 (Datalake-mapping.sql / 12_datalake_family_table_configuration.sql),
-- Acc-only, no Environment column.
--
-- No mapping table/view is needed: folderMapping's business key is natural
-- (source_system/source_container/source_folder/file_name/target_folder), not a surrogate FK into
-- actual_identity.identities, so (unlike acls/datasets/datasetPermissions in Wave 2) there is
-- nothing here to resolve via mig.actual_identity_identities_mapping or
-- mig.usp_RefreshIdentityMapping. Nor is an Environment-tagging view needed any more: the
-- Environment column/schema-change prerequisite (Database-Migration-Execution.md, Wave 2.1, item 1)
-- is applied to EVERY environment's own meta_datalake.folderMapping (Dev/Tst/Acc/Prd), not just
-- Production, so each lower environment's table already carries a real, populated Environment
-- value. PL_LoadSourceToStaging builds/refreshes each mig_stg_<env>.meta_datalake_folderMapping
-- staging table's columns straight from that live source table on every run, so the Environment
-- column (and its value) flows through to staging automatically - there is nothing left to inject
-- via a view. mig.TableConfiguration therefore reads straight from the raw staging tables (same
-- "natural key, no mapping" pattern as datasetSizes/rawFolderMappingListOfValues).
--
-- Load order: LoadOrder = 10 for all 3 (Dev/Tst/Acc) rows - see
-- sql/validate-and-load/15_folderMapping_environment_table_configuration.sql.

USE [DMAP]
GO

-- =========================================================================
-- PREREQUISITE GUARD: per Database-Migration-Execution.md ("Wave 2.1: Folder Mapping
-- Environment-Aware Migration Plan" - Scope: load only), adding the Environment column to
-- meta_datalake.folderMapping (and backfilling pre-existing Production rows to 'prd') is a
-- SEPARATE schema-change activity, owned outside this load-setup script. This script only ever
-- registers the load (metadata_loadToStaging rows) - it never creates or alters the column.
-- Checking Production's copy of the column is used here as the representative "all clear" signal
-- for the whole Dev/Tst/Acc/Prd rollout, since Production is the last environment to receive the
-- change in the agreed rollout order. If the column isn't there yet, stop here rather than
-- registering a load that would fail (or silently load an incomplete business key) once it runs.
-- SET NOEXEC ON causes every later batch in this file to be skipped (not just this one),
-- regardless of which client (SSMS/sqlcmd/Invoke-Sqlcmd) runs it; NOEXEC OFF at the bottom of
-- this file resets the session once the guard has passed.
-- =========================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('meta_datalake.folderMapping') AND name = 'Environment'
)
BEGIN
    RAISERROR('Prerequisite missing: meta_datalake.folderMapping has no Environment column in Production. Apply the separate schema-change (ADD Environment VARCHAR(10) NOT NULL, backfill existing rows to ''prd'') across Dev/Tst/Acc/Prd before running this load-setup script. See Database-Migration-Execution.md, Wave 2.1, item 1.', 16, 1);
    SET NOEXEC ON;
END
GO

-- Acc was already registered by Wave 2's Datalake-mapping.sql
-- (SchemaName='meta_datalake', TableName='folderMapping', Env='acc'); only Dev/Tst are new here.
INSERT INTO [mig].[metadata_loadToStaging]
           ([SchemaName], [TableName], [Env], [Loadtostaging])
     VALUES
           ('meta_datalake', 'folderMapping', 'dev', 1),
           ('meta_datalake', 'folderMapping', 'tst', 1)
GO

-- =========================================================================
-- PRODUCTION LOAD: config-driven, not hand-written.
-- Register these 3 rows in mig.TableConfiguration (see
-- sql/validate-and-load/15_folderMapping_environment_table_configuration.sql), pointing straight
-- at mig_stg_dev/tst/acc.meta_datalake_folderMapping - no views to create or maintain here.
-- =========================================================================

-- sanity check before go-live: confirm no duplicate business keys WITHIN a single environment
-- (across environments, duplicates are expected and fine now that Environment distinguishes them)
-- Run this AFTER at least one Load-to-Staging pass has populated each mig_stg_<env> table.
SELECT source_system, source_container, source_folder, file_name, target_folder, Environment, COUNT(*)
FROM mig_stg_dev.meta_datalake_folderMapping
GROUP BY source_system, source_container, source_folder, file_name, target_folder, Environment
HAVING COUNT(*) > 1;

SELECT source_system, source_container, source_folder, file_name, target_folder, Environment, COUNT(*)
FROM mig_stg_tst.meta_datalake_folderMapping
GROUP BY source_system, source_container, source_folder, file_name, target_folder, Environment
HAVING COUNT(*) > 1;

SELECT source_system, source_container, source_folder, file_name, target_folder, Environment, COUNT(*)
FROM mig_stg_acc.meta_datalake_folderMapping
GROUP BY source_system, source_container, source_folder, file_name, target_folder, Environment
HAVING COUNT(*) > 1;

-- confirm existing Production rows backfilled correctly after the Environment column is added
-- (expect 0 rows - every pre-existing row should show 'prd', nothing else)
SELECT Environment, COUNT(*) AS RowCount
FROM meta_datalake.folderMapping
GROUP BY Environment;
GO

-- Reset session state in case the prerequisite guard above tripped NOEXEC ON for this run.
SET NOEXEC OFF;
GO
