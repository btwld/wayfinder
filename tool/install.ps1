# Installs the okf and okfp binaries for the Concepta OKF Profile on Windows.
#
#   irm https://raw.githubusercontent.com/conceptadev/okf-profile-dist/main/tool/install.ps1 | iex
#
# No Dart SDK, no gh, no administrator prompt. Binaries land in
# %LOCALAPPDATA%\okf\bin (override with OKF_INSTALL_DIR) and that directory
# is added to the user PATH. Versions are pinned below, together with
# install.sh, and CI keeps the two in step (docs/releasing.md).
$ErrorActionPreference = 'Stop'

$OkfVersion = 'v0.3.0'
$OkfpVersion = 'v0.2.0'
$OkfReleases = 'conceptadev/okf'
$OkfpReleases = 'conceptadev/okf-profile-dist'

$installDir = if ($env:OKF_INSTALL_DIR) { $env:OKF_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'okf\bin' }

if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
  throw "install: no prebuilt Windows binaries for $($env:PROCESSOR_ARCHITECTURE); only x64 is supported"
}

function Get-ReportedVersion([string]$Path) {
  if (-not (Test-Path $Path)) { return '' }
  try { return ((& $Path --version 2>$null) -join '').Trim() } catch { return '' }
}

# Attestations are verified when a signed-in gh is around; the download itself
# never needs it.
$verify = $false
if (Get-Command gh -ErrorAction SilentlyContinue) {
  try { gh auth status *> $null; $verify = ($LASTEXITCODE -eq 0) } catch { $verify = $false }
}

function Install-Tool([string]$Name, [string]$Version, [string]$Repo) {
  $bare = $Version.TrimStart('v')
  $asset = "$Name-windows-x64.exe"
  $target = Join-Path $installDir "$Name.exe"

  if ((Get-ReportedVersion $target) -eq "$Name $bare") {
    Write-Host "install: $Name is already $bare, nothing to do"
    return
  }

  $tmp = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName() + '.exe')
  Write-Host "install: downloading $Name $bare for windows-x64"
  Invoke-WebRequest -Uri "https://github.com/$Repo/releases/download/$Version/$asset" -OutFile $tmp -UseBasicParsing
  if ($verify) {
    gh release verify-asset $Version $tmp --repo $Repo *> $null
    if ($LASTEXITCODE -ne 0) { throw "install: $asset did not verify against the $Repo $Version release" }
  }
  # Invoke-WebRequest marks downloads as from the web; clear it so SmartScreen
  # does not block a console tool.
  Unblock-File $tmp
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Move-Item -Force $tmp $target
  Write-Host "install: $(Get-ReportedVersion $target) -> $target"
}

Install-Tool okf $OkfVersion $OkfReleases
Install-Tool okfp $OkfpVersion $OkfpReleases

if (-not $verify) {
  Write-Host 'install: release attestations were not verified (no signed-in gh); that is fine for everyday use'
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $installDir) {
  [Environment]::SetEnvironmentVariable('Path', "$installDir;$userPath", 'User')
  Write-Host "install: added $installDir to your user PATH; open a new terminal to use okf and okfp"
}
if (($env:Path -split ';') -notcontains $installDir) { $env:Path = "$installDir;$env:Path" }
