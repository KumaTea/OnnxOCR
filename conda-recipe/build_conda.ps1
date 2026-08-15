<#
.SYNOPSIS
    Build the noarch conda package for onnxocr.

.DESCRIPTION
    The package is pure Python with bundled ONNX model data, so this produces a
    single `noarch: python` artifact valid on every OS and architecture -- no
    compiler, no per-platform builds.

    Source is the sdist published on PyPI, pinned by sha256, so the conda
    package contains the same bits as the wheel. Pass -Version to build a
    different release; the sha256 is fetched from PyPI automatically unless you
    pass -Sha256 explicitly.

    conda-build is installed into a dedicated env (default: onnxocr-build) so
    nothing touches your existing environments.

.EXAMPLE
    .\build_conda.ps1
    Build 3.1.0 into .\conda-dist

.EXAMPLE
    .\build_conda.ps1 -Version 3.2.0
    Build 3.2.0, fetching its sha256 from PyPI

.EXAMPLE
    .\build_conda.ps1 -BuildEnv pypi
    Reuse an existing env that already has conda-build
#>
[CmdletBinding()]
param(
    [string] $Version      = "3.1.0",
    [string] $Sha256       = "",
    [string] $Conda        = "C:\Pkgs\conda\Scripts\conda.exe",
    [string] $BuildEnv     = "onnxocr-build",
    [string] $OutputFolder = "",
    [string] $Channel      = "conda-forge",
    [switch] $SkipTest,
    [switch] $KeepBuildEnv
)

$ErrorActionPreference = "Stop"
$RecipeDir = $PSScriptRoot
if (-not $OutputFolder) { $OutputFolder = Join-Path (Split-Path $RecipeDir -Parent) "conda-dist" }

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!! $m" -ForegroundColor Yellow }

# conda writes progress to stderr. Under $ErrorActionPreference='Stop', Windows
# PowerShell 5.1 turns native stderr into a terminating NativeCommandError, so a
# perfectly healthy conda run would abort the script. Drop to 'Continue' around
# native calls and judge success by exit code instead.
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $Exe,
        [Parameter(ValueFromRemainingArguments)][string[]] $Arguments
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try   { & $Exe @Arguments }
    finally { $ErrorActionPreference = $prev }
}

# --- Windows: let cmd.exe resolve conda-build's generated batch file --------
# conda-build runs `cmd.exe /d /c conda_build.bat` from the work directory and
# relies on cmd searching the current directory. If
# NoDefaultCurrentDirectoryInExePath is set, cmd refuses to do that and every
# build dies with "'conda_build.bat' is not recognized". Clear it for this
# process only; the parent shell is unaffected.
if (Test-Path Env:\NoDefaultCurrentDirectoryInExePath) {
    Warn "NoDefaultCurrentDirectoryInExePath is set; clearing it for this build (conda-build needs cmd.exe to resolve conda_build.bat from the work dir)"
    Remove-Item Env:\NoDefaultCurrentDirectoryInExePath
}

# --- locate conda -----------------------------------------------------------
if (-not (Test-Path $Conda)) {
    $found = Get-Command conda.exe -ErrorAction SilentlyContinue
    if ($found) { $Conda = $found.Source }
    else { throw "conda.exe not found at '$Conda'. Pass -Conda <path>." }
}
Info "conda: $Conda ($(Invoke-Native $Conda --version))"

# --- resolve the sdist hash -------------------------------------------------
if (-not $Sha256) {
    Info "Fetching sha256 for onnxocr $Version from PyPI"
    try {
        $meta = Invoke-RestMethod -Uri "https://pypi.org/pypi/onnxocr/$Version/json" -UseBasicParsing
    } catch {
        throw "Could not reach PyPI for onnxocr $Version. Publish it first, or pass -Sha256. ($_)"
    }
    $sdist = $meta.urls | Where-Object { $_.packagetype -eq "sdist" } | Select-Object -First 1
    if (-not $sdist) { throw "No sdist published for onnxocr $Version; conda needs the source tarball." }
    $Sha256 = $sdist.digests.sha256
}
Info "onnxocr $Version  sha256=$Sha256"

# meta.yaml reads these via environ.get, so no file editing is needed.
$env:ONNXOCR_VERSION = $Version
$env:ONNXOCR_SHA256  = $Sha256

# --- ensure a conda-build environment --------------------------------------
$envList = Invoke-Native $Conda env list
$hasEnv  = $envList | Select-String -Pattern "^\s*$([regex]::Escape($BuildEnv))\s" -Quiet

if (-not $hasEnv) {
    Info "Creating build env '$BuildEnv' with conda-build (from $Channel)"
    Invoke-Native $Conda create -n $BuildEnv -c $Channel --override-channels -y "python=3.12" conda-build
    if ($LASTEXITCODE -ne 0) { throw "Failed to create build env '$BuildEnv'." }
} else {
    $hasCB = (Invoke-Native $Conda list -n $BuildEnv conda-build) | Select-String -Pattern "^conda-build\s" -Quiet
    if (-not $hasCB) {
        Info "Installing conda-build into existing env '$BuildEnv'"
        Invoke-Native $Conda install -n $BuildEnv -c $Channel --override-channels -y conda-build
        if ($LASTEXITCODE -ne 0) { throw "Failed to install conda-build into '$BuildEnv'." }
    } else {
        Info "Reusing build env '$BuildEnv'"
    }
}

# --- build ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$buildArgs = @(
    "build", $RecipeDir,
    "-c", $Channel, "--override-channels",
    "--output-folder", $OutputFolder
)
if ($SkipTest) { $buildArgs += "--no-test" }

Info "conda build $RecipeDir -> $OutputFolder"
Invoke-Native $Conda run -n $BuildEnv --no-capture-output conda @buildArgs
if ($LASTEXITCODE -ne 0) { throw "conda build failed with exit code $LASTEXITCODE." }

# --- report -----------------------------------------------------------------
$artifacts = Get-ChildItem -Path (Join-Path $OutputFolder "noarch") -Include *.conda, *.tar.bz2 -Recurse -ErrorAction SilentlyContinue
if (-not $artifacts) { throw "Build reported success but produced no noarch artifact in $OutputFolder." }

Info "Built:"
foreach ($a in $artifacts) { "    {0,8:N2} MB  {1}" -f ($a.Length / 1MB), $a.FullName | Write-Host }

if (-not $KeepBuildEnv) {
    Write-Host ""
    Warn "Build env '$BuildEnv' was kept for faster rebuilds. Remove with: conda env remove -n $BuildEnv"
}

Write-Host ""
Info "Install locally to verify:"
Write-Host "    conda create -n onnxocr-test -c $Channel --override-channels -y python=3.12"
Write-Host "    conda install -n onnxocr-test -c `"$OutputFolder`" -c $Channel --override-channels -y onnxocr"
Write-Host ""
Info "Upload to your anaconda.org channel:"
Write-Host "    conda install -n $BuildEnv -c $Channel -y anaconda-client"
Write-Host "    conda run -n $BuildEnv anaconda login"
Write-Host "    conda run -n $BuildEnv anaconda upload `"$($artifacts[0].FullName)`""
