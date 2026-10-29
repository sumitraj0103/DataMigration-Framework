$PowerShellRoot = Split-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -Parent

$LoadCommonFile = Join-Path `
    -Path $PowerShellRoot `
    -ChildPath "common\load-common.ps1"

. $LoadCommonFile

write-Host "Replication Mode: $($MigrationConfig.ReplicationDirFiles.Mode)"

$ReplicationConfig = $MigrationConfig.ReplicationDirFiles

$SourceStorageAccount = Get-SourceStorageAccountName `
    -NamingConventionsFile $NamingConventions

$TargetStorageAccount = Get-TargetStorageAccountName `
    -NamingConventionsFile $NamingConventions

# Get the expected subscription name based on the naming conventions defined in the configuration
$ExpectedSubscription = Get-SubscriptionName `
    -NamingConventionsFile $NamingConventions

# Assert that the user is authenticated and connected to the expected Azure subscription
Assert-Authentication `
    -ExpectedSubscription $ExpectedSubscription


if ($ReplicationConfig.Mode -ne "SelectedDirectories") {
    throw "Replication mode is not 'SelectedDirectories'. Current mode: $($ReplicationConfig.Mode)"
}

if ($ReplicationConfig.ContentMode -ne "DirectoryTreeWithEmptyFiles") {
    throw "Replication content mode is not 'DirectoryTreeWithEmptyFiles'. Current content mode: $($ReplicationConfig.ContentMode)"
}

foreach ($SelectedDirectory in $ReplicationConfig.SelectedDirectories) {
    write-Host "Replicating: $($SelectedDirectory.Path)/$($SelectedDirectory.Container)"

    # Call the function to replicate the directory tree
    Copy-DirectoryTree `
        -SourceStorageAccountName $SourceStorageAccount `
        -SourceContainerName $SelectedDirectory.Container `
        -SourceDirectoryName $SelectedDirectory.Path `
        -TargetStorageAccountName $TargetStorageAccount `
        -TargetContainerName $SelectedDirectory.Container `
        -TargetDirectoryName $SelectedDirectory.Path `
        -DryRun $ReplicationConfig.DryRun
}

