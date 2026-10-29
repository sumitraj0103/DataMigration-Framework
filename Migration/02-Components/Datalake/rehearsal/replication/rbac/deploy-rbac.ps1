param (
    [Parameter(Mandatory=$true)]
    [string] $ResourceName,

    [Parameter(Mandatory=$true)]
    [string] $ResourceGroup,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Rehearsal", "Migration")]
    [string] $Mode,

    [Parameter(Mandatory=$true)]
    [ValidateSet("DEV", 'TST', 'ACC')]
    [string] $Environment
)

$RbacStrategyFile = Join-Path `
    $PSScriptRoot `
    "rbac-migration-strategy.csv"

if (-not (Test-Path $RbacStrategyFile)) {
    throw "RBAC migration strategy file not found: $RbacStrategyFile"
}

$LoadCommonFile = Join-Path `
    $PSScriptRoot `
    "..\common\load-common.ps1"

. $LoadCommonFile
$ExpectedAzureSubscription = Get-SubscriptionName `
    -NamingConventionsFile $NamingConventions

Write-Host "Subscription: $ExpectedAzureSubscription"

$StorageAccountId = az storage account show `
    --name $ResourceName `
    --resource-group $ResourceGroup `
    --query "id" `
    -o tsv

if (-not $StorageAccountId) {
    throw "Storage account '$ResourceName' was not found in Resource Group '$ResourceGroup'."
}

$StorageAccountId = $StorageAccountId.Trim()

function Get-TargetRbacScope {
    param (
        [Parameter(Mandatory=$true)]
        [string] $ScopeType,
        [string] $StorageAccountId,
        [string] $ContainerName
    )

    $ResourceGroupScope = "/subscriptions/$TargetSubscriptionId/resourceGroups/$ResourceGroup"

    switch ($ScopeType) {

        "ResourceGroup" {
            return $ResourceGroupScope
        }

        "StorageAccount" {
            return $StorageAccountId
        }

        "Container" {
            if ([string]::IsNullOrWhiteSpace($ContainerName)) {
                throw "Container name must be provided for 'Container' scope type."
            }
            return "$StorageAccountId/blobServices/default/containers/$ContainerName"
        }

        default {
            throw "Unsupported RBAC scope type: $ScopeType"
        }
    }
}

$Assignments = Import-Csv $RbacStrategyFile
Write-Host "Total RBAC Assignments to Process: $($Assignments.Count)"


if ($Mode -eq "Rehearsal") {
    # TODO: Rehearsal-only storage Account.
    $SourceStorageAccountName = "mscstadmapdev03"
}
else {
    $SourceStorageAccountName = $ResourceName
}

Write-Host "Mode: $Mode"
Write-Host "Environment: $Environment"
Write-Host "Source Storage Account for strategy filtering: $SourceStorageAccountName"
Write-Host "Target Storage Account: $ResourceName"

$RelevantAssignments = $Assignments | Where-Object {
    $_.principalCategory -ne "ManagedIdentity" -and 
    $_.environment -eq $Environment -and 
    ($_.scopeType -eq "ResourceGroup" -or $_.storageAccountName -eq $SourceStorageAccountName)
}
Write-Host "Selected $($RelevantAssignments.Count) relevant assignments for rehearsal"
Write-Host ""
Write-Host "Strategy breakdown:"
$RelevantAssignments |
    Group-Object Strategy |
    ForEach-Object {
        Write-Host " $($_.Name): $($_.Count)"
    }

# Rehearsal deployment selection
# Resource Group assignments are intentionally not deployed during rehearsal.
$DeployableAssignments = $RelevantAssignments | Where-Object {
    $_.Strategy -in @("Keep", "Reassign") -and 
    (
        $Mode -eq "Migration" -or 
        $_.scopeType -ne "ResourceGroup"
    )
}


$SkippedResourceGroups = $RelevantAssignments | Where-Object {
    $_.scopeType -eq "ResourceGroup"
}

$SkippedByStrategy = $RelevantAssignments | Where-Object {
    $_.scopeType -ne "ResourceGroup" -and 
    $_.Strategy -in @("Skip", "Review")
}

$CreatedCount = 0
$FailedCount = 0

foreach ($Assignment in $DeployableAssignments) {

    $PrincipalId = $null
    $TargetPrincipalName = $null
    $PrincipalType = $Assignment.principalCategory

    if ($Assignment.Strategy -eq "Keep") {
        $PrincipalId = $Assignment.principalId
        $TargetPrincipalName = $Assignment.principalName
    }

    elseif ($Assignment.Strategy -eq "Reassign") {

        if ($Mode -eq "Rehearsal") {
            $TargetPrincipalName = $Assignment.RehearsalEquivalentPrincipal
        }
        else {
            $TargetPrincipalName = $Assignment.ProductionEquivalentPrincipal
        }

        if ([string]::IsNullOrWhiteSpace($TargetPrincipalName)) {
            Write-Warning "Skipping '$($Assignment.principalName)' - target equivalent principal is missing."
            continue
        }

        $PrincipalId = az ad group list `
            --display-name $TargetPrincipalName `
            --query "[0].id" `
            -o tsv

        If ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($PrincipalId)) {
            Write-Warning "Skipping '$($Assignment.principalName)' - could not resolve target equivalent group '$TargetPrincipalName'."
            continue
        }
    }

    $TargetScope = Get-TargetRbacScope `
        -ScopeType $Assignment.scopeType `
        -StorageAccountId $StorageAccountId `
        -ContainerName $Assignment.containerName

    Write-Host ""
    Write-Host "RBAC to deploy:"
    Write-Host " Strategy: $($Assignment.strategy)"
    Write-Host " Source principal: $($Assignment.principalName)"

    if ($Assignment.strategy -eq "Reassign") {
        Write-Host " Target principal: $TargetPrincipalName"
    }

    Write-Host " Principal ID: $PrincipalId"
    Write-Host " Principal type: $PrincipalType"
    Write-Host " Role: $($Assignment.roleName)"
    Write-Host " Scope type: $($Assignment.scopeType)"
    Write-Host " Target scope: $TargetScope"

    az role assignment create `
    --assignee-object-id $PrincipalId `
    --assignee-principal-type $PrincipalType `
    --role $Assignment.roleName `
    --scope $TargetScope

    if ($LASTEXITCODE -ne 0) {
        $FailedCount++
        Write-Warning "Failed to create RBAC assignment for target principal '$TargetPrincipalName'"
    } 

    $CreatedCount++
    Write-Host " Successfully created RBAC assignment for target principal '$TargetPrincipalName' at '$TargetScope' scope"
}

Write-Host ""
Write-Host "==============================================="
Write-Host "Pilot RBAC Assignments Summary"
Write-Host "==============================================="
Write-Host " Created: $CreatedCount"
Write-Host " Failed: $FailedCount"
Write-Host " Relevant assignments: $($RelevantAssignments.Count)"
Write-Host " Deployable assignments: $($DeployableAssignments.Count)"
Write-Host " Skipped by strategy: $($SkippedByStrategy.Count)"
Write-Host " Skipped Resource Groups: $($SkippedResourceGroups.Count)"
Write-Host "==============================================="

if ($FailedCount -gt 0) {
    Write-Host "Some RBAC assignments failed. Please review the failed assignments above."
}