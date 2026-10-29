<#
.SYNOPSIS
    Builds a disposable test environment that mirrors PL_Data_Ingestion's dependencies,
    so the ADF move automation (Move-ADF.ps1) can be run as a POC safely before running
    against a real environment.

.DESCRIPTION
    PL_Data_Ingestion depends on:
      - LS_DMAP_SQL       (AzureSqlDatabase) -> dbo.Foldermapping table + sp_GetFolderMappingSourceFolder_V2
      - LS_DMAP_STA       (AzureBlobStorage) -> landing zone container (source files)
      - LS_DMAP_STA_BACKUP(AzureBlobStorage) -> incremental-backups container
      - LS_DMAP_DLSGen2   (AzureBlobFS/ADLS Gen2) -> raw filesystem

    This script creates a throwaway resource group with a test ADF, a test SQL server/DB
    (with the table + stored procedure the pipeline calls), and three test storage
    accounts, then deploys the linked services / datasets / pipeline JSON pointed at
    these test resources, grants the ADF's managed identity access, and uploads a sample
    file so the pipeline can be run end to end.

    Once this is up, run the POC move with:
      ./Move-ADF.ps1 -SourceResourceGroupName <TestResourceGroupName> -TargetResourceGroupName <TestTargetResourceGroupName> -DataFactoryName <AdfName>

.PARAMETER TestResourceGroupName
    Resource group to create for the test environment (the ADF's "source" RG for the POC run).

.PARAMETER TestTargetResourceGroupName
    Empty resource group to create as the move's destination for the POC run.

.PARAMETER Location
    Azure region for all test resources.

.PARAMETER AdfName
    Name for the test Data Factory. Must be globally unique.

.PARAMETER SqlAdminPassword
    SQL admin password (SecureString) for the test SQL server.

.PARAMETER PipelineSourcePath
    Path to the DataFactory ARM-export folder containing pipeline/dataset/linkedService/trigger subfolders.
    Defaults to the DMAP.DataManagementPlatform DataFactory folder.

.EXAMPLE
    $pwd = Read-Host "SQL admin password" -AsSecureString
    ./New-TestEnvironment.ps1 -TestResourceGroupName "rg-adfmove-test-src" -TestTargetResourceGroupName "rg-adfmove-test-dst" -AdfName "adf-move-poc01" -Location "canadacentral" -SqlAdminPassword $pwd
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TestResourceGroupName,

    [Parameter(Mandatory)]
    [string]$TestTargetResourceGroupName,

    [Parameter(Mandatory)]
    [string]$AdfName,

    [string]$Location = "canadacentral",

    [Parameter(Mandatory)]
    [securestring]$SqlAdminPassword,

    [string]$SqlAdminUser = "adfmoveadmin",

    [string]$PipelineSourcePath = "C:\Users\RajS1\dmap-working\DMAP.DataManagementPlatform\DataFactory",

    # Fixed suffix for resource names (storage accounts, SQL server). If omitted, one is
    # derived deterministically from TestResourceGroupName so reruns reuse the same names.
    [string]$Suffix
)

$ErrorActionPreference = 'Stop'

# Workaround: the OneDrive-synced WindowsPowerShell\Modules copy of Az.Accounts is
# missing files (OneDrive sync issue), which breaks Az.Storage's dependency check.
# Prioritize the intact local module copy for this session.
$localModules = "$env:LOCALAPPDATA\PSModules"
if ((Test-Path $localModules) -and ($env:PSModulePath -notlike "$localModules;*")) {
    $env:PSModulePath = "$localModules;$env:PSModulePath"
}

# Fixed suffix (derived from the source RG name if not explicitly provided) so
# re-running this script against the same test environment reuses the same
# resource names instead of creating duplicates each time.
if ($Suffix) {
    $suffix = $Suffix.ToLower()
} else {
    $hash = [System.BitConverter]::ToString(([System.Security.Cryptography.MD5]::Create()).ComputeHash([System.Text.Encoding]::UTF8.GetBytes($TestResourceGroupName))) -replace '-', ''
    $suffix = $hash.Substring(0, 6).ToLower()
}
Write-Host "Using resource name suffix: $suffix"

function Write-Step { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }
function Test-AzResourceGroupExists { param([string]$Name) [bool](Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue) }
function Test-AzStorageAccountExists { param([string]$ResourceGroupName, [string]$Name) [bool](Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $Name -ErrorAction SilentlyContinue) }
function Test-AzSqlServerExists { param([string]$ResourceGroupName, [string]$Name) [bool](Get-AzSqlServer -ResourceGroupName $ResourceGroupName -ServerName $Name -ErrorAction SilentlyContinue) }
function Test-AzSqlDatabaseExists { param([string]$ResourceGroupName, [string]$ServerName, [string]$Name) [bool](Get-AzSqlDatabase -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName $Name -ErrorAction SilentlyContinue) }
function Test-AzStorageContainerExists { param($Context, [string]$Name) [bool](Get-AzStorageContainer -Name $Name -Context $Context -ErrorAction SilentlyContinue) }
function Test-AzRoleAssignmentExists { param([string]$ObjectId, [string]$RoleDefinitionName, [string]$Scope) [bool](Get-AzRoleAssignment -ObjectId $ObjectId -RoleDefinitionName $RoleDefinitionName -Scope $Scope -ErrorAction SilentlyContinue) }

$requiredModules = 'Az.Accounts', 'Az.Resources', 'Az.Storage', 'Az.Sql', 'Az.DataFactory'
$missingModules = $requiredModules | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
if ($missingModules) {
    throw "Missing required module(s): $($missingModules -join ', '). Install with: Install-Module $($missingModules -join ', ') -Scope CurrentUser"
}

# --- Step 1: Resource groups ------------------------------------------------
Write-Step "Step 1: Create source and target resource groups"
if (Test-AzResourceGroupExists -Name $TestResourceGroupName) {
    Write-Host "Resource group '$TestResourceGroupName' already exists, skipping."
} else {
    New-AzResourceGroup -Name $TestResourceGroupName -Location $Location -Force | Out-Null
}
if (Test-AzResourceGroupExists -Name $TestTargetResourceGroupName) {
    Write-Host "Resource group '$TestTargetResourceGroupName' already exists, skipping."
} else {
    New-AzResourceGroup -Name $TestTargetResourceGroupName -Location $Location -Force | Out-Null
}

# --- Step 2: Storage accounts (landing zone, backup, ADLS Gen2) ------------
Write-Step "Step 2: Create storage accounts"
$staLanding = "stalandtst$suffix"
$staBackup = "stabckptst$suffix"
$staDlsGen2 = "stadlstst$suffix"

if (Test-AzStorageAccountExists -ResourceGroupName $TestResourceGroupName -Name $staLanding) {
    Write-Host "Storage account '$staLanding' already exists, skipping."
} else {
    New-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $staLanding -Location $Location -SkuName Standard_LRS -Kind StorageV2 | Out-Null
}
if (Test-AzStorageAccountExists -ResourceGroupName $TestResourceGroupName -Name $staBackup) {
    Write-Host "Storage account '$staBackup' already exists, skipping."
} else {
    New-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $staBackup -Location $Location -SkuName Standard_LRS -Kind StorageV2 | Out-Null
}
if (Test-AzStorageAccountExists -ResourceGroupName $TestResourceGroupName -Name $staDlsGen2) {
    Write-Host "Storage account '$staDlsGen2' already exists, skipping."
} else {
    New-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $staDlsGen2 -Location $Location -SkuName Standard_LRS -Kind StorageV2 -EnableHierarchicalNamespace $true | Out-Null
}

$landingCtx = (Get-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $staLanding).Context
$backupCtx = (Get-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $staBackup).Context
$dlsCtx = (Get-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $staDlsGen2).Context

if (Test-AzStorageContainerExists -Context $landingCtx -Name "inbound") { Write-Host "Container 'inbound' already exists, skipping." } else { New-AzStorageContainer -Name "inbound" -Context $landingCtx | Out-Null }
if (Test-AzStorageContainerExists -Context $backupCtx -Name "incremental-backups") { Write-Host "Container 'incremental-backups' already exists, skipping." } else { New-AzStorageContainer -Name "incremental-backups" -Context $backupCtx | Out-Null }
if (Test-AzStorageContainerExists -Context $dlsCtx -Name "raw") { Write-Host "Container 'raw' already exists, skipping." } else { New-AzStorageContainer -Name "raw" -Context $dlsCtx | Out-Null }

# Sample source files matching the pipeline's expected shape (data file + .chk file)
"sample,data,row" | Out-File .\sample_file.csv -Encoding utf8 -Force
"" | Out-File .\sample_file.chk -Encoding utf8 -Force
Set-AzStorageBlobContent -File .\sample_file.csv -Container "inbound" -Blob "test/sample_file.csv" -Context $landingCtx -Force | Out-Null
Set-AzStorageBlobContent -File .\sample_file.chk -Container "inbound" -Blob "test/sample_file.chk" -Context $landingCtx -Force | Out-Null
Remove-Item .\sample_file.csv, .\sample_file.chk -Force

# --- Step 3: SQL server/database with Foldermapping table + stored proc ---
Write-Step "Step 3: Create SQL server/database and Foldermapping metadata"
$sqlServerName = "sqlmovetst$suffix"
$sqlCred = New-Object System.Management.Automation.PSCredential($SqlAdminUser, $SqlAdminPassword)

if (Test-AzSqlServerExists -ResourceGroupName $TestResourceGroupName -Name $sqlServerName) {
    Write-Host "SQL server '$sqlServerName' already exists, skipping."
} else {
    New-AzSqlServer -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -Location $Location -SqlAdministratorCredentials $sqlCred | Out-Null
}
if (Get-AzSqlServerFirewallRule -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -FirewallRuleName "AllowAllAzureIPs" -ErrorAction SilentlyContinue) {
    Write-Host "Firewall rule 'AllowAllAzureIPs' already exists, skipping."
} else {
    New-AzSqlServerFirewallRule -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -AllowAllAzureIPs | Out-Null
}
if (Test-AzSqlDatabaseExists -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -Name "DMAPTest") {
    Write-Host "SQL database 'DMAPTest' already exists, skipping."
} else {
    New-AzSqlDatabase -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -DatabaseName "DMAPTest" -Edition "GeneralPurpose" -Vcore 2 -ComputeGeneration "Gen5" -MinimumCapacity 0.5 | Out-Null
}

$sqlScript = @"
IF OBJECT_ID('dbo.Foldermapping') IS NULL
CREATE TABLE dbo.Foldermapping (
    Source_System nvarchar(100), Interface_Name nvarchar(100), Trigger_Path nvarchar(500),
    Source_Container nvarchar(100), Source_Folder nvarchar(500), File_Name nvarchar(500),
    Target_Folder nvarchar(500), Required_Rows bit, Backup_Dmap bit
);
GO
IF OBJECT_ID('dbo.sp_GetFolderMappingSourceFolder_V2') IS NOT NULL DROP PROCEDURE dbo.sp_GetFolderMappingSourceFolder_V2;
GO
CREATE PROCEDURE dbo.sp_GetFolderMappingSourceFolder_V2 @Files nvarchar(max), @TriggerPath nvarchar(500)
AS
BEGIN
    SELECT TOP 1 'test' AS Source_System, 'test-interface' AS Interface_Name, @TriggerPath AS Trigger_Path,
        'inbound' AS Source_Container, 'test' AS Source_Folder, 'sample_file.csv' AS File_Name,
        'raw/test' AS Target_Folder, CAST(0 AS bit) AS Required_Rows, CAST(1 AS bit) AS Backup_Dmap;
END
GO
"@
$sqlScript | Out-File .\seed.sql -Encoding utf8 -Force
Invoke-Sqlcmd -ServerInstance "$sqlServerName.database.windows.net" -Database "DMAPTest" -Credential $sqlCred -InputFile .\seed.sql
Remove-Item .\seed.sql -Force

# --- Step 4: Create the test Data Factory ----------------------------------
Write-Step "Step 4: Create test Data Factory"
$adf = Set-AzDataFactoryV2 -ResourceGroupName $TestResourceGroupName -Name $AdfName -Location $Location -Force
$principalId = $adf.Identity.PrincipalId

# --- Step 5: Grant the ADF managed identity access inside the SQL database -
# Azure RBAC roles do not grant data-plane SQL access; the ADF linked service
# authenticates to SQL via AAD token, so the identity needs an Azure AD admin
# configured on the server plus a contained database user.
Write-Step "Step 5: Configure SQL AAD access for ADF managed identity"
$signedInUser = Get-AzADUser -SignedIn -ErrorAction SilentlyContinue
if (-not $signedInUser) {
    Write-Warning "Could not resolve the signed-in AAD user; skipping SQL AAD admin/contained-user setup. Run this manually if the pipeline run in Step 8 fails with a SQL login error."
} else {
    $existingAdmin = Get-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -ErrorAction SilentlyContinue
    if ($existingAdmin) {
        Write-Host "Azure AD admin already configured on '$sqlServerName', skipping."
    } else {
        Set-AzSqlServerActiveDirectoryAdministrator -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -DisplayName $signedInUser.DisplayName -ObjectId $signedInUser.Id | Out-Null
    }

    $accessToken = (Get-AzAccessToken -ResourceUrl "https://database.windows.net").Token
    if ($accessToken -isnot [string]) { $accessToken = [System.Net.NetworkCredential]::new('', $accessToken).Password }
    # Drop and recreate the contained user every run: if the ADF was ever deleted/recreated,
    # its managed identity gets a new AAD object id, and a stale user with the same name
    # would still map to the old (now invalid) SID, causing login failures.
    Start-Sleep -Seconds 20  # allow AAD replication of the ADF's managed identity
    $userScript = @"
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$AdfName')
    DROP USER [$AdfName];
CREATE USER [$AdfName] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [$AdfName];
GRANT EXECUTE ON dbo.sp_GetFolderMappingSourceFolder_V2 TO [$AdfName];
"@
    $userScript | Out-File .\grant-adf-user.sql -Encoding utf8 -Force
    Invoke-Sqlcmd -ServerInstance "$sqlServerName.database.windows.net" -Database "DMAPTest" -AccessToken $accessToken -InputFile .\grant-adf-user.sql
    Remove-Item .\grant-adf-user.sql -Force
}

# --- Step 6: Grant the ADF identity access to the test resources -----------
Write-Step "Step 6: Grant RBAC to ADF managed identity"
Start-Sleep -Seconds 20  # allow AAD replication of the new identity before assigning roles
foreach ($sa in @($staLanding, $staBackup, $staDlsGen2)) {
    $scope = (Get-AzStorageAccount -ResourceGroupName $TestResourceGroupName -Name $sa).Id
    if (Test-AzRoleAssignmentExists -ObjectId $principalId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $scope) {
        Write-Host "Role assignment for '$sa' already exists, skipping."
    } else {
        New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Storage Blob Data Contributor" -Scope $scope | Out-Null
    }
}
$sqlDbId = (Get-AzSqlDatabase -ResourceGroupName $TestResourceGroupName -ServerName $sqlServerName -DatabaseName "DMAPTest").ResourceId
if (Test-AzRoleAssignmentExists -ObjectId $principalId -RoleDefinitionName "Reader" -Scope $sqlDbId) {
    Write-Host "Role assignment on SQL database already exists, skipping."
} else {
    New-AzRoleAssignment -ObjectId $principalId -RoleDefinitionName "Reader" -Scope $sqlDbId | Out-Null
}

# --- Step 7: Deploy linked services, datasets, and the candidate pipeline --
Write-Step "Step 7: Deploy linked services / datasets / pipeline"

# Linked services rebuilt to point at the test resources (auth via ADF managed identity)
$lsSql = @{ name = "LS_DMAP_SQL"; properties = @{ type = "AzureSqlDatabase"; typeProperties = @{ connectionString = "Integrated Security=False;Encrypt=True;Connection Timeout=30;Data Source=$sqlServerName.database.windows.net;Initial Catalog=DMAPTest"; encryptedCredential = $null } } }
$lsSta = @{ name = "LS_DMAP_STA"; properties = @{ type = "AzureBlobStorage"; typeProperties = @{ serviceEndpoint = "https://$staLanding.blob.core.windows.net"; accountKind = "StorageV2" } } }
$lsStaBackup = @{ name = "LS_DMAP_STA_BACKUP"; properties = @{ type = "AzureBlobStorage"; typeProperties = @{ serviceEndpoint = "https://$staBackup.blob.core.windows.net" } } }
$lsDls = @{ name = "LS_DMAP_DLSGen2"; properties = @{ type = "AzureBlobFS"; typeProperties = @{ url = "https://$staDlsGen2.dfs.core.windows.net" } } }

foreach ($ls in @($lsSql, $lsSta, $lsStaBackup, $lsDls)) {
    $tmp = New-TemporaryFile
    ($ls | ConvertTo-Json -Depth 10) | Out-File $tmp.FullName -Encoding utf8
    Set-AzDataFactoryV2LinkedService -ResourceGroupName $TestResourceGroupName -DataFactoryName $AdfName -Name $ls.name -DefinitionFile $tmp.FullName -Force | Out-Null
    Remove-Item $tmp.FullName -Force
}

# Datasets and the candidate pipeline are deployed as-is from the source repo (their
# linkedService references match the names recreated above).
foreach ($datasetName in @("LS_Database", "DS_Landingzone_V2", "DS_STA_BACKUP", "DS_DatalakestoreGen2_V2", "DS_LandingZone")) {
    $path = Join-Path $PipelineSourcePath "dataset\$datasetName.json"
    Set-AzDataFactoryV2Dataset -ResourceGroupName $TestResourceGroupName -DataFactoryName $AdfName -Name $datasetName -DefinitionFile $path -Force | Out-Null
}

$pipelinePath = Join-Path $PipelineSourcePath "pipeline\PL_Data_Ingestion.json"
Set-AzDataFactoryV2Pipeline -ResourceGroupName $TestResourceGroupName -DataFactoryName $AdfName -Name "PL_Data_Ingestion" -DefinitionFile $pipelinePath -Force | Out-Null

# --- Step 8: Run the pipeline once to validate the test setup end to end --
Write-Step "Step 8: Trigger a validation run of PL_Data_Ingestion"
$runId = Invoke-AzDataFactoryV2Pipeline -ResourceGroupName $TestResourceGroupName -DataFactoryName $AdfName -PipelineName "PL_Data_Ingestion" -Parameter @{ TriggerPath = "test" }
Write-Host "Triggered run: $runId. Check status with:"
Write-Host "  Get-AzDataFactoryV2PipelineRun -ResourceGroupName $TestResourceGroupName -DataFactoryName $AdfName -PipelineRunId $runId"

Write-Host "`nTest environment ready." -ForegroundColor Green
Write-Host "Source RG : $TestResourceGroupName"
Write-Host "Target RG : $TestTargetResourceGroupName (empty, used as the move destination)"
Write-Host "ADF name  : $AdfName"
Write-Host "`nRun the POC move with:"
Write-Host "  ./Move-ADF.ps1 -SourceResourceGroupName $TestResourceGroupName -TargetResourceGroupName $TestTargetResourceGroupName -DataFactoryName $AdfName -WhatIf"
