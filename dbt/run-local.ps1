param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$DbtArgs
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.ScriptName
$localConfigPath = Join-Path $scriptDir "local.yml"
$profilesPath = Join-Path $scriptDir "profiles.yml"

if (-not (Test-Path -LiteralPath $localConfigPath)) {
    throw "Missing $localConfigPath. Copy local.template.yml to local.yml or generate it from deploy-fabric.ps1."
}

if (-not (Test-Path -LiteralPath $profilesPath)) {
    throw "Missing $profilesPath."
}

$localConfig = Get-Content -LiteralPath $localConfigPath -Raw | ConvertFrom-Yaml

if ($localConfig.profile_env) {
    foreach ($prop in $localConfig.profile_env.PSObject.Properties) {
        $env:$($prop.Name) = [string]$prop.Value
    }
}

$varsJson = "{}"
if ($localConfig.vars) {
    $varsJson = $localConfig.vars | ConvertTo-Json -Compress -Depth 20
}

$finalArgs = @("--profiles-dir", $scriptDir)
if ($DbtArgs) {
    $finalArgs += $DbtArgs
}
$finalArgs += @("--vars", $varsJson)

& dbt @finalArgs
exit $LASTEXITCODE
