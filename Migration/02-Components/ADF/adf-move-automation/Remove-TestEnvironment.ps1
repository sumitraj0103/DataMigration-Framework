<#
.SYNOPSIS
    Tears down the disposable test environment created by New-TestEnvironment.ps1.
.PARAMETER TestResourceGroupName
    Source-side test resource group to delete.
.PARAMETER TestTargetResourceGroupName
    Target-side test resource group to delete (only needed if the POC move actually ran).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TestResourceGroupName,

    [string]$TestTargetResourceGroupName
)

foreach ($rg in @($TestResourceGroupName, $TestTargetResourceGroupName) | Where-Object { $_ }) {
    if (Get-AzResourceGroup -Name $rg -ErrorAction SilentlyContinue) {
        if ($PSCmdlet.ShouldProcess($rg, "Remove-AzResourceGroup")) {
            Remove-AzResourceGroup -Name $rg -Force
            Write-Host "Removed resource group: $rg"
        }
    }
    else {
        Write-Host "Resource group not found (already removed?): $rg"
    }
}
