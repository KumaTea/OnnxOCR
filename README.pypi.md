# OnnxOCR

Multilingual OCR that runs on ONNX Runtime alone

The upstream project is [jingsongliujing/OnnxOCR](https://github.com/jingsongliujing/OnnxOCR).

This package is built from
[KumaTea/OnnxOCR](https://github.com/KumaTea/OnnxOCR).

## Install

```shell
pip install onnxocr
```

Requires Python 3.11+. The PP-OCRv5 detection, angle-classification and recognition
models are bundled in the wheel (~41 MB).

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
