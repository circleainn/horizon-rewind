param([string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$history = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/common/horizonRewind/history.lua') -Raw
$coordinator = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/ge/extensions/horizonRewind.lua') -Raw
$historySpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'history_spec.lua') -Raw
$coordinatorSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'coordinator_spec.lua') -Raw
$recovery = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/vehicle/extensions/horizonRewindRecovery.lua') -Raw
$recoverySpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'recovery_spec.lua') -Raw
$wheel = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/common/horizonRewind/wheelInterpolation.lua') -Raw
$wheelSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wheel_spec.lua') -Raw
$camera = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/ge/extensions/horizonRewindCamera.lua') -Raw
$cameraSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'camera_spec.lua') -Raw
$vehicle = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/vehicle/extensions/horizonRewindVehicle.lua') -Raw
$optionalSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vehicle_optional_spec.lua') -Raw
$traffic = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/ge/extensions/horizonRewindTraffic.lua') -Raw
$trafficSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'traffic_spec.lua') -Raw
$audio = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/ge/extensions/horizonRewindAudio.lua') -Raw
$audioSpec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'audio_spec.lua') -Raw
if (@($coordinator, $recovery, $wheel, $camera, $vehicle, $history) | Where-Object { $_.Contains(']====]') }) { throw 'Lua delimiter collision' }
$source = "require('lua/console/console-lib').initConsole()`npackage.loaded['horizonRewind/history'] = (function()`n" + $history + "`nend)()`n" +
  'HORIZON_REWIND_COORDINATOR_SOURCE = [====[' + $coordinator + "]====]`n" +
  'testRecoverySource = [====[' + $recovery + "]====]`n" +
  'testWheelSource = [====[' + $wheel + "]====]`n" +
  'HORIZON_REWIND_CAMERA_SOURCE = [====[' + $camera + "]====]`n" +
  'testHistorySource = [====[' + $history + "]====]`n" +
  'testVehicleSource = [====[' + $vehicle + "]====]`n" +
  'testTrafficSource = [====[' + $traffic + "]====]`n" +
  'testAudioSource = [====[' + $audio + "]====]`n" +
  "do`n" + $audioSpec + "`nend`n" +
  "do`n" + $trafficSpec + "`nend`n" +
  "do`n" + $historySpec + "`nend`ndo`n" + $coordinatorSpec + "`nend`ndo`n" + $recoverySpec + "`nend`ndo`n" + $wheelSpec + "`nend`ndo`n" + $cameraSpec + "`nend`ndo`n" + $optionalSpec + "`nend`nprint('ALL_SPECS_PASSED')`n"
$target = Join-Path $PSScriptRoot 'specs.generated.lua'
[IO.File]::WriteAllText($target, $source, [Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $GameRoot
try {
  $output = & (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | ForEach-Object { Write-Output $_ }
  if ($LASTEXITCODE -ne 0 -or ($output -match 'FATAL LUA ERROR') -or -not ($output -match 'ALL_SPECS_PASSED')) {
    throw 'Lua specification tests failed.'
  }
}
finally { Pop-Location }
