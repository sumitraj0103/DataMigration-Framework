param (
    [Parameter(Mandatory=$true)]
    [string]$ResourceName,

    [Parameter(Mandatory=$true)]
    [string]$SourceResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$TargetResourceGroup
)

$PowerShellRoot = Split-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -Parent

$AuthenticationFile = Join-Path `
    -Path $PowerShellRoot `
    -ChildPath "common\authenticate.ps1"

if (-not (Test-Path -LiteralPath $AuthenticationFile)) {
    throw "Authentication file not found: $AuthenticationFile"
}
# $LoadCommonFile = Join-Path `
#     -Path $PSScriptRoot `
#     -ChildPath "common\load-common.ps1"

# Load Authentication script to ensure the user is authenticated and the correct subscription is set
. $AuthenticationFile


Write-Host ""
Write-Host "Storage Account Move"
Write-Host "--------------------"
Write-Host "Resource Name: $ResourceName"
Write-Host "Source Resource Group: $SourceResourceGroup"
Write-Host "Target Resource Group: $TargetResourceGroup"

# Get Storage Account Id
$StorageAccountId = az storage account show `
    --name $ResourceName `
    --resource-group $SourceResourceGroup `
    --query "id" `
    --output tsv

if (-not $StorageAccountId) {
    throw "Storage Account '$ResourceName' not found in resource group '$SourceResourceGroup'."
}

Write-Host ""
Write-Host "Storage Account ID:"
Write-Host $StorageAccountId

# Get the source resource group ID
$SourceResourceGroupId = az group show `
    --name $SourceResourceGroup `
    --query "id" `
    --output tsv

if (-not $SourceResourceGroupId) {
    throw "Source Resource Group '$SourceResourceGroup' not found."
}

Write-Host "Source Resource Group ID: $SourceResourceGroupId"

# Get the target resource group ID
$TargetResourceGroupId = az group show `
    --name $TargetResourceGroup `
    --query "id" `
    --output tsv

if (-not $TargetResourceGroupId) {
    throw "Target Resource Group '$TargetResourceGroup' not found."
}

Write-Host "Target Resource Group ID: $TargetResourceGroupId"

# Get the current subscription ID
$SubscriptionId = az account show `
    --query "id" `
    --output tsv

if (-not $SubscriptionId) {
    throw "Failed to retrieve the current subscription ID."
}

Write-Host "Subscription ID: $SubscriptionId"

$ValidateUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$SourceResourceGroup/validateMoveResources?api-version=2021-04-01"
$ValidationFile = Join-Path $PSScriptRoot "validate-move.json"
$ValidationBody = @{
    resources = @(
        $StorageAccountId
    )
    targetResourceGroup = $TargetResourceGroupId
} 

$ValidationBody | 
    ConvertTo-Json -Depth 5 | 
    Set-Content -Path $ValidationFile -Encoding utf8

Write-Host "Validating move..."

az rest `
    --method POST `
    --uri $ValidateUri `
    --body "@$ValidationFile"

if ($LASTEXITCODE -ne 0) {
    throw "Validation of the move operation failed."
}
Write-Host "Move validation succeeded."

Write-Host ""
Write-Host "Moving Storage Account..."
Write-Host "From: $SourceResourceGroup"
Write-Host "To: $TargetResourceGroup"

# Move the storage account to the target resource group
az resource move `
    --ids $StorageAccountId `
    --destination-group $TargetResourceGroup `

if ($LASTEXITCODE -ne 0) {
    throw "Storage Account move failed."
}
Write-Host "Storage Account '$ResourceName' has been moved to Resource Group '$TargetResourceGroup'."

# Verify storage account landed
$MovedStorageAccountId = az storage account show `
    --name $ResourceName `
    --resource-group $TargetResourceGroup `
    --query "id" `
    --output tsv

if (-not $MovedStorageAccountId) {
    throw "Storage Account '$ResourceName' was not found in Target Resource Group '$TargetResourceGroup' after move."
}

Write-Host ""
Write-Host "Move completed successfully."
Write-Host "New Storage Account ID:"
Write-Host $MovedStorageAccountId

# Verify that the storage account no longer exists in the source resource group
$SourceStorageAccountId = az storage account show `
    --name $ResourceName `
    --resource-group $SourceResourceGroup `
    --query "id" `
    --output tsv 2>$null

if ($SourceStorageAccountId) {
    throw "Storage Account '$ResourceName' still exists in Source Resource Group '$SourceResourceGroup' after move."
}

Write-Host "Source storage account no longer exists in Resource Group '$SourceResourceGroup'."