param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive')
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$adapter=Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/vehicle/extensions/horizonRewindTires.lua') -Raw
$spec=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tire_state_spec.lua') -Raw
if($adapter.Contains(']====]')) {throw 'Lua delimiter collision'}
$source="require('lua/console/console-lib').initConsole()`ntestTireStateSource=[====["+$adapter+"]====]`n"+$spec
$target=Join-Path $PSScriptRoot 'tire_state_spec.generated.lua'
[IO.File]::WriteAllText($target,$source,[Text.UTF8Encoding]::new($false))
$logPath=Join-Path $workspace '.test-results/tire-state-spec.log'
Push-Location -LiteralPath $GameRoot
try {
  $output=& (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | Set-Content -LiteralPath $logPath
  $output | ForEach-Object {Write-Output $_}
  if($LASTEXITCODE-ne 0 -or ($output-match 'FATAL LUA ERROR') -or -not($output-match 'TIRE_STATE_SPEC_DONE 10')) {throw "Tire state tests failed: $logPath"}
} finally {Pop-Location}
