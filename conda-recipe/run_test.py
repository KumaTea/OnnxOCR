"""conda-build test: prove the package works, not just that it imports.

conda-build runs this automatically inside a fresh env built from the
`requirements/run` list, so it also validates the conda dependency mapping.
"""
from pathlib import Path

import numpy as np

import onnxocr
from onnxocr.onnx_paddleocr import ONNXPaddleOcr

pkg = Path(onnxocr.__file__).parent

# The models and font are package data; if they were dropped the package would
# import cleanly and then fail at runtime, so check them explicitly.
required = [
    "models/ppocrv5/det/det.onnx",
    "models/ppocrv5/rec/rec.onnx",
    "models/ppocrv5/cls/cls.onnx",
    "models/ppocrv5/ppocrv5_dict.txt",
    "models/orientation/rapid_orientation.onnx",
    "fonts/simfang.ttf",
]
for rel in required:
    p = pkg / rel
    assert p.is_file(), f"missing packaged data file: {rel}"
    assert p.stat().st_size > 1024, f"suspiciously small (Git LFS pointer?): {rel}"
    print(f"  OK {rel} ({p.stat().st_size / 1048576:.2f} MB)")

# Exercise the real pipeline: this loads det + cls + rec + orientation sessions.
model = ONNXPaddleOcr(use_angle_cls=True, use_gpu=False)
result = model.ocr(np.full((320, 640, 3), 255, dtype=np.uint8))
assert isinstance(result, list) and len(result) == 1, f"unexpected result shape: {result!r}"

print("onnxocr conda package OK")
