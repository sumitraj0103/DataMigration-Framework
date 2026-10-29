<#
.SYNOPSIS
    Manually runs mig.usp_RefreshIdentityMapping on the real Prod database for dev, tst and acc.

.DESCRIPTION
    Syncs mig.actual_identity_identities_mapping from each mig_stg_<env>.actual_identity_identities
    staging table (and backfills prd_id from actual_identity.identities), one @Env at a time.
    Does not create any rows in actual_identity.identities - see usp_RefreshIdentityMapping header.

.PARAMETER PrdServerInstance
    Real Prod Azure SQL server FQDN. Defaults to "msc-ssr-dmap-prd.database.windows.net".

.PARAMETER DatabaseName
    Database name on the Prod server. Defaults to "DMAP".

.PARAMETER Envs
    List of @Env values to refresh, in order. Defaults to dev, tst, acc.

.PARAMETER UserName
    AAD user to sign in as. Passed to Connect-AzAccount so the browser/MFA prompt goes straight to
    that account.

.PARAMETER TenantId
    Azure AD tenant to sign in against. Defaults to "07751f8b-9617-49d5-9024-85f034f400ec".

.PARAMETER SubscriptionId
    Azure subscription to select after sign-in. Defaults to "c47bfe3d-881a-4142-bf65-ec835858a67b".

.EXAMPLE
    .\refresh-identity-mapping.ps1 -UserName "AZ-RajS1@connect2dll.onmicrosoft.com"

.EXAMPLE
    .\refresh-identity-mapping.ps1 -Envs 'dev','tst','acc' -UserName "AZ-RajS1@connect2dll.onmicrosoft.com"
#>
[CmdletBinding()]
param(
    [string]$PrdServerInstance = "msc-ssr-dmap-prd.database.windows.net",
    [string]$DatabaseName = "DMAP",
    [string[]]$Envs = @('dev', 'tst', 'acc'),
    [string]$UserName,
    [string]$TenantId = "07751f8b-9617-49d5-9024-85f034f400ec",
    [string]$SubscriptionId = "c47bfe3d-881a-4142-bf65-ec835858a67b"
)

$ErrorActionPreference = 'Stop'

# Checked via -ListAvailable (not Get-Command) so this does NOT trigger PowerShell's module
# auto-load. SqlServer bundles its own old Microsoft.Identity.Client.dll; if it gets imported
# before Connect-AzAccount runs, that stale assembly wins the binding and every Az sign-in fails
# with "Could not load type ...IMsalSFHttpClientFactory".
$sqlServerModuleAvailable = [bool](Get-Module -ListAvailable -Name SqlServer)
$sqlcmdExeAvailable = [bool](Get-Command sqlcmd -ErrorAction SilentlyContinue)
if (-not $sqlServerModuleAvailable -and -not $sqlcmdExeAvailable) {
    throw "Neither the SqlServer PowerShell module nor sqlcmd.exe was found. Install one of them and retry (e.g. Install-Module SqlServer -Scope CurrentUser)."
}
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw "Az.Accounts module not found. Install it with: Install-Module Az.Accounts -Scope CurrentUser"
}

$connectArgs = @{}
if ($TenantId) { $connectArgs.Tenant = $TenantId }
if ($UserName) { $connectArgs.AccountId = $UserName }
$existingContext = Get-AzContext
if (-not $existingContext -or ($UserName -and $existingContext.Account.Id -ne $UserName)) {
    Connect-AzAccount @connectArgs | Out-Null
}
else {
    Write-Host "Reusing existing Az context for $($existingContext.Account.Id) (skip Connect-AzAccount)." -ForegroundColor DarkGray
}
Set-AzContext -Subscription $SubscriptionId -Tenant $TenantId | Out-Null
$sqlAccessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token

if ($sqlServerModuleAvailable) {
    Import-Module SqlServer -ErrorAction SilentlyContinue
}

Write-Host "=== Refreshing mig.actual_identity_identities_mapping on $PrdServerInstance / $DatabaseName ===" -ForegroundColor Green

foreach ($envName in $Envs) {
    Write-Host "Refreshing mapping for @Env = '$envName'..." -ForegroundColor Cyan
    $query = "EXEC mig.usp_RefreshIdentityMapping @Env = N'$envName';"

    if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
        $result = Invoke-Sqlcmd -ServerInstance $PrdServerInstance -Database $DatabaseName -Query $query `
            -AccessToken $sqlAccessToken -ErrorAction Stop
        Write-Host "  RowsMapped: $($result.RowsMapped)" -ForegroundColor DarkGray
    }
    else {
        Write-Host "  SqlServer module not found, falling back to sqlcmd.exe (-G Azure AD auth)" -ForegroundColor Yellow
        $sqlcmdArgs = @('-S', $PrdServerInstance, '-d', $DatabaseName, '-Q', $query, '-G', '-b')
        if ($UserName) { $sqlcmdArgs += @('-U', $UserName) }
        & sqlcmd @sqlcmdArgs
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed with exit code $LASTEXITCODE for @Env = '$envName'" }
    }
}

Write-Host "=== Identity mapping refresh complete for: $($Envs -join ', ') ===" -ForegroundColor Green
