-- Registers the identity/user/group/serviceprincipal/membersingroup family in
-- mig.TableConfiguration so PL_ValidateAndLoadAllToProduction loads them, in FK order, via
-- the generic mig.usp_LoadValidatedTableToProduction engine instead of hand-written scripts.
-- Source = the mig_stg_<env>.vw_actual_identity_* views (scripts/Identity-mapping.sql), which
-- already resolve ids to prd_id via mig.actual_identity_identities_mapping, so SKIP_EXISTING's
-- plain id match is correct for all of them.
-- All three envs (acc/dev/tst) are IsActive = 1 and run together in a single
-- PL_ValidateAndLoadAllToProduction execution. LoadOrder is kept IDENTICAL across acc/dev/tst
-- (10 = identities, 20 = user/groups/serviceprincipal, 30 = identitiesInGroups) -- do NOT stagger
-- it per env (e.g. 10/20/30 for acc, 40/50/60 for dev, ...). PL_ValidateAndLoadAllToProduction's
-- two-phase split (SELECT ... WHERE LoadOrder <= 10, then refresh mapping, then
-- WHERE LoadOrder > 10) batches by LoadOrder value only, not by SourceSchema, so keeping the same
-- values for every env is what puts every active env's identities in phase 1 together and every
-- active env's dependents in phase 2 together. Staggering LoadOrder per env would instead
-- interleave one env's dependents into the same phase as another env's identities and break the
-- FK-safe sequence.
-- Note: TargetTable uses the real actual_identity table names ('users', 'servicePrincipals'),
-- correcting the acc rows' previous 'user'/'serviceprincipal' typo so the MERGE stays idempotent
-- against what's already live in mig.TableConfiguration.

MERGE mig.TableConfiguration AS t
USING (VALUES
    -- acc
    ('mig_stg_acc', 'vw_actual_identity_identities',       'actual_identity', 'identities',        'entra_id',           'SKIP_EXISTING', 10),
    ('mig_stg_acc', 'vw_actual_identity_users',            'actual_identity', 'users',             'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_acc', 'vw_actual_identity_groups',           'actual_identity', 'groups',            'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_acc', 'vw_actual_identity_serviceprincipal', 'actual_identity', 'servicePrincipals', 'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_acc', 'vw_actual_identity_identitiesInGroups', 'actual_identity', 'identitiesInGroups', 'member_id,group_id', 'SKIP_EXISTING', 30),
    -- dev
    ('mig_stg_dev', 'vw_actual_identity_identities',       'actual_identity', 'identities',        'entra_id',           'SKIP_EXISTING', 10),
    ('mig_stg_dev', 'vw_actual_identity_users',            'actual_identity', 'users',             'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_dev', 'vw_actual_identity_groups',           'actual_identity', 'groups',            'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_dev', 'vw_actual_identity_serviceprincipals','actual_identity', 'servicePrincipals', 'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_dev', 'vw_actual_identity_identitiesInGroups', 'actual_identity', 'identitiesInGroups', 'member_id,group_id', 'SKIP_EXISTING', 30),
    -- tst
    ('mig_stg_tst', 'vw_actual_identity_identities',       'actual_identity', 'identities',        'entra_id',           'SKIP_EXISTING', 10),
    ('mig_stg_tst', 'vw_actual_identity_users',            'actual_identity', 'users',             'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_tst', 'vw_actual_identity_groups',           'actual_identity', 'groups',            'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_tst', 'vw_actual_identity_serviceprincipals','actual_identity', 'servicePrincipals', 'id',                 'SKIP_EXISTING', 20),
    ('mig_stg_tst', 'vw_actual_identity_identitiesInGroups', 'actual_identity', 'identitiesInGroups', 'member_id,group_id', 'SKIP_EXISTING', 30)
) AS s (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, LoadOrder)
ON t.SourceSchema = s.SourceSchema AND t.SourceTable = s.SourceTable
   AND t.TargetSchema = s.TargetSchema AND t.TargetTable = s.TargetTable
WHEN MATCHED THEN
    UPDATE SET BusinessKeyColumns = s.BusinessKeyColumns, LoadStrategy = s.LoadStrategy,
               LoadOrder = s.LoadOrder, IsActive = 1, ModifiedDate = SYSUTCDATETIME()
WHEN NOT MATCHED THEN
    INSERT (SourceSchema, SourceTable, TargetSchema, TargetTable, BusinessKeyColumns, LoadStrategy, LoadOrder, ValidationRequired, IsActive)
    VALUES (s.SourceSchema, s.SourceTable, s.TargetSchema, s.TargetTable, s.BusinessKeyColumns, s.LoadStrategy, s.LoadOrder, 1, 1);
GO
