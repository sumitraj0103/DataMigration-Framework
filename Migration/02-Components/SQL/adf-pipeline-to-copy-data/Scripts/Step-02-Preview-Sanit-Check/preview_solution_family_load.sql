-- Read-only dry run: shows exactly what the solution family (Wave 3) mig.TableConfiguration rows
-- would insert/update into Production, without writing anything.
-- Safe to run anytime; no INSERT/UPDATE statements in this file.
-- Run after mig.usp_RefreshIdentityMapping so group_id resolves correctly. role_id now resolves
-- via mig_stg_acc.vw_meta_role_roles_bridge (Acc only, see item 7 below) - the data-quality fix
-- (Open Question #1) was confirmed to not be happening, so the bridge replaces it permanently.

-- =========================================================================
-- 1) SolutionInTechnologies that can't resolve solution_id / solution_environment_id yet
--    (blocked - the Acc row's solution/environment hasn't loaded to Production, or the bridge's
--    natural-key assumption doesn't hold for this row)
-- =========================================================================
SELECT
    b.id, b.name,
    b.solution_id AS acc_solution_id, sb.prd_id AS solution_id_resolved,
    b.solution_environment_id AS acc_solution_environment_id, seb.prd_id AS solution_environment_id_resolved
FROM mig_stg_acc.meta_solution_solutionInTechnologies AS b
LEFT JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb ON sb.acc_id = b.solution_id
LEFT JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb ON seb.acc_id = b.solution_environment_id
WHERE sb.prd_id IS NULL OR seb.prd_id IS NULL;

-- =========================================================================
-- 2) SolutionInTechnologies - INSERT_IF_NOT_EXISTS (CONFIRMED), business key = name
--    A matched name whose other values differ from staging now FAILS VALIDATION
--    (BUSINESS_KEY_VALUE_MISMATCH) instead of being updated.
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM meta_solution.solutionInTechnologies AS p WHERE p.name = v.name) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM meta_solution.solutionInTechnologies AS p
            WHERE p.name = v.name
              AND (p.solution_id <> v.solution_id
                OR  p.technology_name <> v.technology_name
                OR  p.solution_environment_id <> v.solution_environment_id)
        ) THEN 'WILL FAIL VALIDATION - BUSINESS_KEY_VALUE_MISMATCH (name exists, other values differ)'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_meta_solution_solutionInTechnologies AS v
ORDER BY LoadStatus, v.name;

-- =========================================================================
-- 3) SolutionRoles that can't resolve group_id / solution_id / solution_environment_id /
--    solution_in_technology_id / role_id yet (blocked - see each LEFT JOIN below for which FK is
--    missing). role_id now resolves via the Acc-only roles bridge (name match) instead of passing
--    through unchanged.
-- =========================================================================
SELECT
    b.id, b.name,
    b.group_id AS acc_group_id, gm.prd_id AS group_id_resolved,
    b.solution_id AS acc_solution_id, sb.prd_id AS solution_id_resolved,
    b.solution_environment_id AS acc_solution_environment_id, seb.prd_id AS solution_environment_id_resolved,
    b.solution_in_technology_id AS acc_solution_in_technology_id, sit_prd.id AS solution_in_technology_id_resolved,
    b.role_id AS acc_role_id, rb.prd_id AS role_id_resolved
FROM mig_stg_acc.meta_solution_solutionRoles AS b
LEFT JOIN mig.actual_identity_identities_mapping AS gm ON gm.acc_id = b.group_id
LEFT JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb ON sb.acc_id = b.solution_id
LEFT JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb ON seb.acc_id = b.solution_environment_id
LEFT JOIN mig_stg_acc.meta_solution_solutionInTechnologies AS sit_acc ON sit_acc.id = b.solution_in_technology_id
LEFT JOIN meta_solution.solutionInTechnologies AS sit_prd ON sit_prd.name = sit_acc.name
LEFT JOIN mig_stg_acc.vw_meta_role_roles_bridge AS rb ON rb.acc_id = b.role_id
WHERE gm.prd_id IS NULL OR sb.prd_id IS NULL OR seb.prd_id IS NULL OR sit_prd.id IS NULL OR rb.prd_id IS NULL;

-- =========================================================================
-- 4) SolutionRoles - INSERT_IF_NOT_EXISTS (CONFIRMED), business key = the full resolved-FK
--    combination: group_id,solution_id,role_id,technology_name,solution_environment_id,
--    solution_in_technology_id. A matched combination whose `name` differs from staging now FAILS
--    VALIDATION (BUSINESS_KEY_VALUE_MISMATCH) instead of being updated.
-- =========================================================================
SELECT
    v.*,
    CASE
        WHEN NOT EXISTS (
            SELECT 1 FROM meta_solution.solutionRoles AS p
            WHERE p.group_id = v.group_id AND p.solution_id = v.solution_id AND p.role_id = v.role_id
              AND p.technology_name = v.technology_name AND p.solution_environment_id = v.solution_environment_id
              AND p.solution_in_technology_id = v.solution_in_technology_id
        ) THEN 'WILL BE INSERTED'
        WHEN EXISTS (
            SELECT 1 FROM meta_solution.solutionRoles AS p
            WHERE p.group_id = v.group_id AND p.solution_id = v.solution_id AND p.role_id = v.role_id
              AND p.technology_name = v.technology_name AND p.solution_environment_id = v.solution_environment_id
              AND p.solution_in_technology_id = v.solution_in_technology_id
              AND p.name <> v.name
        ) THEN 'WILL FAIL VALIDATION - BUSINESS_KEY_VALUE_MISMATCH (key exists, name differs)'
        ELSE 'ALREADY IN SYNC - no-op'
    END AS LoadStatus
FROM mig_stg_acc.vw_meta_solution_solutionRoles AS v
ORDER BY LoadStatus, v.name;

-- =========================================================================
-- 5) Row-count summary of all of the above, for a quick before-you-run check
-- =========================================================================
SELECT 'solutionInTechnologies_blocked_unresolved_fk', COUNT(*) FROM mig_stg_acc.meta_solution_solutionInTechnologies AS b
    LEFT JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb ON sb.acc_id = b.solution_id
    LEFT JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb ON seb.acc_id = b.solution_environment_id
    WHERE sb.prd_id IS NULL OR seb.prd_id IS NULL
UNION ALL
SELECT 'solutionInTechnologies_insert', COUNT(*) FROM mig_stg_acc.vw_meta_solution_solutionInTechnologies AS v
    WHERE NOT EXISTS (SELECT 1 FROM meta_solution.solutionInTechnologies AS p WHERE p.name = v.name)
UNION ALL
SELECT 'solutionRoles_blocked_unresolved_fk', COUNT(*) FROM mig_stg_acc.meta_solution_solutionRoles AS b
    LEFT JOIN mig.actual_identity_identities_mapping AS gm ON gm.acc_id = b.group_id
    LEFT JOIN mig_stg_acc.vw_meta_solution_solutions_bridge AS sb ON sb.acc_id = b.solution_id
    LEFT JOIN mig_stg_acc.vw_meta_solution_solutionEnvironments_bridge AS seb ON seb.acc_id = b.solution_environment_id
    LEFT JOIN mig_stg_acc.meta_solution_solutionInTechnologies AS sit_acc ON sit_acc.id = b.solution_in_technology_id
    LEFT JOIN meta_solution.solutionInTechnologies AS sit_prd ON sit_prd.name = sit_acc.name
    LEFT JOIN mig_stg_acc.vw_meta_role_roles_bridge AS rb ON rb.acc_id = b.role_id
    WHERE gm.prd_id IS NULL OR sb.prd_id IS NULL OR seb.prd_id IS NULL OR sit_prd.id IS NULL OR rb.prd_id IS NULL
UNION ALL
SELECT 'solutionRoles_insert', COUNT(*) FROM mig_stg_acc.vw_meta_solution_solutionRoles AS v
    WHERE NOT EXISTS (
        SELECT 1 FROM meta_solution.solutionRoles AS p
        WHERE p.group_id = v.group_id AND p.solution_id = v.solution_id AND p.role_id = v.role_id
          AND p.technology_name = v.technology_name AND p.solution_environment_id = v.solution_environment_id
          AND p.solution_in_technology_id = v.solution_in_technology_id)
UNION ALL
-- 6) Open Question #1 (RESOLVED - fix will not happen): count of Acc role_id rows with NO
--    matching role name in Production at all (a true blocker). Rows where only the id differs are
--    no longer a blocker - they're transparently resolved by mig_stg_acc.vw_meta_role_roles_bridge.
SELECT 'solutionRoles_role_id_unmapped_blockers', COUNT(DISTINCT b.role_id)
FROM mig_stg_acc.meta_solution_solutionRoles AS b
LEFT JOIN mig_stg_acc.vw_meta_role_roles_bridge AS rb ON rb.acc_id = b.role_id
WHERE rb.prd_id IS NULL;
