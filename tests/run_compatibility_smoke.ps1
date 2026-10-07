param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive',
  [string]$GrimeArchive=(Join-Path $env:LOCALAPPDATA 'BeamNG/BeamNG.drive/current/mods/repo/whytey_grime_dynamic_dirt.zip'))
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$userRoot=Join-Path ([IO.Path]::GetTempPath()) ('horizon-rewind-compatibility-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$current=Join-Path $userRoot 'current'
$modRoot=Join-Path $current 'mods/unpacked/horizon_rewind'
New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modRoot -Recurse
New-Item -ItemType Directory -Path (Join-Path $current 'mods/repo') -Force | Out-Null
Copy-Item -LiteralPath $GrimeArchive -Destination (Join-Path $current 'mods/repo/whytey_grime_dynamic_dirt.zip')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindCompatibilitySmoke.lua') -Destination (Join-Path $modRoot 'lua/ge/extensions/horizonRewindCompatibilitySmoke.lua')
$script=Join-Path $modRoot 'scripts/horizonRewindCompatibilitySmoke'
New-Item -ItemType Directory -Path $script -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $script 'modScript.lua'),"extensions.load('horizonRewindCompatibilitySmoke')",[Text.UTF8Encoding]::new($false))
Write-Output "Compatibility test: $userRoot"
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -WorkingDirectory $GameRoot -ArgumentList @('-userpath',$userRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(160)
while(-not $process.WaitForExit(1000)){if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $process.Id -Force;throw 'Compatibility test timed out'}}
$report=Join-Path $current 'horizon-rewind-compatibility.json'
if(-not(Test-Path -LiteralPath $report)){throw "Compatibility report missing: $userRoot"}
$value=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Write-Output "$($value.ok): $($value.message)"
Write-Output "Report: $report"
if($value.ok -ne $true){throw 'Compatibility test failed'}
