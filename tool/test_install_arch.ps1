# Architecture detection is the one part of install.ps1 that running the real
# installer cannot cover: a .NET static property cannot be shadowed the way
# tool/verify_installer.ps1 shadows Invoke-WebRequest. Each case runs a copy of
# install.ps1 with that probe substituted, and asserts every substitution
# matched, so a rewritten installer fails here instead of passing vacuously.
#
# Every case stops at a check that precedes the first download, so the test
# needs no network and installs nothing. Cases that must clear the architecture
# gate set an unusable WAYFINDER_VERSION and expect its rejection as proof.
$ErrorActionPreference = 'Stop'
$Source = Get-Content (Join-Path $PSScriptRoot 'install.ps1') -Raw
$ProbeExpression = '[string][System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture'
$MachineExpression = "[Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE', 'Machine')"
$PassedGate = 'WAYFINDER_VERSION must be a published release version.'
$TestRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('wayfinder arch ' + [guid]::NewGuid().ToString('N'))
$OriginalVersion = $env:WAYFINDER_VERSION
$OriginalRoot = $env:WAYFINDER_INSTALL_ROOT
$OriginalWow = $env:PROCESSOR_ARCHITEW6432
$OriginalProcess = $env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory $TestRoot | Out-Null
# Nothing here reaches an installation, but no case may depend on the host's
# LOCALAPPDATA to clear the caller-input checks that precede the version check.
$env:WAYFINDER_INSTALL_ROOT = Join-Path $TestRoot 'runtime'

# Returns the message install.ps1 fails with, or '' when it does not fail.
function Get-Refusal {
    param(
        [Parameter(Mandatory = $true)][string]$Case,
        [Parameter(Mandatory = $true)][hashtable]$Substitutions
    )
    $Text = $Source
    foreach ($Substitution in $Substitutions.GetEnumerator()) {
        if (-not $Text.Contains($Substitution.Key)) {
            throw "install.ps1 no longer contains, so $Case cannot be tested: $($Substitution.Key)"
        }
        $Text = $Text.Replace($Substitution.Key, $Substitution.Value)
    }
    $Copy = Join-Path $TestRoot "install-$Case.ps1"
    Set-Content $Copy $Text -Encoding UTF8
    try { & $Copy } catch { return $_.Exception.Message }
    return ''
}

function Assert-Refusal {
    param(
        [Parameter(Mandatory = $true)][string]$Case,
        [Parameter(Mandatory = $true)][hashtable]$Substitutions,
        [Parameter(Mandatory = $true)][string]$Expected
    )
    $Message = Get-Refusal -Case $Case -Substitutions $Substitutions
    if ($Message -notlike "*$Expected*") {
        throw "$Case`: expected a failure like '$Expected', got '$Message'."
    }
    Write-Host "OK: $Case"
}

try {
    # The #98 regression. An empty probe is unknown, not unsupported, so the
    # machine environment decides and this x64 runner clears the gate.
    $env:WAYFINDER_VERSION = 'unusable'
    Assert-Refusal -Case 'empty-probe-uses-the-environment' -Expected $PassedGate `
        -Substitutions @{ $ProbeExpression = "''" }

    # AMD64 is how Windows names x64 in the environment.
    Assert-Refusal -Case 'amd64-environment-is-x64' -Expected $PassedGate `
        -Substitutions @{ $ProbeExpression = "''"; $MachineExpression = "'AMD64'" }

    # A probe that does report the machine still decides.
    Assert-Refusal -Case 'arm64-probe-is-refused' -Expected 'Windows Arm64 has no prebuilt' `
        -Substitutions @{ $ProbeExpression = "'Arm64'" }

    # An Arm64 machine running an emulated x64 process: the machine scope
    # reports the hardware that the process variable would misreport as AMD64.
    Assert-Refusal -Case 'arm64-environment-is-refused' -Expected 'Windows ARM64 has no prebuilt' `
        -Substitutions @{ $ProbeExpression = "''"; $MachineExpression = "'ARM64'" }

    # Nothing to go on: say so, rather than name an architecture (#98).
    $env:PROCESSOR_ARCHITEW6432 = ''
    $env:PROCESSOR_ARCHITECTURE = ''
    Assert-Refusal -Case 'indeterminate-is-reported' -Expected 'Could not determine' `
        -Substitutions @{ $ProbeExpression = "''"; $MachineExpression = '$null' }

    Write-Host 'PASS: install.ps1 architecture detection, fallback and refusals.'
} finally {
    $env:WAYFINDER_VERSION = $OriginalVersion
    $env:WAYFINDER_INSTALL_ROOT = $OriginalRoot
    $env:PROCESSOR_ARCHITEW6432 = $OriginalWow
    $env:PROCESSOR_ARCHITECTURE = $OriginalProcess
    Remove-Item $TestRoot -Recurse -Force -ErrorAction SilentlyContinue
}
