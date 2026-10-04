param([string]$OutputName = 'horizon_rewind_circleainn.zip')
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetFileName($OutputName) -ne $OutputName -or -not $OutputName.EndsWith('.zip')) {
  throw 'OutputName must be a ZIP file name, without a directory.'
}
$source = Join-Path $PSScriptRoot 'mod'
$outputDirectory = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
$output = Join-Path $outputDirectory $OutputName
Add-Type -AssemblyName System.IO.Compression
$file = [IO.File]::Open($output, [IO.FileMode]::Create)
$archive = [IO.Compression.ZipArchive]::new($file, [IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -LiteralPath $source -File -Recurse | Sort-Object FullName | ForEach-Object {
    $entryName = [IO.Path]::GetRelativePath($source, $_.FullName).Replace('\', '/')
    $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
    $inputStream = [IO.File]::OpenRead($_.FullName)
    $outputStream = $entry.Open()
    try { $inputStream.CopyTo($outputStream) }
    finally { $inputStream.Dispose(); $outputStream.Dispose() }
  }
  $licenseEntry = $archive.CreateEntry('LICENSE.txt', [IO.Compression.CompressionLevel]::Optimal)
  $licenseInput = [IO.File]::OpenRead((Join-Path $PSScriptRoot 'LICENSE'))
  $licenseOutput = $licenseEntry.Open()
  try { $licenseInput.CopyTo($licenseOutput) }
  finally { $licenseInput.Dispose(); $licenseOutput.Dispose() }
}
finally { $archive.Dispose(); $file.Dispose() }
Write-Output $output
