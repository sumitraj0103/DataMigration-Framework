$ReplicationDirFiles = @{
    
    Mode = "SelectedDirectories"
    ContentMode = "DirectoryTreeWithEmptyFiles" #DirectoryOnly (copies only the directories, no childs). DirectoryTreeAndFiles (copies the directories and all files in them). DirectoryTree (copies the directories and all the childs, but not the files). DirectoryTreeWithEmptyFiles (copies the directories and all the childs, but creates empty files only).
    DryRun = $True
    SelectedDirectories = @(
        @{
            Container = "raw"
            Path = "Global/AssetManagement/FINAL"
        },
        @{
            Container = "curated"
            Path = "CADMAP/ADHOC"
        },
        @{
            Container = "curated"
            Path = "CADMAP/BEHAVIOURAL_SCORES"
        }
    )

}

$DeploymentConfig = @{
    Description = @"
    Values: WhatIf | Create. 
    WhatIf: Performs a what-if deployment to validate the Bicep template without making any changes. 
    Create: Deploys the Bicep template to create or update resources in the specified resource group.
"@
    Mode = "WhatIf" # Change to "WhatIf" for a what-if deployment (running debug mode).
}


$MigrationConfig = @{
    
    NamingConventions = $NamingConventions

    DeploymentConfigMode = $DeploymentConfig.Mode
    
    Paths = @{
        StorageAccountTemplate = "$PSScriptRoot\..\storageAccount\input\sa-dev03-formatted.bicep"
        WhatIfOutput = "$PSScriptRoot\..\storageAccount\output\what-if\sa-dev03-predeploy-what-if.json"
        StorageAccountDeploymentOutput = "$PSScriptRoot\..\storageAccount\output\deployments\sa-dev03-deployment-output.json"
        StorageAccountDeploymentErrorOutput = "$PSScriptRoot\..\storageAccount\output\deployments\sa-dev03-deployment-error-output.json"
    }

    ReplicationDirFiles = $ReplicationDirFiles
}
return $MigrationConfig
