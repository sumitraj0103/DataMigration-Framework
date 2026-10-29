-- Registers the solution family (Wave 3) in mig.TableConfiguration so PL_ValidateAndLoadAllToProduction
-- loads them, in FK order, via the generic mig.usp_LoadValidatedTableToProduction engine.
-- Only solutionInTechnologies and solutionRoles are registered here - solutions/solutionEnvironments/
-- roles are staged (scripts/Solution-mapping.sql) purely as bridges/sanity-check sources and are
-- never loaded to Production by this wave (see "# Wave 3: Solution Family Migration Plan" in
-- Database-Migration-Execution.md for the full rationale).
--
-- Both tables load from the mig_stg_acc.vw_* views (scripts/Solution-mapping.sql), which resolve
-- group_id (Wave 1 identity mapping), solution_id/solution_environment_id (natural-key bridges)
-- and solution_in_technology_id (Production name lookup) - technology_name passes through
-- unchanged (confirmed identical across environments). role_id is resolved via an Acc-only
-- natural-key bridge (mig_stg_acc.vw_meta_role_roles_bridge, matched on name): Open Question #1's
-- Acc role_id data-quality fix was confirmed to NOT be happening, so this bridge is now permanent
-- (dev/tst role_id already matches prd, so no bridge is used/needed for those environments).
--
-- IdentityInsertMode = 'AUTO' for both: nothing references solutionRoles.id as an unchanged FK,
-- and solutionInTechnologies.id is resolved by solutionRoles via its `name` lookup against
-- Production (not by copying the staging id), so Production should generate both ids fresh - same
-- reasoning as Wave 2's folderMapping/acls.
--
-- LoadOrder = 40 / 50 (new values, after Wave 1/2's 10/20/30): solutionInTechnologies (40) must
-- load strictly before solutionRoles (50), since solutionRoles.solution_in_technology_id is
-- resolved against Production's already-loaded solutionInTechnologies row by name. Both fall in
-- PL_ValidateAndLoadAllToProduction's existing LoadOrder > 10 phase (after the identity mapping
-- refresh needed for group_id); no new refresh step is required.
--
-- LoadStrategy = 'INSERT_IF_NOT_EXISTS' - CONFIRMED (Go/No-Go "Load Strategy" row resolved), not
-- 'UPSERT': these rows control group access/permissions in Production, so an already-existing
-- business-key row whose other values differ from staging must fail validation
-- (BUSINESS_KEY_VALUE_MISMATCH) rather than be silently overwritten. A matching row whose values
-- already agree is a no-op either way; only a genuinely new business key gets inserted.
--
-- IsActive = 0 on first insert AND on every re-run of this script (WHEN MATCHED also forces 0,
-- mirroring 12_datalake_family_table_configuration.sql's Wave 2 pattern): several Go/No-Go items
-- are still open (the solutionEnvironments bridge key: name vs abbreviation; staging scope;
-- business keys; load order), so re-running this registration script must not silently activate
-- the family. The Acc role_id data-quality item (Open Question #1) is RESOLVED - the fix will not
-- happen, and is now handled permanently by mig_stg_acc.vw_meta_role_roles_bridge, so it's no
-- longer a go-live blocker on its own; the item-7 sanity check in Solution-mapping.sql now only
-- flags Acc role names with no Production match at all (a genuine blocker), not id drift (which
-- the bridge resolves transparently). Once every remaining Go/No-Go item is resolved, run the
-- commented-out activation statement at the bottom of this file to flip both rows to IsActive = 1
-- in one step, rather than relying on this MERGE to do it implicitly.

MERGE mig.TableConfiguration AS t
USING (VALUES
    ('mig_stg_acc', 'vw_meta_solution_solutionInTechnologies', 'meta_solution', 'solutionInTechnologies', 'name', 'INSERT_IF_NOT_EXISTS', 40, 'AUTO'),
    ('mig_stg_acc', 'vw_meta_solution_solutionRoles',          'meta_solution', 'solutionRoles',          'group_id,solution_id,role_id,technology_name,solution_environment_id,solution_in_technology_id', 'INSERT_IF_NOT_EXISTS', 50, 'AUTO')
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
-- ACTIVATION (DO NOT RUN YET) - once the team confirms every remaining Go/No-Go item above (the
-- solutionEnvironments bridge key, staging scope, business keys, load order), run this to go live
-- with both Wave 3 rows registered above. Left commented out deliberately so re-running this whole
-- file never accidentally activates the family before those items clear.
-- =========================================================================
-- UPDATE mig.TableConfiguration
-- SET IsActive = 1, ModifiedDate = SYSUTCDATETIME()
-- WHERE (SourceSchema, SourceTable, TargetSchema, TargetTable) IN (
--     ('mig_stg_acc', 'vw_meta_solution_solutionInTechnologies', 'meta_solution', 'solutionInTechnologies'),
--     ('mig_stg_acc', 'vw_meta_solution_solutionRoles',          'meta_solution', 'solutionRoles')
-- );
-- GO
