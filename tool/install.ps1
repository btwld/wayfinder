# Install the complete Wayfinder runtime and okfp without Dart or admin rights.
$ErrorActionPreference = 'Stop'
$WayfinderVersion = '0.0.1-dev.1'
$ReleaseRoot = "https://github.com/conceptadev/wayfinder-dist/releases/download/wayfinder-v$WayfinderVersion"
if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
    throw 'Only Windows x64 has a prebuilt Wayfinder bundle.'
}
$RuntimeRoot = if ($env:WAYFINDER_INSTALL_ROOT) { $env:WAYFINDER_INSTALL_ROOT } else {
    Join-Path $env:LOCALAPPDATA 'WayfinderRuntime'
}
if (-not [System.IO.Path]::IsPathRooted($RuntimeRoot)) {
    throw 'WAYFINDER_INSTALL_ROOT must be an absolute path.'
}
# Windows exposes the current bundle bin directory through the user PATH. Each
# version stays intact, so updating never replaces DLLs held by running programs.
$Asset = 'wayfinder-windows-x64.tar.gz'
$Stage = Join-Path $RuntimeRoot ('.install.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
try {
    $Archive = Join-Path $Stage $Asset
    Invoke-WebRequest "$ReleaseRoot/$Asset" -OutFile $Archive
    $Checksum = Join-Path $Stage 'checksum'
    Invoke-WebRequest "$ReleaseRoot/$Asset.sha256" -OutFile $Checksum
    $Expected = ((Get-Content $Checksum -Raw).Trim() -split '\s+')[0]
    if ($Expected -notmatch '^[a-fA-F0-9]{64}$' -or
        (Get-FileHash $Archive -Algorithm SHA256).Hash -ne $Expected) {
        throw 'Release checksum mismatch.'
    }
    # Normalize both sides of the containment check, including Windows 8.3
    # aliases such as RUNNER~1 in a caller-supplied installation root.
    $Bundle = [System.IO.Path]::GetFullPath((Join-Path $Stage 'bundle'))
    New-Item -ItemType Directory -Path $Bundle | Out-Null
    & tar -xzf $Archive -C $Bundle
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the runtime bundle.' }
    foreach ($Line in Get-Content (Join-Path $Bundle 'SHA256SUMS')) {
        if ($Line -notmatch '^([a-f0-9]{64})  (.+)$') { throw 'Invalid bundle checksum manifest.' }
        $Hash = $Matches[1]
        $Relative = $Matches[2]
        $File = [System.IO.Path]::GetFullPath((Join-Path $Bundle $Relative))
        if (-not $File.StartsWith($Bundle + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Invalid path in bundle manifest.'
        }
        if ((Get-FileHash $File -Algorithm SHA256).Hash -ne $Hash) {
            throw "Bundle checksum mismatch: $Relative"
        }
    }
    $Binary = Join-Path $Bundle 'bin/wayfinder.exe'
    $Actual = & $Binary --version
    if ($LASTEXITCODE -ne 0 -or $Actual -ne "wayfinder $WayfinderVersion") {
        throw 'Unexpected application version.'
    }
    & (Join-Path $Bundle 'bin/okfp.exe') --version
    if ($LASTEXITCODE -ne 0) { throw 'The validation gate could not start.' }
    $Destination = Join-Path $RuntimeRoot ($WayfinderVersion + '-' + [guid]::NewGuid().ToString('N'))
    Move-Item $Bundle $Destination
    $Bin = Join-Path $Destination 'bin'
    $PreviousFile = Join-Path $RuntimeRoot 'installed-bin.txt'
    $Previous = if (Test-Path $PreviousFile) { (Get-Content $PreviousFile -Raw).Trim() } else { '' }
    $UserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $Entries = @($UserPath -split ';' | Where-Object { $_ -and $_ -ne $Previous -and $_ -ne $Bin })
    [Environment]::SetEnvironmentVariable('PATH', (@($Bin) + $Entries) -join ';', 'User')
    $env:PATH = (@($Bin) + @($env:PATH -split ';' | Where-Object { $_ -and $_ -ne $Previous })) -join ';'
    Set-Content $PreviousFile $Bin
    Write-Host "Installed Wayfinder $WayfinderVersion and okfp. Open a new terminal to refresh PATH."
} finally {
    Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
}
