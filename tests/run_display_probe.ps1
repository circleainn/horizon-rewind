param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive',[int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
$runName='horizon-display-probe-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$testRoot=Join-Path ([IO.Path]::GetTempPath()) $runName
if ($testRoot -match '\s' -or (Test-Path -LiteralPath $testRoot)) { throw 'A new path without spaces is required' }
$modRoot=Join-Path $testRoot 'current/mods/unpacked/horizon_display_probe'
$extensionRoot=Join-Path $modRoot 'lua/ge/extensions'
$vehicleRoot=Join-Path $modRoot 'lua/vehicle/extensions'
$scriptRoot=Join-Path $modRoot 'scripts/horizonDisplayProbe'
New-Item -ItemType Directory -Path $extensionRoot,$vehicleRoot,$scriptRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindDisplayProbe.lua') -Destination $extensionRoot
[IO.File]::WriteAllText((Join-Path $scriptRoot 'modScript.lua'),"extensions.load('horizonRewindDisplayProbe')",[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $vehicleRoot 'horizonRewindDisplayWatcher.lua'),'local M={}; M.onReset=function() hrDisplayResetCount=(hrDisplayResetCount or 0)+1 end; return M',[Text.UTF8Encoding]::new($false))
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -ArgumentList @('-userpath',$testRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WorkingDirectory $GameRoot -WindowStyle Hidden -PassThru
Write-Output "DISPLAY_PROBE_RUNNING pid=$($process.Id) directory=$testRoot"
$deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $process.WaitForExit(1000)) {
  if ([DateTime]::UtcNow -gt $deadline) { Stop-Process -Id $process.Id -Force; throw "Display probe timeout; inspect $testRoot" }
}
$reportPath=Join-Path $testRoot 'current/horizon-display-probe.json'
if (-not (Test-Path -LiteralPath $reportPath)) { throw "No display probe report; inspect $testRoot" }
$report=Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$report | ConvertTo-Json -Depth 7
if (-not $report.ok) { throw "Display probe failed: $($report.detail)" }
