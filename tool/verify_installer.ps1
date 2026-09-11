param([Parameter(Mandatory=$true)][string]$Archive)
$ErrorActionPreference = 'Stop'
$SourceArchive = (Resolve-Path $Archive).Path
$Workspace = Split-Path $PSScriptRoot -Parent
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wayfinder install ' + [guid]::NewGuid().ToString('N'))
$OriginalPath = $env:PATH
$OriginalUserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$OriginalRoot = $env:WAYFINDER_INSTALL_ROOT
$OriginalData = $env:WAYFINDER_DATA_DIR
New-Item -ItemType Directory $TestRoot | Out-Null
$env:WAYFINDER_INSTALL_ROOT = Join-Path $TestRoot 'runtime'
$env:WAYFINDER_DATA_DIR = Join-Path $TestRoot 'data'
$env:PATH = (($env:PATH -split ';') | Where-Object {
    $_ -and -not (Test-Path (Join-Path $_ 'dart.exe')) -and -not (Test-Path (Join-Path $_ 'dart.bat'))
}) -join ';'
if (Get-Command dart -ErrorAction SilentlyContinue) { throw 'Probe PATH must not contain Dart.' }
$script:Corrupt = $false
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile)
    if ($Uri.EndsWith('.sha256')) {
        if ($script:Corrupt) { Set-Content $OutFile (('0' * 64) + '  wayfinder-windows-x64.tar.gz') }
        else { Copy-Item ($SourceArchive + '.sha256') $OutFile }
    } else { Copy-Item $SourceArchive $OutFile }
}
try {
    & (Join-Path $PSScriptRoot 'install.ps1')
    $InstalledBin = (Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim()
    $Corpus = Join-Path $Workspace 'packages/wayfinder/test/fixtures/knowledge'
    $Result = & (Join-Path $InstalledBin 'wayfinder.exe') index $Corpus --output=json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $Result.embeddedChunks -le 0) { throw 'Initial indexing failed.' }
    & (Join-Path $InstalledBin 'wayfinder.exe') search $Corpus password --output=json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Installed search failed.' }
    Remove-Item (Join-Path (Split-Path $InstalledBin -Parent) 'models/embedding.gguf')
    & (Join-Path $PSScriptRoot 'install.ps1')
    $InstalledBin = (Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim()
    $Result = & (Join-Path $InstalledBin 'wayfinder.exe') index $Corpus --output=json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $Result.embeddedChunks -ne 0) { throw 'Repair did not preserve the index.' }
    $script:Corrupt = $true
    $Rejected = $false
    try { & (Join-Path $PSScriptRoot 'install.ps1') } catch {
        if ($_.Exception.Message -notlike '*checksum mismatch*') { throw }
        $Rejected = $true
    }
    if (-not $Rejected) { throw 'Corrupted download was accepted.' }
    if ((Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim() -ne $InstalledBin) {
        throw 'Failed installation changed the current runtime.'
    }
    Write-Host 'PASS: no-Dart Windows install, quoted paths, retrieval, repair, index reuse, corrupt download refusal.'
} finally {
    [Environment]::SetEnvironmentVariable('PATH', $OriginalUserPath, 'User')
    $env:PATH = $OriginalPath
    $env:WAYFINDER_INSTALL_ROOT = $OriginalRoot
    $env:WAYFINDER_DATA_DIR = $OriginalData
    Remove-Item $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
