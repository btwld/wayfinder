# Install the complete Wayfinder runtime without Dart or admin rights.
# The script block keeps preferences and variables out of the caller's session
# when run through `irm ... | iex`.
& {
$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 downloads far slower while drawing progress.
$ProgressPreference = 'SilentlyContinue'
# Windows PowerShell 5.1 hosts can still default to TLS 1.0, which GitHub
# refuses with an unhelpful transport error. PowerShell 7 already negotiates
# TLS 1.2, and this setting outlives the script, so only older hosts pay it.
if ($PSVersionTable.PSVersion.Major -lt 6) {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
}
function Get-MachineArchitecture {
    # The .NET probe is absent before .NET 4.7.1, and some interactive Windows
    # PowerShell 5.1 sessions return nothing from it instead of an architecture,
    # so an empty result means unknown rather than unsupported (#98).
    try {
        $Probe = [string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
        if ($Probe) { return $Probe }
    } catch {
        # The name resolved to a type without a usable OSArchitecture.
    }
    # Windows' own machine-scope environment reports the hardware, even inside
    # an emulated process, where the process variable claims AMD64 on an Arm64
    # machine. PROCESSOR_ARCHITEW6432 reports it for a 32-bit process on 64-bit
    # Windows, where PROCESSOR_ARCHITECTURE reports x86.
    $Fallback = ''
    try { $Fallback = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine') } catch { }
    if (-not $Fallback) { $Fallback = $env:PROCESSOR_ARCHITEW6432 }
    if (-not $Fallback) { $Fallback = $env:PROCESSOR_ARCHITECTURE }
    if ($Fallback -eq 'AMD64') { return 'X64' }
    return $Fallback
}
# Check the machine, its tools and every caller input before any download, so
# a typo costs no round trip and no partial state. install.sh does the same.
$Architecture = Get-MachineArchitecture
if (-not $Architecture) {
    throw ('Could not determine this machine''s processor architecture; the installer ' +
        'did not assume one. On Windows x64, install from a clean session with: ' +
        'powershell -NoProfile -Command "irm ' +
        'https://raw.githubusercontent.com/btwld/wayfinder/main/tool/install.ps1 | iex"')
}
if ($Architecture -ne 'X64') {
    throw "Windows $Architecture has no prebuilt Wayfinder bundle; only Windows x64 has one."
}
# Windows has shipped tar since Windows 10 1803; name it when it is missing.
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    throw 'Required command is missing: tar'
}
$Skills = if ($env:WAYFINDER_SKILLS) { $env:WAYFINDER_SKILLS } else { 'all' }
if ($Skills -notin @('all', 'claude', 'agents', 'none')) {
    throw 'WAYFINDER_SKILLS must be all, claude, agents or none.'
}
# Windows exposes the current bundle bin directory through the user PATH. Each
# version stays intact, so updating never replaces DLLs held by running programs.
$RuntimeRoot = if ($env:WAYFINDER_INSTALL_ROOT) { $env:WAYFINDER_INSTALL_ROOT } else {
    Join-Path $env:LOCALAPPDATA 'WayfinderRuntime'
}
if (-not [System.IO.Path]::IsPathRooted($RuntimeRoot)) {
    throw 'WAYFINDER_INSTALL_ROOT must be an absolute path.'
}
# The default is the newest stable Wayfinder release. WAYFINDER_VERSION selects
# another published release; CI and `wayfinder update` use it to pin a version.
$WayfinderVersion = $env:WAYFINDER_VERSION
if (-not $WayfinderVersion) {
    # GitHub's latest-release page redirects to its tag. The web redirect avoids
    # the API's per-address rate limit; only application releases may be latest.
    $Response = Invoke-WebRequest 'https://github.com/btwld/wayfinder/releases/latest' -UseBasicParsing
    # Windows PowerShell 5.1 and PowerShell 7 expose the final URL differently.
    $Final = if ($Response.BaseResponse.ResponseUri) {
        $Response.BaseResponse.ResponseUri.AbsoluteUri
    } else {
        $Response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
    }
    if ($Final -notmatch '/releases/tag/wayfinder-v(\d+\.\d+\.\d+)$') {
        throw 'The latest release is not a Wayfinder release; set WAYFINDER_VERSION.'
    }
    $WayfinderVersion = $Matches[1]
}
if ($WayfinderVersion -notmatch '^\d+\.\d+\.\d+(-[A-Za-z0-9.-]+)?$') {
    throw 'WAYFINDER_VERSION must be a published release version.'
}
$ReleaseRoot = "https://github.com/btwld/wayfinder/releases/download/wayfinder-v$WayfinderVersion"
$Asset = 'wayfinder-windows-x64.tar.gz'
$Stage = Join-Path $RuntimeRoot ('.install.' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Stage -Force | Out-Null
try {
    $Archive = Join-Path $Stage $Asset
    Write-Host "Downloading Wayfinder $WayfinderVersion for windows-x64..."
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
