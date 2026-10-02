# OnnxOCR packaging fork

This repo (KumaTea/OnnxOCR) packages upstream
[jingsongliujing/OnnxOCR](https://github.com/jingsongliujing/OnnxOCR) for PyPI
(`onnxocr`) and conda. Upstream owns the code. We own the packaging layer and
keep changes to upstream's files to a documented minimum.

## Release lines

Each major version is one model generation. Remotes: `origin` is this fork,
`upstream` is jingsongliujing/OnnxOCR.

| Line | Branch | Built from | Models in the wheel | Status |
|---|---|---|---|---|
| 1.x | `release/1.x` | upstream `353a61e` (2025-05-13, last commit before PP-OCRv5) | PP-OCRv4 det/rec/cls + `ppocr_keys_v1.txt` | frozen |
| 2.x | `release/2.x` | upstream `f51dabe` (2025-06-21) | PP-OCRv5 (default), PP-OCRv4, ch_ppocr_server_v2.0 det/cls | frozen; byte-identical to the yanked `2025.5` |
| 3.x | `main` | `upstream/main` | PP-OCRv5 | active; follows upstream `main` |
| 4.x | `release/4.x` | `main` + `upstream/ppocrv6` merged | PP-OCRv6 small (default) + tiny, PP-OCRv5 | active, interim (see below) |

Yanked on PyPI: `2025.5`, because as CalVer it sorts above every SemVer release.
Yank `3.1.0` once `3.1.1` is live; it crashes in `ONNXPaddleOcr()` when
`det_limit_side_len` is not a multiple of 32.

## Rules

- **Version numbers.** Major = model generation or a change of default model.
  Minor = upstream feature sync. Patch = our fixes or packaging-only changes.
  Never publish a number upstream already tags for different code (upstream's
  `v3.0.0` is `4420385`).
- **Packaging layer.** These files are ours: `pyproject.toml`, `MANIFEST.in`,
  `README.pypi.md`, `conda-recipe/`, `CLAUDE.md`, `PATCHES.md`. Add new files
  rather than editing upstream ones (`Readme*.md`, `requirements.txt`, ...) so
  upstream merges stay conflict-free. `README.pypi.md` exists because
  `README.md` would collide with upstream's `Readme.md` on Windows.
- **Source patches.** Any change to an upstream-owned file (e.g. anything in
  `onnxocr/`) gets its own commit and an entry in `PATCHES.md`. Keep it a few
  lines; if a fix would need a rewrite, don't carry it. Frozen lines (1.x, 2.x)
  take no source patches. Work around bugs there with dependency pins instead,
  e.g. `numpy<2.0.0`.
- **Wheel size.** PyPI rejects files over 100 MB. Check models' *deflated*
  size before adding any. This is why PP-OCRv6 medium (~100 MB deflated) is
  not in the 4.x wheel.
- **Dependencies** list only what the shipped code imports. Verify them with a
  clean-venv install plus real inference, not by copying upstream's
  `requirements.txt`. 2.x is the exception: it keeps `2025.5`'s metadata
  verbatim.
- **Model files** are Git LFS upstream since `e5172f7`. Fetch them with
  `git lfs pull upstream` on upstream-based branches.

## Syncing upstream

- `git fetch upstream`.
- **3.x:** merge `upstream/main` into `main`. Recheck each 3.x entry in
  `PATCHES.md`; drop the ones upstream has fixed.
- **4.x:** merge `main` into `release/4.x`, which brings packaging and patches.
  Also merge `upstream/ppocrv6` if it moved.
- **When upstream merges ppocrv6 into its `main`**, `main` becomes the 4.x line:
  1. Branch `release/3.x` from `main`. 3.x is then frozen except for fixes.
  2. Merge `upstream/main` into `main` and carry over the 4.x-only patches and
     packaging from `release/4.x` (see `PATCHES.md`). Bump to the next 4.x
     version.
  3. Retire `release/4.x`.

## Building and verifying a release

Work on other lines in a throwaway worktree:
`git worktree add <tmp-dir> release/2.x`.

1. `uv build --out-dir dist`. This builds the sdist first, then the wheel from
   the sdist, so `MANIFEST.in` governs both.
2. `uvx twine check dist/onnxocr-<ver>*`.
3. Diff the new wheel's `RECORD` against the previous release of the same line.
   Only the files you meant to change should differ. For 2.x, every package
   file must match `2025.5`'s sha256. That relies on building on Windows with
   `core.autocrlf=true`, because `2025.5` shipped CRLF files.
4. Clean venv (`uv venv -p 3.12`, `uv pip install dist/<wheel>`) and run:
   `ONNXPaddleOcr()` det+cls+rec on `onnxocr/test_images/`, `sav2Img`, and
   `det_limit_side_len=340, det_limit_type="min"`, the way
   `D:\GitHub\genshin-dual-sub` calls it.
5. The maintainer uploads: `uvx twine upload dist/onnxocr-<ver>*`.
6. Conda, after the PyPI upload: `conda-recipe\build_conda.ps1 -Version <ver>`.
   The recipe pins the PyPI sdist's sha256.
