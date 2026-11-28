# Clearcut engineering notes

How the image engine works, why, and how it is tested. Numbers come from the automated quality
suite (`QA/`), which runs on every engine change; the latest report and contact sheets are on the
`qa-results` branch under `latest/`.

## 1. Assessment of the previous implementation (6 Nov 2026)

| Problem seen | Root cause found | Evidence |
|---|---|---|
| Feathered, rough edges | Apple's subject model predicts on a **512 × 512 grid** whatever the photo size. Its soft edge (≈10 px at 1600 px, ≈25 px at 4032 px) was stretched to full size and then steepened. Steepening makes the edge hard, but along the model's coarse outline, not the photo's real edge, so it wobbles, cuts into the product or leaves a band of old background. | Probe on the CI Mac: instance mask 512 × 512; transition 0.99 → 0.03 over 10 px at 1600 px. |
| Halos / old-background tint | Defringing choked the edge by long side ÷ 1600 px and painted edge pixels with blurred interior colour: it ate into the product and smeared texture, but couldn't remove tint the steepened edge had already placed outside the product. | Worst-edge colour error (ΔE 95th percentile) 33–35 on several scenes. |
| Missing small parts, filled gaps | The model drops thin protrusions (a 40 px strap vanished entirely in the probe) and fills narrow gaps (between comb teeth). Steepening cannot add back or remove whole parts. | Probe; comb scene kept 37% extra background. |
| Composited look | Blending in gamma-encoded sRGB (Core Image sRGB working space) darkens or lightens edges; shadows drawn as translucent black film rather than reduced light. | Code review. |
| Artificial backgrounds | Backdrops were generated procedurally; the supplied timber photo (1771 px) was stretched 2.3× over 4032 px photos. | Code review, visual check. |
| Unconvincing shadows | One blurred, offset silhouette at one scale: same for every product regardless of shape; no contact darkening. | Code review. |
| No safety net | A poor cutout was presented as success; no tests. | Code review. |

## 2. Approach chosen

All processing is on the phone. The engine lives in `Core/` and is compiled into both the app
and a Swift package that GitHub Actions tests on a Mac, so what is measured is exactly what ships.

**Segmentation.** Apple Vision `VNGenerateForegroundInstanceMaskRequest` is kept: it is the best
general on-device subject model available without bundling a third-party network. When the item
fills under 55% of the frame, a second pass runs on a crop around it, spending the model's whole
512 grid on the item (2–4× more edge detail).

*Considered and not adopted (for now):* converting an open dichotomous-segmentation network
(BiRefNet, IS-Net, U²-Net) to Core ML. They can resolve finer detail, but add 100–900 MB to the app,
need a conversion pipeline with no way to validate on-device speed and memory from here, and the
measurements below show that most of the visible error came from processing after the model,
not from the model. Revisit if real photos show the model itself is the limit (see section 5).

**Matting** (`Core/Matting.swift`), in order:
1. *Islands*: drops stray pieces under 4% of the main item.
2. *Colour evidence*, only when the item clearly stands apart from a fairly even background:
   - recovers parts the model missed, but only regions made of the same material as the part
     of the item they touch (a strap continuing from a watch); shadows and background texture fail
     that test;
   - carves out gaps the model filled in, but only where the surrounding product is itself clearly
     different from the background, so light products on light surfaces are never carved;
   - recognises shadows (darker, same hue) as background; very dark products are not shadows.
3. *Edge refinement*, at full resolution: a colour guided filter (He et al.) snaps the outline to
   the photo's real edges; in the edge band, each pixel's alpha is solved from local item and
   background colours (how far its colour lies from the background towards the item). Genuinely
   mixed pixels stay partial; nothing is artificially steepened or choked. Where item and
   background colours are too alike, the guided-filter result stands.
4. *Foreground colour*: approximate fast foreground estimation ("blur fusion", Forte & Pitié 2021)
   removes old-background tint from edge pixels without blurring them.

**Compositing** (`Core/Compositor.swift`) blends in linear light, so edges and shadows behave like
light. Backdrops fill the frame by a centred crop, never stretched out of proportion.

**Shadows** (`Core/Shadows.swift`), for a product lying on a surface under overhead light:
- contact: a tight, dark occlusion where the item meets the surface, at full resolution;
- cast: four height bands estimated from the item's outline (distance from its edge), each offset
  away from the light and softened more the higher it sits: thin parts cast short crisp shadows,
  thick parts longer softer ones;
- ambient: a faint wide occlusion.
All sizes scale with the photo, so one setting behaves consistently across a batch while each
shadow still follows its own product's shape. Shadows multiply the surface's light.

**Confidence.** Each photo is marked good, "Check" (fills the frame, or colour evidence disagreed
strongly) or "Not cut out" (no item found, or too small). Failed photos are kept as the original.

## 3. Quality suite

- `QA/make_testset.py` builds ground-truth scenes: products made from real photographic materials
  (CC0 Poly Haven scans), shaded, placed on real photographic surfaces with contact shadows, then
  "photographed" with lens softness, sensor noise and JPEG compression. The exact cutout is known.
  Scenes: dark garment on light, white on white, black on dark wood, thin straps, fine chain,
  mug handle gap, reflective bottle, fuzzy edge, sunglasses with thin arms, comb with narrow teeth.
- `QA/cutbench` runs every method on every scene and scores IoU, boundary F (2 px), edge alpha
  error, missed item, kept background, and edge colour error (ΔE) after compositing on a new
  backdrop, which captures halos and tint. It renders contact sheets with 4× zooms on the worst edge
  spot, and fails the run if the shipping method regresses against `QA/baseline.json`.
- `QA/Tests` unit tests: orientation and size handling, export dimensions, transparent export,
  edge snapping, soft edges kept soft, tint removal, island removal, loud failure, shadow behaviour,
  colour round trip, backdrop fill.
- `QA/photos/`: put real photos here; they are processed every run and shown on contact sheets with
  blind measures (edge width, pieces, confidence).

## 4. Results on the ground-truth scenes

Means over the 10 scenes that produced a cutout (the fine chain produced none with either method;
see section 5). From the quality run on commit df7e8e7, now the regression baseline.

| Method | IoU | Boundary F (2 px) | Edge alpha error | Missed item | Kept background | Edge ΔE mean | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Previous app | 0.960 | 0.835 | 0.127 | 1.20% | 4.03% | 7.61 | 37.2 |
| New engine | **0.995** | **0.972** | **0.088** | **0.28%** | **0.27%** | **5.60** | **18.3** |

Worst visible edge spot (ΔE 95%) per scene, previous app to new: navy shirt 35 to 9, watch straps
33 to 9, mug 17 to 8, bottle 33 to 18, black on dark wood 32 to 25, comb 48 to 7.

24 MP export check: a 5712 × 4284 photo comes out 5712 × 4284; cutout 4.5 s and compositing plus
JPEG 2.8 s on the CI Mac (Apple M2, virtualised); whole-benchmark peak memory 750 MB.

Deliberate trade-off: edge alpha and edge colours are solved in linear light (physically correct).
Against solving in sRGB it lowers the worst edge errors (shirt ΔE 95% 20 to 9, white on white 27 to
21) but raises the mean edge error slightly on two scenes (shirt 3.6 to 4.7, watch 2.5 to 3.3).
The baseline was reset on that basis.

Independent review (a separate reviewer with no part in writing the code) found: the confidence
flag almost never fired; edge solving and compositing used different colour encodings; the shadow
was weak and its contact term read as an outline; 24 MP memory was unmeasured; exports re-saved
untouched originals. All were fixed and re-measured. It also found the comb's leftover background,
traced with debug maps to the background estimate falling to black under large items, now fixed.

## 5. Known limitations (honest list)

- **Fine jewellery**: Apple's model finds no subject in the fine-chain scene. The photo is flagged
  "Not cut out" and kept as the original. A touch-up can't create a cutout from nothing.
- **Very thin parts**: the sunglasses' arms (about 10 px wide) are still missed in the test scene
  (2.3% of the item) and this is not flagged, because nothing tells the engine a part is missing.
  Touch-up (Restore) fixes it by hand.
- **Low contrast edges** (white on white, black on dark): edges are correct in position but softer
  (ΔE 95% 21–25), because there is little colour difference to work with. Black on dark is flagged
  "Check".
- **Synthetic scenes are not real photos.** They measure the engine reliably but cannot represent
  every real material (fur, glass, sheer fabric). Real photos in `QA/photos/` are needed to judge
  those, by eye.
- Colour: output is 8-bit sRGB (the web standard). iPhone Display P3 and HDR colour outside sRGB is
  mapped in, so very saturated colours can lose a little intensity.
- Background scale is fixed at about 1 m across the frame; very close-up shots of small items show
  the grain larger than it would really appear.
- The supplied timber photo is 1771 px, so it is enlarged for full-size photos (labelled
  "Low resolution" in the app).
- Apple's model does not run in the iOS simulator, so the automated app check proves the screens and
  the failure path, not on-device cutting. On-device speed and memory are untested.

## 6. Background library

`Clearcut/Backdrops/` holds CC0 photo-scanned surfaces from Poly Haven, prepared by
`tools/fetch_backgrounds.py` (run from the "Background library" workflow) to show about 1 m of real
surface, at the source's own resolution, never upscaled. `library.json` lists titles and groups. Any
other .jpg placed in the folder appears automatically under "Yours"; backgrounds can also be added
from Photos inside the app. Surfaces under 3000 px are labelled "Low resolution".

## 7. Changes of 25 November 2026

Prompted by a real failure: a dark jacket on herringbone parquet lost both cuffs, and the touch-up
screen made the fix hard (the result was shown over a wood backdrop that looked like the floor, the
paint hid what it fixed, a second finger for zooming left paint dots, and panning needed a mode).

- **Second opinion** (`Segmenter.recoverParts`): after the network passes, Apple's subject finder
  runs once at working size (about 0.1 s). Pieces it includes that the network dropped are added
  back when they touch the item, are smaller than it, and mostly don't look like the surface
  around them (local colour histograms of surface and item) or like that surface in shadow (all
  three channels dimmed alike). Unit test: a grey cuff is recovered, a darker-brown shadow is not.
- **Low light** (`CutoutNetwork.exposureCurve`): dark or very flat photos get a tone curve before
  the network sees them (1% to 99% stretched, dark mid-tones lifted). Well-exposed photos are
  untouched, so the ground-truth scenes should not move; the quality run confirms it.
- **GPU** (`CutoutNetwork`, app only): the network was CPU-only. The app now tries the GPU, checks
  it against the CPU on the first photo per iOS version (outline IoU over 0.985, mean difference
  under 0.02), and keeps using it only if they agree; any non-finite or flat GPU output drops back
  to the CPU for good. The bench stays on the CPU. **Switched off the same day** (`useGPU = false`):
  on Mathew's iPhone 11 the app was closed by iOS for passing its 2348 MB memory limit during the
  first-photo check (GPU and CPU copies of the model loaded together). Revisit with on-phone memory
  measurements and one copy loaded at a time.
- **Touch-up rebuilt** (`Clearcut/TouchUp.swift`): UIKit canvas at 2048 px. The item is shown cut out
  over a checkerboard with the removed part faint behind it, and strokes change the matte as you
  draw. One finger paints; two fingers pan and zoom and cancel the stroke they interrupted; a
  two-finger tap undoes; Undo and Redo; a magnifier in the top corner shows the spot under the
  finger; brush size is in screen points. **Smart edges** (on by default) samples the colour where a
  stroke starts and only changes similar colours (tolerance 34, fading out by 54), so a stroke along
  an edge stops at it. Apply replays the same strokes on the full-size matte with the full-size photo;
  a unit test checks the replay matches live painting exactly.
- **Hold to compare** on the photo screen shows the original in place.

## 8. Changes of 26 November 2026 (branch `faster-cutouts`)

Asked for: cutouts that feel instant, cleaner cutouts, no taglines.

- **Quick cutout** (`BatchStore.quickLook`, `Segmenter.quickMask`): each new photo is decoded at
  1024 px and Apple's subject finder alone gives a rough cutout for its grid tile, so the whole batch
  appears within a second or so per photo. Full cutouts then run oldest first and replace the quick
  ones; a small spinner sits on a tile until its full cutout is in. A quick render can never land
  over the full one (the grid checks the matte it was made from). Apple's model only runs while the
  network is unloaded (`networkSegment` now unloads on every exit, not only on success).
- **Fast hardware** (`CutoutNetwork`): the Neural Engine (`.all`), then the GPU, are tried. On the
  first photo per iOS version the fast copy runs, is unloaded, then the CPU copy runs on the same
  input and the outputs are compared (`agree`). Only one copy is ever in memory, which was the cause
  of the 25 Nov crash. The option is saved as failed before the check starts, so if iOS closes the
  app during it, it is not tried again. The bench stays on the CPU.
- **Timings**: every "Clearcut memory" log line now ends with seconds since the previous one, so a
  USB log shows where each photo's time goes (decode, network, second opinion, matting).
- **Text removed**: home screen tagline and description, shadow style descriptions, touch-up
  gesture help, "Pinch to zoom" hint.
- Not changed: edge refinement. Without the bench (macOS only) and Mathew's problem photos, blind
  changes would risk the measured scenes.

## 9. Later on 26 November 2026

- **Crash on photo 1 of 2**: no crash report (a memory kill). The safety rule then marked both fast
  options failed, so later runs used the CPU (network 6 to 9 s per photo, footprint 130 to 240 MB
  between stages). The GPU option is removed; the Neural Engine (`.cpuAndNeuralEngine`) is checked
  again under key `network.fast.v3.ane.*`, and the log now gives the check's outline overlap and
  mean difference and, on every line, the app's peak memory since launch.
- **Batches**: at most 40 (`BatchStore.maxPerBatch`). The batch folder moved from the temporary
  folder to Application Support (excluded from backup) with `batch.json`; reopening restores it and
  continues unfinished photos. The photo being cut out is recorded (`batch.inProgress.v1`); if the
  app is closed on it, it is skipped on reopening so it can't crash the app again.
- **Image size**: `ImageIOHelpers.maxSide` 8192 caps every decode.
- **Security review**: no network code at all; Photos access is add-only through the system picker;
  exports are re-encoded from pixels, so location and camera metadata are not carried over; the
  repo has no secrets or email addresses; workflows run only on pushes to `main`, use only
  `actions/*` and have scoped permissions; the model download is checked against SHA-256 hashes.
  Open point: releases (the .ipa) are downloadable by anyone while the repo is public.
- **Attribution**: About screen (version, © Woolfall, privacy, credits, MIT text), Info.plist
  `NSHumanReadableCopyright`, `LICENSE`, `PrivacyInfo.xcprivacy` (no tracking, no data collected,
  UserDefaults reason CA92.1).

## 10. Coat video, 26 November 2026 (late)

- **Crash**: the Neural Engine check sat about 35 s on photo 1, then iOS closed the app. With
  GPU twice and Neural Engine twice killed on the iPhone 11, `useAcceleration` is now false. On
  reopening, the resume worked: the batch came back and the photo was marked "Skipped".
- **See-through blotches in a black coat on a grey floor** (flagged "Some background may be left
  between parts of the item"): new `Matting.fillFalseHoles`, run after colour evidence, before
  the guided filter. Regions with probability under 0.85 that are enclosed by the item stay
  see-through only if most pixels look like the outside surface (smoothed 16-level colour
  histograms, surface density over 3x item density) or that surface in shadow (all channels
  dimmed alike, at least 40% of its brightness). Otherwise they are filled. Unit test: a gap
  showing the floor is kept, a patch of the item's own material is filled. Note
  `falseHolesFilledPx` in the bench report.

## 11. Apple's outline as the solid inside (build 40, reverted 27 November 2026)

Tried: `Segmentation.solid` carried Apple's mask into `Matting.fillFalseHoles`, which also judged
non-solid pixels inside Apple's outline (shrunk by 1.2% of the long side) when at least 60%
bordered by item. Mathew found build 40 promising but with too much feathering, so `main` went
back to build 39's code (revert of 1ba78c4; the code is still in git history).

Likely cause, for a second attempt: where Apple's outline is larger than the item (it often takes
in a soft shadow or the fuzz along an edge), the network's soft edge band falls inside Apple's
"solid inside" and can be filled to fully solid, widening the item into the surface; the guided
filter then blends that wider edge, which reads as feathering. A second attempt should never
touch pixels within a few pixels of the network's own outline (only patches whose whole rim is
well inside the item), and be compared against build 39 on Mathew's photos before shipping.

**Reverting**: tags `build-38` and `build-39` on GitHub; their apps are in `builds/` (not in git,
checksums in `builds/SHA256SUMS`), installable with SideStore.

## 12. Icon and home demo photo, 27 November 2026

- **Icon** (`tools/make_icon.py`, v2): a terracotta T-shirt cut by a white diagonal; top left as
  photographed on speckled carpet (harsh off-centre shadow, slightly duller fabric), bottom right
  cut out on the transparency checkerboard with a soft shadow. Checked at 120 px. Rendered with
  Pillow and numpy installed to a scratch folder (`pip3 install --target`), since neither is on
  this PC's Python.
- **Home demo photo**: `HomeDemo` uses `demo-photo.jpg` and `demo-cutout.png` from the bundle (put
  them in `Clearcut/Demo/`; same pixel size; the cutout is Clearcut's own transparent export of
  that photo). Without them it draws the shirt symbol. `Library` skips `demo-*` files so the photo
  never shows up as a backdrop. Wikimedia Commons searched for CC0 garments on 27 Nov: the best
  candidates (a hoodie on carpet, a work jacket on a blanket) carry a clothing brand or a company
  logo, the rest have price tags or are museum pieces on grey. None used.

## 13. Engine v3 from the research list, 27 November 2026

Sources read 27 Nov (Mathew's list): MODNet, FBA Matting, MatteFormer, ViTMatte, ViTAE/GFM,
DeepFashion2, ModaNet, Fashionpedia, Apple's salient object segmentation article, WWDC23 10176,
background-remover-ios, ML Kit Subject Segmentation. Licences in `docs/decisions.md`.

What carried over:
- **Apple's own design** (salient object segmentation article): 512 x 512 prediction, then guided
  upsampling to full resolution, plus a confidence branch. Clearcut's pipeline already has this
  shape (network, guided filter, confidence).
- **Instance selection** (WWDC23): `Segmenter.appleMask(of:overlapping:)` reads Apple's instance
  labels and keeps only subjects with at least a quarter of their area on the network's item
  (`chooseInstances`, unit-tested). A hanger, tag or second item can't enter the second opinion.
- **Glance and focus / trimap** (GFM, AIM, MatteFormer's trimap tokens): definite item, definite
  background, and an unknown band where fine work happens. `fillFalseHoles` now judges patches in
  Apple's shrunk outline only where they are also at least the band width from where the network
  is confident the surface begins. This is build 40's idea with its feathering cause removed; a
  unit test checks a soft edge is left exactly as drawn when Apple's outline is larger.
- **Consistency as a self-check** (MODNet's sub-objective consistency): `Segmentation.agreement`
  is the IoU of Apple's chosen subjects and the network; under 0.5 the photo is marked Check.
  Bench note `appleAgreement`.
- **Evaluation** (FBA, MatteFormer report SAD, MSE, Grad, Conn on Composition-1k): Gradient and
  Connectivity errors added to `Metrics` and the bench table, written from the standard
  definitions (Rhemann et al. 2009 / Deep Image Matting evaluation; from memory, the fetched pages
  did not define them; the gradient kernel normalisation may differ from the MATLAB code, so
  compare runs with each other, not with published numbers). Report only; gate them once a
  baseline is recorded. Gradient catches feathering, Connectivity catches blotches.
- **Foreground colour** (FBA predicts F, B and alpha together): Clearcut already estimates F with
  Forte and Pitié's blur fusion; no change.

Not adopted: any matting network (non-commercial or unclear weights; MODNet is for portraits).
Training a garment model on Fashionpedia (CC BY 4.0 annotations) needs a GPU and per-image licence
checks: a later project.

## 14. Real-photo test set and method, 27 November 2026

Build 42 (section 13) felt worse on Mathew's photos while passing the made-up scenes, as builds
40 and 42 both did. The research list's main lesson is methodological: matting moved from
synthetic composites (Composition-1k) to real-photo benchmarks (AIM-500, PPM-100, AM-2K) because
synthetic scores don't transfer. So the engine went back to build 39 (`Matting.swift`,
`Segmenter.swift` restored from tag `build-39`; their section 13 tests removed) and changes are
now judged on real photos first.

- `tools/add_real_photo.py ORIGINAL REFERENCE.png NAME "what"`: turns a photo and its reference
  cutout (a transparent PNG of the same photo, e.g. Clearcut's export after touch-up) into a scene
  in `QA/realset/NAME/` (photo.jpg upright, max 3024 px, no EXIF; alpha.png; fg.png; meta.json).
  HEIC needs pillow-heif. Pillow comes from the scratch `pip3 install --target` folder on this PC.
- `QA/real_scenes.py` copies every realset scene into the quality run as `R_NAME`, so the bench
  scores real photos with every measure, including Gradient (feathering) and Connectivity
  (blotches). Not gated until a first run gives their baseline.
- `tools/compare_runs.py A B`: two quality runs side by side (finished renders and all measures,
  real photos first) as `QA/compare/A-vs-B/index.html` (not in git). Tried on runs 35 and 36.
- Getting photos: the iPhone on USB is reachable with `afcclient` (camera roll, DCIM), only with
  Mathew's say-so and only the photos he picks.
- Next method steps (from MODNet, GFM): measure the whole-shape part and the edge part separately;
  log where Apple's model and the network disagree on real batches to find failure classes before
  changing rules; one change at a time, each shown against build 39 on the real set.
- 27 Nov, first batch: 54 latest camera-roll items copied from the phone (Mathew's instruction)
  to `QA/incoming/2026-11-27/` (not in git). `tools/photoroom_reference.py` turns
  white-background Photoroom exports into references: SIFT + RANSAC similarity finds each one's
  original (Photoroom only scaled by 0.595, no reframing), colours matched, alpha solved against
  white, warped back to the original; near-white item pixels counted as unknown (under 0.2%).
  11 clean pairs in `realset-draft/` (Columbia and Michigan jackets: whole shots, close-ups,
  tape measures), each checked by eye. Caution learned: JPEGs on parquet in the camera roll are
  Clearcut exports, not originals (pale rim, library parquet); only HEICs on concrete are
  camera originals. Not usable yet: cream bag (only screenshots), collar close-up 3213 and two
  front shots (originals not in the batch), the vest (no reference). Six shipping-label
  screenshots with other people's details were left out. Waiting on Mathew's decision about
  the public repo before moving the drafts into `QA/realset/`.

## 15. Experimental branch `experimental-cutout`, 28 November 2026

Asked for: an audit for speed and accuracy, on an experimental build of the personal app only.
Measured on this PC with the same network (ONNX copy of BiRefNet Lite, `tools/netlab/`), whose raw
output matches the app's (striped sleeve close-up: overlap 0.33 here, 0.32 on GitHub's Mac).

**Where it went wrong.** On `QA/realset` (11 Woolfall photos, all on grey concrete) the raw network
is fine when the garment covers up to about 45% of the frame (overlap 0.978 to 0.995) and fails on
all five photos where it covers 58 to 75% (0.06 to 0.39). A salient-object network looks for an
object *on* a background; when the garment fills the frame it treats the garment as the background
and picks what lies on it (the ruler, a sleeve). The network's edges were right; its choice of
object was wrong. So the cause is the model's framing, not resolution, thresholds or matting. In
quality run 47 the app's safety nets rescued two of the five (hem, front close-up); three stayed
broken (side 0.47, striped sleeve 0.30, underarm 0.35: 53 to 70% of the garment missed).

**Canvas tests** (raw network overlap, five close-ups): plain 0.06 to 0.39; mirrored edges as the
app does now 0.08 to 0.63; flat grey canvas padded by 0.35 of the long side **0.992 to 0.997 on
all five**; grey 0.5 0.92 to 0.997; grey 0.2 0.62 to 0.998; grey 1.0 picks the whole rectangle.
On the six normal photos grey 0.35 is 0.002 to 0.003 below plain, so it runs only where the app
already ran its second, mirrored pass (first result doubtful): no extra network run.

**Change 1, grey canvas for doubtful photos** (`Segmenter.networkSegment`, `acceptCanvas`). Its
result is kept unless it covers 97% of the frame (the rectangle that made build 233e853 drop the
grey canvas), agrees with the plain pass anyway, or what it adds looks like the surface left over.
That last test compares colour *distributions* (16-level histograms, smoothed): the old
`preferWide` compared average colours and would have rejected both striped Michigan close-ups,
because navy and cream stripes average to concrete grey. No "surface in shadow" rule: black fabric
passes it. On rejection the old mirrored pass runs as before. Unit test with a striped close-up,
the whole frame and a grabbed piece of floor.

**Change 2, detail crop only for small items** (`zoomMaxShare` 0.5, was 0.8). On the six normal
photos the crop changed boundary F (2 px) by +0.019, +0.002, -0.001, -0.021, -0.009 (one had no
crop): no gain, for a whole network run (6 to 9 s on an iPhone 11 CPU, 2.5 s on GitHub's Mac).

**Speed, not changed here.** The network dominates (one pass 2.45 s, whole pipeline 7 to 13 s per
photo on GitHub's Mac). The Neural Engine stays off (iPhone 11 memory kills, section 10). Matting
and the box blurs are single-threaded; spreading them over cores is the next speed step, once the
GitHub run shows how much time they take.

Not verified: compiled only on GitHub; the finished cutouts (after matting) are measured by the
branch's quality run, not here; synthetic scenes (plain backdrops, small items) only there.
