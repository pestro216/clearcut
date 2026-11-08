# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 7.5 s.

Network probe on 01_navy_shirt_on_white: raw output -23.828 to 22.625, mean -4.672; item area 25.6%; one pass 5.63 s.

Generated 2026-11-08T02:54:20Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 12.56 s, compositing and JPEG 3.19 s, JPEG 4.3 MB, peak memory so far 4518 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9991 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 13.29 s | good |
| 02_white_on_white | 0.9978 | 0.997 | 0.171 | 0.22% | 0.00% | 10.68 | 21.08 | 11.69 s | good |
| 03_black_on_dark_wood | 0.9994 | 1.000 | 0.083 | 0.02% | 0.04% | 8.86 | 25.12 | 13.90 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.06 | 14.11 s | good |
| 06_mug_handle_gap | 0.9994 | 1.000 | 0.028 | 0.02% | 0.05% | 1.99 | 6.79 | 9.04 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 13.10 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.13 | 10.32 s | good |
| 09_sunglasses_gaps | 0.9743 | 0.786 | 0.139 | 2.31% | 0.27% | 8.61 | 62.17 | 14.32 s | good |
| 10_comb_narrow_teeth | 0.9021 | 0.903 | 0.105 | 5.55% | 4.70% | 6.91 | 33.85 | 12.18 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9996 | 1.000 | 0.046 | 0.01% | 0.04% | 3.45 | 10.00 | 14.43 s | good |
| 12_striped_shirt_on_carpet | 0.9977 | 0.919 | 0.102 | 0.12% | 0.11% | 8.61 | 29.97 | 6.26 s | good |
| 13_leather_vest_cropped_lining | 0.7966 | 0.338 | 0.373 | 0.15% | 25.34% | 17.17 | 42.84 | 10.41 s | check: The item fills almost the whole frame |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9221 | 0.721 | 0.235 | 5.47% | 3.17% | 14.96 | 37.16 |
| previous app | 0.9473 | 0.877 | 0.127 | 4.84% | 0.44% | 7.21 | 24.16 |
| BiRefNet only | 0.8603 | 0.682 | 0.221 | 1.55% | 1301.61% | 11.55 | 30.01 |
| edges: tight levels | 0.9715 | 0.910 | 0.089 | 0.71% | 2.60% | 5.57 | 22.88 |
| edges: radius 3 | 0.9703 | 0.910 | 0.098 | 0.79% | 2.66% | 6.39 | 23.03 |
| edges: radius 3, tight levels | 0.9703 | 0.910 | 0.081 | 0.79% | 2.66% | 5.14 | 22.45 |
| edges: radius 8, finer eps | 0.9723 | 0.907 | 0.106 | 0.73% | 2.49% | 6.54 | 23.04 |
| new | 0.9715 | 0.910 | 0.107 | 0.71% | 2.60% | 6.82 | 23.17 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 4518 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 37.1% | 28.9% | 6.7 px | 1 | 8.77 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 4.30 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 51.7% | 58.5% | 9.1 px | 2 | 4.50 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 64.0% | 38.2% | 6.9 px | 1 | 4.34 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_1.jpg | 51.6% | 52.6% | 10.6 px | 1 | 4.59 s | good |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 8.12 s | good |
| web_09_1.jpg | 54.7% | 41.5% | 10.1 px | 1 | 8.81 s | good |
| web_10_0.jpg | 38.2% | 46.1% | 10.1 px | 1 | 4.50 s | good |
| web_10_1.jpg | 36.2% | 34.8% | 7.3 px | 1 | 9.14 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 4.8% | 74.6% | 15.8 px | 1 | 13.39 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 9.9% | 43.3% | 9.2 px | 4 | 13.76 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.8% | 42.7% | 10.0 px | 1 | 8.73 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 50.0% | 8.9 px | 1 | 4.35 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 37.1% | 45.4% | 11.4 px | 1 | 14.24 s | good |
| web_14_1.jpg | 17.6% | 37.9% | 6.5 px | 4 | 9.73 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 9.40 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.7% | 37.0% | 7.7 px | 1 | 12.45 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 58.2% | 11.9% | 2.7 px | 1 | 4.55 s | good |
| web_16_1.jpg | 57.7% | 26.0% | 5.7 px | 1 | 5.52 s | good |
| web_19_0.jpg | 26.9% | 34.8% | 6.8 px | 1 | 9.74 s | good |
| web_19_1.jpg | 21.7% | 57.9% | 10.4 px | 3 | 9.88 s | good |
| web_20_0.jpg | 16.3% | 51.5% | 10.2 px | 1 | 9.44 s | good |
| web_20_1.jpg | 48.4% | 44.7% | 9.4 px | 1 | 5.48 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_0.jpg | 15.0% | 51.7% | 5.0 px | 1 | 5.23 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 93.1% | 45.5% | 8.4 px | 1 | 5.48 s | check: The item fills almost the whole frame |
| web_22_0.jpg | 42.7% | 22.7% | 5.6 px | 1 | 4.77 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 4.77 s | good |
| web_23_0.jpg | 54.5% | 62.9% | 14.1 px | 1 | 8.92 s | good |
| web_23_1.jpg | 29.1% | 44.8% | 9.5 px | 1 | 13.64 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.1% | 41.6% | 8.8 px | 1 | 10.08 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.6% | 39.6% | 8.5 px | 1 | 14.72 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.0% | 23.5% | 5.1 px | 1 | 10.63 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.5% | 23.9% | 5.4 px | 1 | 9.90 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.7% | 51.2% | 10.9 px | 1 | 10.26 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 5.87 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 35.3% | 22.2% | 4.8 px | 1 | 9.89 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 38.7% | 23.0% | 4.8 px | 1 | 10.24 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.6% | 41.6% | 8.9 px | 1 | 11.59 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.5% | 3.6 px | 1 | 10.71 s | good |
| web_31_0.jpg | 83.0% | 51.8% | 16.9 px | 1 | 9.92 s | good |
| web_31_1.jpg | 19.2% | 33.5% | 6.7 px | 1 | 5.65 s | good |
| web_33_0.jpg | 7.5% | 30.4% | 6.9 px | 1 | 13.72 s | good |
| web_33_1.jpg | 32.9% | 15.8% | 3.4 px | 1 | 4.85 s | good |
| web_35_0.jpg | 26.6% | 13.0% | 2.7 px | 1 | 9.15 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.4% | 41.5% | 9.1 px | 1 | 14.75 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 38.4% | 57.0% | 6.5 px | 3 | 6.92 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 17.64 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 21.5% | 33.5% | 7.3 px | 1 | 5.30 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 17.7% | 33.0% | 7.7 px | 2 | 9.01 s | check: Some background may be left between parts of the item |
| web_39_0.jpg | 44.4% | 40.0% | 8.4 px | 3 | 9.74 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 4.53 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.4% | 6.7 px | 5 | 4.79 s | good |
| web_40_1.jpg | 4.5% | 26.8% | 5.6 px | 1 | 14.39 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 36.0% | 37.8% | 6.2 px | 2 | 4.87 s | good |
| web_43_0.jpg | 43.4% | 24.1% | 5.2 px | 1 | 5.23 s | good |
| web_43_1.jpg | 38.2% | 36.6% | 5.4 px | 1 | 5.15 s | check: Item and background are similar in colour, so edges may be soft |
| web_44_0.jpg | 42.4% | 42.5% | 5.6 px | 5 | 10.54 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.6% | 33.3% | 6.7 px | 1 | 10.13 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.1% | 8.2 px | 2 | 4.43 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 23.5% | 45.2% | 8.7 px | 2 | 8.39 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 4.69 s | good |
| web_46_1.jpg | 45.5% | 35.1% | 6.4 px | 2 | 8.50 s | check: Some background may be left between parts of the item |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 12.88 s | good |
| web_48_1.jpg | 31.9% | 30.7% | 6.5 px | 1 | 8.11 s | good |
| web_49_0.jpg | 16.8% | 40.6% | 7.9 px | 2 | 12.19 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.3% | 42.5% | 8.8 px | 1 | 8.17 s | good |
| web_50_0.jpg | 2.9% | 20.8% | 4.4 px | 1 | 12.91 s | good |
| web_50_1.jpg | 30.5% | 28.3% | 6.3 px | 4 | 8.69 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.2% | 32.6% | 7.0 px | 1 | 8.53 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.7% | 46.6% | 9.5 px | 1 | 8.67 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 9.9% | 46.2% | 8.0 px | 1 | 12.20 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_0.jpg | 46.2% | 56.3% | 11.8 px | 1 | 8.95 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 33.3% | 37.0% | 7.0 px | 1 | 8.85 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 10.4% | 2.2 px | 1 | 8.56 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 8.77 s | good |
| web_58_0.jpg | 49.9% | 57.6% | 11.8 px | 1 | 10.64 s | good |
| web_60_0.jpg | 18.6% | 37.7% | 7.5 px | 1 | 9.94 s | good |
| web_60_1.jpg | 13.2% | 40.5% | 8.6 px | 1 | 14.85 s | check: Item and background are similar in colour, so edges may be soft |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9021 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.903 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.91 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
