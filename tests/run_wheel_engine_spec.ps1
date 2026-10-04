param([string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive')
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$wheelSource = Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/common/horizonRewind/wheelInterpolation.lua') -Raw
$spec = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'wheel_engine_spec.lua') -Raw
if ($wheelSource.Contains(']====]')) { throw 'Lua source delimiter collision' }
$generated = 'testWheelSource = [====[' + $wheelSource + "]====]`n" + $spec
$target = Join-Path $PSScriptRoot 'wheel_engine_spec.generated.lua'
[IO.File]::WriteAllText($target, $generated, [Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $GameRoot
try {
  $output = & (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | ForEach-Object { Write-Output $_ }
  if ($LASTEXITCODE -ne 0 -or ($output -match 'FATAL LUA ERROR') -or -not ($output -match 'WHEEL_ENGINE_SPEC_DONE 4')) {
    throw 'Native wheel geometry checks failed.'
  }
}
finally { Pop-Location }
