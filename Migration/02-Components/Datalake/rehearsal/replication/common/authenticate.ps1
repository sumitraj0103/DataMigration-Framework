

$LoadCommonFile = Join-Path `
    $PSScriptRoot `
    "load-common.ps1"

if (-not (Test-Path -LiteralPath $LoadCommonFile)) {
    throw "Load common file not found: $LoadCommonFile"
}

# Load shared functions and $MigrationConfig from this scripts scope.
 . $LoadCommonFile

Write-Host "MigrationConfig is null? $($null -eq $MigrationConfig)"

connect-AzureCli

$ExpectedAzureSubscription = Get-SubscriptionName `
    -NamingConventionsFile $NamingConventions

$account = Set-ExpectedAzureSubscription `
    -ExpectedSubscription $ExpectedAzureSubscription

write-Host "Expected Subscription: $ExpectedAzureSubscription matches Current Subscription: $($account.name)"

