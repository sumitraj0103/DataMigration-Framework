# Synchronise Deployment & Testing Guide (Strategy 2 — Prod to Lower Environment Synchronization)

This guide is a step-by-step walkthrough for setting up and testing the **Prod -> Lower
Environment Synchronization** implementation described in
[README.md](README.md) and summarized in
[../Database-Migration-Execution.md](../Database-Migration-Execution.md#strategy-2-production-to-lower-environment-synchronization).

Everything needed lives inside this `Synchronise/` folder and is fully independent of Strategy 1
(`../deploy.ps1`, `../deploy-validate-and-load.ps1`, `../sql`, `../adf`) — it does not modify
anything from that side.

---

## 1. What gets deployed

| # | Script | Creates |
|---|--------|---------|
| 1 | `sql/01_mig_sync_configuration.sql` | `mig.SyncConfiguration` — one row per table to sync, env-specific flag, business keys |
| 2 | `sql/02_mig_sync_run.sql` | `mig.SyncRun` — one row per per-table/per-environment sync attempt |
| 3 | `sql/03_mig_sync_master_run.sql` | `mig.SyncMasterRun` — one row per batch (`PL_SyncAllProdToLowerEnvironments`) run |
| 4 | `sql/04_sample_sync_configuration_data.sql` | Sample configuration rows (one env-specific, one non-env-specific) |
| 5 | `sql/05_test_table_ci_aic.sql` (`-DeployTestTable`) | `dbo.CI_AIC` test table + 5 dummy rows, run on **Dev/Tst/Acc/Prd** |
| 6 | `sql/06_sample_sync_configuration_for_ci_aic.sql` (`-DeployTestTable`) | `mig.SyncConfiguration` row for `dbo.CI_AIC` (Prd only) |
| — | `adf/pipelines/PL_SyncProdToLowerEnvironment.json` | Syncs one table into one target environment, with duplicate-business-key checks before and after the upsert |
| — | `adf/pipelines/PL_SyncAllProdToLowerEnvironments.json` | Fans out over all active configs x Dev/Test/Acc |

All SQL scripts are idempotent (safe to re-run). All objects live on the **Prd server's `DMAP`
database**, `mig` schema — the same server/database used by Strategy 1.

---

## 2. Prerequisites

- Strategy 1 (`../deploy.ps1`) already deployed, or at minimum the shared ADF plumbing already
  published: `LS_ProdSqlMig`, `LS_SourceSqlMig_Dev`, `LS_SourceSqlMig_Test`, `LS_SourceSqlMig_Acc`
  linked services, and `DS_StagingTableMig`, `DS_SourceTableMig_Dev/Test/Acc` datasets.
  `deploy-synchronise-adf.ps1` only publishes pipelines — it does not create linked
  services/datasets.
- `SqlServer` PowerShell module (`Install-Module SqlServer -Scope CurrentUser`) or `sqlcmd.exe`,
  for `deploy-synchronise-sql.ps1`.
- For `deploy-synchronise-adf.ps1`: `Az.DataFactory` module and an authenticated Az session
  (`Connect-AzAccount`).
- Real source/target tables to sync (the sample data uses placeholder table names `dbo.EnvSpecificConfig`
  and `dbo.ReferenceData` — replace with your actual tables before running against a real environment).

---

## 3. Deploy the SQL objects

### 3.1 Local SQL Server

```powershell
cd Synchronise
.\deploy-synchronise-sql.ps1
```

### 3.2 Azure SQL (Prd server)

```powershell
.\deploy-synchronise-sql.ps1 -PrdServerInstance "dmap-prd-sql.database.windows.net" `
                              -UseIntegratedSecurity:$false `
                              -Credential (Get-Credential)
```

### 3.3 Tables only, no sample configuration rows

```powershell
.\deploy-synchronise-sql.ps1 -PrdServerInstance "dmap-prd-sql.database.windows.net" `
                              -UseIntegratedSecurity:$false -Credential (Get-Credential) `
                              -SkipSampleData
```

**Verify:**

```sql
SELECT * FROM mig.SyncConfiguration;
SELECT * FROM mig.SyncRun;
SELECT * FROM mig.SyncMasterRun;
```

Expect the two sample `SyncConfiguration` rows (if `-SkipSampleData` was not used) and empty
`SyncRun` / `SyncMasterRun` tables (no syncs have run yet).

---

## 4. Publish the ADF pipelines

```powershell
.\deploy-synchronise-adf.ps1 -ResourceGroupName "rg-dmap-adf" -DataFactoryName "adf-dmap-poc"
```

This publishes `PL_SyncProdToLowerEnvironment` first, then `PL_SyncAllProdToLowerEnvironments`
(which references it). Re-run with the same parameters any time you change a pipeline JSON file —
`-Force` is used under the hood so it's safe to re-publish.

This script is independent of the SQL deployment (step 3) — re-run it on its own whenever you
only change a pipeline JSON file, without needing to touch the SQL objects again.

**Verify** in the ADF Studio (Author tab) that both pipelines appear, or via PowerShell:

```powershell
Get-AzDataFactoryV2Pipeline -ResourceGroupName "rg-dmap-adf" -DataFactoryName "adf-dmap-poc" |
    Where-Object { $_.Name -like 'PL_Sync*' } | Select-Object Name
```

---

## 5. Configure a table to sync

### 5.1 Fastest path: use the built-in `dbo.CI_AIC` test table

Re-run the deploy script with `-DeployTestTable` (in addition to the parameters from step 3/4) to
create `dbo.CI_AIC` (InstanceName/AICClassification/ShortDescription/ServiceOwnerName/
LinkedApplicationOwner/ProductOwner/InsertDate) with 5 dummy rows on **Dev, Tst, Acc, and Prd**,
and seed a `mig.SyncConfiguration` row for it (non-environment-specific, `BusinessKeyColumns =
InstanceName`):

```powershell
.\deploy-synchronise.ps1 -DeployTestTable `
    -DevServerInstance "dmap-dev-sql.database.windows.net" -TstServerInstance "dmap-tst-sql.database.windows.net" `
    -AccServerInstance "dmap-acc-sql.database.windows.net" -PrdServerInstance "dmap-prd-sql.database.windows.net" `
    -UseIntegratedSecurity:$false -Credential (Get-Credential)
```

**Verify** the table and dummy rows exist on all four servers, and the config exists on Prd:

```sql
SELECT * FROM dbo.CI_AIC;                 -- run against Dev, Tst, Acc, and Prd
SELECT * FROM mig.SyncConfiguration WHERE SourceTable = 'CI_AIC';  -- Prd only
```

Skip straight to section 6, using the `CI_AIC` configuration's `SyncConfigurationId`.

### 5.2 Or point at your own real tables

Adjust the placeholder sample rows from `04_sample_sync_configuration_data.sql` (adjust to your
schema):

```sql
-- Environment-specific example
UPDATE mig.SyncConfiguration
SET SourceSchema = 'dbo', SourceTable = 'YourEnvSpecificTable',
    TargetSchema = 'dbo', TargetTable = 'YourEnvSpecificTable',
    EnvironmentColumn = 'Environment', BusinessKeyColumns = 'Id'
WHERE SourceTable = 'EnvSpecificConfig';

-- Non-environment-specific example
UPDATE mig.SyncConfiguration
SET SourceSchema = 'dbo', SourceTable = 'YourReferenceTable',
    TargetSchema = 'dbo', TargetTable = 'YourReferenceTable',
    BusinessKeyColumns = 'Code'
WHERE SourceTable = 'ReferenceData';
```

Make sure the corresponding table exists (with matching columns) on the Prd server and on each
lower environment server you intend to test against.

---

## 6. Test 1 — Sync a single table to a single environment

```powershell
$configId = (Invoke-Sqlcmd -ServerInstance "dmap-prd-sql.database.windows.net" -Database DMAP `
    -Query "SELECT SyncConfigurationId FROM mig.SyncConfiguration WHERE SourceTable = 'YourReferenceTable'").SyncConfigurationId

Invoke-AzDataFactoryV2Pipeline -ResourceGroupName "rg-dmap-adf" -DataFactoryName "adf-dmap-poc" `
    -PipelineName PL_SyncProdToLowerEnvironment `
    -Parameters @{ ConfigurationId = $configId; TargetEnvironment = "dev" }
```

**Verify:**

```sql
SELECT TOP 1 * FROM mig.SyncRun ORDER BY SyncRunId DESC;
```

Expected: `SyncStatus = 'SUCCESS'`, `CompletedAt` populated. Then confirm the rows landed in the
Dev database's target table.

---

## 7. Test 2 — Run the full batch (all active configs x all environments)

```powershell
Invoke-AzDataFactoryV2Pipeline -ResourceGroupName "rg-dmap-adf" -DataFactoryName "adf-dmap-poc" `
    -PipelineName PL_SyncAllProdToLowerEnvironments
```

**Verify:**

```sql
SELECT * FROM mig.SyncMasterRun ORDER BY SyncMasterRunId DESC;
SELECT * FROM mig.SyncRun WHERE BatchId = (SELECT TOP 1 BatchId FROM mig.SyncMasterRun ORDER BY SyncMasterRunId DESC);
```

Expected: one `SyncMasterRun` row with `RunStatus = 'SUCCESS'`, and one `SyncRun` row per active
`SyncConfiguration` x environment combination, all `SyncStatus = 'SUCCESS'`, sharing that
`BatchId`.

---

## 8. Test 3 — Failure is audited (e.g. bad table/column name)

Temporarily point a configuration at a non-existent table or column:

```sql
UPDATE mig.SyncConfiguration SET SourceTable = 'DoesNotExist' WHERE SyncConfigurationId = @configId;
```

Run it (section 6). Expected: the pipeline run in ADF Monitor shows **Failed**, and:

```sql
SELECT TOP 1 SyncStatus, ErrorMessage, CompletedAt FROM mig.SyncRun ORDER BY SyncRunId DESC;
```

shows `SyncStatus = 'ERROR'` with the underlying Copy Activity error message captured. Revert the
change afterwards:

```sql
UPDATE mig.SyncConfiguration SET SourceTable = 'YourReferenceTable' WHERE SyncConfigurationId = @configId;
```

If you ran the full batch (section 7) instead of a single table, check `mig.SyncMasterRun` —
expect `RunStatus = 'FAILED'` for that batch, while the other (successful) rows in `mig.SyncRun`
for that same `BatchId` still show `SUCCESS` (only the failing table/environment fails).

---

## 9. Test 4 — Duplicate business key in Production source (blocked before upsert)

Insert two Production rows sharing the same `BusinessKeyColumns` value:

```sql
INSERT INTO dbo.YourReferenceTable (Code, ...) VALUES ('DUP1', ...), ('DUP1', ...);
```

Run the sync for that configuration (section 6). Expected: the pipeline run **fails** with error
code `DuplicateBusinessKeyInSource` before any Copy Activity runs (no rows are written to the
lower environment). Verify:

```sql
SELECT TOP 1 SyncStatus, ErrorMessage FROM mig.SyncRun ORDER BY SyncRunId DESC;
```

Expect `SyncStatus = 'ERROR'` with `ErrorMessage` mentioning duplicate business keys in the
Production source. Clean up the duplicate rows afterwards.

## 10. Test 5 — Duplicate business key in the lower environment target (blocked after upsert)

Insert two rows sharing the same `BusinessKeyColumns` value directly into the **lower
environment's** target table (simulating a pre-existing duplicate unrelated to this sync):

```sql
-- run against the Dev/Test/Acc server, not Prd
INSERT INTO dbo.YourReferenceTable (Code, ...) VALUES ('DUP2', ...), ('DUP2', ...);
```

Run the sync for that configuration/environment (section 6). Expected: the Copy Activity
(upsert) still runs, but the pipeline **fails afterward** with error code
`DuplicateBusinessKeyInTarget`. Verify with the same query as Test 4 — `SyncStatus = 'ERROR'`.
Clean up the duplicate rows in the lower environment afterwards.

## 11. Where to look when something goes wrong

| Symptom | Check |
|---|---|
| Pipeline not found | Re-run step 4; confirm `-ResourceGroupName`/`-DataFactoryName` are correct. |
| Copy activity fails with a linked service/dataset error | Confirm `../deploy.ps1 -DeployAdf` was run first (see Prerequisites). |
| `SyncStatus = 'ERROR'`, errorCode `DuplicateBusinessKeyInSource` | Duplicate `BusinessKeyColumns` value(s) exist in the Production source (after any environment filter) — dedupe the source before re-running. |
| `SyncStatus = 'ERROR'`, errorCode `DuplicateBusinessKeyInTarget` | Duplicate `BusinessKeyColumns` value(s) exist in the lower-environment target table after the upsert — dedupe the target table. |
| `SyncStatus = 'ERROR'` (other) | Read `mig.SyncRun.ErrorMessage` for that row. |
| Whole batch marked `FAILED` | Check `mig.SyncMasterRun.ErrorMessage`, then drill into `mig.SyncRun` for the same `BatchId` to find which table/environment failed. |
| No rows appear in the lower environment | Confirm `BusinessKeyColumns` matches an actual unique/primary key on the target table (required for `upsert` to work), and that `EnvironmentColumn` is set correctly for environment-specific tables. |
