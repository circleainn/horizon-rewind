param([string]$GameRoot='C:\Steam\steamapps\common\BeamNG.drive',[string]$Model='bastion',[switch]$WithDirt,[switch]$Coast)
$ErrorActionPreference='Stop'
if($Model -notmatch '^[a-zA-Z0-9_]+$') {throw 'Invalid vehicle model'}
$workspace=Split-Path -Parent $PSScriptRoot
$userRoot=Join-Path ([IO.Path]::GetTempPath()) ('horizon-rewind-drive-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
if($userRoot -match '\s'){throw 'Test user path must not contain spaces'}
$current=Join-Path $userRoot 'current'
$modRoot=Join-Path $current 'mods/unpacked/horizon_rewind'
New-Item -ItemType Directory -Path $modRoot -Force | Out-Null
Copy-Item -Path (Join-Path $workspace 'mod/*') -Destination $modRoot -Recurse
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindDriveSmoke.lua') -Destination (Join-Path $modRoot 'lua/ge/extensions/horizonRewindDriveSmoke.lua')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'horizonRewindDriveProbe.lua') -Destination (Join-Path $modRoot 'lua/vehicle/extensions/horizonRewindDriveProbe.lua')
$script=Join-Path $modRoot 'scripts/horizonRewindDriveSmoke'
New-Item -ItemType Directory -Path $script -Force | Out-Null
$coastLiteral=if($Coast){'true'}else{'false'}
[IO.File]::WriteAllText((Join-Path $script 'modScript.lua'),("HR_DRIVE_MODEL='$Model';HR_DRIVE_COAST=$coastLiteral;extensions.load('horizonRewindDriveSmoke')"),[Text.UTF8Encoding]::new($false))
if($WithDirt){$repo=Join-Path $current 'mods/repo';New-Item -ItemType Directory -Path $repo -Force | Out-Null;Copy-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'BeamNG/BeamNG.drive/current/mods/repo/whytey_grime_dynamic_dirt.zip') -Destination $repo}
Write-Output "Drive test: $userRoot"
$process=Start-Process -FilePath (Join-Path $GameRoot 'Bin64/BeamNG.drive.x64.exe') -WorkingDirectory $GameRoot -ArgumentList @('-userpath',$userRoot,'-headless','-level','smallgrid','-gfx','null','-noui') -WindowStyle Hidden -PassThru
$deadline=[DateTime]::UtcNow.AddSeconds(200)
while(-not $process.WaitForExit(1000)){if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $process.Id -Force;throw 'Drive test timed out'}}
$report=Join-Path $current 'horizon-rewind-drive.json'
if(-not(Test-Path -LiteralPath $report)){throw "Drive report missing: $userRoot"}
$value=Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
Write-Output "$($value.ok): $($value.message)"
Write-Output "Report: $report"
if($value.ok -ne $true){throw 'Drive test failed'}
