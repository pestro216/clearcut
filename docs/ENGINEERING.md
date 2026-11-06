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
