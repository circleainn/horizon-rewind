param(
  [string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive',
  [string]$FluidArchive = (Join-Path $env:LOCALAPPDATA 'BeamNG\BeamNG.drive\current\mods\repo\fluidspill-100.zip')
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$sources = [ordered]@{
  HR_FLUID_COMPAT_SOURCE = 'mod/lua/common/horizonRewind/fluidCompat.lua'
  HR_FLUID_GE_SOURCE = 'mod/lua/ge/extensions/horizonRewindFluids.lua'
  HR_FLUID_VEHICLE_SOURCE = 'mod/lua/vehicle/extensions/horizonRewindFluids.lua'
}
$bundle = ''
foreach ($entry in $sources.GetEnumerator()) {
  $source = Get-Content -LiteralPath (Join-Path $workspace $entry.Value) -Raw
  if ($source.Contains(']====]')) { throw 'Lua delimiter collision' }
  $bundle += $entry.Key + '=[====[' + $source + "]====]`n"
}
if (Test-Path -LiteralPath $FluidArchive) {
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($FluidArchive)
  try {
    foreach ($pair in @(@('HR_INSTALLED_FLUID_GE_SOURCE','lua/ge/extensions/fluidspill/main.lua'), @('HR_INSTALLED_FLUID_VEHICLE_SOURCE','lua/vehicle/extensions/fluidspill/fluid.lua'))) {
      $reader = [IO.StreamReader]::new($archive.GetEntry($pair[1]).Open())
      try { $source = $reader.ReadToEnd() } finally { $reader.Dispose() }
      if ($source.Contains(']====]')) { throw 'Lua delimiter collision' }
      $bundle += $pair[0] + '=[====[' + $source + "]====]`n"
    }
  } finally { $archive.Dispose() }
}
$bundle += Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fluid_spec.lua') -Raw
# The generated bundle includes installed third-party source; keep it local,
# temporary and out of the repository and distributable mod.
$target = Join-Path ([IO.Path]::GetTempPath()) ('horizon-fluid-spec-' + [Guid]::NewGuid().ToString('N') + '.lua')
[IO.File]::WriteAllText($target, $bundle, [Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $GameRoot
try {
  $output = & (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | ForEach-Object { Write-Output $_ }
  if ($LASTEXITCODE -ne 0 -or ($output -match 'FATAL LUA ERROR') -or -not ($output -match 'FLUID_SPECS_PASSED')) {
    throw "Fluid compatibility tests failed. Temporary runner: $target"
  }
} finally { Pop-Location }
