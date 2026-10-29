$PowerShellRoot = Split-Path `
    -Path (Split-Path -Path $PSScriptRoot -Parent) `
    -Parent

$AuthenticationFile = Join-Path `
    -Path $PowerShellRoot `
    -ChildPath "common\authenticate.ps1"

if (-not (Test-Path -LiteralPath $AuthenticationFile)) {
    throw "Authentication file not found: $AuthenticationFile"
}
$LoadCommonFile = Join-Path `
    -Path $PSScriptRoot `
    -ChildPath "common\load-common.ps1"

# Load Authentication script to ensure the user is authenticated and the correct subscription is set
. $AuthenticationFile

# Load shared functions and $MigrationConfig from this scripts scope.
. $LoadCommonFile

if ($null -eq $MigrationConfig) {
    throw "MigrationConfig is null after loading common functions."
}

if ($null -eq $NamingConventions) {
    throw "NamingConventions is null after loading common functions."
}

# Get the target storage account name based on the naming conventions defined in the configuration
$TargetStorageAccount = Get-TargetStorageAccountName `
    -NamingConventionsFile $NamingConventions

write-Host "Target Storage Account Name: $TargetStorageAccount"

# Generate the target resource group name based on the naming conventions defined in the configuration
$TargetResourceGroup = Get-TargetResourceGroupName `
    -NamingConventionsFile $NamingConventions

Write-Host "Target Resource Group Name: $TargetResourceGroup"

# Get the expected subscription name based on the naming conventions defined in the configuration
$ExpectedSubscription = Get-SubscriptionName `
    -NamingConventionsFile $NamingConventions

$AzureContext = Assert-Authentication `
    -ExpectedSubscription $ExpectedSubscription

$DeploymentName = "storage-account-deploymentTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"


Write-Host ""
Write-Host "Deployment Summary:"
Write-Host "-------------------"
Write-Host "Deployment Name: $DeploymentName"
Write-Host "Subscription: $($AzureContext.name)"
Write-Host "Resource Group: $TargetResourceGroup"
Write-Host "Storage Account: $TargetStorageAccount"
Write-Host "Bicep Template: $($MigrationConfig.Paths.StorageAccountTemplate)"
Write-Host "-------------------"

$DeploymentMode = $MigrationConfig.DeploymentConfigMode

switch ($DeploymentMode) {
    "WhatIf" {
        Write-Host "Performing a 'what-if' deployment to validate the Bicep template for the target storage account..."
        # Save the what-if result in memory to check for errors before writing to file
        $WhatIfOutput = az deployment group what-if `
            --name $DeploymentName `
            --resource-group $TargetResourceGroup `
            --template-file $MigrationConfig.Paths.StorageAccountTemplate `
            --parameters StorageAccountName=$TargetStorageAccount `
            --result-format FullResourcePayloads `
            --no-pretty-print `
            --no-prompt `
            --only-show-errors `
            --output json
            #--output json | Out-File -FilePath $MigrationConfig.Paths.WhatIfOutput -Encoding utf8
        
        $WhatIfExitCode = $LASTEXITCODE
        
        if ($WhatIfExitCode -ne 0) {
            throw (
                "What-if deployment failed. "
            )
        }

        # Check if the what-if output is empty or null
        if ([string]::IsNullOrEmpty($WhatIfOutput -join "")) {
            throw "What-if completed but returned no output."
        } else {
            Write-Host "What-if deployment completed. Output saved to: $($MigrationConfig.Paths.WhatIfOutput)"
        }

        # Save the what-if output to a file
        $WhatIfOutput |
            Out-File `
                -FilePath $MigrationConfig.Paths.WhatIfOutput `
                -Encoding utf8 `
                -Force

    }
    "Create" {
        Write-Host "Performing a 'create' deployment to deploy the Bicep template for the target storage account..."
        $DeploymentOutput = az deployment group create `
            --name $DeploymentName `
            --resource-group $TargetResourceGroup `
            --template-file $MigrationConfig.Paths.StorageAccountTemplate `
            --parameters StorageAccountName=$TargetStorageAccount `
            --output json

        $DeploymentExitCode = $LASTEXITCODE

        # FAILURE HANDLING: If the deployment fails, capture the error details and save them to a file
        if ($DeploymentExitCode -ne 0) {
            Write-Host "Deployment failed. Retrieving deployment error details..."
            $DeploymentOperations = az deployment operation group list `
                --name $DeploymentName `
                --resource-group $TargetResourceGroup `
                --query "[?properties.provisioningState=='Failed'].{resource:properties.targetResource.resourceName,resourceType:properties.targetResource.resourceType,state:properties.provisioningState,statusMessage:properties.statusMessage}" `
                --output json

            $OperationsExitCode = $LASTEXITCODE

            if ($OperationsExitCode -eq 0) {
                Write-Host "Deployment failed. Saving error details to: $($MigrationConfig.Paths.StorageAccountDeploymentErrorOutput)"
                $DeploymentOperations | Out-File `
                    -FilePath $MigrationConfig.Paths.StorageAccountDeploymentErrorOutput `
                    -Encoding utf8 `
                    -Force
            } else {
                Write-Host "No deployment operations retrieved or failed to retrieve operations."
            }

            throw (
                "Storage account deployment failed. " +
                "Please check the deployment output file for details: $MigrationConfig.Paths.StorageAccountDeploymentErrorOutput"
            )
        }

        if ([string]::IsNullOrWhitespace($DeploymentOutput -join "")) {
            throw "Deployment completed but returned no output."
        } 

        # Save the successful deployment output to a file
        $DeploymentOutput | Out-File `
            -FilePath $MigrationConfig.Paths.StorageAccountDeploymentOutput `
            -Encoding utf8 `
            -Force

        # Remove diagnostics from an older failed run
        if(Test-Path $MigrationConfig.Paths.StorageAccountDeploymentErrorOutput) {
            Remove-Item $MigrationConfig.Paths.StorageAccountDeploymentErrorOutput -Force
        }
    }
    default {
        throw "Invalid DeploymentConfigMode: $DeploymentMode. Expected 'WhatIf' or 'Create'."
    }
}




