# Install the complete Wayfinder runtime without Dart or admin rights.
# The script block keeps preferences and variables out of the caller's session
# when run through `irm ... | iex`.
& {
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 downloads far slower while drawing progress.
$ProgressPreference = 'SilentlyContinue'
$WayfinderVersion = '0.0.2'
if ($env:WAYFINDER_VERSION) {
    $WayfinderVersion = $env:WAYFINDER_VERSION
}
if ($WayfinderVersion -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') {
    throw 'WAYFINDER_VERSION must be a published release version.'
}
$Skills = if ($env:WAYFINDER_SKILLS) { $env:WAYFINDER_SKILLS } else { 'all' }
if ($Skills -notin @('all', 'claude', 'agents', 'none')) {
    throw 'WAYFINDER_SKILLS must be all, claude, agents or none.'
}
$ReleaseRoot = "https://github.com/conceptadev/wayfinder/releases/download/wayfinder-v$WayfinderVersion"
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
    Invoke-WebRequest "$ReleaseRoot/$Asset" -OutFile $Archive -UseBasicParsing
    $Checksum = Join-Path $Stage 'checksum'
    Invoke-WebRequest "$ReleaseRoot/$Asset.sha256" -OutFile $Checksum -UseBasicParsing
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
    $Destination = Join-Path $RuntimeRoot ($WayfinderVersion + '-' + [guid]::NewGuid().ToString('N'))
    Move-Item $Bundle $Destination
    $Bin = Join-Path $Destination 'bin'
    # Windows PowerShell and PowerShell 7 default to different encodings.
    $PreviousFile = Join-Path $RuntimeRoot 'installed-bin.txt'
    $Previous = if (Test-Path $PreviousFile) { (Get-Content $PreviousFile -Raw -Encoding UTF8).Trim() } else { '' }
    $UserPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $Entries = @($UserPath -split ';' | Where-Object { $_ -and $_ -ne $Previous -and $_ -ne $Bin })
    [Environment]::SetEnvironmentVariable('PATH', (@($Bin) + $Entries) -join ';', 'User')
    $env:PATH = (@($Bin) + @($env:PATH -split ';' | Where-Object { $_ -and $_ -ne $Previous })) -join ';'
    Set-Content $PreviousFile $Bin -Encoding UTF8
    Write-Host "Installed Wayfinder $WayfinderVersion. Open a new terminal to refresh PATH."
    # Agent skills ship with releases that bundle them. A skills failure never
    # undoes the installed runtime.
    if ($Skills -ne 'none' -and (Test-Path (Join-Path $Destination 'skills'))) {
        & (Join-Path $Bin 'wayfinder.exe') skills install "--agent=$Skills"
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Skills were not installed; run wayfinder skills install.'
        }
    }
} finally {
    Remove-Item $Stage -Recurse -Force -ErrorAction SilentlyContinue
}
}
