<#
.SYNOPSIS
    Single script to create all Synchronise (mig.Sync*) configuration tables on the REAL
    production database, using Azure AD authentication (no SQL login/password).

.DESCRIPTION
    REAL-environment counterpart of .\deploy-synchronise-sql.ps1 (learning/exploration POC).
    Runs, against the real Prod server only, in order:
      sql/01_mig_sync_configuration.sql
      sql/02_mig_sync_run.sql
      sql/03_mig_sync_master_run.sql

    No sample/test data is inserted by default (unlike deploy-synchronise-sql.ps1, which seeds
    sample config rows and an optional dbo.CI_AIC test table for the learning POC) - this script
    only creates the schema objects. Pass -IncludeSampleConfiguration if you specifically want the
    sample mig.SyncConfiguration rows from 04_sample_sync_configuration_data.sql seeded too.

    Uses an Azure AD access token (via Connect-AzAccount / Get-AzAccessToken) passed straight to
    Invoke-Sqlcmd -AccessToken, since the SqlServer module's built-in interactive AAD broker can
    throw a MSAL/WinForms version-mismatch error on some machines. Requires the SqlServer
    PowerShell module (Invoke-Sqlcmd), or sqlcmd.exe (-G) as a fallback.

.PARAMETER PrdServerInstance
    Real Prod Azure SQL server FQDN. Defaults to "msc-ssr-dmap-prd.database.windows.net".

.PARAMETER DatabaseName
    Database name on the Prod server. Defaults to "DMAP".

.PARAMETER UserName
    AAD user to sign in as, e.g. "AZ-RajS1@connect2dll.onmicrosoft.com". Passed to
    Connect-AzAccount so the browser/MFA prompt goes straight to that account.

.PARAMETER TenantId
    Azure AD tenant to sign in against. Defaults to "07751f8b-9617-49d5-9024-85f034f400ec" (the
    real environment's tenant).

.PARAMETER SubscriptionId
    Azure subscription to select after sign-in. Defaults to "c47bfe3d-881a-4142-bf65-ec835858a67b"
    (MSC-SUB-INFRASTRUCTURE).

.PARAMETER IncludeSampleConfiguration
    Also run 04_sample_sync_configuration_data.sql to seed sample mig.SyncConfiguration rows.
    Omitted by default for production.

.PARAMETER RunSchemaDeployment
    Must be passed explicitly to actually run the schema scripts against Prod. Omit this switch
    to do a dry run (no database changes).

.EXAMPLE
    # Dry run - no database changes, just shows what would run.
    .\deploy-synchronise-sql-production.ps1

.EXAMPLE
    # Actually apply the schema changes once ready, same MFA login as SSMS.
    .\deploy-synchronise-sql-production.ps1 -RunSchemaDeployment -UserName "AZ-RajS1@connect2dll.onmicrosoft.com"
#>
[CmdletBinding()]
param(
    [string]$PrdServerInstance = "msc-ssr-dmap-prd.database.windows.net",
    [string]$DatabaseName = "DMAP",
    [string]$UserName,
    [string]$TenantId = "07751f8b-9617-49d5-9024-85f034f400ec",
    [string]$SubscriptionId = "c47bfe3d-881a-4142-bf65-ec835858a67b",
    [switch]$IncludeSampleConfiguration,
    [switch]$RunSchemaDeployment
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlRoot = Join-Path $scriptRoot 'sql'

function Invoke-SyncConfigSqlScript {
    param([Parameter(Mandatory)] [string]$Path)

    Write-Host "Running $([System.IO.Path]::GetFileName($Path)) on $PrdServerInstance / $DatabaseName..." -ForegroundColor Cyan

    if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
        Invoke-Sqlcmd -ServerInstance $PrdServerInstance -Database $DatabaseName -InputFile $Path `
            -AccessToken $sqlAccessToken -ErrorAction Stop
    }
    else {
        Write-Host "  SqlServer module not found, falling back to sqlcmd.exe (-G Azure AD auth)" -ForegroundColor Yellow
        $sqlcmdArgs = @('-S', $PrdServerInstance, '-d', $DatabaseName, '-i', $Path, '-G', '-b')
        if ($UserName) { $sqlcmdArgs += @('-U', $UserName) }
        & sqlcmd @sqlcmdArgs
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed with exit code $LASTEXITCODE for $Path" }
    }
}

if (-not $RunSchemaDeployment) {
    Write-Host "=== Synchronise production configuration deployment (real environment) - DRY RUN ===" -ForegroundColor Yellow
    Write-Host "Skipping all database schema changes (-RunSchemaDeployment not specified)." -ForegroundColor Yellow
    Write-Host "Re-run with -RunSchemaDeployment when you are ready to apply the mig.Sync* schema to $PrdServerInstance / $DatabaseName." -ForegroundColor Yellow
    return
}

if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) -and -not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw "Neither the SqlServer PowerShell module nor sqlcmd.exe was found. Install one of them and retry (e.g. Install-Module SqlServer -Scope CurrentUser)."
}

if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw "Az.Accounts module not found. Install it with: Install-Module Az.Accounts -Scope CurrentUser"
}
$connectArgs = @{}
if ($TenantId) { $connectArgs.Tenant = $TenantId }
if ($UserName) { $connectArgs.AccountId = $UserName }
if (-not (Get-AzContext) -or $UserName -or $TenantId) {
    Connect-AzAccount @connectArgs | Out-Null
}
Set-AzContext -Subscription $SubscriptionId -Tenant $TenantId | Out-Null
$sqlAccessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net/").Token

Write-Host "=== Synchronise production configuration deployment (real environment) ===" -ForegroundColor Green
Write-Host "Prd server: $PrdServerInstance / database: $DatabaseName / auth: Azure AD access token"

Invoke-SyncConfigSqlScript -Path (Join-Path $sqlRoot '01_mig_sync_configuration.sql')
Invoke-SyncConfigSqlScript -Path (Join-Path $sqlRoot '02_mig_sync_run.sql')
Invoke-SyncConfigSqlScript -Path (Join-Path $sqlRoot '03_mig_sync_master_run.sql')

if ($IncludeSampleConfiguration) {
    Invoke-SyncConfigSqlScript -Path (Join-Path $sqlRoot '04_sample_sync_configuration_data.sql')
}

Write-Host "=== Synchronise production configuration deployment complete ===" -ForegroundColor Green
Write-Host "No dbo.CI_AIC test table was created. Populate mig.SyncConfiguration rows for real tables before running PL_SyncAllProdToLowerEnvironments."
