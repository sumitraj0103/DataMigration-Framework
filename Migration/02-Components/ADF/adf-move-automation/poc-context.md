# ADF Cross-Resource-Group Move — Automation Plan

## Objective
Move an Azure Data Factory (ADF) instance from one resource group to another resource group within the same subscription, while preserving all functionality (RBAC access, connected resources, triggers), via an automated process.

## Automation Steps

1. **Discovery — Capture current access/role assignments**
   - Enumerate all RBAC role assignments scoped to the ADF resource itself, and any assignments scoped to the current resource group that apply to the ADF's managed identity (system-assigned or user-assigned).
   - Also enumerate role assignments granted *to* the ADF's managed identity on other resources (e.g., Storage Account, SQL Server/Database, Key Vault) — these are the permissions ADF needs on downstream resources, not permissions on ADF itself.
   - Record: principal ID, role definition, scope, for later reassignment.

2. **Run the Azure Resource Move**
   - Use `az resource move` / Azure Resource Mover to move the ADF resource from the source resource group to the target resource group.
   - Note: resource move preserves the resource's identity (object ID for system-assigned managed identity stays the same), but role assignments scoped to the *old resource group* will no longer apply, and any role assignments scoped directly to the ADF resource ID may need to be re-validated since the resource ID path changes (new RG in the ID).

3. **Reassign Access**
   - Re-create role assignments captured in step 1 against the new resource ID / new resource group scope as needed.
   - Since the managed identity's object ID is unchanged (for system-assigned identity), role assignments on *downstream* resources (Storage, SQL, Key Vault, Logic Apps, etc.) that reference the identity by object ID typically remain valid and don't need to be recreated — but assignments scoped to the *old RG* on ADF itself do need recreating in the new RG.
   - Verify Key Vault access policies (if using access policies instead of RBAC) still reference the correct identity.

4. **Post-move validation / manual steps**
   - If triggers were stopped prior to the move, manually restart/re-activate all triggers (tumbling window, schedule, event-based) after the move completes.
   - Validate Managed Private Endpoints / Integration Runtime connectivity if applicable.
   - Validate Event Grid subscriptions / system topics still fire correctly (ADF's identity is the subscriber in some designs).

## Known Dependencies (from prior investigation)
- ADF needs access to the Storage Account (data movement, staging).
- ADF needs access to the Database (Azure SQL).

## Connected Resources Inventory
Source: [Test-ADF-Connected-Resource.csv](Test-ADF-Connected-Resource.csv)

All resources currently sit in resource group `msc-rsg-dmap-tst`, subscription `c47bfe3d-881a-4142-bf65-ec835858a67b`.

| Resource Type | Resource Name(s) | Suggested Post-Move Action |
|---|---|---|
| Smart Detector Alert Rules | Failure Anomalies - MSC-AIS-DMAP-TST(-API) | No action — these alert on App Insights components, not ADF directly; verify they still resolve target resource IDs after move. |
| Event Grid System Topics | mscstadmaptst-*, mscstadmaptst03-* | These are topics on Storage Accounts (blob events), not ADF — no change needed unless ADF is an event subscriber; verify event subscriptions pointing to ADF/pipelines still work. |
| Action Group | DMAPAG | No change — used by alert rules, not tied to ADF resource ID directly. |
| Application Insights | MSC-AIS-DMAP-TST, MSC-AIS-DMAP-TST-API | No change needed unless ADF pipeline diagnostics push here; verify diagnostic settings on ADF still point to correct workspace/App Insights after move. |
| Metric Alerts | "More than 1TB ingested", "whenadfpipelinefailed" | **Action required** — these likely scope directly to the ADF resource ID; update alert rule scope/target resource ID to the new resource ID post-move. |
| Scheduled Query Rules | DMAP API - 500 Failure on endpoint | Verify scope; update if it references old ADF resource ID. |
| Key Vault | MSC-KVA-DMAP-TST | **Action required** — if using access policies (not RBAC), confirm ADF's managed identity (object ID unchanged) still has an access policy entry; if using RBAC, recreate role assignment scoped to Key Vault only if it was scoped via the old ADF resource ID (uncommon) — typically no change needed since object ID persists. |
| Logic Apps | MSC-LOG-DMAP-TST-FOLDERMAPPING, MSC-LOG-PBI-CAPACITY-MAIL-ALERT-TST, MSC-LOG-RBAC-TST | Verify any Logic App that triggers ADF pipelines (via HTTP call to ADF REST API with resource ID) is updated to reference the new resource group/resource ID. `MSC-LOG-RBAC-TST` in particular may automate RBAC assignment — review/update its logic if it hardcodes ADF resource ID or RG name. |
| Dashboard | Portal dashboard 92557bb8-... | **Action required** — update tile references/resource IDs pinned to ADF if the dashboard breaks after move. |
| Resource Graph Query | MSC-ARG-DMAP-TST-RESOURCELIST | Review query — if it filters by resource group name, update to include new RG. |
| SQL Server / Databases | msc-ssr-dmap-tst, DMAP, master | **Action required** — confirm ADF managed identity still has the SQL role/user mapping (identity object ID unchanged, so typically no change needed); verify firewall rules / VNet rules if RG-scoped. |
| Storage Accounts | mscstadmaptst, mscstadmaptst01, mscstadmaptst03 | **Action required** — confirm RBAC role assignments (e.g., Storage Blob Data Contributor) granted to ADF's managed identity remain valid (object ID unchanged = no recreation needed); if assignments were scoped at RG level for the old RG, ADF loses that inherited access and a new assignment is needed in the new RG or directly on the storage accounts. |
| Web/API Connections (Logic App connectors) | azureblobtst, excelonlinebusinesstst, keyvaulttst, office365(tst), sharepointonlinetst, sql(tst), visualstudioteamservicestst | No direct action for ADF move — these belong to Logic Apps, not ADF; only relevant if Logic Apps are being moved together. |
| App Service Plans | MSC-ASP-DMAP-TST, MSC-ASP-DMAP-TST-API | No action — unrelated to ADF unless hosting a companion API used by pipelines. |
| Web Apps / Function Apps | MSC-FUA-DMAP-TST, MSC-FUA-DMAP-TST-API | Verify any Web/Function App that calls ADF's REST API (e.g., to trigger pipelines) uses the updated resource ID/RG in its configuration. |

## Azure DevOps Pipeline (Agent-Run Automation)

Instead of running `Move-ADF.ps1` manually from a local machine, an Azure DevOps YAML pipeline (`azure-pipelines.yml`) runs it on a Microsoft-hosted agent and publishes the audit artifacts for download.

Key points:
- **Trigger**: `trigger: none` — the pipeline is run on-demand (manually queued) rather than on every commit, since this is a one-off/controlled operation.
- **Parameters** (supplied when queuing the run): `sourceResourceGroupName`, `targetResourceGroupName`, `dataFactoryName`, `subscriptionId` (optional), `whatIf` (defaults to `true` for a dry run), and `azureServiceConnection` (the Azure DevOps service connection with permissions on the subscription/RGs).
- **Agent**: `windows-latest` Microsoft-hosted pool (PowerShell + Az modules needed).
- **Steps**:
  1. Ensure `Az.Accounts`, `Az.Resources`, `Az.DataFactory` modules are installed on the agent.
  2. Run `Move-ADF.ps1` via the `AzurePowerShell@5` task, authenticating through the service connection (no local login/credentials needed) and writing audit CSVs to `$(Build.ArtifactStagingDirectory)/adf-move-audit`.
  3. Publish that folder as a pipeline artifact named `adf-move-audit` (runs even if the script fails, via `condition: always()`), so the CSVs (role assignments before/after, triggers running before move) can be downloaded from the pipeline run summary.
- **Service connection**: requires an Azure Resource Manager service connection (service principal or workload identity federation) scoped to the subscription, with RBAC sufficient to read/move the ADF and manage role assignments.
- **Safety**: `whatIf` parameter is `true` by default so the first run can be validated before performing an actual move (requires `Move-ADF.ps1` to honor `-WhatIf` via `SupportsShouldProcess`, which it already declares).

See [azure-pipelines.yml](azure-pipelines.yml).

## Open Items to Clarify
- Confirm whether ADF uses a system-assigned or user-assigned managed identity (affects whether object ID persists through the move).
- Confirm whether any RBAC assignments are scoped at the resource-group level (inherited) vs. resource level (explicit) — RG-level assignments will need to be explicitly recreated in the new RG.
- Confirm which triggers must be manually stopped before move and restarted after (tumbling window triggers in particular cannot be moved while running).