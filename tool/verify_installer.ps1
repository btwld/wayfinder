param([Parameter(Mandatory=$true)][string]$Archive)
$ErrorActionPreference = 'Stop'
$SourceArchive = (Resolve-Path $Archive).Path
$Workspace = Split-Path $PSScriptRoot -Parent
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wayfinder install ' + [guid]::NewGuid().ToString('N'))
$OriginalPath = $env:PATH
$OriginalUserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$OriginalRoot = $env:WAYFINDER_INSTALL_ROOT
$OriginalData = $env:WAYFINDER_DATA_DIR
$OriginalVersion = $env:WAYFINDER_VERSION
$OriginalProfile = $env:USERPROFILE
New-Item -ItemType Directory $TestRoot | Out-Null
$env:USERPROFILE = Join-Path $TestRoot 'home'
$env:WAYFINDER_INSTALL_ROOT = Join-Path $TestRoot 'runtime'
$env:WAYFINDER_DATA_DIR = Join-Path $TestRoot 'data'
$env:WAYFINDER_VERSION = (
    Select-String -Path (Join-Path $Workspace 'packages/wayfinder_cli/pubspec.yaml') -Pattern '^version: (.+)$'
).Matches[0].Groups[1].Value
$env:PATH = (($env:PATH -split ';') | Where-Object {
    $_ -and -not (Test-Path (Join-Path $_ 'dart.exe')) -and -not (Test-Path (Join-Path $_ 'dart.bat'))
}) -join ';'
if (Get-Command dart -ErrorAction SilentlyContinue) { throw 'Probe PATH must not contain Dart.' }
$DownloadState = @{ Corrupt = $false }
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing)
    if ($Uri.EndsWith('.sha256')) {
        if ($DownloadState.Corrupt) { Set-Content $OutFile (('0' * 64) + '  wayfinder-windows-x64.tar.gz') }
        else { Copy-Item ($SourceArchive + '.sha256') $OutFile }
    } else { Copy-Item $SourceArchive $OutFile }
}
try {
    & (Join-Path $PSScriptRoot 'install.ps1')
    $InstalledBin = (Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim()
    foreach ($Base in @('.claude', '.agents')) {
        if (-not (Test-Path (Join-Path $env:USERPROFILE "$Base/skills/use-wayfinder/SKILL.md"))) {
            throw "Skills were not installed for $Base."
        }
    }
    $Corpus = Join-Path $Workspace 'packages/wayfinder_cli/test/fixtures/knowledge'
    $Result = & (Join-Path $InstalledBin 'wayfinder.exe') index $Corpus --output=json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $Result.embeddedChunks -le 0) { throw 'Initial indexing failed.' }
    & (Join-Path $InstalledBin 'wayfinder.exe') search $Corpus password --output=json | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Installed search failed.' }
    Remove-Item (Join-Path (Split-Path $InstalledBin -Parent) 'models/embedding.gguf')
    & (Join-Path $PSScriptRoot 'install.ps1')
    $InstalledBin = (Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim()
    $Result = & (Join-Path $InstalledBin 'wayfinder.exe') index $Corpus --output=json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $Result.embeddedChunks -ne 0) { throw 'Repair did not preserve the index.' }
    $DownloadState.Corrupt = $true
    $Rejected = $false
    try { & (Join-Path $PSScriptRoot 'install.ps1') } catch {
        if ($_.Exception.Message -notlike '*checksum mismatch*') { throw }
        $Rejected = $true
    }
    if (-not $Rejected) { throw 'Corrupted download was accepted.' }
    if ((Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim() -ne $InstalledBin) {
        throw 'Failed installation changed the current runtime.'
    }
    # The #98 session, end to end: an architecture probe that returns nothing
    # must still install. A .NET static property cannot be shadowed the way
    # Invoke-WebRequest is above, so this runs a copy of the installer with that
    # probe emptied, and asserts the substitution matched so it cannot pass
    # vacuously. tool/test_install_arch.ps1 covers the refusals without a bundle.
    $DownloadState.Corrupt = $false
    $ProbeExpression = '[string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture'
    $InstallerSource = Get-Content (Join-Path $PSScriptRoot 'install.ps1') -Raw
    if (-not $InstallerSource.Contains($ProbeExpression)) {
        throw 'install.ps1 no longer probes the architecture.'
    }
    $EmptyProbeInstaller = Join-Path $TestRoot 'install-empty-probe.ps1'
    Set-Content $EmptyProbeInstaller $InstallerSource.Replace($ProbeExpression, "''") -Encoding UTF8
    & $EmptyProbeInstaller
    $InstalledBin = (Get-Content (Join-Path $env:WAYFINDER_INSTALL_ROOT 'installed-bin.txt') -Raw).Trim()
    $Result = & (Join-Path $InstalledBin 'wayfinder.exe') index $Corpus --output=json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $null -eq $Result) { throw 'Install with an empty architecture probe failed.' }
    Write-Host 'PASS: no-Dart Windows install, quoted paths, retrieval, repair, index reuse, corrupt download refusal, empty architecture probe.'
} finally {
    [Environment]::SetEnvironmentVariable('PATH', $OriginalUserPath, 'User')
    $env:PATH = $OriginalPath
    $env:WAYFINDER_INSTALL_ROOT = $OriginalRoot
    $env:WAYFINDER_DATA_DIR = $OriginalData
    $env:WAYFINDER_VERSION = $OriginalVersion
    $env:USERPROFILE = $OriginalProfile
    Remove-Item $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
