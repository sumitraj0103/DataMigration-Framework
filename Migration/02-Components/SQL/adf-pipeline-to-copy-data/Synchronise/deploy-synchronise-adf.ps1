<#
.SYNOPSIS
    Publishes the ADF side of Strategy 2 (Prod -> Lower Environment Synchronization):
    PL_SyncProdToLowerEnvironment and PL_SyncAllProdToLowerEnvironments.

.DESCRIPTION
    Publishes the pipeline JSON under .\adf\pipelines to an existing Data Factory. This script
    only publishes pipelines -- it reuses the linked services/datasets (LS_ProdSqlMig,
    LS_SourceSqlMig_Dev/Test/Acc, DS_StagingTableMig, DS_SourceTableMig_Dev/Test/Acc) already
    published by ..\deploy.ps1 -DeployAdf, so that must be run first (or those objects must
    already exist in the target Data Factory). Does not touch SQL -- see
    .\deploy-synchronise-sql.ps1 to deploy the mig.SyncConfiguration/SyncRun/SyncMasterRun tables
    first.

    Kept entirely separate from deploy.ps1 / deploy-validate-and-load.ps1 (Strategy 1) so the two
    efforts aren't mixed together.

    Requires the Az.DataFactory module and an authenticated Az session (Connect-AzAccount).

.PARAMETER ResourceGroupName
    Resource group hosting the Data Factory instance.

.PARAMETER DataFactoryName
    Name of the existing Data Factory instance to publish the pipelines to.

.EXAMPLE
    .\deploy-synchronise-adf.ps1 -ResourceGroupName "rg-dmap-adf" -DataFactoryName "adf-dmap-poc"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ResourceGroupName,
    [Parameter(Mandatory)] [string]$DataFactoryName
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$adfPipelinesRoot = Join-Path $scriptRoot 'adf\pipelines'

if (-not (Get-Module -ListAvailable -Name Az.DataFactory)) {
    throw "Az.DataFactory module not found. Install it with: Install-Module Az.DataFactory -Scope CurrentUser"
}

if (-not (Get-AzContext)) {
    throw "No authenticated Az session found. Run Connect-AzAccount first."
}

# Get-AzDataFactoryV2 occasionally fails transiently right after a fresh session/token refresh.
# Retry a few times with a short delay instead of immediately assuming the Data Factory is missing.
$adf = $null
$lastError = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $adf = Get-AzDataFactoryV2 -ResourceGroupName $ResourceGroupName -Name $DataFactoryName -ErrorAction Stop
        break
    } catch {
        $lastError = $_
        if ($attempt -lt 3) {
            Write-Warning "Get-AzDataFactoryV2 attempt $attempt failed ($($_.Exception.Message)); retrying..."
            Start-Sleep -Seconds 5
        }
    }
}
if (-not $adf) {
    if ($lastError) {
        throw "Data Factory '$DataFactoryName' could not be looked up in resource group '$ResourceGroupName' after 3 attempts. Last error: $($lastError.Exception.Message)"
    }
    throw "Data Factory '$DataFactoryName' not found in resource group '$ResourceGroupName'. Create it first with ..\deploy.ps1 -DeployAdf."
}

Write-Host "=== Publishing Synchronise pipelines to Data Factory '$DataFactoryName' ===" -ForegroundColor Green

# PL_SyncAllProdToLowerEnvironments references PL_SyncProdToLowerEnvironment, so publish the
# referenced pipeline first.
$pipelineFiles = Get-ChildItem $adfPipelinesRoot -Filter '*.json'
$pipelineFiles = $pipelineFiles | Sort-Object -Property @{ Expression = { (Get-Content $_.FullName -Raw) -match 'PipelineReference' } }, Name
foreach ($file in $pipelineFiles) {
    $name = $file.BaseName
    Set-AzDataFactoryV2Pipeline -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -DefinitionFile $file.FullName -Force | Out-Null
    Write-Host "  Pipeline: $name"
}

Write-Host "=== ADF deployment complete ===" -ForegroundColor Green
Write-Host "Run e.g.: Invoke-AzDataFactoryV2Pipeline -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -PipelineName PL_SyncAllProdToLowerEnvironments"
