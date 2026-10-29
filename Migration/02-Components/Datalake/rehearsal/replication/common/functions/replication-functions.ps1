

function New-TargetDirectory{
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetStorageAccountName,

        [Parameter(Mandatory=$true)]
        [string]$TargetContainerName,

        [Parameter(Mandatory=$true)]
        [string]$TargetDirectoryName,

        [Parameter()]
        [bool]$DryRun = $false
    )

    $Exists = az storage fs directory exists `
        --account-name $TargetStorageAccountName `
        --file-system $TargetContainerName `
        --name $TargetDirectoryName `
        --auth-mode login `
        --query exists `
        --output tsv

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to check target directory: $TargetContainerName/$TargetDirectoryName in storage account: $TargetStorageAccountName"
    }


    if ($Exists -eq "true") {
        Write-Host "Target directory already exists: $TargetContainerName/$TargetDirectoryName in storage account: $TargetStorageAccountName"
        return
    }

    Write-Host "Creating target directory: $TargetContainerName/$TargetDirectoryName in storage account: $TargetStorageAccountName"

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create target directory: $TargetContainerName/$TargetDirectoryName in storage account: $TargetStorageAccountName"
        return
    }

    az storage fs directory create `
        --account-name $TargetStorageAccountName `
        --file-system $TargetContainerName `
        --name $TargetDirectoryName `
        --auth-mode login `
        --only-show-errors `
        --output none

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create target directory: $TargetContainerName/$TargetDirectoryName in storage account: $TargetStorageAccountName"
    }

}

function Copy-DirectoryTree {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourceStorageAccountName,

        [Parameter(Mandatory=$true)]
        [string]$SourceContainerName,

        [Parameter(Mandatory=$true)]
        [string]$SourceDirectoryName,

        [Parameter(Mandatory=$true)]
        [string]$TargetStorageAccountName,

        [Parameter(Mandatory=$true)]
        [string]$TargetContainerName,

        [Parameter(Mandatory=$true)]
        [string]$TargetDirectoryName,

        [Parameter()]
        [bool]$DryRun = $false
    )

    Write-Host "Copying directory tree from $SourceStorageAccountName/$SourceContainerName/$SourceDirectoryName to $TargetStorageAccountName/$TargetContainerName/$TargetDirectoryName"

    Write-Host "Source Account: $SourceStorageAccountName"
    Write-Host "Source Container: $SourceContainerName"
    Write-Host "Source Directory: $SourceDirectoryName"

    # Read immediate children from source
    $Items = az storage fs file list `
        --account-name $SourceStorageAccountName `
        --file-system $SourceContainerName `
        --path $SourceDirectoryName `
        --auth-mode login `
        --output json | ConvertFrom-Json
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list child directories in source: $SourceStorageAccountName/$SourceContainerName/$SourceDirectoryName"
    }

    $Directories = $Items | Where-Object { $_.isDirectory -eq $true } | Select-Object -ExpandProperty name

    $Files = $Items | Where-Object { $_.isDirectory -eq $false } | Select-Object -ExpandProperty name

    $DirectoriesToCreate = @($SourceDirectoryName)

    if ($Directories) {
        $DirectoriesToCreate += $Directories
    }

    foreach ($SourcePath in $DirectoriesToCreate) {
        if ([string]::IsNullOrWhiteSpace($SourcePath)) {
            Write-Host "Skipping empty child directory name."
            continue
        }

        if($SourcePath -eq $SourceDirectoryName) {
            $TargetPath = $TargetDirectoryName
        }
        else {
            $RelativePath = $SourcePath.Substring($SourceDirectoryName.Length).TrimStart('/')
            $TargetPath = "$TargetDirectoryName/$RelativePath"
        }

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would create: $TargetContainerName/$TargetPath"
        }

        New-TargetDirectory `
            -TargetStorageAccountName $TargetStorageAccountName `
            -TargetContainerName $TargetContainerName `
            -TargetDirectoryName $TargetPath `
            -DryRun $DryRun
    }

    foreach ($SourceFilePath in $Files) {
        if ([string]::IsNullOrWhiteSpace($SourceFilePath)) {
            Write-Host "Skipping empty child file name."
            continue
        }

        $RelativeFilePath = $SourceFilePath.Substring($SourceDirectoryName.Length).TrimStart('/')
        $TargetFilePath = "$TargetDirectoryName/$RelativeFilePath"

        if ($DryRun) {
            Write-Host "[DRY-RUN] Would create empty file: $TargetContainerName/$TargetFilePath"
        }
        New-TargetEmptyFile `
            -TargetStorageAccountName $TargetStorageAccountName `
            -TargetContainerName $TargetContainerName `
            -TargetFilePath $TargetFilePath `
            -DryRun $DryRun
    }
    
}

function New-TargetEmptyFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$TargetStorageAccountName,

        [Parameter(Mandatory=$true)]
        [string]$TargetContainerName,

        [Parameter(Mandatory=$true)]
        [string]$TargetFilePath,

        [Parameter()]
        [bool]$DryRun = $false
    )

    if ($DryRun) {
        Write-Host "[DRY-RUN] Would create empty file: $TargetContainerName/$TargetFilePath in storage account: $TargetStorageAccountName"
        return
    }

    Write-Host "Checking target file: $TargetContainerName/$TargetFilePath in storage account: $TargetStorageAccountName"

    $Exists = az storage fs file exists `
        --account-name $TargetStorageAccountName `
        --file-system $TargetContainerName `
        --path $TargetFilePath `
        --auth-mode login `
        --query exists `
        --output tsv

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to check if target file exists: $TargetStorageAccountName/$TargetContainerName/$TargetFilePath"
    }

    if ($Exists -eq "true") {
        Write-Host "Target file already exists: $TargetContainerName/$TargetFilePath in storage account: $TargetStorageAccountName"
        return
    }

    Write-Host "Creating empty target file: $TargetContainerName/$TargetFilePath in storage account: $TargetStorageAccountName"

    az storage fs file create `
        --account-name $TargetStorageAccountName `
        --file-system $TargetContainerName `
        --path $TargetFilePath `
        --auth-mode login `
        --only-show-errors `
        --output none
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create empty target file: $TargetContainerName/$TargetFilePath in storage account: $TargetStorageAccountName"
    }
}