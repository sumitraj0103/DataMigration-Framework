<#
.SYNOPSIS
    Deploys the SQL/database side of Strategy 2 (Prod -> Lower Environment Synchronization):
    mig.SyncConfiguration / mig.SyncRun / mig.SyncMasterRun tables, sample configuration data, and
    optionally the dbo.CI_AIC test table with dummy rows on Dev/Tst/Acc/Prd.

.DESCRIPTION
    Runs the SQL scripts under .\sql (relative to this file, i.e. Synchronise\sql) in order against
    the Prd server. Does not touch ADF -- see .\deploy-synchronise-adf.ps1 for publishing the
    pipelines once this has been run.

    Kept entirely separate from deploy.ps1 / deploy-validate-and-load.ps1 (Strategy 1) so the two
    efforts aren't mixed together.

    Requires the SqlServer PowerShell module (Invoke-Sqlcmd), or sqlcmd.exe as a fallback.

.PARAMETER PrdServerInstance
    SQL Server/Azure SQL instance hosting the Prd (source) environment's DMAP database.
    Defaults to "localhost". For Azure SQL, use "<prd-server-name>.database.windows.net".

.PARAMETER DevServerInstance
    SQL Server/Azure SQL instance hosting the Dev environment's DMAP database. Only used with
    -DeployTestTable. Defaults to "localhost".

.PARAMETER TstServerInstance
    SQL Server/Azure SQL instance hosting the Tst environment's DMAP database. Only used with
    -DeployTestTable. Defaults to "localhost".

.PARAMETER AccServerInstance
    SQL Server/Azure SQL instance hosting the Acc environment's DMAP database. Only used with
    -DeployTestTable. Defaults to "localhost".

.PARAMETER UseIntegratedSecurity
    Use Windows Authentication (default: $true). Set to $false and supply -Credential to use SQL
    auth - required for Azure SQL Database.

.PARAMETER Credential
    SQL authentication credential, used for all servers touched by this script (Prd, and Dev/Tst/Acc
    when -DeployTestTable is set). Only used when -UseIntegratedSecurity:$false.

.PARAMETER SkipSampleData
    Skip 04_sample_sync_configuration_data.sql (tables only, no sample configuration rows).

.PARAMETER DeployTestTable
    Also create the dbo.CI_AIC test table (05_test_table_ci_aic.sql) with dummy rows on Prd AND on
    Dev/Tst/Acc (via -DevServerInstance/-TstServerInstance/-AccServerInstance), then seed a
    non-environment-specific mig.SyncConfiguration row for it on Prd
    (06_sample_sync_configuration_for_ci_aic.sql).

.EXAMPLE
    .\deploy-synchronise-sql.ps1 -PrdServerInstance "dmap-prd-sql.database.windows.net" -UseIntegratedSecurity:$false -Credential (Get-Credential)

.EXAMPLE
    # Also create the dbo.CI_AIC test table + dummy data on all 4 environments, and seed its sync config
    .\deploy-synchronise-sql.ps1 -DeployTestTable `
        -DevServerInstance "dmap-dev-sql.database.windows.net" -TstServerInstance "dmap-tst-sql.database.windows.net" `
        -AccServerInstance "dmap-acc-sql.database.windows.net" -PrdServerInstance "dmap-prd-sql.database.windows.net" `
        -UseIntegratedSecurity:$false -Credential (Get-Credential)
#>
[CmdletBinding()]
param(
    [string]$PrdServerInstance = "localhost",
    [string]$DevServerInstance = "localhost",
    [string]$TstServerInstance = "localhost",
    [string]$AccServerInstance = "localhost",
    [bool]$UseIntegratedSecurity = $true,
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$SkipSampleData,
    [switch]$DeployTestTable
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sqlRoot = Join-Path $scriptRoot 'sql'
$DmapDatabaseName = "DMAP"

if (-not $UseIntegratedSecurity -and -not $Credential) {
    throw "UseIntegratedSecurity is false but no -Credential was supplied. Pass -Credential (Get-Credential)."
}

function Invoke-SyncSqlScript {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [string]$ServerInstance = $PrdServerInstance
    )

    Write-Host "Running $([System.IO.Path]::GetFileName($Path)) on $ServerInstance / $DmapDatabaseName..." -ForegroundColor Cyan

    $params = @{
        ServerInstance = $ServerInstance
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
        $sqlcmdArgs = @('-S', $ServerInstance, '-d', $DmapDatabaseName, '-i', $Path, '-b')
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

Write-Host "=== Strategy 2 (Prod -> Lower Environment Synchronization) SQL deployment ===" -ForegroundColor Green
Write-Host "Prd server: $PrdServerInstance / database: $DmapDatabaseName"

Invoke-SyncSqlScript -Path (Join-Path $sqlRoot '01_mig_sync_configuration.sql')
Invoke-SyncSqlScript -Path (Join-Path $sqlRoot '02_mig_sync_run.sql')
Invoke-SyncSqlScript -Path (Join-Path $sqlRoot '03_mig_sync_master_run.sql')

if (-not $SkipSampleData) {
    Invoke-SyncSqlScript -Path (Join-Path $sqlRoot '04_sample_sync_configuration_data.sql')
}
else {
    Write-Host "Skipping sample sync configuration data (-SkipSampleData specified)." -ForegroundColor Yellow
}

if ($DeployTestTable) {
    Write-Host "=== Creating dbo.CI_AIC test table + dummy data on Dev/Tst/Acc/Prd ===" -ForegroundColor Green
    $ciAicScript = Join-Path $sqlRoot '05_test_table_ci_aic.sql'
    foreach ($server in @($DevServerInstance, $TstServerInstance, $AccServerInstance, $PrdServerInstance)) {
        Invoke-SyncSqlScript -Path $ciAicScript -ServerInstance $server
    }
    Invoke-SyncSqlScript -Path (Join-Path $sqlRoot '06_sample_sync_configuration_for_ci_aic.sql')
}
else {
    Write-Host "Skipping dbo.CI_AIC test table (-DeployTestTable not specified)." -ForegroundColor Yellow
}

Write-Host "=== SQL deployment complete ===" -ForegroundColor Green
Write-Host "Next: run .\deploy-synchronise-adf.ps1 -ResourceGroupName <rg> -DataFactoryName <adf> to publish the pipelines."
