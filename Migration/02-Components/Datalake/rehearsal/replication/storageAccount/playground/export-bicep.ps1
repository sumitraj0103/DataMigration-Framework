$PowerShellRoot = Split-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    # -Parent

# $AuthenticationFile = Join-Path `
#     -Path $PowerShellRoot `
#     -ChildPath "Migration\12-PowerShellTests\common\authenticate.ps1"

# # Write-Host "$AuthenticationFile"
# # write-Host "$PSScriptRoot"

# if (-not (Test-Path -LiteralPath $AuthenticationFile)) {
#     throw "Authentication file not found: $AuthenticationFile"
# }
# $LoadCommonFile = Join-Path `
#     -Path $PSScriptRoot `
#     -ChildPath "common\load-common.ps1"

# # Load Authentication script to ensure the user is authenticated and the correct subscription is set
# . $AuthenticationFile

# # Load shared functions and $MigrationConfig from this scripts scope.
# . $LoadCommonFile

# if ($null -eq $MigrationConfig) {
#     throw "MigrationConfig is null after loading common functions."
# }

# # Get the target storage account name based on the naming conventions defined in the configuration
# $TargetStorageAccount = Get-TargetStorageAccountName `
#     -MigrationConfig $MigrationConfig

# write-Host "Target Storage Account Name: $TargetStorageAccount"

# # Generate the target resource group name based on the naming conventions defined in the configuration
# $TargetResourceGroup = Get-TargetResourceGroupName `
#     -MigrationConfig $MigrationConfig

# Write-Host "Target Resource Group Name: $TargetResourceGroup"

# # Get the resource id of the storage account
# $id = (az resource show -g $TargetResourceGroup -n $TargetStorageAccount --resource-type "Microsoft.Storage/storageAccounts" --query id -o tsv)

# az group export --name $TargetResourceGroup --resource-ids $id --output bicep > "$PSScriptRoot\storageAccount\output\sa-dev03-cloned.json"

$rawJson = Get-Content -Path "$PSScriptRoot\storageAccount\output\sa-dev03-deployment-output.json" -Raw

'{"$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#", "contentVersion": "1.0.0.0", "resources": [{"apiVersion":"2026-04-01",' + $rawJson.TrimStart('{') + '}]}' | Out-File "$PSScriptRoot\storageAccount\output\sa-dev03-cloned.json" -Encoding utf8 -Force

az bicep decompile --file "$PSScriptRoot\storageAccount\output\sa-dev03-cloned.json" --force