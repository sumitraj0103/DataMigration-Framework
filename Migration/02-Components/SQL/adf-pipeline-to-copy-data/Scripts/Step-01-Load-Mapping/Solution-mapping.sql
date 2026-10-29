-- Wave 3: Solution Family prep script (mirrors Identity-mapping.sql / Datalake-mapping.sql).
-- See "# Wave 3: Solution Family Migration Plan" in Database-Migration-Execution.md for the full
-- design discussion and Go/No-Go items; this script implements that plan.
--
-- Scope: only `meta_solution.solutionInTechnologies` and `meta_solution.solutionRoles` load to
-- Production. `meta_solution.solutions`, `meta_solution.solutionEnvironments` and `meta_role.roles`
-- are staged here too, but ONLY as bridges to resolve Acc's surrogate ids to Production's - they
-- are NOT registered in mig.TableConfiguration and are never written to Production by this wave
-- (solutions/solutionEnvironments are already populated by a separate, existing CMDB-driven
-- script; roles is static seed data, confirmed identical across dev/tst/prd).
--
-- UPDATE (Open Question #1 resolved, go/no-go): the Acc `role_id` data-quality fix will **not**
-- happen - Acc's `meta_role.roles.id` values are confirmed to permanently differ from
-- dev/tst/prd (prd/dev/tst all agree with each other; only Acc has drifted, e.g. prd
-- "Solution Principal Reader"/"Solution Engineer Reader" = ids 5/6, Acc = ids 6/7 for the same
-- role names). Since this will never be fixed at the source, `role_id` can no longer be copied
-- through unchanged - it now needs the same kind of natural-key bridge used for `solution_id`/
-- `solution_environment_id` below, scoped to Acc only (dev/tst already match prd, so no bridge is
-- needed/used for those environments).
--
-- Mapping needed:
--   - `solutionRoles.group_id` is a surrogate FK into `actual_identity.groups`/`.identities`,
--     resolved via the EXISTING Wave 1 mapping table `mig.actual_identity_identities_mapping` -
--     no new mapping table needed.
--   - `solutionInTechnologies.solution_id`, `solutionRoles.solution_id` and
--     `*.solution_environment_id` are surrogate FKs whose Acc-side ids do NOT match the ids
--     Production already assigned (via the separate solutions/solutionEnvironments load script),
--     so they are resolved live via natural-key bridge views below (no persisted mapping table):
--       * solutions:           bridge key = ci (UNIQUE NOT NULL)
--       * solutionEnvironments: bridge key = (solution_id [resolved], name)
--   - `solutionRoles.role_id` is now ALSO resolved live via a natural-key bridge view (Acc only -
--     see UPDATE above): bridge key = `name` (UNIQUE NOT NULL on `meta_role.roles`). This bridge
--     is only populated/used from `mig_stg_acc` - dev/tst stage straight from their own identical
--     `role_id` values with no bridge required.
--   - `solutionRoles.solution_in_technology_id` is resolved against PRODUCTION's
--     `meta_solution.solutionInTechnologies` (not a staged bridge), via its `name` business key,
--     since solutionInTechnologies loads earlier in this same wave, not pre-existing like
--     solutions/solutionEnvironments.
--   - `*.technology_name` is copied through unchanged: `meta_technology.technologies` has no
--     surrogate id (`name` is its actual PK).
--
-- Load order:
--   (pipeline-level) refresh mig.actual_identity_identities_mapping (pick up any new prd_ids
--     needed for solutionRoles.group_id) - already done by Wave 1/2's refresh step.
--   40: solutionInTechnologies (loads from vw_meta_solution_solutionInTechnologies)
--   50: solutionRoles (loads from vw_meta_solution_solutionRoles; must run after 40 since it
--       resolves solution_in_technology_id against Production's just-loaded solutionInTechnologies)

USE [DMAP]
GO

INSERT INTO [mig].[metadata_loadToStaging]
           ([SchemaName], [TableName], [Env], [Loadtostaging])
     VALUES
           -- bridge-only (never loaded to Production, see header)
           ('meta_solution', 'solutions',               'acc', 1),
           ('meta_solution', 'solutionEnvironments',     'acc', 1),
           ('meta_role',     'roles',                    'acc', 1),
           -- loaded to Production via the vw_* views below
           ('meta_solution', 'solutionInTechnologies',   'acc', 1),
           ('meta_solution', 'solutionRoles',            'acc', 1)
GO

-- =========================================================================
-- BRIDGE VIEWS - resolve Acc's surrogate solutions.id / solutionEnvironments.id to the matching
-- Production id via natural key. Not persisted mapping tables (unlike Wave 1's identity mapping),
-- since solutions/solutionEnvironments are small, mostly-static reference data already loaded to
-- Production by a separate script - a live join is simplest and always current.
-- =========================================================================

-- Solutions bridge: Acc's solutions.id -> Production's solutions.id, via ci (UNIQUE NOT NULL).
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_solution_solutions_bridge
AS
SELECT
    b.id   AS acc_id,
    p.id   AS prd_id
FROM mig_stg_acc.meta_solution_solutions AS b
INNER JOIN meta_solution.solutions AS p
    ON p.ci = b.ci;
GO

-- SolutionEnvironments bridge: Acc's solutionEnvironments.id -> Production's
-- solutionEnvironments.id, via (resolved solution_id, name). Needs confirmation per the Go/No-Go
-- table (could instead be (solution_id, abbreviation)) - update both this view and the sanity
-- check below together if that changes.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge
AS
SELECT
    b.id   AS acc_id,
    p.id   AS prd_id
FROM mig_stg_acc.meta_solution_solutionEnvironments AS b
INNER JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb
    ON sb.acc_id = b.solution_id
INNER JOIN meta_solution.solutionEnvironments AS p
    ON p.solution_id = sb.prd_id
   AND p.name = b.name;
GO

-- Roles bridge (Acc only - see UPDATE note at top of file): Acc's meta_role.roles.id ->
-- Production's meta_role.roles.id, via name (UNIQUE NOT NULL). Replaces the former "pass through
-- unchanged" assumption now that the Acc role_id data-quality fix is confirmed not happening.
-- dev/tst stage their own role_id directly with no bridge - their ids already agree with prd.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_role_roles_bridge
AS
SELECT
    b.id   AS acc_id,
    p.id   AS prd_id
FROM mig_stg_acc.meta_role_roles AS b
INNER JOIN meta_role.roles AS p
    ON p.name = b.name;
GO

-- =========================================================================
-- PRODUCTION-LOAD VIEWS - these are what mig.TableConfiguration points at
-- (sql/validate-and-load/13_solution_family_table_configuration.sql).
-- =========================================================================

-- SolutionInTechnologies: solution_id/solution_environment_id resolved via the bridges above;
-- technology_name and name pass through unchanged. All FKs are NOT NULL on the target table, so
-- INNER JOIN is correct - an unresolved bridge should exclude the row, not load it with a NULL FK.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_solution_solutionInTechnologies
AS
SELECT
    sb.prd_id   AS solution_id,
    b.technology_name,
    seb.prd_id  AS solution_environment_id,
    b.name
FROM mig_stg_acc.meta_solution_solutionInTechnologies AS b
INNER JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb
    ON sb.acc_id = b.solution_id
INNER JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb
    ON seb.acc_id = b.solution_environment_id;
GO

-- SolutionRoles: group_id via the Wave 1 identity mapping; solution_id/solution_environment_id via
-- the bridges above; solution_in_technology_id via Production's (already-loaded-this-wave)
-- solutionInTechnologies, matched on name; role_id via the roles bridge above (Acc only - the
-- data-quality fix isn't happening, see header UPDATE); technology_name passes through unchanged
-- (see header). All FKs are NOT NULL on the target table, so every join below is INNER - an
-- unresolved FK should block the row from loading, not load it with a NULL/wrong value.
CREATE OR ALTER VIEW mig_stg_acc.vw_meta_solution_solutionRoles
AS
SELECT
    b.name,
    gm.prd_id     AS group_id,
    sb.prd_id     AS solution_id,
    rb.prd_id     AS role_id,
    b.technology_name,
    seb.prd_id    AS solution_environment_id,
    sit_prd.id    AS solution_in_technology_id
FROM mig_stg_acc.meta_solution_solutionRoles AS b
INNER JOIN mig.actual_identity_identities_mapping AS gm
    ON gm.acc_id = b.group_id
INNER JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb
    ON sb.acc_id = b.solution_id
INNER JOIN mig_stg_acc.vw_meta_role_roles_bridge AS rb
    ON rb.acc_id = b.role_id
INNER JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb
    ON seb.acc_id = b.solution_environment_id
INNER JOIN mig_stg_acc.meta_solution_solutionInTechnologies AS sit_acc
    ON sit_acc.id = b.solution_in_technology_id
INNER JOIN meta_solution.solutionInTechnologies AS sit_prd
    ON sit_prd.name = sit_acc.name;
GO

-- =========================================================================
-- PRODUCTION LOAD: config-driven, not hand-written.
-- No new persisted mapping table/refresh proc for Wave 3 - mig.usp_RefreshIdentityMapping
-- (Wave 1) already keeps mig.actual_identity_identities_mapping in sync for
-- solutionRoles.group_id, and the role bridge above is a live view, not a persisted table.
-- Register only these 2 tables in mig.TableConfiguration (see
-- sql/validate-and-load/13_solution_family_table_configuration.sql) - solutions/
-- solutionEnvironments/roles stay staged-only (bridge use only, never loaded here).
-- =========================================================================

-- sanity checks before go-live: confirm no duplicate business keys in staging
SELECT name, COUNT(*)
FROM mig_stg_acc.meta_solution_solutionInTechnologies
GROUP BY name
HAVING COUNT(*) > 1;

SELECT group_id, solution_id, role_id, technology_name, solution_environment_id, solution_in_technology_id, COUNT(*)
FROM mig_stg_acc.vw_meta_solution_solutionRoles
GROUP BY group_id, solution_id, role_id, technology_name, solution_environment_id, solution_in_technology_id
HAVING COUNT(*) > 1;

-- confirm every solution_id / solution_environment_id referenced by staging resolves via the
-- bridges (any rows returned are blockers for go-live - either the solution/environment doesn't
-- exist yet in Production, or the bridge key assumption above is wrong)
SELECT DISTINCT b.solution_id
FROM mig_stg_acc.meta_solution_solutionInTechnologies AS b
LEFT JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb ON sb.acc_id = b.solution_id
WHERE sb.prd_id IS NULL;

SELECT DISTINCT b.solution_environment_id
FROM mig_stg_acc.meta_solution_solutionInTechnologies AS b
LEFT JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb ON seb.acc_id = b.solution_environment_id
WHERE seb.prd_id IS NULL;

SELECT DISTINCT b.group_id
FROM mig_stg_acc.meta_solution_solutionRoles AS b
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.acc_id = b.group_id
WHERE m.prd_id IS NULL;

SELECT DISTINCT b.solution_in_technology_id
FROM mig_stg_acc.meta_solution_solutionRoles AS b
INNER JOIN mig_stg_acc.meta_solution_solutionInTechnologies AS sit_acc ON sit_acc.id = b.solution_in_technology_id
LEFT JOIN meta_solution.solutionInTechnologies AS sit_prd ON sit_prd.name = sit_acc.name
WHERE sit_prd.id IS NULL;

-- Open Question #1 (RESOLVED - fix will not happen): role_id is no longer copied through
-- unchanged, it is resolved via mig_stg_acc.vw_meta_role_roles_bridge (name match). Any rows
-- returned below are a true go-live blocker for solutionRoles - they mean the Acc role name has
-- no matching row in Production's meta_role.roles at all (not just a differing id, which the
-- bridge already handles transparently).
SELECT DISTINCT b.role_id AS acc_role_id, r_acc.name AS role_name
FROM mig_stg_acc.meta_solution_solutionRoles AS b
LEFT JOIN mig_stg_acc.meta_role_roles AS r_acc ON r_acc.id = b.role_id
LEFT JOIN mig_stg_acc.vw_meta_role_roles_bridge AS rb ON rb.acc_id = b.role_id
WHERE rb.prd_id IS NULL;
