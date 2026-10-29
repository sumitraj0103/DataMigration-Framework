-- Registers Wave 2.1 (Database-Migration-Execution.md, "Wave 2.1: Folder Mapping
-- Environment-Aware Migration Plan") in mig.TableConfiguration so PL_ValidateAndLoadAllToProduction
-- loads meta_datalake.folderMapping from ALL THREE lower environments (Dev/Tst/Acc), not just Acc.
-- Carved out of Wave 2 (sql/validate-and-load/12_datalake_family_table_configuration.sql) because
-- folderMapping now needs an Environment column + a multi-source load, unlike the rest of that
-- family. meta_datalake.rawFolderMappingListOfValues is NOT part of this wave - it stays exactly as
-- configured by 12_datalake_family_table_configuration.sql (Acc-only, SKIP_EXISTING, no Environment
-- column).
--
-- Each source reads straight from mig_stg_<env>.meta_datalake_folderMapping - no view needed. The
-- Environment column/schema-change prerequisite (item 1 below) is applied to every environment's
-- own meta_datalake.folderMapping (Dev/Tst/Acc/Prd), so each source table already carries a real,
-- populated Environment value that flows through to staging automatically (scripts/FolderMapping-mapping.sql).
-- This is the same "one TableConfiguration row per env, all at the same LoadOrder" pattern already
-- used by Wave 1's identity family (sql/validate-and-load/10_identity_family_table_configuration.sql).
-- No mapping table / identity refresh dependency: folderMapping has no identity-surrogate FK, only
-- natural keys.
-- BusinessKeyColumns now includes Environment (6 columns, was 5) so the same mapping rule can
-- exist once per environment without SKIP_EXISTING treating the 2nd/3rd environment's row as a
-- duplicate of the 1st. IdentityInsertMode stays AUTO: id is a surrogate not referenced elsewhere
-- as an unchanged FK, so Production should assign its own new id on insert.
-- LoadOrder = 10: no FK dependency on anything else in this or any other wave.
--
-- Scope reminder (Database-Migration-Execution.md, Wave 2.1): the Environment column itself is a
-- separate, out-of-scope schema-change prerequisite - this script only registers the load
-- (mig.TableConfiguration rows). It never creates or alters the column.
-- The Acc row below reuses the exact (SourceSchema, SourceTable, TargetSchema, TargetTable) tuple
-- Wave 2 originally registered for folderMapping, so the MERGE updates that row in place (picking
-- up the new 6-column BusinessKeyColumns) and reactivates it (IsActive = 1) rather than needing a
-- separate deactivate-the-old-row step. Dev/Tst are brand new rows, inserted with IsActive = 0
-- pending explicit go-live activation, per the existing convention for new family registrations.

-- =========================================================================
-- PREREQUISITE GUARD: refuse to register the load if meta_datalake.folderMapping doesn't already
-- have the Environment column in Production (see scripts/FolderMapping-mapping.sql for the same
-- check). SET NOEXEC ON skips every later batch in this file regardless of client
-- (SSMS/sqlcmd/Invoke-Sqlcmd); NOEXEC OFF at the bottom resets the session once the guard passes.
-- =========================================================================
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('meta_datalake.folderMapping') AND name = 'Environment'
)
BEGIN
    RAISERROR('Prerequisite missing: meta_datalake.folderMapping has no Environment column in Production. Apply the separate schema-change (ADD Environment VARCHAR(10) NOT NULL, backfill existing rows to ''prd'') before registering this TableConfiguration. See Database-Migration-Execution.md, Wave 2.1, item 1.', 16, 1);
    SET NOEXEC ON;
END
GO

-- One-time cleanup note: Wave 2's original single-source (Acc-only, no Environment) config for
-- folderMapping used this exact (SourceSchema, SourceTable, TargetSchema, TargetTable) tuple, so
-- no separate deactivate step is needed here - the MERGE below matches that row directly and
-- updates it in place (new BusinessKeyColumns/LoadOrder, IsActive = 1).
MERGE mig.TableConfiguration AS t
USING (VALUES
    ('mig_stg_dev', 'meta_datalake_folderMapping', 'meta_datalake', 'folderMapping', 'source_system,source_container,source_folder,file_name,target_folder,Environment', 'SKIP_EXISTING', 10, 'AUTO'),
    ('mig_stg_tst', 'meta_datalake_folderMapping', 'meta_datalake', 'folderMapping', 'source_system,source_container,source_folder,file_name,target_folder,Environment', 'SKIP_EXISTING', 10, 'AUTO'),
    ('mig_stg_acc', 'meta_datalake_folderMapping', 'meta_datalake', 'folderMapping', 'source_system,source_container,source_folder,file_name,target_folder,Environment', 'SKIP_EXISTING', 10, 'AUTO')
) AS s (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, LoadOrder, IdentityInsertMode)
ON t.SourceSchema = s.SourceSchema AND t.SourceTable = s.SourceTable
   AND t.TargetSchema = s.TargetSchema AND t.TargetTable = s.TargetTable
WHEN MATCHED THEN
    UPDATE SET BusinessKeyColumns = s.BusinessKeyColumns, LoadStrategy = s.LoadStrategy,
               LoadOrder = s.LoadOrder, IdentityInsertMode = s.IdentityInsertMode,
               IsActive = 1, ModifiedDate = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, LoadOrder, IdentityInsertMode, ValidationRequired, IsActive)
    VALUES (s.SourceSchema, s.SourceTable, s.TargetSchema, s.TargetTable, s.BusinessKeyColumns, s.LoadStrategy, s.LoadOrder, s.IdentityInsertMode, 1, 0);
GO

-- Reset session state in case the prerequisite guard above tripped NOEXEC ON for this run.
SET NOEXEC OFF;
GO
