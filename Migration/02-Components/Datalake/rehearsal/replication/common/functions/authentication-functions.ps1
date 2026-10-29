function Connect-AzureCli {


    Write-Host "Checking Azure CLI authentication..."

    az account get-access-token --output none 1>$null 2>$null

    $TokenExitCode = $LASTEXITCODE

    if ($TokenExitCode -eq 0) {
        Write-Host "Azure CLI is authenticated with a valid token."
    }
    else {
        Write-Host "Azure CLI is not authenticated or the token has expired."
        Write-Host "Launching az login..."
        az login

        if ($LASTEXITCODE -ne 0) {
            Write-Host "Azure login failed. Please check your credentials and try again." 
            Write-Host "Please ensure you activate the resource groups via the Azure portal on Privileged Identity Management."
            exit 1
        }

        # Confir the new login can actually obtain a token
        az account get-access-token --output none 1>$null 2>$null

        if ($LASTEXITCODE -ne 0) {
            throw "Azure login was successful, but failed to obtain an access token. Please check your credentials and try again."
        }

        Write-Host "Azure login successful."
    }

}

function Set-ExpectedAzureSubscription {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ExpectedSubscription
    )

    $account = az account show --output json | ConvertFrom-Json

    if ($account.name -ne $ExpectedSubscription) {
        Write-Host "Wrong subscription selected. Current subscription: $($account.name). Expected subscription: $ExpectedSubscription"
        Write-Host "Launching 'az account set --subscription $ExpectedSubscription'..."
        az account set --subscription "$ExpectedSubscription"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to set the subscription to $ExpectedSubscription. Please check if the subscription name is correct and you have access to it."
            exit 1
        }
        $account = az account show --output json | ConvertFrom-Json

        Write-Host "Subscription successfully set to: $ExpectedSubscription"
    }
    else {
        Write-Host "Current subscription matches the expected subscription"
    }
    Write-Host "-----Authentication successful.------Connected to Subscription: $($account.name)"

return $account

}

function Assert-Authentication {
    param (
        [Parameter(Mandatory=$true)]
        [string]$ExpectedSubscription
    )

    $AccountJson = az account show --output json 2>$null

    if($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($AccountJson)) {
        throw @"
Azure authentication is not available.

Run:
    common\authenticate.ps1
to authenticate with Azure CLI and set the expected subscription: $ExpectedSubscription.
"@
    }

    $Account = $AccountJson | ConvertFrom-Json

    if($Account.name -ne $ExpectedSubscription) {
        throw @"
        Incorrect Azure Subscription selected.
        Expected: $ExpectedSubscription
        Current: $($Account.name)

        Run common\authenticate.ps1 to authenticate with Azure CLI and set the expected subscription.
"@
    }

    Write-Host "Azure authentication is valid"
    Write-Host "Connected to Subscription: $($Account.name)"

    return $Account
}


