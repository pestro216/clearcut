# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 10.5 s.

Network probe on 01_navy_shirt_on_white: raw output -23.828 to 22.625, mean -4.672; item area 25.6%; one pass 6.89 s.

Generated 2026-11-08T01:41:28Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 14.63 s, compositing and JPEG 4.39 s, JPEG 4.3 MB, peak memory so far 3822 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9991 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 15.10 s | good |
| 02_white_on_white | 0.9978 | 0.997 | 0.171 | 0.22% | 0.00% | 10.68 | 21.08 | 12.91 s | good |
| 03_black_on_dark_wood | 0.9994 | 1.000 | 0.083 | 0.02% | 0.04% | 8.86 | 25.12 | 16.82 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.06 | 17.16 s | good |
| 06_mug_handle_gap | 0.9994 | 1.000 | 0.028 | 0.02% | 0.05% | 1.99 | 6.79 | 11.43 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 16.67 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.13 | 11.58 s | good |
| 09_sunglasses_gaps | 0.9743 | 0.786 | 0.139 | 2.31% | 0.27% | 8.61 | 62.17 | 16.20 s | good |
| 10_comb_narrow_teeth | 0.9021 | 0.903 | 0.105 | 5.55% | 4.70% | 6.91 | 33.85 | 16.91 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9996 | 1.000 | 0.046 | 0.01% | 0.04% | 3.45 | 10.00 | 15.28 s | good |
| 12_striped_shirt_on_carpet | 0.9977 | 0.919 | 0.102 | 0.12% | 0.11% | 8.61 | 29.97 | 7.37 s | good |
| 13_leather_vest_cropped_lining | 0.7966 | 0.338 | 0.373 | 0.15% | 25.34% | 17.17 | 42.84 | 12.94 s | check: The item fills almost the whole frame |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9221 | 0.721 | 0.235 | 5.47% | 3.17% | 14.96 | 37.16 |
| previous app | 0.9473 | 0.877 | 0.127 | 4.84% | 0.44% | 7.21 | 24.16 |
| previous app + surface model | 0.9508 | 0.881 | 0.113 | 4.52% | 0.41% | 6.76 | 24.31 |
| BiRefNet only | 0.8603 | 0.682 | 0.221 | 1.55% | 1301.61% | 11.55 | 30.01 |
| new: no zoom pass | 0.9713 | 0.905 | 0.115 | 0.72% | 2.62% | 7.21 | 23.75 |
| new: no colour evidence | 0.9592 | 0.913 | 0.110 | 1.69% | 3.04% | 7.10 | 25.07 |
| new: no edge refinement | 0.9655 | 0.881 | 0.124 | 1.21% | 2.74% | 8.66 | 31.31 |
| new | 0.9715 | 0.910 | 0.107 | 0.71% | 2.60% | 6.82 | 23.17 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 3822 MB.

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9021 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.903 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.91 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
