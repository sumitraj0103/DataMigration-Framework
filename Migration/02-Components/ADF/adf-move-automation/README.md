# How to Run Move-ADF.ps1

## Prerequisites
- PowerShell 7+ (recommended) or Windows PowerShell 5.1.
- Az PowerShell modules installed:
  ```powershell
  Install-Module Az.Accounts, Az.Resources, Az.DataFactory -Scope CurrentUser
  ```
- An account with sufficient permissions:
  - `Owner` or `User Access Administrator` + `Contributor` on both the source and target resource groups (needed to move resources and to read/create role assignments).
- The target resource group must already exist.

## 1. Sign in and select the subscription
```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId "<subscription-id>"
```

## 2. Dry run first (recommended)
Use `-WhatIf` to preview every action (role assignment discovery is still executed and audited, but no triggers are stopped/started, no move happens, and no role assignments are created):
```powershell
./Move-ADF.ps1 `
  -SourceResourceGroupName "msc-rsg-dmap-tst" `
  -TargetResourceGroupName "msc-rsg-dmap-tst-new" `
  -DataFactoryName "msc-adf-dmap-tst" `
  -WhatIf
```

## 3. Run for real
```powershell
./Move-ADF.ps1 `
  -SourceResourceGroupName "msc-rsg-dmap-tst" `
  -TargetResourceGroupName "msc-rsg-dmap-tst-new" `
  -DataFactoryName "msc-adf-dmap-tst"
```

Optional parameters:
- `-SubscriptionId "<id>"` — pass instead of calling `Set-AzContext` beforehand.
- `-LogPath "C:\some\folder"` — where audit CSVs are written (defaults to the script's own folder).

## 4. What happens, in order
1. **Discover** — reads role assignments scoped to the ADF resource and to the source resource group (for ADF's managed identity), and records currently running triggers.
2. **Stop triggers** — stops any running triggers (required before a move).
3. **Move** — moves the ADF resource into the target resource group.
4. **Reassign** — recreates the captured role assignments against the new resource ID / target resource group scope.
5. **Restart triggers** — restarts the triggers that were running before the move.

## 5. Check the output
A timestamped folder `adf-move-audit-yyyyMMdd-HHmmss` is created next to the script (or under `-LogPath`), containing:
- `adf-resource-scoped-assignments.csv` — who had access to the ADF resource before the move.
- `adf-identity-rg-scoped-assignments.csv` — RG-level access ADF's identity had before the move.
- `triggers-running-before-move.csv` — triggers that were running before the move.
- `role-assignments-recreated.csv` — role assignments recreated after the move.

Review these to confirm nothing was missed, and check the console output for a `Move complete.` message and the final `ADF move complete.` summary.

## 6. Post-run validation
- Confirm all previously running triggers show `Started` in the new resource group:
  ```powershell
  Get-AzDataFactoryV2Trigger -ResourceGroupName "msc-rsg-dmap-tst-new" -DataFactoryName "msc-adf-dmap-tst" | Select TriggerName, RuntimeState
  ```
- Spot-check downstream resources (Storage Account, SQL Database, Key Vault) still allow the ADF managed identity to connect (object ID is unchanged by the move, so this is usually unaffected).
- Review the "Open Items to Clarify" and "Connected Resources Inventory" sections in [poc-context.md](poc-context.md) for resources that need manual follow-up (alert rule scopes, dashboards, Logic Apps referencing the old resource ID).

## Troubleshooting
- **"ADF has no managed identity"** — the script exits early; enable a system-assigned identity on the ADF before moving, or adjust the script if a user-assigned identity is used.
- **Move-AzResource fails with dependency errors** — some resources (e.g., linked private endpoints) may block a move; check the error detail for the blocking resource type.
- **New-AzRoleAssignment "already exists" errors** — safe to ignore if re-running the script after a partial failure; the assignment is already in place.

## Rehearsing the move on a disposable test environment (POC run)
Use [New-TestEnvironment.ps1](New-TestEnvironment.ps1) to stand up a throwaway environment that mirrors `PL_Data_Ingestion`'s
real dependencies (SQL table/stored proc, landing zone/backup/ADLS Gen2 storage accounts, linked services, datasets, the
pipeline itself), so you can run a POC of [Move-ADF.ps1](Move-ADF.ps1) without touching production resources.

```powershell
Connect-AzAccount
$sqlPwd = Read-Host "SQL admin password" -AsSecureString
./New-TestEnvironment.ps1 -TestResourceGroupName "rg-adfmove-test-src" -TestTargetResourceGroupName "rg-adfmove-test-dst" -AdfName "adf-move-poc01" -Location "canadacentral" -SqlAdminPassword $sqlPwd
```

This creates two resource groups (source + empty target), the storage/SQL dependencies, the test ADF with its
managed identity granted access, deploys the linked services/datasets/pipeline, seeds a sample file, and triggers one
pipeline run to confirm the setup works end to end.

Optional parameters:
- `-Suffix "<value>"` — fixed suffix used for resource names (storage accounts, SQL server). If omitted, one is derived deterministically from `-TestResourceGroupName` so reruns reuse the same names.
- `-SqlAdminUser "<name>"` — SQL admin username (defaults to `adfmoveadmin`).
- `-PipelineSourcePath "<path>"` — path to the DataFactory ARM-export folder containing pipeline/dataset/linkedService/trigger subfolders.

Then run the POC move exactly as you would for real:
```powershell
./Move-ADF.ps1 -SourceResourceGroupName "rg-adfmove-test-src" -TargetResourceGroupName "rg-adfmove-test-dst" -DataFactoryName "adf-move-poc01" -WhatIf
./Move-ADF.ps1 -SourceResourceGroupName "rg-adfmove-test-src" -TargetResourceGroupName "rg-adfmove-test-dst" -DataFactoryName "adf-move-poc01"
```

Clean up afterwards with [Remove-TestEnvironment.ps1](Remove-TestEnvironment.ps1):
```powershell
./Remove-TestEnvironment.ps1 -TestResourceGroupName "rg-adfmove-test-src" -TestTargetResourceGroupName "rg-adfmove-test-dst"
```

Requires the additional `Az.Sql` and `Az.Storage` modules:
```powershell
Install-Module Az.Sql, Az.Storage -Scope CurrentUser
```
