# netlab: the cutout network on this PC

Runs BiRefNet Lite (the network inside the app) on Linux with ONNX Runtime, so changes to how the
network is used can be measured on `QA/realset` before any app build. Results are the raw network
only (no matting), which is where the close-up failures start.

Setup (not in git, about 450 MB, in `QA/.research/`): Python wheels for numpy, Pillow, SciPy,
opencv-python-headless and onnxruntime unpacked into `QA/.research/py/`, and
`onnx-community/BiRefNet_lite-ONNX` `onnx/model.onnx` (MIT, SHA-256 5600024376f5...0f03333)
in `QA/.research/model/`. Each run needs about 7 GB of memory: run one at a time.

- `canvas.py SCENE VARIANT`: overlap with the reference for `plain`, or the photo padded by a share
  of its long side (`grey_0.35`, `reflect_0.35`, `replicate_0.35`, `white_0.5` ...).
- `zoom.py SCENE`: whole photo against whole photo plus the detail crop, on edge measures.
- `guard.py`: what `Segmenter.acceptCanvas` would decide for each cached canvas result.

Results append to `QA/.research/results.txt`; network outputs are cached in `QA/.research/cache/`.
