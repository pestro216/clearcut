# Clearcut on Android: contingency plan

*27 November 2026. iPhone stays the priority; this keeps the Android route open and costed.*

## Where the iPhone app stands

The engine (`Core/`, about 3,000 lines of Swift) is mostly plain arithmetic on two simple image
types (`Plane`, `RGBAImage`). Apple-only code is confined to:

| File | Apple dependency | Android equivalent |
|---|---|---|
| `Core/Segmenter.swift` | Vision subject finder (`VNGenerateForegroundInstanceMaskRequest`) | Google ML Kit Subject Segmentation |
| `Core/CutoutNetwork.swift` | Core ML runs BiRefNet Lite | ONNX Runtime Mobile or LiteRT (TensorFlow Lite) running the same model |
| `Core/Buffers.swift` | ImageIO decode/encode, Core Graphics, vImage resize | Android `ImageDecoder` / `Bitmap`, plain resampling code |
| `Core/Compositor.swift` | Core Graphics images in and out | `Bitmap` |
| `Matting`, `Shadows` | Accelerate for a few vector sums | plain loops |
| `Clearcut/` (the app) | SwiftUI, UIKit, Photos | Jetpack Compose, Android Photo Picker, MediaStore |

Everything else (matting, false-hole check, shadows, surfaces, brush, metrics) has no Apple
dependency.

## Android building blocks (checked 27 Nov 2026)

- **ML Kit Subject Segmentation** (developers.google.com/ml-kit/vision/subject-segmentation/android):
  beta, no service-level agreement. Adds about 200 KB to the app; the model itself downloads
  through Google Play services (at install with the manifest entry
  `com.google.mlkit.vision.DEPENDENCIES = subject_segment`, else on first use, when requests return
  nothing until it arrives). Gives a foreground confidence mask and, with multiple subjects
  enabled, one mask per subject with its position: the same shape of output as Apple's, so the
  quick cutout, the second opinion and instance selection carry over. Needs at least 512 x 512
  input. The page does not state whether inference is on the device; check before promising
  "photos never leave your phone" on Android. Minimum Android API 24.
- **The cutout network**: BiRefNet is MIT licensed. A Core ML file can't run on Android; the
  original model has to be exported to ONNX (or LiteRT) and checked against the iPhone output with
  the same agreement test the app already has (`CutoutNetwork.agree`).
- **Memory**: Android phones vary far more than iPhones. The one-photo-at-a-time design, the
  40-photo batch, the saved batch that resumes after a crash and the 8192 px cap all carry over
  and matter more there.

## Two routes

1. **Swift on Android** (preferred to try first). Swift has an Android SDK (from memory: an
   official Swift Android workgroup and SDK appeared during 2025; verify the current state before
   starting). `Core/` minus the four Apple files would compile into a library that a Kotlin app
   calls. One engine, one set of fixes, one bench. Risk: tooling maturity, build size.
2. **Kotlin port of the engine** (fallback). Rewrite `Core/` in Kotlin. Proven tooling, but every
   future engine fix has to be made twice, and the two can drift.

Either way, the same ground-truth scenes (`QA/make_testset.py`, plain Python) and the same
metrics (IoU, boundary F, edge error, edge colour, gradient, connectivity) decide whether the
Android cutout matches the iPhone one, scene by scene.

## Rules from now on, so the door stays open

- New engine logic goes in files that import only Foundation (and Accelerate only as a speed-up
  with a plain-loop equivalent). Apple frameworks stay in the four adapter files above.
- Engine inputs and outputs stay plain arrays (`Plane`, `RGBAImage`, `[UInt8]` alpha).
- Anything that needs a model must name its licence; only commercially usable weights
  (see `docs/decisions.md`, 27 Nov licence review) can ship on either platform.

## What it would take

- A Google Play developer account (one-time fee; check the current amount) and two or three
  Android test phones of different memory sizes, including a low-end one.
- Spike: compile `Core/` minus the adapters with the Swift Android SDK; if that works, a minimal
  Kotlin app that picks one photo and runs ML Kit plus the network. Then the batch screen.
- Nothing is spent on this until the iPhone app has passed stage 1 of `docs/app-store-plan.md`.
