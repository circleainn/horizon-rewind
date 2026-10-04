param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive')
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$userRoot=Join-Path ([IO.Path]::GetTempPath()) ('horizon-rewind-traffic-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$current=Join-Path $userRoot 'current'
$modRoot=Join-Path $current 'mods/unpacked/horizon_rewind'
New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modRoot -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindTrafficSmoke.lua') -Destination (Join-Path $modRoot 'lua/ge/extensions/horizonRewindTrafficSmoke.lua')
$script=Join-Path $modRoot 'scripts/horizonRewindTrafficSmoke'
New-Item -ItemType Directory -Path $script -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $script 'modScript.lua'),"extensions.load('horizonRewindTrafficSmoke')",[Text.UTF8Encoding]::new($false))
Write-Output "Traffic test: $userRoot"
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -WorkingDirectory $GameRoot -ArgumentList @('-userpath',$userRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(160)
while(-not $process.WaitForExit(1000)){if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $process.Id -Force;throw 'Traffic test timed out'}}
$report=Join-Path $current 'horizon-rewind-traffic.json'
if(-not(Test-Path -LiteralPath $report)){throw "Traffic report missing: $userRoot"}
$value=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Write-Output "$($value.ok): $($value.message)"
Write-Output "Report: $report"
if($value.ok -ne $true){throw 'Traffic test failed'}
