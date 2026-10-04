param(
  [string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive',
  [string]$ParticleArchive = (Join-Path $env:LOCALAPPDATA 'BeamNG\BeamNG.drive\current\mods\repo\dynamic_damage_particles.zip')
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($ParticleArchive)
try {
  $reader = [IO.StreamReader]::new($archive.GetEntry('lua/ge/extensions/crashDebris.lua').Open())
  try { $installedSource = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally { $archive.Dispose() }
$sources = [ordered]@{
  testDynamicParticlesSource = $installedSource
  testParticlesAdapterSource = (Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/ge/extensions/horizonRewindParticles.lua') -Raw)
  testEffectsAdapterSource = (Get-Content -LiteralPath (Join-Path $workspace 'mod/lua/vehicle/extensions/horizonRewindEffects.lua') -Raw)
}
$bundle = "require('lua/console/console-lib').initConsole()`n"
foreach ($entry in $sources.GetEnumerator()) {
  if ($entry.Value.Contains(']====]')) { throw 'Lua delimiter collision' }
  $bundle += $entry.Key + '=[====[' + $entry.Value + "]====]`n"
}
$bundle += Get-Content -LiteralPath (Join-Path $PSScriptRoot 'particles_spec.lua') -Raw
# The installed third-party source exists only in this local temporary runner.
$target = Join-Path ([IO.Path]::GetTempPath()) ('horizon-particles-spec-' + [Guid]::NewGuid().ToString('N') + '.lua')
[IO.File]::WriteAllText($target, $bundle, [Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $GameRoot
try {
  $output = & (Join-Path $GameRoot 'Bin64/console.x64.exe') file $target 2>&1
  $output | ForEach-Object { Write-Output $_ }
  if ($LASTEXITCODE -ne 0 -or ($output -match 'FATAL LUA ERROR') -or -not ($output -match 'PARTICLES_SPECS_PASSED')) {
    throw "Particle compatibility tests failed. Temporary runner: $target"
  }
} finally { Pop-Location }
