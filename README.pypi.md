# OnnxOCR

Multilingual OCR that runs on ONNX Runtime alone

The upstream project is [jingsongliujing/OnnxOCR](https://github.com/jingsongliujing/OnnxOCR).

This package is built from
[KumaTea/OnnxOCR](https://github.com/KumaTea/OnnxOCR).

## Release lines

Each major version is one model generation:

| Version | Models | Built from |
|---|---|---|
| 4.x | PP-OCRv6 small (default) and tiny, plus PP-OCRv5 | upstream `ppocrv6` branch |
| 3.x | PP-OCRv5 | upstream `main` |
| 2.x | PP-OCRv5 (default) and PP-OCRv4, 2025 code | upstream, June 2025 (was `2025.5`) |
| 1.x | PP-OCRv4 | upstream, May 2025 |

To stay on one generation, pin the major version, e.g. `pip install "onnxocr<4"`.

## Install

```shell
pip install onnxocr
```

Requires Python 3.11+. The wheel (~75 MB) bundles the PP-OCRv6 small and tiny
detection and recognition models, the PP-OCRv5 models and the angle classifier.

Optional extras:

| Extra | Enables |
|---|---|
| `onnxocr[pdf]` | PDF input (`pymupdf`, `pdf2image`) |
| `onnxocr[qwen]` | Qwen3.5-2B ONNX information extraction |
| `onnxocr[doc]` | RapidDoc document → Markdown pipeline |
| `onnxocr[office]` | DOCX/PPTX/XLSX/HTML/LaTeX conversion for the doc pipeline |
| `onnxocr[all]` | everything above |

## Usage

```python
import cv2
from onnxocr.onnx_paddleocr import ONNXPaddleOcr

model = ONNXPaddleOcr(use_angle_cls=True, use_gpu=False)

img = cv2.imread("test.jpg")
result = model.ocr(img)

for box, (text, score) in result[0]:
    print(f"{score:.3f}  {text}")
```

Save an annotated image:

```python
from onnxocr.onnx_paddleocr import sav2Img

sav2Img(img, result, name="result.jpg")
```

Non-ASCII paths on Windows need `cv2.imdecode` rather than `cv2.imread`:

```python
import numpy as np
img = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)
```

### Model size

PP-OCRv6 comes in three sizes. This package defaults to **small**; upstream
defaults to medium.

| `ocr_model_size` | Bundled | CPU speed vs PP-OCRv5 |
|---|---|---|
| `"tiny"` | yes | ~2× faster, weaker on Japanese and Latin text |
| `"small"` (default) | yes | similar |
| `"medium"` | no: ~140 MB, over PyPI's file size limit | ~4× slower |

```python
model = ONNXPaddleOcr(ocr_model_size="tiny")
```

To use medium, download and extract
[PP-OCRv6_medium_det](https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_medium_det_onnx_infer.tar)
and
[PP-OCRv6_medium_rec](https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_medium_rec_onnx_infer.tar)
from PaddleX, then pass their paths:

```python
model = ONNXPaddleOcr(
    ocr_model_size="medium",
    det_model_dir="PP-OCRv6_medium_det_onnx_infer/inference.onnx",
    rec_model_dir="PP-OCRv6_medium_rec_onnx_infer/inference.onnx",
)
```

### Other modes

`ONNXPaddleOcr` also exposes license-plate, table and layout recognition via
`use_plate_recognition=True`, `use_table_recognition=True` and
`use_layout_analysis=True`.
Those models are not bundled — download them first:

```shell
python scripts/download_models.py --source huggingface
```

See the [upstream README](https://github.com/jingsongliujing/OnnxOCR#readme) for those
modes, the HTTP API service, the WebUI and Docker images.
