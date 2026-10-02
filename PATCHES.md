# Source patches

Changes we carry to upstream-owned files: everything outside the packaging layer
listed in `CLAUDE.md`. Packaging files (`pyproject.toml`, `MANIFEST.in`, ...)
are not listed here. Remove an entry once upstream ships the fix.

## 1.x (`release/1.x`): none

Unmodified upstream `353a61e`.

## 2.x (`release/2.x`): none

Unmodified upstream `f51dabe`.

## 3.x (`main`)

### `onnxocr/utils.py`: `create_blank_img` dtype `int8` → `uint8`

- Commit: `ff8c972` (with the 3.1.0 packaging), since 3.1.0. One line.
- Why: `np.ones(..., dtype=np.int8) * 255` overflows to -1. Under numpy 2 it
  raises `OverflowError` in `sav2Img` → `draw_ocr` → `text_visual`. Fixing it
  let 3.x drop the `numpy<2.0.0` pin, which also unblocks Python 3.13+.
- Upstream: not reported.

### `onnxocr/predict_det.py`: round the det warm-up input to a multiple of 32

- Commit: `6647729`, since 3.1.1. Five lines.
- Why: the warm-up added upstream in `8100479` runs the detector on a
  `det_limit_side_len` × `det_limit_side_len` input as-is. The DB network only
  accepts sizes whose FPN feature maps line up; real inputs are always rounded
  by `DetResizeForTest`. So `ONNXPaddleOcr(det_limit_side_len=340)` raised
  `Shape mismatch attempting to re-use buffer. {1,96,11,11} != {1,96,12,12}`,
  and a float side length raised a `TypeError` from `np.zeros`.
- Upstream: not reported. Also present on upstream's `ppocrv6` branch.

## 4.x (`release/4.x`)

All 3.x patches (merged from `main`), plus:

### `onnxocr/onnx_paddleocr.py`, `onnxocr/utils.py`: default PP-OCRv6 size medium → small

- Commit: `e1c0320`, since 4.0.0. Three lines: the fallback in
  `_normalize_ppocrv6_size`, and the `--det_model_dir` / `--rec_model_dir`
  defaults in `infer_args`.
- Why: PP-OCRv6 medium det+rec deflate to ~100 MB, so the wheel can't ship
  them. small is the largest size that fits and runs close to PP-OCRv5 on CPU
  (medium is ~4× slower).
- Deliberately not patched: `layout_markdown.py` (doc pipeline) and the
  explicit "PP-OCRv6" / "PP-OCRv6 medium" entries in `ocr_images_pdfs.py` still
  use medium. Without it they raise upstream's "Model file not found ...
  download models first" error, like the doc pipeline's other non-bundled
  models.
- Upstream: an intentional divergence, not to be upstreamed. Revisit if medium
  becomes installable, e.g. as an `onnxocr[medium]` extra backed by a separate
  model package. Extras can add dependencies but not package data.
