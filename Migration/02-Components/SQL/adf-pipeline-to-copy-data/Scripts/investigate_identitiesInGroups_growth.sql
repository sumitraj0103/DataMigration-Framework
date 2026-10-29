-- Investigate why ~3600 new rows get inserted into actual_identity.identitiesInGroups every run.

-- 1) Does the staging table grow day over day, or is it a fixed-size snapshot reloaded daily?
--    (run once per day / compare across days)
SELECT COUNT(*) AS StagingRowCount
FROM mig_stg_acc.actual_identity_identitiesInGroups;

-- 2) How many distinct (member_id, group_id) pairs (post-mapping) are in staging right now
--    vs. how many already exist in Production? The gap should equal the next run's insert count.
SELECT COUNT(*) AS StagingDistinctPairs
FROM (
    SELECT DISTINCT mm.prd_id AS member_id, mg.prd_id AS group_id
    FROM mig_stg_acc.actual_identity_identitiesInGroups AS b
    INNER JOIN mig.actual_identity_identities_mapping AS mm ON mm.acc_id = b.member_id
    INNER JOIN mig.actual_identity_identities_mapping AS mg ON mg.acc_id = b.group_id
) x;

SELECT COUNT(*) AS ProductionRowCount
FROM actual_identity.identitiesInGroups;

-- 3) Pairs present in staging today that are NOT yet in Production - this is what the next
--    SKIP_EXISTING run will insert. Inspect a sample to see if they look like "new" real
--    memberships or re-appearing/duplicated data.
SELECT TOP 50
    mm.prd_id AS member_id,
    mg.prd_id AS group_id
FROM mig_stg_acc.actual_identity_identitiesInGroups AS b
INNER JOIN mig.actual_identity_identities_mapping AS mm ON mm.acc_id = b.member_id
INNER JOIN mig.actual_identity_identities_mapping AS mg ON mg.acc_id = b.group_id
WHERE NOT EXISTS (
    SELECT 1 FROM actual_identity.identitiesInGroups AS t
    WHERE t.member_id = mm.prd_id AND t.group_id = mg.prd_id
);

-- 4) Sanity check: is the mapping table producing duplicates? (one acc_id mapping to >1 entra_id
--    would multiply every join and could masquerade as "new" pairs each run)
SELECT acc_id, COUNT(*)
FROM mig.actual_identity_identities_mapping
WHERE acc_id IS NOT NULL
GROUP BY acc_id
HAVING COUNT(*) > 1;

-- 5) Does the staging table itself contain duplicate (member_id, group_id) rows that keep
--    being re-inserted by the Load-to-Staging pipeline (append instead of truncate+reload)?
SELECT member_id, group_id, COUNT(*)
FROM mig_stg_acc.actual_identity_identitiesInGroups
GROUP BY member_id, group_id
HAVING COUNT(*) > 1;

-- 6) Track growth of the actual Production table over the LoadRun history to confirm it is
--    monotonically increasing by ~3600/day rather than cycling (which would indicate something
--    is deleting rows from Production between runs, forcing re-insert).
SELECT ConfigurationId, BatchId, LoadStatus, RecordsRead, RecordsInserted, StartedAt, CompletedAt
FROM mig.LoadRun
WHERE ConfigurationId = 6
ORDER BY StartedAt;
