-- Read-only dry run: shows exactly what mig.usp_RefreshIdentityMapping + the identity-family
-- mig.TableConfiguration rows would insert into Production, without writing anything.
-- Safe to run anytime; no INSERT/UPDATE statements in this file.

-- =========================================================================
-- 1) Identities that would be newly created in actual_identity.identities
--    (entra_id exists in acc staging, but has no prd_id yet in the mapping table)
-- =========================================================================
SELECT
    s.id          AS acc_id,
    s.entra_id,
    s.name,
    s.type,
    s.active
FROM mig_stg_acc.actual_identity_identities AS s
LEFT JOIN mig.actual_identity_identities_mapping AS m
    ON m.entra_id = s.entra_id
WHERE m.prd_id IS NULL;

-- =========================================================================
-- 2) Entra ids in acc staging that have no mapping row at all yet
--    (these get a mapping row inserted by the pipeline's validate-and-load step, not by usp_RefreshIdentityMapping)
-- =========================================================================
SELECT
    s.id AS acc_id,
    s.entra_id
FROM mig_stg_acc.actual_identity_identities AS s
WHERE NOT EXISTS (
    SELECT 1 FROM mig.actual_identity_identities_mapping m WHERE m.entra_id = s.entra_id
);

-- =========================================================================
-- 3) Users that would be inserted into actual_identity.[user]
--    (SKIP_EXISTING via vw_actual_identity_users: only rows whose resolved id
--    is not already in production; identities step above must run first for new ones)
-- =========================================================================
SELECT v.*
FROM mig_stg_acc.vw_actual_identity_users AS v
WHERE NOT EXISTS (
    SELECT 1 FROM actual_identity.[user] AS p WHERE p.id = v.id
);

-- =========================================================================
-- 3b) Readable version of 3), with entra_id/name and a status column
--     (prd_id NULL = identity not created in Prod yet, so this user can't load until a
--     rerun of usp_RefreshIdentityMapping after the identities step picks up the new prd_id)
-- =========================================================================
SELECT
    b.id          AS acc_id,
    si.entra_id,
    si.name,
    b.email,
    b.upn,
    m.prd_id,
    CASE
        WHEN m.prd_id IS NULL THEN 'BLOCKED - identity not created in Prod yet'
        WHEN EXISTS (SELECT 1 FROM actual_identity.[user] AS p WHERE p.id = m.prd_id) THEN 'ALREADY EXISTS - will be skipped'
        ELSE 'WILL BE INSERTED'
    END AS LoadStatus
FROM mig_stg_acc.actual_identity_users AS b
JOIN mig_stg_acc.actual_identity_identities AS si
    ON si.id = b.id
LEFT JOIN mig.actual_identity_identities_mapping AS m
    ON m.acc_id = b.id
ORDER BY LoadStatus, si.entra_id;

-- =========================================================================
-- 4) Groups that would be inserted into actual_identity.groups
-- =========================================================================
SELECT v.*
FROM mig_stg_acc.vw_actual_identity_groups AS v
WHERE NOT EXISTS (
    SELECT 1 FROM actual_identity.groups AS p WHERE p.id = v.id
);

-- =========================================================================
-- 5) ServicePrincipals that would be inserted into actual_identity.serviceprincipal
-- =========================================================================
SELECT v.*
FROM mig_stg_acc.vw_actual_identity_servicePrincipal AS v
WHERE NOT EXISTS (
    SELECT 1 FROM actual_identity.servicePrincipals AS p WHERE p.id = v.id
);

-- =========================================================================
-- 6) IdentitiesInGroups memberships that would be inserted
-- =========================================================================
SELECT v.*
FROM mig_stg_acc.vw_actual_identity_identitiesInGroups AS v
WHERE NOT EXISTS (
    SELECT 1 FROM actual_identity.identitiesInGroups AS p
    WHERE p.member_id = v.member_id AND p.group_id = v.group_id
);

-- =========================================================================
-- 7) Row-count summary of all of the above, for a quick before-you-run check
-- =========================================================================
SELECT 'identities_new'      AS TableName, COUNT(*) AS RowsToInsert
FROM mig_stg_acc.actual_identity_identities AS s
LEFT JOIN mig.actual_identity_identities_mapping AS m ON m.entra_id = s.entra_id
WHERE m.prd_id IS NULL
UNION ALL
SELECT 'user', COUNT(*) FROM mig_stg_acc.vw_actual_identity_users AS v
    WHERE NOT EXISTS (SELECT 1 FROM actual_identity.[users] AS p WHERE p.id = v.id)
UNION ALL
SELECT 'groups', COUNT(*) FROM mig_stg_acc.vw_actual_identity_groups AS v
    WHERE NOT EXISTS (SELECT 1 FROM actual_identity.groups AS p WHERE p.id = v.id)
UNION ALL
SELECT 'serviceprincipal', COUNT(*) FROM mig_stg_acc.vw_actual_identity_serviceprincipal AS v
    WHERE NOT EXISTS (SELECT 1 FROM actual_identity.serviceprincipal AS p WHERE p.id = v.id)
UNION ALL
SELECT 'identitiesInGroups', COUNT(*) FROM mig_stg_acc.vw_actual_identity_identitiesInGroups AS v
    WHERE NOT EXISTS (
        SELECT 1 FROM actual_identity.identitiesInGroups AS p
        WHERE p.member_id = v.member_id AND p.group_id = v.group_id
    );
