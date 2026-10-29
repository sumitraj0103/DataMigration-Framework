# Strategy 2: Production to Lower Environment Synchronization

This folder is a **self-contained implementation** of Strategy 2 from
[../Database-Migration-Execution.md](../Database-Migration-Execution.md#strategy-2-production-to-lower-environment-synchronization).
It is kept separate from the Strategy 1 (Load to Production) files in `../sql` and `../adf` so the
two efforts don't get mixed together during development.

Data flows the **opposite direction** from Strategy 1: from **Production down into each lower
environment** (Dev/Tst/Acc), using **UPSERT**, either scoped to a single environment's records
(environment-specific tables) or across all records (non-environment-specific tables).

## Why this can't reuse the Strategy 1 stored procedures

Strategy 1's `usp_LoadValidatedTableToProduction` runs a single in-database `MERGE` because the
staging table and the Production table live on the **same SQL server** (Prd). Strategy 2 syncs
across **different SQL servers** (Prod -> Dev / Tst / Acc), so the upsert has to happen via an ADF
**Copy Activity** with `writeBehavior: upsert`, not a single cross-server T-SQL statement.

## Folder layout

```
Synchronise/
  README.md
  deploy-synchronise.ps1
  sql/
    01_mig_sync_configuration.sql   -- metadata: which tables to sync, env-specific?, business keys
    02_mig_sync_run.sql             -- audit table: one row per sync attempt (per table/environment)
    03_mig_sync_master_run.sql      -- audit table: one row per PL_SyncAllProdToLowerEnvironments run
    04_sample_sync_configuration_data.sql
    05_test_table_ci_aic.sql        -- dbo.CI_AIC test table + dummy rows (run on Dev/Tst/Acc/Prd)
    06_sample_sync_configuration_for_ci_aic.sql -- SyncConfiguration row for dbo.CI_AIC (Prd only)
  adf/
    pipelines/
      PL_SyncProdToLowerEnvironment.json     -- syncs one table into one target environment
      PL_SyncAllProdToLowerEnvironments.json -- fans out over mig.SyncConfiguration x target envs
```

Linked services and datasets are **reused** from `../adf/linkedServices` and `../adf/datasets`
(`LS_ProdSqlMig`, `LS_SourceSqlMig_Dev/Test/Acc`, `DS_StagingTableMig`, `DS_SourceTableMig_Dev/Test/Acc`)
since the Prod and lower-environment connections already exist for Strategy 1 — no need to
duplicate them.

## Design

### 1. Metadata: `mig.SyncConfiguration` (lives on the Prd server, `mig` schema)

| Column | Purpose |
|---|---|
| `SourceSchema` / `SourceTable` | Production table to sync from |
| `TargetSchema` / `TargetTable` | Table name/schema in the lower environment (usually same name) |
| `TargetEnvironment` | Which single lower environment this row syncs into: `dev`, `tst`, or `acc` (lowercase, case-sensitive). To sync the same table into more than one environment, add one configuration row per environment. |
| `SyncStrategy` | `UPSERT_ALL`, `INSERT_ALL`, `UPSERT_ENV_SPECIFIC`, or `INSERT_ENV_SPECIFIC` — see below |
| `EnvironmentColumn` | Column used to filter Production rows to `TargetEnvironment`'s records; required (and only used) when `SyncStrategy` is `UPSERT_ENV_SPECIFIC` or `INSERT_ENV_SPECIFIC` (e.g. `Environment`) |
| `BusinessKeyColumns` | Key column(s) used as the UPSERT/INSERT match key — a single column name (e.g. `InstanceName`) or multiple comma-separated column names (e.g. `Col1,Col2`) |
| `IsActive` | Whether this configuration is enabled |

## SyncStrategy

| `SyncStrategy` | Description |
|---|---|
| `UPSERT_ALL` | Update and insert **all** Production rows into the lower environment, matched on the business key. |
| `INSERT_ALL` | Insert **all** Production rows into the lower environment, matched on the business key. Do not update rows whose business key already exists. |
| `UPSERT_ENV_SPECIFIC` | Update and insert only the environment-specific rows from Production into the lower environment, matched on the business key. E.g. when syncing Prod -> Dev, it picks only the Dev-related rows and inserts/updates the Dev database. |
| `INSERT_ENV_SPECIFIC` | Insert only the environment-specific rows from Production into the lower environment, matched on the business key. E.g. when syncing Prod -> Dev, it picks only the Dev-related rows and inserts them into the Dev database. Do not update rows whose business key already exists. |

### 2. SyncStrategy (matches the umbrella doc)

| `SyncStrategy` | Environment filter | Write behavior |
|---|---|---|
| `UPSERT_ALL` | None — all Production rows | **Upsert**: insert new business keys, update existing ones |
| `INSERT_ALL` | None — all Production rows | **Insert-only**: insert new business keys, skip (never update) rows whose business key already exists in the target |
| `UPSERT_ENV_SPECIFIC` | Only rows where `EnvironmentColumn = TargetEnvironment` | **Upsert**: insert new business keys, update existing ones |
| `INSERT_ENV_SPECIFIC` | Only rows where `EnvironmentColumn = TargetEnvironment` | **Insert-only**: insert new business keys, skip (never update) rows whose business key already exists in the target |

A `CHECK` constraint on `mig.SyncConfiguration` enforces that `EnvironmentColumn` is populated
whenever `SyncStrategy` is `UPSERT_ENV_SPECIFIC` or `INSERT_ENV_SPECIFIC`.

For the two `UPSERT_*` strategies the mechanism is an ADF Copy Activity with an `AzureSqlSink`
configured for `writeBehavior: "upsert"`, keyed on `BusinessKeyColumns`. For the two `INSERT_*`
strategies, `writeBehavior` is `"insert"` and the Production source query itself excludes any row
whose `BusinessKeyColumns` value already exists in the lower-environment target table (looked up
via a `STRING_AGG`-based query against the target before the copy runs).

### 3. Pipelines

- **`PL_SyncProdToLowerEnvironment`** (parameters: `ConfigurationId`, `TargetEnvironment`)
  1. Looks up the row in `mig.SyncConfiguration`, including `TargetEnvironment` and `SyncStrategy`.
  2. **Pre-upsert duplicate check**: groups the (env-filtered, if applicable) Production source
     query by `BusinessKeyColumns` and checks for any group with `COUNT(*) > 1`. If duplicates are
     found, the sync is blocked before anything is copied: `mig.SyncRun` is marked `ERROR` and the
     pipeline fails explicitly.
  4. Runs a `Switch` on `TargetEnvironment` (`dev` / `tst` / `acc`, lowercase and case-sensitive) so the Copy Activity's source
     input / sink output datasets point at the matching linked service (`DS_SourceTableMig_Dev/Test/Acc`).
  5. Looks up existing `BusinessKeyColumns` values already present in the target table
     (`GetExistingTargetKeys<Env>`) — used only by `INSERT_ONLY_MATCHED_ENV` to skip existing rows.
  6. Builds the Production source query and `writeBehavior` based on `SyncStrategy` (see table
     above), then runs the Copy Activity: source = Production table (`DS_StagingTableMig` bound to
     `LS_ProdSqlMig`), sink = lower-environment table.
  7. **Post-copy duplicate check**: groups the lower-environment target table by
     `BusinessKeyColumns` and checks for any group with `COUNT(*) > 1`. Implemented as a single
     Lookup running `IF EXISTS (...) THROW ...` (ADF doesn't allow an `IfCondition` activity nested
     directly inside a `Switch` case), so the Lookup itself fails the `Switch` when duplicates are
     found.
  8. Logs the outcome (status, error message if any) to `mig.SyncRun`.
- **`PL_SyncAllProdToLowerEnvironments`** (no required parameters)
  1. Reads all active rows from `mig.SyncConfiguration` (each row already specifies its own
     `TargetEnvironment`).
  2. `ForEach` row, invokes `PL_SyncProdToLowerEnvironment` with `ConfigurationId` +
     `TargetEnvironment`.

### 4. Run history and error auditing

Every run is audited, and every failure is recorded before the pipeline itself is failed (so ADF
monitoring reflects the failure while the error is still queryable in SQL):

| Table | One row per | On failure |
|---|---|---|
| `mig.SyncMasterRun` | `PL_SyncAllProdToLowerEnvironments` execution (`BatchId`) | `RunStatus = 'FAILED'`, `ErrorMessage` set, then the pipeline explicitly fails (`FailSyncMasterRun`). |
| `mig.SyncRun` | `PL_SyncProdToLowerEnvironment` execution (`ConfigurationId` + `TargetEnvironment` + `BatchId`) | `SyncStatus = 'ERROR'`, `ErrorMessage` set from the Copy Activity's error, then the pipeline explicitly fails (`FailSyncRun`). |

Both pipelines insert a `RUNNING` row up front, then either mark it `SUCCESS`/`ERROR` (or
`FAILED` for the master) on completion — there is no scenario where a run finishes without a
corresponding audit row, and no scenario where an error is swallowed silently. Query `mig.SyncRun`
joined to `mig.SyncMasterRun` on `BatchId` to see the full run history and drill into any failure.

### 5. Where results are recorded

| Table | Purpose |
|---|---|
| `mig.SyncConfiguration` | Drives what gets synced, to which environment(s), and how (env-specific vs. all rows). |
| `mig.SyncMasterRun` | One row per `PL_SyncAllProdToLowerEnvironments` execution (master run history + overall status). |
| `mig.SyncRun` | One row per `PL_SyncProdToLowerEnvironment` execution: `ConfigurationId`, `TargetEnvironment`, `BatchId`, status, rows read/inserted/updated, error message. |

## Deployment

For a full step-by-step walkthrough (deploy SQL, publish ADF pipelines, configure a real table,
and run/verify test syncs), see
[Synchronise-Deploy-and-Test-Guide.md](Synchronise-Deploy-and-Test-Guide.md).

Run `.\deploy-synchronise.ps1` from this folder (mirrors `..\deploy-validate-and-load.ps1`'s
conventions). By default it runs the SQL scripts in `sql/` in order against the Prd server's DMAP
database (same server/DB that already hosts `mig.TableConfiguration` etc. for Strategy 1). Add
`-DeployAdf -ResourceGroupName <rg> -DataFactoryName <adf>` to also publish the pipeline JSON
under `adf/pipelines/` to an existing Data Factory — it only publishes pipelines, since the linked
services/datasets it references (`LS_ProdSqlMig`, `LS_SourceSqlMig_Dev/Test/Acc`,
`DS_StagingTableMig`, `DS_SourceTableMig_Dev/Test/Acc`) must already exist there via
`..\deploy.ps1 -DeployAdf`.

```powershell
# SQL only, local/Windows auth
.\deploy-synchronise.ps1

# SQL + publish pipelines to an existing Data Factory
.\deploy-synchronise.ps1 -PrdServerInstance "dmap-prd-sql.database.windows.net" -UseIntegratedSecurity:$false -Credential (Get-Credential) `
    -DeployAdf -ResourceGroupName "rg-dmap-adf" -DataFactoryName "adf-dmap-poc"

# Also create the dbo.CI_AIC test table + dummy data on Dev/Tst/Acc/Prd, and seed its sync config
.\deploy-synchronise.ps1 -DeployTestTable `
    -DevServerInstance "dmap-dev-sql.database.windows.net" -TstServerInstance "dmap-tst-sql.database.windows.net" `
    -AccServerInstance "dmap-acc-sql.database.windows.net" -PrdServerInstance "dmap-prd-sql.database.windows.net" `
    -UseIntegratedSecurity:$false -Credential (Get-Credential)
```

## Open items / next iterations

- [ ] Confirm the exact `EnvironmentColumn` value convention (e.g. `dev`/`tst`/`acc` vs `DEV`/`TST`/`ACC`) per table.
- [ ] Decide whether `PL_SyncAllProdToLowerEnvironments` should run on a schedule/trigger.
- [ ] Add a delete/soft-delete sync path if Production rows can be removed (current design only covers insert/update).
- [ ] Consider adding a dedicated `mig.SyncValidationError` table (like Strategy 1's `mig.ValidationError`) if per-row duplicate details (not just row counts) need to be captured, rather than just the blocking `mig.SyncRun.ErrorMessage`.
