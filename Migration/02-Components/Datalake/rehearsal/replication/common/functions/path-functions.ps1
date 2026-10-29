function Get-PowerShellRoot {
    $currentFolder = Get-Item -LiteralPath $PSScriptRoot

    while ($null -ne $currentFolder) {
        if ($currentFolder.Name -eq "12-Replication") {
            return $currentFolder.FullName
        }
        $currentFolder = $currentFolder.Parent
    }
    throw "Could not find the '12-Replication' folder in the path hierarchy."
}

function Get-CommonFolder {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PowerShellRoot
    )
    return Join-Path `
        -Path $PowerShellRoot `
        -ChildPath "common"
}

function Get-ConfigFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$PowerShellRoot
    )
    return Join-Path `
        $PowerShellRoot `
        "common\config.ps1"
}