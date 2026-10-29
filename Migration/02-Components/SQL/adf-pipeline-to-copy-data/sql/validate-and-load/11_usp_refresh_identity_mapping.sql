-- Use Case 1.2 (Part 2) pre-step: keeps mig.actual_identity_identities_mapping in sync with
-- actual_identity.identities before the FK-dependent family (user/groups/serviceprincipal/
-- membersingroup) is loaded via mig.TableConfiguration. Never creates identities in Production
-- itself - that is the job of the normal TableConfiguration-driven load of the identities table
-- (business key = entra_id, so SKIP_EXISTING creates any entra_id missing from Prod and lets the
-- target table assign its own new id). This proc only keeps the mapping table's per-env id columns
-- and prd_id in sync, so run it again after the identities load to pick up newly created prd_ids
-- before loading user/groups/serviceprincipal/identitiesInGroups. Safe to re-run (idempotent).
--
-- @Env = 'ALL' (default): refreshes every env that currently has active identity-family rows in
-- mig.TableConfiguration (derived from SourceSchema = 'mig_stg_<env>'). Needed because acc/dev/tst
-- now all run together in a single PL_ValidateAndLoadAllToProduction execution - a brand new
-- entra_id that only exists in e.g. mig_stg_dev would never get a mapping row (and so never load)
-- if this proc only ever refreshed a single hardcoded env.
-- @Env = '<env>' (e.g. 'dev'): refreshes just that one env - still supported for manual/ad hoc use
-- (see refresh-identity-mapping.ps1).
CREATE OR ALTER PROCEDURE mig.usp_RefreshIdentityMapping
    @Env SYSNAME = 'ALL'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Sql NVARCHAR(MAX);
    DECLARE @RowsMapped INT = 0;
    DECLARE @EnvIdCol SYSNAME, @StagingSchema SYSNAME, @CurrentEnv SYSNAME;

    DECLARE @Envs TABLE (Env SYSNAME PRIMARY KEY);

    IF @Env IS NULL OR @Env = 'ALL'
        INSERT INTO @Envs (Env)
        SELECT DISTINCT SUBSTRING(SourceSchema, LEN('mig_stg_') + 1, 100)
        FROM mig.TableConfiguration
        WHERE IsActive = 1
          AND TargetSchema = 'actual_identity'
          AND SourceSchema LIKE 'mig_stg_%';
    ELSE
        INSERT INTO @Envs (Env) VALUES (@Env);

    IF NOT EXISTS (SELECT 1 FROM @Envs)
        THROW 51021, 'No active identity-family envs found in mig.TableConfiguration to refresh.', 1;

    DECLARE EnvCursor CURSOR LOCAL FAST_FORWARD FOR SELECT Env FROM @Envs;
    OPEN EnvCursor;
    FETCH NEXT FROM EnvCursor INTO @CurrentEnv;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @EnvIdCol = @CurrentEnv + N'_id';
        SET @StagingSchema = N'mig_stg_' + @CurrentEnv;

        IF OBJECT_ID(QUOTENAME(@StagingSchema) + '.actual_identity_identities', 'U') IS NULL
            THROW 51020, 'Staging schema/table for the given @Env does not exist.', 1;

        BEGIN TRANSACTION;

        -- 1) mapping rows missing entirely (entra_id never seen before, any env)
        SET @Sql = N'
            INSERT INTO mig.actual_identity_identities_mapping (entra_id, ' + QUOTENAME(@EnvIdCol) + N')
            SELECT s.entra_id, s.id
            FROM ' + QUOTENAME(@StagingSchema) + N'.actual_identity_identities AS s
            WHERE NOT EXISTS (
                SELECT 1 FROM mig.actual_identity_identities_mapping m WHERE m.entra_id = s.entra_id
            );';
        EXEC sp_executesql @Sql;

        -- 2) backfill this env's id column where the entra_id already has a mapping row from another env
        SET @Sql = N'
            UPDATE m
            SET m.' + QUOTENAME(@EnvIdCol) + N' = s.id
            FROM mig.actual_identity_identities_mapping AS m
            JOIN ' + QUOTENAME(@StagingSchema) + N'.actual_identity_identities AS s
                ON s.entra_id = m.entra_id
            WHERE m.' + QUOTENAME(@EnvIdCol) + N' IS NULL;';
        EXEC sp_executesql @Sql;

        COMMIT TRANSACTION;

        FETCH NEXT FROM EnvCursor INTO @CurrentEnv;
    END

    CLOSE EnvCursor;
    DEALLOCATE EnvCursor;

    -- 3) backfill prd_id for any entra_id that now exists in Production (e.g. just created by the
    -- identities TableConfiguration load) but whose mapping row still shows prd_id = NULL.
    -- Env-agnostic by design, so it runs once after every env's id column above is synced.
    BEGIN TRANSACTION;

    UPDATE m
    SET m.prd_id = p.id
    FROM mig.actual_identity_identities_mapping AS m
    JOIN actual_identity.identities AS p ON p.entra_id = m.entra_id
    WHERE m.prd_id IS NULL;

    SET @RowsMapped = @@ROWCOUNT;

    COMMIT TRANSACTION;

    SELECT @RowsMapped AS RowsMapped;
END
GO

