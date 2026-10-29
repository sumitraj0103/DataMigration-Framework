INSERT INTO mig.actual_identity_identities_mapping
(
    entra_id,
    acc_id,
    prd_id
)
SELECT
    a.entra_id,
    a.id,
    p.id
FROM mig_stg_acc.actual_identity_identities a
JOIN actual_identity.identities p
    ON p.entra_id = a.entra_id;



CREATE TABLE mig.actual_identity_identities_mapping
(
    entra_id NVARCHAR(255) NOT NULL,
    dev_id   BIGINT NULL,
    tst_id   BIGINT NULL,
    acc_id   BIGINT NULL,
    prd_id   BIGINT NULL,
 
    CONSTRAINT UQ_acutal_identity_identities_mapping_entra_id
        UNIQUE (entra_id)
);


USE [DMAP]
GO

INSERT INTO [mig].[metadata_loadToStaging]
           ([SchemaName]
           ,[TableName]
           ,[Env]
           ,[Loadtostaging])
     VALUES ('actual_identity','groups','acc',1)         
GO

INSERT INTO [mig].[metadata_loadToStaging]
           ([SchemaName], [TableName], [Env], [Loadtostaging])
     VALUES
           ('actual_identity', 'identities',         'dev', 1),
           ('actual_identity', 'users',              'dev', 1),
           ('actual_identity', 'servicePrincipals',   'dev', 1),
           ('actual_identity', 'identitiesInGroups',  'dev', 1),
           ('actual_identity', 'identities',          'tst', 1),
           ('actual_identity', 'users',               'tst', 1),
           ('actual_identity', 'servicePrincipals',   'tst', 1),
           ('actual_identity', 'identitiesInGroups',  'tst', 1)
GO



  select * from mig_stg_acc.actual_identity_identities
  where entra_id= '02a8d037-0a04-4415-8460-950336684cd4'


  
  select * from actual_identity.identities
  where entra_id= '02a8d037-0a04-4415-8460-950336684cd4'

-- check for duplicate acc_id and prd_id in the mapping table
SELECT acc_id, COUNT(*)
FROM mig.actual_identity_identities_mapping
GROUP BY acc_id
HAVING COUNT(*) > 1;


SELECT prd_id, COUNT(*)
FROM mig.actual_identity_identities_mapping
GROUP BY prd_id
HAVING COUNT(*) > 1;


-- Identities: no id/mapping involved here - entra_id is the business key, and Production assigns
-- its own new id on insert (that new id then gets picked up into mapping.prd_id on the next
-- mig.usp_RefreshIdentityMapping run, before user/groups/serviceprincipal/identitiesInGroups load)
CREATE OR ALTER VIEW [mig_stg_acc].[vw_actual_identity_identities]
AS
SELECT
    m.prd_id AS id,
    b.type,
    b.entra_id,
    b.name,
    b.active
FROM mig_stg_acc.actual_identity_identities b
JOIN mig.actual_identity_identities_mapping m
    ON m.acc_id = b.id;
GO


CREATE OR ALTER VIEW mig_stg_acc.vw_actual_identity_users
AS
SELECT
    m.prd_id AS id,
    b.email,
    b.upn
FROM mig_stg_acc.actual_identity_users AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.acc_id = b.id;
GO

-- Group: id is PK & FK to Identity.id, same remap as User
CREATE OR ALTER VIEW mig_stg_acc.vw_actual_identity_groups
AS
SELECT
    m.prd_id AS id,
    b.ci
FROM mig_stg_acc.actual_identity_groups AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.acc_id = b.id;
GO

-- ServicePrincipal: id is PK & FK to Identity.id, no other columns to carry over
CREATE OR ALTER VIEW mig_stg_acc.vw_actual_identity_serviceprincipal
AS
SELECT
    m.prd_id AS id
FROM mig_stg_acc.actual_identity_servicePrincipals AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.acc_id = b.id;
GO

-- MembersInGroup: both member_id and group_id are identity ids, so each needs its own
-- join to the mapping table to resolve to the matching prd_id
CREATE OR ALTER VIEW mig_stg_acc.vw_actual_identity_identitiesInGroups
AS
SELECT
    mm.prd_id AS member_id,
    mg.prd_id AS group_id
FROM mig_stg_acc.actual_identity_identitiesInGroups AS b
INNER JOIN mig.actual_identity_identities_mapping AS mm
    ON mm.acc_id = b.member_id
INNER JOIN mig.actual_identity_identities_mapping AS mg
    ON mg.acc_id = b.group_id;
GO


-- =========================================================================
-- PRODUCTION LOAD: config-driven, not hand-written.
-- mig.usp_RefreshIdentityMapping (sql/validate-and-load/11_usp_refresh_identity_mapping.sql) never
-- writes to actual_identity.identities - it only keeps mapping's dev_id/tst_id/acc_id/prd_id in
-- sync. Identity creation happens through the normal identities config row (business key =
-- entra_id, SKIP_EXISTING), which lets Production assign its own new id. PL_ValidateAndLoadAllToProduction
-- therefore runs in two phases: refresh mapping -> load LoadOrder<=10 (identities) -> refresh
-- mapping again (to pick up the new prd_ids) -> load LoadOrder>10 (user/groups/serviceprincipal/
-- identitiesInGroups), whose vw_* views can now resolve every id via mig.actual_identity_identities_mapping.
-- Register these 5 tables in mig.TableConfiguration (sql/validate-and-load/10_identity_family_table_configuration.sql).
-- =========================================================================
-- Create Views for  test load
CREATE OR ALTER VIEW [mig_stg_tst].[vw_actual_identity_identities]
AS
SELECT
    m.prd_id AS id,
    b.type,
    b.entra_id,
    b.name,
    b.active
FROM mig_stg_tst.actual_identity_identities b
JOIN mig.actual_identity_identities_mapping m
    ON m.tst_id = b.id;
GO



CREATE OR ALTER VIEW mig_stg_tst.vw_actual_identity_users
AS
SELECT
    m.prd_id AS id,
    b.email,
    b.upn
FROM mig_stg_tst.actual_identity_users AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.tst_id = b.id;
GO

-- Group: id is PK & FK to Identity.id, same remap as User
CREATE OR ALTER VIEW mig_stg_tst.vw_actual_identity_groups
AS
SELECT
    m.prd_id AS id,
    b.ci
FROM mig_stg_tst.actual_identity_groups AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.tst_id = b.id;
GO

-- ServicePrincipal: id is PK & FK to Identity.id, no other columns to carry over
CREATE OR ALTER VIEW mig_stg_tst.vw_actual_identity_serviceprincipals
AS
SELECT
    m.prd_id AS id
FROM mig_stg_tst.actual_identity_servicePrincipals AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.tst_id = b.id;
GO

-- MembersInGroup: both member_id and group_id are identity ids, so each needs its own
-- join to the mapping table to resolve to the matching prd_id
CREATE OR ALTER VIEW mig_stg_tst.vw_actual_identity_identitiesInGroups
AS
SELECT
    mm.prd_id AS member_id,
    mg.prd_id AS group_id
FROM mig_stg_tst.actual_identity_identitiesInGroups AS b
INNER JOIN mig.actual_identity_identities_mapping AS mm
    ON mm.tst_id = b.member_id
INNER JOIN mig.actual_identity_identities_mapping AS mg
    ON mg.tst_id = b.group_id;
GO


-- Create Views for  dev load


CREATE OR ALTER VIEW [mig_stg_dev].[vw_actual_identity_identities]
AS
SELECT
    m.prd_id AS id,
    b.type,
    b.entra_id,
    b.name,
    b.active
FROM mig_stg_dev.actual_identity_identities b
JOIN mig.actual_identity_identities_mapping m
    ON m.dev_id = b.id;
GO



CREATE OR ALTER VIEW mig_stg_dev.vw_actual_identity_users
AS
SELECT
    m.prd_id AS id,
    b.email,
    b.upn
FROM mig_stg_dev.actual_identity_users AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.dev_id = b.id;
GO

-- Group: id is PK & FK to Identity.id, same remap as User
CREATE OR ALTER VIEW mig_stg_dev.vw_actual_identity_groups
AS
SELECT
    m.prd_id AS id,
    b.ci
FROM mig_stg_dev.actual_identity_groups AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.dev_id = b.id;
GO

-- ServicePrincipal: id is PK & FK to Identity.id, no other columns to carry over
CREATE OR ALTER VIEW mig_stg_dev.vw_actual_identity_serviceprincipals
AS
SELECT
    m.prd_id AS id
FROM mig_stg_dev.actual_identity_servicePrincipals AS b
INNER JOIN mig.actual_identity_identities_mapping AS m
    ON m.dev_id = b.id;
GO

-- MembersInGroup: both member_id and group_id are identity ids, so each needs its own
-- join to the mapping table to resolve to the matching prd_id
CREATE OR ALTER VIEW mig_stg_dev.vw_actual_identity_identitiesInGroups
AS
SELECT
    mm.prd_id AS member_id,
    mg.prd_id AS group_id
FROM mig_stg_dev.actual_identity_identitiesInGroups AS b
INNER JOIN mig.actual_identity_identities_mapping AS mm
    ON mm.dev_id = b.member_id
INNER JOIN mig.actual_identity_identities_mapping AS mg
    ON mg.dev_id = b.group_id;
GO
