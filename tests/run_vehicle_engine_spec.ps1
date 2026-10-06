param([string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive')
$workspace = Split-Path -Parent $PSScriptRoot
$historySource = Get-Content -Raw -LiteralPath (Join-Path $workspace 'mod/lua/common/horizonRewind/history.lua')
$vehicleSource = Get-Content -Raw -LiteralPath (Join-Path $workspace 'mod/lua/vehicle/extensions/horizonRewindVehicle.lua')
$wheelSource = Get-Content -Raw -LiteralPath (Join-Path $workspace 'mod/lua/common/horizonRewind/wheelInterpolation.lua')
$specSource = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'vehicle_engine_spec.lua')
if ($historySource.Contains(']====]') -or $vehicleSource.Contains(']====]') -or $wheelSource.Contains(']====]')) { throw 'Lua source delimiter collision' }
$generated = 'testHistorySource = [====[' + $historySource + "]====]`n" + 'testWheelSource = [====[' + $wheelSource + "]====]`n" + 'testVehicleSource = [====[' + $vehicleSource + "]====]`n" + $specSource
$target = Join-Path $PSScriptRoot 'vehicle_engine_spec.generated.lua'
[System.IO.File]::WriteAllText($target, $generated, [System.Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $GameRoot
try {
  $output = & (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | ForEach-Object { Write-Output $_ }
  if ($LASTEXITCODE -ne 0 -or ($output -match 'FATAL LUA ERROR') -or -not ($output -match 'ENGINE_SPEC_DONE restoreCount=8 expectedErrors=1')) {
    throw 'Vehicle engine integration failed; inspect the preceding log.'
  }
}
finally { Pop-Location }
