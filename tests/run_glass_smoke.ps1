param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive')
$ErrorActionPreference='Stop'
$workspace=Split-Path -Parent $PSScriptRoot
$userRoot=Join-Path ([IO.Path]::GetTempPath()) ('horizon-rewind-glass-'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
$current=Join-Path $userRoot 'current'
$modRoot=Join-Path $current 'mods/unpacked/horizon_rewind'
New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modRoot -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindGlassSmoke.lua') -Destination (Join-Path $modRoot 'lua/ge/extensions/horizonRewindGlassSmoke.lua')
$script=Join-Path $modRoot 'scripts/horizonRewindGlassSmoke'
New-Item -ItemType Directory -Path $script -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $script 'modScript.lua'),"extensions.load('horizonRewindGlassSmoke')",[Text.UTF8Encoding]::new($false))
Write-Output "Glass test: $userRoot"
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -WorkingDirectory $GameRoot -ArgumentList @('-userpath',$userRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(160)
while(-not $process.WaitForExit(1000)){if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $process.Id -Force;throw 'Glass test timed out'}}
$report=Join-Path $current 'horizon-rewind-glass.json'
if(-not(Test-Path -LiteralPath $report)){throw "Glass report missing: $userRoot"}
$value=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Write-Output "$($value.ok): $($value.message)"
Write-Output "Report: $report"
if($value.ok -ne $true){throw 'Glass test failed'}
