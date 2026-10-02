<#
.SYNOPSIS
    Build the PyPI sdist and wheel of one or more onnxocr release lines.

.DESCRIPTION
    Every release line is a branch: a fixed upstream commit plus our packaging
    (and, for 3.x/4.x, the source patches listed in PATCHES.md). The table in
    $Lines below is the record of which upstream commit each line is built
    from and how its branch was made. CLAUDE.md explains the scheme.

      Line  Branch       Upstream base
      1.x   release/1.x  353a61e  last commit before PP-OCRv5 (PP-OCRv4)
      2.x   release/2.x  f51dabe  source of the yanked 2025.5 (PP-OCRv5 + v4)
      3.x   main         upstream/main (PP-OCRv5)
      4.x   release/4.x  main + upstream/ppocrv6 (PP-OCRv6)

    For each line the script:
      1. checks out the branch (local, else origin/<branch>) into a temporary
         detached worktree, so your own checkout is never touched
      2. checks the upstream base is an ancestor, and warns if upstream or
         main has commits the line has not merged yet
      3. fetches the Git LFS models (3.x/4.x) and fails on any LFS pointer
      4. uv build: sdist first, then the wheel from the sdist, into -OutDir
      5. twine check, and fails if a file is over PyPI's 100 MB limit or the
         wheel contains an .onnx LFS pointer instead of a model
      6. with -Smoke, installs the wheel into a fresh Python 3.12 venv and runs
         det+cls+rec with det_limit_side_len=340 plus sav2Img

    Nothing is uploaded. The upload command is printed at the end.

.EXAMPLE
    .\build_release.ps1
    Build all four lines into .\dist

.EXAMPLE
    .\build_release.ps1 -Line 3,4 -Smoke
    Build 3.x and 4.x and smoke-test both wheels

.EXAMPLE
    .\build_release.ps1 -Line 2 -Ref 2311a20
    Build one line from a specific commit, e.g. to reproduce an old release
#>
[CmdletBinding()]
param(
    [ValidateSet("1", "2", "3", "4")]
    [string[]] $Line   = @("1", "2", "3", "4"),
    [string]   $Ref    = "",
    [string]   $OutDir = "",
    [switch]   $Smoke,
    [switch]   $KeepWorktree
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $Repo "dist" }
if ($Ref -and $Line.Count -ne 1) { throw "-Ref needs exactly one -Line." }

# Base:      upstream commit the line must contain (checked with merge-base).
# Track:     refs whose new commits mean the line is behind (warning only).
# MadeWith:  how the branch was created; packaging commits follow on top.
$Lines = [ordered]@{
    "1" = @{ Branch = "release/1.x"; Base = "353a61e"; Track = @()
             MadeWith = "git branch release/1.x 353a61e   # + pyproject.toml, MANIFEST.in" }
    "2" = @{ Branch = "release/2.x"; Base = "f51dabe"; Track = @()
             MadeWith = "git branch release/2.x f51dabe   # + pyproject.toml, MANIFEST.in" }
    "3" = @{ Branch = "main";        Base = "23b9798"; Track = @("upstream/main")
             MadeWith = "git merge upstream/main          # on main; packaging + PATCHES.md" }
    "4" = @{ Branch = "release/4.x"; Base = "754b93e"; Track = @("main", "upstream/ppocrv6")
             MadeWith = "git branch release/4.x main; git merge upstream/ppocrv6   # + 4.x patch, packaging" }
}

$PyPILimit = 100MB

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "!!! $m" -ForegroundColor Yellow }

# git, git-lfs and uv write progress to stderr. Under $ErrorActionPreference
# 'Stop', Windows PowerShell 5.1 turns native stderr into a terminating error,
# so drop to 'Continue' around native calls and judge success by exit code.
function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $Exe,
        [Parameter(ValueFromRemainingArguments)][string[]] $Arguments
    )
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # Resolve the executable itself, never a same-named function or alias.
    $app = Get-Command $Exe -CommandType Application | Select-Object -First 1
    try   { & $app @Arguments }
    finally { $ErrorActionPreference = $prev }
}

function RepoGit { Invoke-Native git -C $Repo @args }

function Test-Ancestor($ancestor, $commit) {
    RepoGit merge-base --is-ancestor $ancestor $commit 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

function Resolve-Commit($name) {
    foreach ($candidate in @($name, "origin/$name")) {
        $sha = RepoGit rev-parse --verify --quiet "$candidate^{commit}" 2>$null
        if ($LASTEXITCODE -eq 0 -and $sha) { return @($candidate, "$sha".Trim()) }
    }
    throw "Cannot resolve '$name' locally or on origin. Run: git fetch origin upstream"
}

function Get-LfsPointers($root) {
    Get-ChildItem -Path (Join-Path $root "onnxocr") -Recurse -Filter *.onnx -File |
        Where-Object { $_.Length -lt 1KB } |
        Where-Object { (Get-Content $_.FullName -TotalCount 1) -like "version https://git-lfs*" }
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Get-WheelPointers($wheel) {
    $zip = [IO.Compression.ZipFile]::OpenRead($wheel)
    try { $zip.Entries | Where-Object { $_.FullName -like "*.onnx" -and $_.Length -lt 1KB } | ForEach-Object FullName }
    finally { $zip.Dispose() }
}

$SmokePy = @'
import sys, cv2, onnxocr
from onnxocr.onnx_paddleocr import ONNXPaddleOcr, sav2Img
img = cv2.imread(sys.argv[1])
eng = ONNXPaddleOcr(use_gpu=False, use_angle_cls=True, det_limit_side_len=340, det_limit_type="min")
res = eng.ocr(img)
sav2Img(img, res, name=sys.argv[2])
model = eng.args.det_model_dir.replace("\\", "/").split("/models/")[1]
print(f"SMOKE OK: {len(res[0])} lines, det={model}, from {onnxocr.__file__}")
'@

# --- preflight --------------------------------------------------------------
foreach ($tool in @("git", "uv")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool not found on PATH." }
}
Info "Fetching origin and upstream"
RepoGit fetch --quiet origin
RepoGit fetch --quiet upstream
if ($LASTEXITCODE -ne 0) { Warn "git fetch upstream failed; ancestry warnings may be stale." }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$built = @()

foreach ($key in $Line) {
    $spec = $Lines[$key]
    $name, $sha = Resolve-Commit $(if ($Ref) { $Ref } else { $spec.Branch })
    Write-Host ""
    Info "$key.x: $name ($($sha.Substring(0, 9)))   made with: $($spec.MadeWith)"

    if (-not (Test-Ancestor $spec.Base $sha)) {
        throw "$name does not contain upstream base $($spec.Base); this is not the $key.x line."
    }
    if (-not $Ref) {
        foreach ($track in $spec.Track) {
            $behind = "$(RepoGit rev-list --count "$sha..$track" 2>$null)".Trim()
            if ($LASTEXITCODE -eq 0 -and $behind -ne "0") {
                Warn "$name is $behind commit(s) behind $track; merge it first if this release should include them."
            }
        }
    }
    if ($key -eq "2" -and "$(RepoGit config core.autocrlf)".Trim() -ne "true") {
        Warn "core.autocrlf is not 'true': 2.x files will not be byte-identical to 2025.5 (built with CRLF)."
    }

    $wt = Join-Path ([IO.Path]::GetTempPath()) ("onnxocr-$key.x-" + [IO.Path]::GetRandomFileName())
    # Check out LFS pointers only; models are pulled below with a fallback remote.
    $prevSkip = $env:GIT_LFS_SKIP_SMUDGE
    $env:GIT_LFS_SKIP_SMUDGE = "1"
    try {
        RepoGit worktree add --detach --quiet $wt $sha
        if ($LASTEXITCODE -ne 0) { throw "git worktree add failed." }
    } finally { $env:GIT_LFS_SKIP_SMUDGE = $prevSkip }

    try {
        # --- models ---------------------------------------------------------
        if (Get-LfsPointers $wt) {
            Info "Fetching LFS models"
            Invoke-Native git -C $wt lfs pull origin
            if (Get-LfsPointers $wt) { Invoke-Native git -C $wt lfs pull upstream }
            $left = Get-LfsPointers $wt
            if ($left) { throw "Still LFS pointers after pulling from origin and upstream:`n  $($left.FullName -join "`n  ")" }
        }

        # --- build ----------------------------------------------------------
        $pyproject = Get-Content (Join-Path $wt "pyproject.toml") -Raw
        if ($pyproject -notmatch '(?m)^version\s*=\s*"([^"]+)"') { throw "No version in pyproject.toml." }
        $version = $Matches[1]
        $old = Get-ChildItem $OutDir -Filter "onnxocr-$version*" -File
        if ($old) { Warn "Replacing existing $($old.Name -join ', ')"; $old | Remove-Item }

        Info "uv build onnxocr $version -> $OutDir"
        Invoke-Native uv build $wt --out-dir $OutDir
        if ($LASTEXITCODE -ne 0) { throw "uv build failed for $key.x." }

        $files = Get-ChildItem $OutDir -File | Where-Object { $_.Name -like "onnxocr-$version-*.whl" -or $_.Name -eq "onnxocr-$version.tar.gz" }
        $wheel = $files | Where-Object Extension -eq ".whl"
        if ($files.Count -ne 2) { throw "Expected one sdist and one wheel for $version, found: $($files.Name -join ', ')" }

        # --- verify ---------------------------------------------------------
        $twineArgs = @("twine", "check") + @($files.FullName)
        Invoke-Native uvx @twineArgs
        if ($LASTEXITCODE -ne 0) { throw "twine check failed for $version." }
        foreach ($f in $files) {
            if ($f.Length -gt $PyPILimit) { throw "$($f.Name) is $([math]::Round($f.Length / 1MB, 1)) MB, over PyPI's 100 MB limit." }
        }
        $pointers = Get-WheelPointers $wheel.FullName
        if ($pointers) { throw "Wheel contains LFS pointers instead of models:`n  $($pointers -join "`n  ")" }

        if ($Smoke) {
            $venv = "$wt-venv"
            $script = "$wt-smoke.py"
            Set-Content -Path $script -Value $SmokePy -Encoding ASCII
            Info "Smoke test in a fresh Python 3.12 venv"
            Invoke-Native uv venv --quiet --python 3.12 $venv
            Invoke-Native uv pip install --quiet --python "$venv\Scripts\python.exe" $wheel.FullName
            if ($LASTEXITCODE -ne 0) { throw "Installing $($wheel.Name) failed." }
            # Run from outside the worktree so the installed wheel is imported, not the source tree.
            Push-Location ([IO.Path]::GetTempPath())
            try {
                $out = Invoke-Native "$venv\Scripts\python.exe" $script (Join-Path $wt "onnxocr\test_images\00006737.jpg") "$wt-smoke.jpg" 2>&1
            } finally { Pop-Location }
            $ok = $out | Where-Object { "$_" -like "SMOKE OK*" }
            if (-not $ok) { $out | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" }; throw "Smoke test failed for $version." }
            Info "$ok"
            Remove-Item -Recurse -Force $venv, $script, "$wt-smoke.jpg" -ErrorAction SilentlyContinue
        }
        $built += $files
    }
    finally {
        if ($KeepWorktree) { Warn "Kept worktree $wt (remove with: git worktree remove --force `"$wt`")" }
        else { RepoGit worktree remove --force $wt | Out-Null }
    }
}

# --- report -----------------------------------------------------------------
Write-Host ""
Info "Built:"
foreach ($f in $built) { "    {0,8:N1} MB  {1}" -f ($f.Length / 1MB), $f.Name | Write-Host }
Write-Host ""
Info "Upload (after checking the above):"
$uploadList = ($built | ForEach-Object { '"' + $_.FullName + '"' }) -join " "
Write-Host "    uvx twine upload $uploadList"
