<#
.SYNOPSIS
    Single script to create all migration (mig.*) configuration tables and stored procedures on
    the REAL production database, using Azure AD authentication (no SQL login/password).

.DESCRIPTION
    Runs, against the real Prod server only, in order:
      sql/13_mig_metadata_loadToStaging.sql            - mig.metadata_loadToStaging (PL_LoadAllToStaging)
      sql/14_add_id_to_metadata_lp.sql
      sql/validate-and-load/01_mig_table_configuration.sql
      sql/validate-and-load/02_mig_validation_run.sql
      sql/validate-and-load/03_mig_validation_error.sql
      sql/validate-and-load/04_mig_load_run.sql
      sql/validate-and-load/05_usp_validate_table_for_production_load.sql
      sql/validate-and-load/06_usp_load_validated_table_to_production.sql
      sql/validate-and-load/08_mig_master_run.sql
      sql/validate-and-load/09_mig_staging_load_run.sql
      sql/validate-and-load/11_usp_refresh_identity_mapping.sql
      sql/validate-and-load/10_identity_family_table_configuration.sql

    No test/sample data is inserted (unlike deploy.ps1/deploy-validate-and-load.ps1, which seed
    dummy rows for the learning POC) - this script only creates the schema objects.

    Requires the SqlServer PowerShell module (Invoke-Sqlcmd) with Azure AD auth support, or
    sqlcmd.exe with the -G flag as a fallback. You must be an authenticated Azure AD user/service
    principal with permission to run DDL on the target database (or be added as a db_ddladmin /
    db_owner there beforehand).

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

.PARAMETER RunSchemaDeployment
    Must be passed explicitly to actually run the schema scripts against Prod. Omit this switch
    to do a dry run (no database changes) when you only want to deploy the ADF artifacts for now
    and are not yet ready for the database schema change.

.EXAMPLE
    # Dry run - no database changes, just shows what would run.
    .\deploy-migration-config-production.ps1

.EXAMPLE
    # Actually apply the schema changes once ready, same MFA login as SSMS.
    .\deploy-migration-config-production.ps1 -RunSchemaDeployment -UserName "AZ-RajS1@connect2dll.onmicrosoft.com"
#>
[CmdletBinding()]
param(
    [string]$PrdServerInstance = "msc-ssr-dmap-prd.database.windows.net",
    [string]$DatabaseName = "DMAP",
    [string]$UserName,
    [string]$TenantId = "07751f8b-9617-49d5-9024-85f034f400ec",
    [string]$SubscriptionId = "c47bfe3d-881a-4142-bf65-ec835858a67b",
    [switch]$RunSchemaDeployment
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlRoot = Join-Path $scriptRoot 'sql'
$validateLoadRoot = Join-Path $sqlRoot 'validate-and-load'

function Invoke-MigConfigSqlScript {
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
    Write-Host "=== Production migration configuration deployment (real environment) - DRY RUN ===" -ForegroundColor Yellow
    Write-Host "Skipping all database schema changes (-RunSchemaDeployment not specified)." -ForegroundColor Yellow
    Write-Host "Re-run with -RunSchemaDeployment when you are ready to apply the mig.* schema to $PrdServerInstance / $DatabaseName." -ForegroundColor Yellow
    return
}

# Checked via -ListAvailable (not Get-Command) so this does NOT trigger PowerShell's module
# auto-load. SqlServer bundles its own old Microsoft.Identity.Client.dll; if it gets imported
# before Connect-AzAccount runs, that stale assembly wins the binding and every Az sign-in
# (interactive or device code) fails with "Could not load type ...IMsalSFHttpClientFactory".
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

# Only import SqlServer now, after Az sign-in has already succeeded - safe at this point since
# Connect-AzAccount/Get-AzAccessToken have finished using their own Microsoft.Identity.Client copy.
if ($sqlServerModuleAvailable) {
    Import-Module SqlServer -ErrorAction SilentlyContinue
}

Write-Host "=== Production migration configuration deployment (real environment) ===" -ForegroundColor Green
Write-Host "Prd server: $PrdServerInstance / database: $DatabaseName / auth: Azure AD access token"

Invoke-MigConfigSqlScript -Path (Join-Path $sqlRoot '13_mig_metadata_loadToStaging.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $sqlRoot '14_add_id_to_metadata_lp.sql')

Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '01_mig_table_configuration.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '02_mig_validation_run.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '03_mig_validation_error.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '04_mig_load_run.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '05_usp_validate_table_for_production_load.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '06_usp_load_validated_table_to_production.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '08_mig_master_run.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '09_mig_staging_load_run.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '11_usp_refresh_identity_mapping.sql')
Invoke-MigConfigSqlScript -Path (Join-Path $validateLoadRoot '10_identity_family_table_configuration.sql')

Write-Host "=== Production migration configuration deployment complete ===" -ForegroundColor Green
Write-Host "No sample/test data was inserted. Populate mig.TableConfiguration rows for real tables before running PL_ValidateAndLoadAllToProduction."
