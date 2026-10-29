<#
.SYNOPSIS
    Publishes the Synchronise ADF pipelines (PL_SyncProdToLowerEnvironment,
    PL_SyncAllProdToLowerEnvironments) into the existing, real Azure Data Factory instance:
    MSC-DAF-DMAPSB-MGPOC (RG: MSC-RSG-DMAPSB-TRACC, subscription: MSC-SUB-INFRASTRUCTURE).

.DESCRIPTION
    REAL-environment counterpart of .\deploy-synchronise-adf.ps1 (learning/exploration POC).
    Only publishes the two pipelines under .\adf\pipelines - it reuses the linked
    services/datasets already published by ..\deploy-real-environment.ps1 (LS_ProdSqlMig,
    LS_SourceSqlMig_Dev/Test/Acc, DS_StagingTableMig, DS_SourceTableMig_Dev/Test/Acc), so that
    script must be run first. Does not touch SQL - see .\deploy-synchronise-sql-production.ps1
    for the mig.SyncConfiguration/SyncRun/SyncMasterRun schema.

    Uses the same saved Az context file as ..\deploy-real-environment.ps1
    ("$env:USERPROFILE\.azcontext-dmap-real.json") so switching between the learning and real
    environments never requires re-authenticating.

.PARAMETER SubscriptionId
    Azure subscription containing the Data Factory. Defaults to "c47bfe3d-881a-4142-bf65-ec835858a67b"
    (MSC-SUB-INFRASTRUCTURE).

.PARAMETER ResourceGroupName
    Resource group of the existing Data Factory. Defaults to "MSC-RSG-DMAPSB-TRACC".

.PARAMETER DataFactoryName
    Name of the existing Data Factory instance. Defaults to "MSC-DAF-DMAPSB-MGPOC".

.PARAMETER TenantId
    Azure AD tenant of the real environment account. Pass this the first time (or whenever you
    need to switch accounts) so the script signs you in with the right tenant/account. Defaults
    to "07751f8b-9617-49d5-9024-85f034f400ec".

.PARAMETER AccountId
    Azure AD user/service principal to sign in as for the real environment.

.PARAMETER ContextFile
    Path to the saved Az context file shared with ..\deploy-real-environment.ps1, so this
    environment's login stays separate from the learning environment's login.
    Defaults to "$env:USERPROFILE\.azcontext-dmap-real.json".

.EXAMPLE
    .\deploy-synchronise-adf-real-environment.ps1

.EXAMPLE
    .\deploy-synchronise-adf-real-environment.ps1 -AccountId "AZ-RajS1@connect2dll.onmicrosoft.com"
#>
[CmdletBinding()]
param(
    [string]$SubscriptionId = "c47bfe3d-881a-4142-bf65-ec835858a67b",
    [string]$ResourceGroupName = "MSC-RSG-DMAPSB-TRACC",
    [string]$DataFactoryName = "MSC-DAF-DMAPSB-MGPOC",

    [string]$TenantId = "07751f8b-9617-49d5-9024-85f034f400ec",
    [string]$AccountId,
    [string]$ContextFile = "$env:USERPROFILE\.azcontext-dmap-real.json"
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$adfPipelinesRoot = Join-Path $scriptRoot 'adf\pipelines'

if (-not (Get-Module -ListAvailable -Name Az.DataFactory)) {
    throw "Az.DataFactory module not found. Install it with: Install-Module Az.DataFactory -Scope CurrentUser"
}
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw "Az.Accounts module not found. Install it with: Install-Module Az.Accounts -Scope CurrentUser"
}

# Reuse the same saved context as deploy-real-environment.ps1 - isolated from the learning
# environment's default/shared Az session.
if (Test-Path $ContextFile) {
    Import-AzContext -Path $ContextFile | Out-Null
}
if ($TenantId -or $AccountId -or -not (Get-AzContext)) {
    $connectArgs = @{}
    if ($TenantId) { $connectArgs.Tenant = $TenantId }
    if ($AccountId) { $connectArgs.AccountId = $AccountId }
    Connect-AzAccount @connectArgs | Out-Null
}
Set-AzContext -Subscription $SubscriptionId -Tenant $TenantId | Out-Null
Save-AzContext -Path $ContextFile -Force | Out-Null

Write-Host "=== DMAP real environment Synchronise ADF deployment ===" -ForegroundColor Green
Write-Host "Subscription: $SubscriptionId / RG: $ResourceGroupName / ADF: $DataFactoryName"

$adf = $null
for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $adf = Get-AzDataFactoryV2 -ResourceGroupName $ResourceGroupName -Name $DataFactoryName -ErrorAction Stop
        break
    }
    catch {
        if ($attempt -eq 3) { throw }
        Write-Host "Retrying Data Factory lookup ($attempt/3)..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
    }
}
Write-Host "Found existing Data Factory '$($adf.DataFactoryName)' in '$($adf.Location)'." -ForegroundColor Cyan

Write-Host "Publishing Synchronise pipelines..." -ForegroundColor Cyan
# PL_SyncAllProdToLowerEnvironments references PL_SyncProdToLowerEnvironment, so publish the
# referenced pipeline first.
$pipelineFiles = Get-ChildItem $adfPipelinesRoot -Filter '*.json'
$pipelineFiles = $pipelineFiles | Sort-Object -Property @{ Expression = { (Get-Content $_.FullName -Raw) -match 'PipelineReference' } }, Name
foreach ($file in $pipelineFiles) {
    $name = $file.BaseName
    Set-AzDataFactoryV2Pipeline -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -DefinitionFile $file.FullName -Force | Out-Null
    Write-Host "  Pipeline: $name"
}

Write-Host "=== Real environment Synchronise ADF deployment complete ===" -ForegroundColor Green
Write-Host "Run e.g.: Invoke-AzDataFactoryV2Pipeline -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -PipelineName PL_SyncAllProdToLowerEnvironments"
