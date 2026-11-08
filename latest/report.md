# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 11.9 s.

Generated 2026-11-08T00:01:18Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 10.98 s, compositing and JPEG 4.61 s, JPEG 4.4 MB, peak memory so far 3068 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.2808 | 0.346 | 0.349 | 0.01% | 256.10% | 17.90 | 47.40 | 9.73 s | good |
| 02_white_on_white | 0.1969 | 0.288 | 0.390 | 0.04% | 407.68% | 19.33 | 50.08 | 9.37 s | good |
| 03_black_on_dark_wood | 0.1430 | 0.000 | 0.494 | 0.00% | 599.38% | 32.66 | 63.83 | 9.00 s | check: The item fills almost the whole frame |
| 04_watch_thin_straps | 0.3402 | 0.477 | 0.069 | 0.01% | 193.90% | 4.30 | 9.72 | 8.64 s | good |
| 05_fine_chain_on_marble | 0.0048 | 0.000 | 0.740 | 0.00% | 20698.35% | 25.73 | 35.88 | 7.96 s | check: The item fills almost the whole frame |
| 06_mug_handle_gap | 0.9984 | 1.000 | 0.039 | 0.02% | 0.13% | 2.59 | 8.75 | 12.72 s | good |
| 07_reflective_bottle | 0.9953 | 0.965 | 0.107 | 0.04% | 0.43% | 5.64 | 17.38 | 14.52 s | good |
| 08_fuzzy_knit_edge | 0.1572 | 0.000 | 0.503 | 0.00% | 536.29% | 20.13 | 42.63 | 7.90 s | check: The item fills almost the whole frame |
| 09_sunglasses_gaps | 0.1677 | 0.517 | 0.310 | 1.60% | 486.96% | 15.33 | 48.50 | 11.96 s | good |
| 10_comb_narrow_teeth | 0.7551 | 0.760 | 0.214 | 21.25% | 4.29% | 12.32 | 50.62 | 10.91 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.4225 | 0.387 | 0.187 | 0.01% | 136.67% | 11.56 | 54.79 | 9.91 s | good |
| 12_striped_shirt_on_carpet | 0.9969 | 0.891 | 0.114 | 0.14% | 0.17% | 9.20 | 35.03 | 7.77 s | good |
| 13_leather_vest_cropped_lining | 0.7585 | 0.000 | 0.499 | 0.00% | 31.85% | 22.73 | 43.41 | 6.52 s | check: The item fills almost the whole frame |
| 14_shirt_closeup_fills_frame | 0.7392 | 0.218 | 0.420 | 0.01% | 35.28% | 18.59 | 42.95 | 6.41 s | check: The item fills almost the whole frame |
| 15_shirt_cut_off_by_frame | 0.5724 | 0.000 | 0.500 | 0.00% | 74.69% | 21.65 | 43.42 | 8.26 s | check: The item fills almost the whole frame |
| 16_vest_closeup_corners | 0.9999 | 0.946 | 0.089 | 0.01% | 0.00% | 5.66 | 18.17 | 9.31 s | check: The item fills almost the whole frame |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9221 | 0.721 | 0.235 | 5.47% | 3.17% | 14.96 | 37.16 |
| previous app | 0.9473 | 0.877 | 0.127 | 4.84% | 0.44% | 7.21 | 24.16 |
| previous app + surface model | 0.9508 | 0.881 | 0.113 | 4.52% | 0.41% | 6.76 | 24.31 |
| BiRefNet only | 0.5151 | 0.237 | 0.385 | 2.59% | 1466.07% | 19.59 | 44.96 |
| new: no zoom pass | 0.5329 | 0.423 | 0.315 | 1.45% | 1466.40% | 15.40 | 38.65 |
| new: no colour evidence | 0.5183 | 0.434 | 0.331 | 2.33% | 1467.65% | 16.14 | 38.42 |
| new: no edge refinement | 0.5286 | 0.294 | 0.359 | 1.80% | 1464.90% | 18.05 | 42.59 |
| new | 0.5330 | 0.425 | 0.314 | 1.45% | 1466.39% | 15.33 | 38.28 |

Peak memory of the whole benchmark process: 3068 MB.

**Regression check: FAILED**

- 02_white_on_white: IoU 0.1969 < 0.9979
- 02_white_on_white: boundary F 0.288 < 0.999
- 02_white_on_white: edge ΔE 19.33 > 9.39
- 02_white_on_white: kept background rose
- 08_fuzzy_knit_edge: IoU 0.1572 < 0.9982
- 08_fuzzy_knit_edge: boundary F 0.000 < 0.998
- 08_fuzzy_knit_edge: edge ΔE 20.13 > 3.45
- 08_fuzzy_knit_edge: kept background rose
- 01_navy_shirt_on_white: IoU 0.2808 < 0.9988
- 01_navy_shirt_on_white: boundary F 0.346 < 1.000
- 01_navy_shirt_on_white: edge ΔE 17.90 > 4.72
- 01_navy_shirt_on_white: kept background rose
- 11_red_shirt_24mp: IoU 0.4225 < 0.9994
- 11_red_shirt_24mp: boundary F 0.387 < 1.000
- 11_red_shirt_24mp: edge ΔE 11.56 > 5.75
- 11_red_shirt_24mp: kept background rose
- 04_watch_thin_straps: IoU 0.3402 < 0.9980
- 04_watch_thin_straps: boundary F 0.477 < 1.000
- 04_watch_thin_straps: edge ΔE 4.30 > 3.33
- 04_watch_thin_straps: kept background rose
- 03_black_on_dark_wood: IoU 0.1430 < 0.9987
- 03_black_on_dark_wood: boundary F 0.000 < 0.997
- 03_black_on_dark_wood: edge ΔE 32.66 > 9.40
- 03_black_on_dark_wood: kept background rose
- 09_sunglasses_gaps: IoU 0.1677 < 0.9737
- 09_sunglasses_gaps: boundary F 0.517 < 0.786
- 09_sunglasses_gaps: edge ΔE 15.33 > 8.51
- 09_sunglasses_gaps: kept background rose
- 10_comb_narrow_teeth: IoU 0.7551 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.760 < 1.000
- 10_comb_narrow_teeth: edge ΔE 12.32 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
