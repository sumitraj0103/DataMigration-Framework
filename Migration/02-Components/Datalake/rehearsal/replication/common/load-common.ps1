# $ErrorActionPreference = "Stop"

$FunctionFolder = Join-Path $PSScriptRoot "functions"
$ConfigFile = Join-Path $PSScriptRoot "config.ps1"
$NamingConventions = Join-Path $PSScriptRoot "..\..\shared\naming-conventions.json"

$FunctionFiles = @(
    "path-functions.ps1",
    "naming-functions.ps1",
    "authentication-functions.ps1",
    "replication-functions.ps1"
)

foreach ($FunctionFile in $FunctionFiles) {
    $FunctionPath = Join-Path $FunctionFolder $FunctionFile

    if (-not(Test-Path -LiteralPath $FunctionPath)) {
        throw "Function file not found: $FunctionFile"
    }
    . $FunctionPath
}

if (-not(Test-Path -LiteralPath $ConfigFile)) {
    throw "Configuration file not found: $ConfigFile"
}

$MigrationConfig = & "$ConfigFile"

if ($null -eq $MigrationConfig) {
    throw "config.ps1 did not return MigrationConfig."
}
$NamingConventions = Get-Content `
    -Path $NamingConventions `
    -Raw | ConvertFrom-Json
