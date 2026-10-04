param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive',[int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$runName='horizon-cluster-probe-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$testRoot=Join-Path ([IO.Path]::GetTempPath()) $runName
if ($testRoot -match '\s' -or (Test-Path -LiteralPath $testRoot)) { throw 'A new path without spaces is required' }
$modRoot=Join-Path $testRoot 'current/mods/unpacked/horizon_cluster_probe'
$extensionRoot=Join-Path $modRoot 'lua/ge/extensions'
$scriptRoot=Join-Path $modRoot 'scripts/horizonClusterProbe'
New-Item -ItemType Directory -Path $extensionRoot,$scriptRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindClusterProbe.lua') -Destination $extensionRoot
[IO.File]::WriteAllText((Join-Path $scriptRoot 'modScript.lua'),"extensions.load('horizonRewindClusterProbe')",[Text.UTF8Encoding]::new($false))
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -ArgumentList @('-userpath',$testRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WorkingDirectory $GameRoot -WindowStyle Hidden -PassThru
Write-Output "CLUSTER_PROBE_RUNNING pid=$($process.Id) directory=$testRoot"
$deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $process.WaitForExit(1000)) {
  if ([DateTime]::UtcNow -gt $deadline) { Stop-Process -Id $process.Id -Force; throw "Cluster probe timeout; inspect $testRoot" }
}
$results=Join-Path $workspace '.test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
$reportPath=Join-Path $testRoot 'current/horizon-cluster-probe.json'
$logPath=Join-Path $testRoot 'current/beamng.log'
Copy-Item -LiteralPath $logPath -Destination (Join-Path $results ($runName+'.log'))
if (-not (Test-Path -LiteralPath $reportPath)) { throw "No cluster probe report; inspect $logPath" }
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $results ($runName+'.json'))
$report=Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$report | ConvertTo-Json -Depth 7
if (-not $report.ok) { throw "Cluster probe failed: $($report.detail)" }
