param([string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$generated = ''
foreach ($item in @(
  @('testHistorySource','mod/lua/common/horizonRewind/history.lua'),
  @('testWheelSource','mod/lua/common/horizonRewind/wheelInterpolation.lua'),
  @('testVehicleSource','mod/lua/vehicle/extensions/horizonRewindVehicle.lua')
)) {
  $source = Get-Content -Raw -LiteralPath (Join-Path $workspace $item[1])
  if ($source.Contains(']====]')) { throw 'Lua source delimiter collision' }
  $generated += $item[0] + ' = [====[' + $source + "]====]`n"
}
$generated += Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'closure_engine_spec.lua')
$target = Join-Path $PSScriptRoot 'closure_engine_spec.generated.lua'
[IO.File]::WriteAllText($target,$generated,[Text.UTF8Encoding]::new($false))
$results = Join-Path $workspace '.test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
$logPath = Join-Path $results ('closure-engine-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Push-Location -LiteralPath $GameRoot
try {
  $output = & (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | Set-Content -LiteralPath $logPath
  $output | ForEach-Object { Write-Output $_ }
  if ($LASTEXITCODE -ne 0 -or ($output -match 'FATAL LUA ERROR') -or -not ($output -match 'CLOSURE_ENGINE_SPEC_DONE assertions=7 atomicRestores=3')) {
    throw "Closure engine tests failed. Inspect $logPath"
  }
  Write-Output "Closure test log: $logPath"
}
finally { Pop-Location }
