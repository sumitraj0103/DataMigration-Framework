<#
.SYNOPSIS
    Deploys the DMAP pipeline artifacts (linked services, datasets, pipelines, triggers) into the
    existing, real Azure Data Factory instance: MSC-DAF-DMAPSB-MGPOC (RG: MSC-RSG-DMAPSB-TRACC,
    subscription: MSC-SUB-INFRASTRUCTURE).

.DESCRIPTION
    This script is for the REAL environment, as opposed to deploy.ps1 (learning/exploration POC).
    Differences from deploy.ps1:
      - The 4 Azure SQL databases (Dev/tst/Acc/Prd) already exist - this script never creates or
        provisions SQL servers/databases and never runs the sql/*.sql scripts.
      - The Data Factory instance already exists - this script never creates it, only
        publishes/updates linked services, datasets, pipelines and triggers into it.
      - The linked services are published from .\adf\linkedServices-real (not .\adf\linkedServices),
        which use the Data Factory's System-Assigned Managed Identity to authenticate to Azure SQL
        instead of a SQL login/password. This requires that each SQL database already has a
        contained user for the Data Factory's managed identity, e.g. run, as an AAD admin, on each
        database:
            CREATE USER [MSC-DAF-DMAPSB-MGPOC] FROM EXTERNAL PROVIDER;
            ALTER ROLE db_datareader ADD MEMBER [MSC-DAF-DMAPSB-MGPOC];
            ALTER ROLE db_datawriter ADD MEMBER [MSC-DAF-DMAPSB-MGPOC];   -- target/Prd only
        This script does not (and cannot, via managed identity) create those users itself.

    Datasets, pipelines and triggers are shared with the learning environment (.\adf\datasets,
    .\adf\pipelines, .\adf\triggers) since they only reference linked service *names*, which are
    identical between .\adf\linkedServices and .\adf\linkedServices-real.

.PARAMETER SubscriptionName
    Azure subscription name or ID containing the Data Factory. Defaults to "MSC-SUB-INFRASTRUCTURE".

.PARAMETER ResourceGroupName
    Resource group of the existing Data Factory. Defaults to "MSC-RSG-DMAPSB-TRACC".

.PARAMETER DataFactoryName
    Name of the existing Data Factory instance. Defaults to "MSC-DAF-DMAPSB-MGPOC".

.PARAMETER DevServerInstance
    Real Dev Azure SQL server FQDN. Defaults to "msc-ssr-dmap-dev.database.windows.net".

.PARAMETER TstServerInstance
    Real Test Azure SQL server FQDN. Defaults to "msc-ssr-dmap-tst.database.windows.net".

.PARAMETER AccServerInstance
    Real Acc Azure SQL server FQDN. Defaults to "msc-ssr-dmap-acc.database.windows.net".

.PARAMETER PrdServerInstance
    Real Prod (target) Azure SQL server FQDN. Defaults to "msc-ssr-dmap-prd.database.windows.net".

.PARAMETER DatabaseName
    Database name on every server. Defaults to "DMAP" - change this if the real databases use a
    different name.

.PARAMETER TenantId
    Azure AD tenant of the real environment account. Pass this the first time (or whenever you
    need to switch accounts) so the script signs you in with the right tenant/account instead of
    reusing whatever account is currently active in this PowerShell session.

.PARAMETER AccountId
    Azure AD user/service principal to sign in as for the real environment. Optional hint passed
    to Connect-AzAccount alongside -TenantId.

.PARAMETER ContextFile
    Path to a saved Az context file used to keep this environment's login separate from the
    learning environment's login, so switching between them never requires re-authenticating.
    Defaults to "$env:USERPROFILE\.azcontext-dmap-real.json". The learning environment
    (deploy.ps1) keeps using your normal/default Az session and is unaffected by this file.

.EXAMPLE
    # First run: sign in interactively as the real-environment account, context gets saved for reuse.
    .\deploy-real-environment.ps1 -TenantId "<real-tenant-id>" -AccountId "you@realtenant.com"

.EXAMPLE
    # Subsequent runs: reuses the saved context file, no re-login needed.
    .\deploy-real-environment.ps1
#>
[CmdletBinding()]
param(
    [string]$SubscriptionName = "MSC-SUB-INFRASTRUCTURE",
    [string]$ResourceGroupName = "MSC-RSG-DMAPSB-TRACC",
    [string]$DataFactoryName = "MSC-DAF-DMAPSB-MGPOC",

    [string]$DevServerInstance = "msc-ssr-dmap-dev.database.windows.net",
    [string]$TstServerInstance = "msc-ssr-dmap-tst.database.windows.net",
    [string]$AccServerInstance = "msc-ssr-dmap-acc.database.windows.net",
    [string]$PrdServerInstance = "msc-ssr-dmap-prd.database.windows.net",
    [string]$DatabaseName = "DMAP",

    [string]$TenantId,
    [string]$AccountId,
    [string]$ContextFile = "$env:USERPROFILE\.azcontext-dmap-real.json"
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$adfRoot = Join-Path $scriptRoot 'adf'

if (-not (Get-Module -ListAvailable -Name Az.DataFactory)) {
    throw "Az.DataFactory module not found. Install it with: Install-Module Az.DataFactory -Scope CurrentUser"
}
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    throw "Az.Accounts module not found. Install it with: Install-Module Az.Accounts -Scope CurrentUser"
}

# Keep this environment's login isolated from whatever account/context is active for the
# learning environment - do not touch the shared/default Az context.
if (Test-Path $ContextFile) {
    Import-AzContext -Path $ContextFile | Out-Null
}
if ($TenantId -or -not (Get-AzContext)) {
    $connectArgs = @{}
    if ($TenantId) { $connectArgs.Tenant = $TenantId }
    if ($AccountId) { $connectArgs.AccountId = $AccountId }
    Connect-AzAccount @connectArgs | Out-Null
}
Set-AzContext -Subscription $SubscriptionName | Out-Null
Save-AzContext -Path $ContextFile -Force | Out-Null
Write-Host "Az context saved to $ContextFile for reuse on future runs." -ForegroundColor DarkGray

Write-Host "=== DMAP real environment ADF deployment ===" -ForegroundColor Green
Write-Host "Subscription: $SubscriptionName / RG: $ResourceGroupName / ADF: $DataFactoryName"
Write-Host "Dev: $DevServerInstance / Test: $TstServerInstance / Acc: $AccServerInstance / Prd: $PrdServerInstance (database: $DatabaseName)"

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

Write-Host "Publishing linked services (Managed Identity auth)..." -ForegroundColor Cyan
$adfTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "dmap-adf-real-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $adfTempDir -Force | Out-Null
try {
    Get-ChildItem (Join-Path $adfRoot 'linkedServices-real') -Filter '*.json' | ForEach-Object {
        $name = $_.BaseName
        $content = (Get-Content -Path $_.FullName -Raw) `
            -replace '\{\{SOURCE_DEV_SQL_SERVER_FQDN\}\}', $DevServerInstance `
            -replace '\{\{SOURCE_TEST_SQL_SERVER_FQDN\}\}', $TstServerInstance `
            -replace '\{\{SOURCE_ACC_SQL_SERVER_FQDN\}\}', $AccServerInstance `
            -replace '\{\{TARGET_SQL_SERVER_FQDN\}\}', $PrdServerInstance `
            -replace '\{\{DMAP_DATABASE_NAME\}\}', $DatabaseName
        $tempFile = Join-Path $adfTempDir "$name.json"
        Set-Content -Path $tempFile -Value $content -NoNewline
        Set-AzDataFactoryV2LinkedService -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -DefinitionFile $tempFile -Force | Out-Null
        Write-Host "  Linked service: $name -> managed identity"
    }
}
finally {
    Remove-Item -Path $adfTempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Publishing datasets..." -ForegroundColor Cyan
Get-ChildItem (Join-Path $adfRoot 'datasets') -Filter '*.json' | ForEach-Object {
    $name = $_.BaseName
    Set-AzDataFactoryV2Dataset -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -DefinitionFile $_.FullName -Force | Out-Null
    Write-Host "  Dataset: $name"
}

Write-Host "Publishing pipelines..." -ForegroundColor Cyan
# Pipelines that invoke other pipelines (ExecutePipeline) must be published after their referenced
# pipelines exist. A single reference/no-reference split isn't enough for multi-level chains (e.g.
# PL_MasterLoadAndValidate -> PL_ValidateAndLoadAllToProduction -> PL_ValidateAndLoadToProduction),
# so do a proper topological sort based on the actual "referenceName" values found in each file.
$pipelineFiles = @(Get-ChildItem (Join-Path $adfRoot 'pipelines') -Filter '*.json')
$pipelinesByName = @{}
foreach ($file in $pipelineFiles) { $pipelinesByName[$file.BaseName] = $file }

$published = New-Object 'System.Collections.Generic.HashSet[string]'
$orderedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
function Add-DmapPipelineInOrder {
    param([string]$Name, [System.Collections.Generic.HashSet[string]]$Visiting)

    if ($published.Contains($Name) -or -not $pipelinesByName.ContainsKey($Name)) { return }
    if (-not $Visiting.Add($Name)) { throw "Circular pipeline reference detected involving '$Name'." }

    $file = $pipelinesByName[$Name]
    $content = Get-Content $file.FullName -Raw
    $refMatches = [regex]::Matches($content, '"pipeline"\s*:\s*\{\s*"referenceName"\s*:\s*"([^"]+)"')
    foreach ($match in $refMatches) {
        Add-DmapPipelineInOrder -Name $match.Groups[1].Value -Visiting $Visiting
    }

    $orderedFiles.Add($file)
    $published.Add($Name) | Out-Null
    $Visiting.Remove($Name) | Out-Null
}

foreach ($name in ($pipelinesByName.Keys | Sort-Object)) {
    Add-DmapPipelineInOrder -Name $name -Visiting (New-Object 'System.Collections.Generic.HashSet[string]')
}

foreach ($file in $orderedFiles) {
    $name = $file.BaseName
    Set-AzDataFactoryV2Pipeline -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -DefinitionFile $file.FullName -Force | Out-Null
    Write-Host "  Pipeline: $name"
}

$triggersDir = Join-Path $adfRoot 'triggers'
if (Test-Path $triggersDir) {
    Write-Host "Publishing triggers..." -ForegroundColor Cyan
    Get-ChildItem $triggersDir -Filter '*.json' | ForEach-Object {
        $name = ($_.BaseName -replace '^TR_', '')
        Set-AzDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -DefinitionFile $_.FullName -Force | Out-Null
        Start-AzDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -Name $name -Force | Out-Null
        Write-Host "  Trigger: $name (started)"
    }
}

Write-Host "=== Real environment ADF deployment complete ===" -ForegroundColor Green
Write-Host "IMPORTANT: if this is the first deployment of the managed-identity linked services, make sure" -ForegroundColor Yellow
Write-Host "the Data Factory's managed identity has a contained user + role membership on every SQL database (see script header)." -ForegroundColor Yellow
Write-Host "Run e.g.: Invoke-AzDataFactoryV2Pipeline -ResourceGroupName $ResourceGroupName -DataFactoryName $DataFactoryName -PipelineName PL_LoadAllToStaging"
