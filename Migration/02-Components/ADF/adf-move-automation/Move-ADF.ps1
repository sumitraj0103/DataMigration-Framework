<#
.SYNOPSIS
    Automates moving an Azure Data Factory (ADF) from one resource group to another
    within the same subscription, preserving RBAC access and trigger state.

.DESCRIPTION
    Runs the following steps in sequence:
      1. Discover  - capture RBAC role assignments scoped to the ADF resource and to the
                     source resource group (for the ADF's managed identity), and record
                     which triggers are currently running.
      2. Prepare   - stop any running triggers (required before an ADF can be moved).
      3. Move      - move the ADF resource to the target resource group.
      4. Reassign  - recreate the captured role assignments against the new scope.
      5. Restart   - restart the triggers that were running before the move.

    All discovered/recreated role assignments and trigger state are exported to CSV
    files under -LogPath for audit purposes.

.PARAMETER SourceResourceGroupName
    Resource group that currently contains the ADF instance.

.PARAMETER TargetResourceGroupName
    Resource group to move the ADF instance into.

.PARAMETER DataFactoryName
    Name of the Azure Data Factory to move.

.PARAMETER SubscriptionId
    Subscription containing both resource groups. Optional - defaults to the current
    Az context subscription. Source and target must be in the same subscription.

.PARAMETER LogPath
    Folder to write audit CSVs (role assignments before/after, trigger state). Defaults
    to the script's folder.

.EXAMPLE
    ./Move-ADF.ps1 -SourceResourceGroupName msc-rsg-dmap-tst -TargetResourceGroupName msc-rsg-dmap-tst-new -DataFactoryName msc-adf-dmap-tst
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$SourceResourceGroupName,

    [Parameter(Mandatory)]
    [string]$TargetResourceGroupName,

    [Parameter(Mandatory)]
    [string]$DataFactoryName,

    [string]$SubscriptionId,

    [string]$LogPath = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$auditFolder = Join-Path $LogPath "adf-move-audit-$timestamp"
New-Item -ItemType Directory -Path $auditFolder -Force -WhatIf:$false | Out-Null

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

# Export-Csv writes nothing at all when piped zero objects, so empty result sets
# need an explicit empty file instead of relying on the pipeline.
# Audit files must always be written, even in -WhatIf mode, so force -WhatIf:$false here.
function Export-AuditCsv {
    param($InputObject, [string]$Path)
    $items = @($InputObject | Where-Object { $_ })
    if ($items.Count -eq 0) {
        "" | Out-File -FilePath $Path -Encoding utf8 -WhatIf:$false
    } else {
        $items | Export-Csv $Path -NoTypeInformation -WhatIf:$false
    }
}

# --- Setup / context -------------------------------------------------------
if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}
$context = Get-AzContext
Write-Host "Using subscription: $($context.Subscription.Id) ($($context.Subscription.Name))"

$adf = Get-AzDataFactoryV2 -ResourceGroupName $SourceResourceGroupName -Name $DataFactoryName
$adfResourceId = $adf.DataFactoryId
$principalId = $adf.Identity.PrincipalId

if (-not $principalId) {
    throw "ADF '$DataFactoryName' has no managed identity; cannot verify/re-map RBAC assignments."
}
Write-Host "ADF resource id: $adfResourceId"
Write-Host "ADF managed identity principal id: $principalId (unchanged by the move)"

# --- Step 1: Discover access --------------------------------------------
Write-Step "Step 1: Discover role assignments and trigger state"

# Assignments scoped directly on the ADF resource (who has access TO adf)
$resourceScopedAssignments = Get-AzRoleAssignment -Scope $adfResourceId |
    Where-Object { $_.Scope -eq $adfResourceId }

# Assignments scoped on the source resource group that apply to ADF's own identity
# (i.e. inherited permissions ADF has on downstream resources via RG-level grants)
$rgScopedAssignmentsForAdfIdentity = Get-AzRoleAssignment -ObjectId $principalId |
    Where-Object { $_.Scope -eq "/subscriptions/$($context.Subscription.Id)/resourceGroups/$SourceResourceGroupName" }

Export-AuditCsv -InputObject $resourceScopedAssignments -Path (Join-Path $auditFolder 'adf-resource-scoped-assignments.csv')
Export-AuditCsv -InputObject $rgScopedAssignmentsForAdfIdentity -Path (Join-Path $auditFolder 'adf-identity-rg-scoped-assignments.csv')

Write-Host "Captured $($resourceScopedAssignments.Count) role assignment(s) scoped to the ADF resource."
Write-Host "Captured $($rgScopedAssignmentsForAdfIdentity.Count) role assignment(s) scoped to the source RG for ADF's identity."

$triggers = Get-AzDataFactoryV2Trigger -ResourceGroupName $SourceResourceGroupName -DataFactoryName $DataFactoryName
$runningTriggers = $triggers | Where-Object { $_.RuntimeState -eq 'Started' }
Export-AuditCsv -InputObject ($runningTriggers | Select-Object @{Name='TriggerName';Expression={$_.Name}}, RuntimeState) -Path (Join-Path $auditFolder 'triggers-running-before-move.csv')
Write-Host "Captured $($runningTriggers.Count) running trigger(s)."

# --- Step 2: Stop running triggers (required before move) ---------------
Write-Step "Step 2: Stop running triggers"
foreach ($trigger in $runningTriggers) {
    if ($PSCmdlet.ShouldProcess($trigger.Name, "Stop trigger")) {
        Stop-AzDataFactoryV2Trigger -ResourceGroupName $SourceResourceGroupName -DataFactoryName $DataFactoryName -Name $trigger.Name -Force
        Write-Host "Stopped trigger: $($trigger.Name)"
    }
}

# --- Step 3: Move the ADF resource ---------------------------------------
Write-Step "Step 3: Move ADF to target resource group"
if ($PSCmdlet.ShouldProcess($adfResourceId, "Move to resource group $TargetResourceGroupName")) {
    # Move-AzResource can fail with "The type initializer for 'ApiVersionCache' threw an
    # exception" due to a broken/conflicting Az.Resources module cache. Call the ARM
    # "moveResources" REST API directly instead, to avoid that cmdlet entirely.
    $moveUri = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$SourceResourceGroupName/moveResources?api-version=2021-04-01"
    $moveBody = @{
        resources         = @($adfResourceId)
        targetResourceGroup = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$TargetResourceGroupName"
    } | ConvertTo-Json

    $moveResponse = Invoke-AzRestMethod -Method POST -Path $moveUri -Payload $moveBody

    if ($moveResponse.StatusCode -eq 202) {
        # Long-running operation - poll the Location header until it completes.
        $asyncUrl = $moveResponse.Headers.GetValues('Location') | Select-Object -First 1
        do {
            Start-Sleep -Seconds 10
            $pollResponse = Invoke-AzRestMethod -Method GET -Uri $asyncUrl
        } while ($pollResponse.StatusCode -eq 202)

        if ($pollResponse.StatusCode -ge 300) {
            throw "ADF move failed: $($pollResponse.StatusCode) $($pollResponse.Content)"
        }
    } elseif ($moveResponse.StatusCode -ge 300) {
        throw "ADF move failed: $($moveResponse.StatusCode) $($moveResponse.Content)"
    }
    Write-Host "Move complete."
}

$newAdfResourceId = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$TargetResourceGroupName/providers/Microsoft.DataFactory/factories/$DataFactoryName"

# --- Step 4: Reassign access ----------------------------------------------
Write-Step "Step 4: Reassign RBAC in the new scope"

$recreated = New-Object System.Collections.Generic.List[object]

# Recreate assignments that were scoped directly on ADF (scope path changes with the RG)
foreach ($ra in $resourceScopedAssignments) {
    if ($PSCmdlet.ShouldProcess($ra.RoleDefinitionName, "Recreate on $newAdfResourceId for $($ra.ObjectId)")) {
        $new = New-AzRoleAssignment -ObjectId $ra.ObjectId -RoleDefinitionName $ra.RoleDefinitionName -Scope $newAdfResourceId
        $recreated.Add($new)
        Write-Host "Recreated '$($ra.RoleDefinitionName)' for $($ra.ObjectId) on $newAdfResourceId"
    }
}

# Recreate ADF-identity assignments that were inherited from the source RG, now on the target RG
# Excluded for now: RG-scoped assignments are reviewed and applied manually instead of being auto-recreated.
# foreach ($ra in $rgScopedAssignmentsForAdfIdentity) {
#     $targetScope = "/subscriptions/$($context.Subscription.Id)/resourceGroups/$TargetResourceGroupName"
#     if ($PSCmdlet.ShouldProcess($ra.RoleDefinitionName, "Recreate on $targetScope for ADF identity")) {
#         $new = New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName $ra.RoleDefinitionName -Scope $targetScope
#         $recreated.Add($new)
#         Write-Host "Recreated '$($ra.RoleDefinitionName)' for ADF identity on $targetScope"
#     }
# }

Export-AuditCsv -InputObject $recreated -Path (Join-Path $auditFolder 'role-assignments-recreated.csv')

# --- Step 5: Restart triggers ---------------------------------------------
Write-Step "Step 5: Restart triggers that were running before the move"
foreach ($trigger in $runningTriggers) {
    if ($PSCmdlet.ShouldProcess($trigger.Name, "Start trigger")) {
        Start-AzDataFactoryV2Trigger -ResourceGroupName $TargetResourceGroupName -DataFactoryName $DataFactoryName -Name $trigger.Name -Force
        Write-Host "Started trigger: $($trigger.Name)"
    }
}

Write-Host "`nADF move complete. Audit files written to: $auditFolder" -ForegroundColor Green
