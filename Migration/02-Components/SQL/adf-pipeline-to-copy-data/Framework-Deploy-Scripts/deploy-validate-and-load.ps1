<#
.SYNOPSIS
    Deploys the Use Case 1.2 (Part 2) metadata-driven validation/production-load framework:
    mig.TableConfiguration / mig.ValidationRun / mig.ValidationError / mig.LoadRun /
    mig.MasterRun / mig.StagingLoadRun tables, mig.usp_ValidateTableForProductionLoad /
    mig.usp_LoadValidatedTableToProduction stored procedures, and a sample configuration +
    staging test data row.

.DESCRIPTION
    Runs the SQL scripts under .\sql\validate-and-load in order, against the Prd server only (the
    same server that hosts the mig_stg_<env> staging tables and Production target tables in this
    POC). Independent of deploy.ps1 / sql/00-14 (Part 1, PL_LoadSourceToStaging /
    PL_LoadAllToStaging) -- this script does not touch those.

    Requires the SqlServer PowerShell module (Invoke-Sqlcmd), or sqlcmd.exe as a fallback.

.PARAMETER PrdServerInstance
    SQL Server/Azure SQL instance hosting the Prd (target) environment's DMAP database.
    Defaults to "localhost". For Azure SQL, use "<prd-server-name>.database.windows.net".

.PARAMETER UseIntegratedSecurity
    Use Windows Authentication (default: $true). Set to $false and supply -Credential to use SQL
    auth - required for Azure SQL Database.

.PARAMETER Credential
    SQL authentication credential. Only used when -UseIntegratedSecurity:$false.

.PARAMETER SkipSampleData
    Skip 07_sample_config_and_staging_test_data.sql (tables/stored procedures only, no test data).

.EXAMPLE
    .\deploy-validate-and-load.ps1 -PrdServerInstance "dmap-prd-sql.database.windows.net" -UseIntegratedSecurity:$false -Credential (Get-Credential)

.EXAMPLE
    .\deploy-validate-and-load.ps1
#>
[CmdletBinding()]
param(
    [string]$PrdServerInstance = "localhost",
    [bool]$UseIntegratedSecurity = $true,
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$SkipSampleData
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlRoot = Join-Path $scriptRoot 'sql\validate-and-load'
$DmapDatabaseName = "DMAP"

if (-not $UseIntegratedSecurity -and -not $Credential) {
    throw "UseIntegratedSecurity is false but no -Credential was supplied. Pass -Credential (Get-Credential)."
}

function Invoke-ValidateLoadSqlScript {
    param([Parameter(Mandatory)] [string]$Path)

    Write-Host "Running $([System.IO.Path]::GetFileName($Path)) on $PrdServerInstance / $DmapDatabaseName..." -ForegroundColor Cyan

    $params = @{
        ServerInstance = $PrdServerInstance
        Database       = $DmapDatabaseName
        InputFile      = $Path
        ErrorAction    = 'Stop'
    }
    if (-not $UseIntegratedSecurity) {
        $params.Username = $Credential.UserName
        $params.Password = $Credential.GetNetworkCredential().Password
    }

    if (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) {
        Invoke-Sqlcmd @params
    }
    else {
        Write-Host "  SqlServer module not found, falling back to sqlcmd.exe" -ForegroundColor Yellow
        $sqlcmdArgs = @('-S', $PrdServerInstance, '-d', $DmapDatabaseName, '-i', $Path, '-b')
        if (-not $UseIntegratedSecurity) {
            $sqlcmdArgs += @('-U', $Credential.UserName, '-P', $Credential.GetNetworkCredential().Password)
        }
        & sqlcmd @sqlcmdArgs
        if ($LASTEXITCODE -ne 0) { throw "sqlcmd failed with exit code $LASTEXITCODE for $Path" }
    }
}

if (-not (Get-Command Invoke-Sqlcmd -ErrorAction SilentlyContinue) -and -not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
    throw "Neither the SqlServer PowerShell module nor sqlcmd.exe was found. Install one of them and retry (e.g. Install-Module SqlServer -Scope CurrentUser)."
}

Write-Host "=== Use Case 1.2 (Part 2) validation/load framework deployment ===" -ForegroundColor Green
Write-Host "Prd server: $PrdServerInstance / database: $DmapDatabaseName"

Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '01_mig_table_configuration.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '02_mig_validation_run.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '03_mig_validation_error.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '04_mig_load_run.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '05_usp_validate_table_for_production_load.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '06_usp_load_validated_table_to_production.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '08_mig_master_run.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '09_mig_staging_load_run.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '11_usp_refresh_identity_mapping.sql')
Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '10_identity_family_table_configuration.sql')

if (-not $SkipSampleData) {
    Invoke-ValidateLoadSqlScript -Path (Join-Path $sqlRoot '07_sample_config_and_staging_test_data.sql')
}
else {
    Write-Host "Skipping sample config/staging test data (-SkipSampleData specified)." -ForegroundColor Yellow
}

Write-Host "=== Deployment complete ===" -ForegroundColor Green
Write-Host "See Validate-and-load-Deploy-and-Test-Guide.md for how to run a validation + load test."
