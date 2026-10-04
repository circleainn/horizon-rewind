param([string]$GrimeArchive=(Join-Path $env:LOCALAPPDATA 'BeamNG/BeamNG.drive/current/mods/repo/whytey_grime_dynamic_dirt.zip'))
$ErrorActionPreference='Stop'
$destination=Join-Path ([IO.Path]::GetTempPath()) ('horizon-grime-canvas-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $destination | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($GrimeArchive)
try {
  foreach($name in @('dirt','rough','glass')) {
    $entry=$archive.GetEntry("vehicles/common/dynamic_dirt/$name.js")
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,(Join-Path $destination "$name.js"))
  }
} finally {$archive.Dispose()}
$previous=$env:GRIME_CANVAS_DIRECTORY
try {
  $env:GRIME_CANVAS_DIRECTORY=$destination
  node (Join-Path $PSScriptRoot 'grime_canvas_spec.cjs')
  if($LASTEXITCODE -ne 0){throw 'Grime canvas checks failed'}
} finally {$env:GRIME_CANVAS_DIRECTORY=$previous}
