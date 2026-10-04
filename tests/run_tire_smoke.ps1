param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive',[string]$Model='pickup',[int]$TimeoutSeconds=220,[switch]$PrepareOnly)
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
if($Model -notmatch '^[a-zA-Z0-9_]+$') { throw 'Model must be a BeamNG vehicle folder name' }
$runName='horizon-rewind-tires-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
$userRoot=Join-Path ([IO.Path]::GetTempPath()) $runName
if ($userRoot -match '\s') { throw 'Use a TEMP path without spaces' }
$current=Join-Path $userRoot 'current'
$modRoot=Join-Path $current 'mods/unpacked/horizon_rewind'
$repo=Join-Path $current 'mods/repo'
New-Item -ItemType Directory -Path $modRoot,$repo -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modRoot -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindTireSmoke.lua') -Destination (Join-Path $modRoot 'lua/ge/extensions/horizonRewindTireSmoke.lua')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindTireProbe.lua') -Destination (Join-Path $modRoot 'lua/vehicle/extensions/horizonRewindTireProbe.lua')
$script=Join-Path $modRoot 'scripts/horizonRewindTireSmoke'
New-Item -ItemType Directory -Path $script -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $script 'modScript.lua'),("hrTireSmokeModel='"+$Model+"'; extensions.load('horizonRewindTireSmoke')"),[Text.UTF8Encoding]::new($false))
foreach($name in @('DetachableTires.zip','TireImpactPunctures.zip')) { Copy-Item -LiteralPath ((Join-Path $env:LOCALAPPDATA 'BeamNG/BeamNG.drive/current/mods/repo/')+$name) -Destination $repo }
$reportPath=Join-Path $current 'horizon-rewind-tire-smoke.json'
Write-Output "Tire user directory: $userRoot"
if ($PrepareOnly) { return }
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -WorkingDirectory $GameRoot -ArgumentList @('-userpath',$userRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WindowStyle Hidden -PassThru
Write-Output "Tire test process ID: $($process.Id)"
$deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
while (-not $process.WaitForExit(1000)) { if ([DateTime]::UtcNow -gt $deadline) { Stop-Process -Id $process.Id -Force;throw "Tire smoke timed out; inspect $userRoot" } }
if (-not (Test-Path -LiteralPath $reportPath)) { throw "Missing tire smoke report; inspect $userRoot" }
$report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
Write-Output ('Result: '+$report.ok+'; '+$report.detail)
Write-Output "Report: $reportPath"
$results=Join-Path $workspace '.test-results'
New-Item -ItemType Directory -Path $results -Force | Out-Null
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $results ($runName+'-'+$Model+'.json'))
if($report.ok -eq $true) { Copy-Item -LiteralPath $reportPath -Destination (Join-Path $results ('tire-smoke-'+$Model+'.json')) }
if ($report.ok -ne $true) { throw "Tire smoke failed: $($report.detail)" }
Write-Output 'TIRE_SMOKE_PASSED'
