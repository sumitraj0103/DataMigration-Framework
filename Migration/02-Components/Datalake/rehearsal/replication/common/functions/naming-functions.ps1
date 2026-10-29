function Get-SubscriptionName {
    param (
        [Parameter(Mandatory=$true)]
        [pscustomobject]$NamingConventionsFile
    )
    
    return (
        "{0}-{1}-{2}" -f `
        $NamingConventionsFile.CompanyCodePrefix,
        $NamingConventionsFile.ResourceTypes.Subscription,
        $NamingConventionsFile.Teams.Infrastructure
    ).Trim()
}

function Get-TargetStorageAccountName {
    param (
        [Parameter(Mandatory=$true)]
        [pscustomobject]$NamingConventionsFile
    )

    return (
        "{0}{1}{2}{3}{4}{5}03" -f `
        $NamingConventionsFile.CompanyCodePrefix,
        $NamingConventionsFile.ResourceTypes.StorageAccount,
        $NamingConventionsFile.Teams.DataManagementPlatform,
        $NamingConventionsFile.Environments.Sandbox,
        $NamingConventionsFile.SandboxTestSuffix,
        $NamingConventionsFile.Environments.Development
    ).ToLower()
}

function Get-TargetResourceGroupName {
    param (
        [Parameter(Mandatory=$true)]
        [pscustomobject]$NamingConventionsFile
    )

    return (
        "{0}-{1}-{2}{3}-{4}" -f `
        $NamingConventionsFile.CompanyCodePrefix,
        $NamingConventionsFile.ResourceTypes.ResourceGroup,
        $NamingConventionsFile.Teams.DataManagementPlatform,
        $NamingConventionsFile.Environments.Sandbox,
        $NamingConventionsFile.SandboxTestSuffix
    )
}

function Get-SourceStorageAccountName {
    param (
        [Parameter(Mandatory=$true)]
        [pscustomobject]$NamingConventionsFile
    )

    return (
        "{0}{1}{2}{3}03" -f `
        $NamingConventionsFile.CompanyCodePrefix,
        $NamingConventionsFile.ResourceTypes.StorageAccount,
        $NamingConventionsFile.Teams.DataManagementPlatform,
        $NamingConventionsFile.Environments.Development
    ).ToLower()
}



