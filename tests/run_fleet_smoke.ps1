param(
  [string]$GameRoot = 'C:\Steam\steamapps\common\BeamNG.drive',
  [string]$UserRoot = '',
  [int]$TimeoutSeconds = 480,
  [switch]$ProbeWithoutFlexReset,
  [switch]$PrepareOnly
)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path -Parent $PSScriptRoot
$gameExecutable = Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe'
if (-not (Test-Path -LiteralPath $gameExecutable)) { throw "Game executable not found: $gameExecutable" }
if (-not $UserRoot) {
  $runName = 'horizon-rewind-fleet-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
  $UserRoot = Join-Path ([IO.Path]::GetTempPath()) $runName
}
$UserRoot = [IO.Path]::GetFullPath($UserRoot)
if ($UserRoot -match '\s') { throw 'Use a test user path without spaces; the native launcher does not reliably parse quoted user paths.' }
if (Test-Path -LiteralPath $UserRoot) { throw "Fleet test needs a fresh isolated directory; refusing to overwrite $UserRoot" }
$currentRoot = Join-Path $UserRoot 'current'
$modDestination = Join-Path $currentRoot 'mods/unpacked/horizon_rewind'
New-Item -ItemType Directory -Path $modDestination -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modDestination -Recurse
if ($ProbeWithoutFlexReset) {
  $probePath = Join-Path $modDestination 'lua/ge/extensions/horizonRewind.lua'
  $probeSource = (Get-Content -LiteralPath $probePath -Raw).Replace('car:resetBrokenFlexMesh()', 'do end')
  [IO.File]::WriteAllText($probePath, $probeSource, [Text.UTF8Encoding]::new($false))
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindFleetSmoke.lua') -Destination (Join-Path $modDestination 'lua/ge/extensions/horizonRewindFleetSmoke.lua')
$driverDirectory = Join-Path $modDestination 'scripts/horizonRewindFleetSmoke'
New-Item -ItemType Directory -Path $driverDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $driverDirectory 'modScript.lua'), "extensions.load('horizonRewindFleetSmoke')", [Text.UTF8Encoding]::new($false))
$reportPath = Join-Path $currentRoot 'horizon-rewind-fleet.json'
$logPath = Join-Path $currentRoot 'beamng.log'
$launchArguments = @('-userpath', $UserRoot, '-headless', '-level', 'smallgrid', '-gfx', 'null', '-noui')
Write-Output "Fleet test user directory: $UserRoot"
Write-Output "Fleet report: $reportPath"
Write-Output "Fleet engine log: $logPath"
if ($PrepareOnly) {
  Write-Output "Prepared only. Launch executable: $gameExecutable"
  Write-Output "Arguments: $($launchArguments -join ' ')"
  return
}

# Only this newly launched process is eligible for termination on timeout.
$process = Start-Process -FilePath $gameExecutable -ArgumentList $launchArguments -WorkingDirectory $GameRoot -WindowStyle Hidden -PassThru
Write-Output "Fleet test process ID: $($process.Id)"
$deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $process.WaitForExit(1000)) {
  if ([DateTime]::UtcNow -gt $deadline) {
    Stop-Process -Id $process.Id -Force
    throw "Fleet test exceeded $TimeoutSeconds seconds. Inspect $reportPath and $logPath"
  }
}
if (-not (Test-Path -LiteralPath $reportPath)) {
  throw "Fleet test exited without a report (exit $($process.ExitCode)); inspect $logPath"
}
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
$report.cases | Select-Object label, model, previousVehicleId, vehicleId, sameVehicleId, historyAtHold, rewindDistance, resumedDistance
if ($report.ok -ne $true -or $report.completedCases -ne $report.expectedCases) {
  throw "Fleet test failed (process exit $($process.ExitCode)): $($report.detail). Inspect $reportPath and $logPath"
}
Write-Output "FLEET_SMOKE_PASSED: $($report.completedCases) cases. $($report.detail)"
