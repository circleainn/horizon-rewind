param(
  [string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive',
  [string]$FluidArchive = (Join-Path $env:LOCALAPPDATA 'BeamNG\BeamNG.drive\current\mods\repo\fluidspill-100.zip'),
  [string]$ParticleArchive = (Join-Path $env:LOCALAPPDATA 'BeamNG\BeamNG.drive\current\mods\repo\dynamic_damage_particles.zip'),
  [int]$TimeoutSeconds = 160,
  [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$runName = 'horizon-rewind-damage-effects-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$userRoot = Join-Path ([IO.Path]::GetTempPath()) $runName
if ($userRoot -match '\s') { throw 'Use a TEMP directory without spaces; the native launcher does not reliably parse quoted user paths.' }
$currentRoot = Join-Path $userRoot 'current'
$modDestination = Join-Path $currentRoot 'mods/unpacked/horizon_rewind'
$repo = Join-Path $currentRoot 'mods/repo'
New-Item -ItemType Directory -Path $modDestination,$repo -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modDestination -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindDamageEffectsSmoke.lua') -Destination (Join-Path $modDestination 'lua/ge/extensions/horizonRewindDamageEffectsSmoke.lua')
$driverDirectory = Join-Path $modDestination 'scripts/horizonRewindDamageEffectsSmoke'
New-Item -ItemType Directory -Path $driverDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $driverDirectory 'modScript.lua'), "extensions.load('horizonRewindDamageEffectsSmoke')", [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $FluidArchive -Destination $repo
if (Test-Path -LiteralPath $ParticleArchive) { Copy-Item -LiteralPath $ParticleArchive -Destination $repo }
$reportPath = Join-Path $currentRoot 'horizon-rewind-damage-effects-smoke.json'
$logPath = Join-Path $currentRoot 'beamng.log'
$arguments = @('-userpath',$userRoot,'-headless','-level','smallgrid','-gfx','null','-noui')
Write-Output "Effects user root: $userRoot"
Write-Output "Effects report: $reportPath"
Write-Output "Effects log: $logPath"
if ($PrepareOnly) { Write-Output "Arguments: $($arguments -join ' ')"; return }
$process = Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -WorkingDirectory $GameRoot -ArgumentList $arguments -WindowStyle Hidden -PassThru
Write-Output "Effects process ID: $($process.Id)"
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $process.WaitForExit(1000)) {
  if ([DateTime]::UtcNow -gt $deadline) { Stop-Process -Id $process.Id -Force; throw "Effects test timed out; see $logPath" }
}
if (-not (Test-Path -LiteralPath $reportPath)) { throw "No effects report; inspect $logPath" }
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
Write-Output ($report | ConvertTo-Json -Depth 8)
if ($report.ok -ne $true) { throw "Effects test failed: $($report.detail). Inspect $logPath" }
Write-Output 'DAMAGE_EFFECTS_SMOKE_PASSED'
