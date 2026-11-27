# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 8.1 s.

Network probe on 01_navy_shirt_on_white: raw output -23.828 to 22.625, mean -4.672; item area 25.6%; one pass 4.98 s.

Generated 2026-11-27T00:22:24Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 16.24 s, compositing and JPEG 3.30 s, JPEG 4.3 MB, peak memory so far 3663 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Gradient | Connectivity | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9991 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 0.95 | 5.07 | 22.20 s | good |
| 02_white_on_white | 0.9974 | 0.993 | 0.174 | 0.26% | 0.00% | 10.76 | 20.69 | 2.14 | 8.59 | 17.57 s | good |
| 03_black_on_dark_wood | 0.9996 | 1.000 | 0.089 | 0.03% | 0.02% | 10.14 | 27.06 | 0.71 | 3.23 | 29.16 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.06 | 0.10 | 0.39 | 18.28 s | good |
| 06_mug_handle_gap | 0.9997 | 1.000 | 0.023 | 0.03% | 0.00% | 1.67 | 5.53 | 0.12 | 0.29 | 14.02 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 1.45 | 4.55 | 16.51 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.13 | 0.29 | 1.26 | 13.46 s | good |
| 09_sunglasses_gaps | 0.9743 | 0.786 | 0.139 | 2.31% | 0.27% | 8.61 | 62.17 | 4.17 | 9.09 | 19.03 s | good |
| 10_comb_narrow_teeth | 0.9021 | 0.903 | 0.105 | 5.55% | 4.70% | 6.91 | 33.85 | 8.25 | 58.31 | 19.55 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9996 | 1.000 | 0.046 | 0.01% | 0.04% | 3.45 | 10.00 | 0.94 | 5.12 | 15.87 s | good |
| 12_striped_shirt_on_carpet | 0.9977 | 0.919 | 0.102 | 0.12% | 0.11% | 8.61 | 29.97 | 6.37 | 23.35 | 9.89 s | good |
| 13_leather_vest_cropped_lining | 0.7978 | 0.384 | 0.373 | 0.00% | 25.34% | 17.17 | 42.84 | 13.22 | 2325.20 | 12.06 s | check: The item fills almost the whole frame |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9221 | 0.721 | 0.235 | 5.47% | 3.17% | 14.96 | 37.16 |
| previous app | 0.9473 | 0.877 | 0.127 | 4.84% | 0.44% | 7.21 | 24.16 |
| BiRefNet only | 0.8600 | 0.681 | 0.224 | 1.56% | 1300.86% | 11.66 | 30.59 |
| edges: tight levels | 0.9716 | 0.913 | 0.089 | 0.71% | 2.60% | 5.66 | 23.21 |
| edges: radius 3 | 0.9704 | 0.914 | 0.098 | 0.78% | 2.65% | 6.50 | 23.08 |
| edges: radius 3, tight levels | 0.9704 | 0.914 | 0.082 | 0.78% | 2.65% | 5.22 | 22.86 |
| edges: radius 8, finer eps | 0.9724 | 0.911 | 0.106 | 0.72% | 2.49% | 6.62 | 23.14 |
| new | 0.9716 | 0.913 | 0.107 | 0.71% | 2.60% | 6.91 | 23.19 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 3663 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 50.1% | 28.6% | 7.0 px | 1 | 12.97 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 6.83 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 73.5% | 59.4% | 8.5 px | 1 | 6.06 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 46.1% | 27.5% | 6.8 px | 1 | 5.55 s | good |
| web_05_1.jpg | 78.2% | 43.8% | 7.6 px | 1 | 5.92 s | check: Some background may be left between parts of the item |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 13.57 s | good |
| web_09_1.jpg | 60.6% | 32.1% | 8.1 px | 1 | 15.42 s | good |
| web_10_0.jpg | 38.3% | 46.5% | 10.2 px | 1 | 7.73 s | good |
| web_10_1.jpg | 36.2% | 34.5% | 7.2 px | 1 | 11.95 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 11.9% | 58.4% | 12.0 px | 1 | 15.88 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 23.3% | 61.1% | 9.7 px | 2 | 11.59 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.7% | 41.4% | 9.7 px | 1 | 11.77 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 50.0% | 8.9 px | 1 | 7.57 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 38.4% | 39.3% | 9.1 px | 1 | 18.26 s | good |
| web_14_1.jpg | 17.6% | 37.9% | 6.5 px | 4 | 13.12 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 11.22 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.9% | 36.6% | 9.0 px | 1 | 17.51 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 0.3% | 42.9% | 4.8 px | 4 | 19.42 s | check: Item and background are similar in colour, so edges may be soft |
| web_16_1.jpg | 17.9% | 45.6% | 9.9 px | 1 | 12.60 s | check: Item and background are similar in colour, so edges may be soft |
| web_19_0.jpg | 26.9% | 34.7% | 6.8 px | 1 | 12.50 s | good |
| web_19_1.jpg | 22.0% | 58.4% | 10.3 px | 3 | 10.95 s | good |
| web_20_0.jpg | 16.3% | 51.5% | 10.2 px | 1 | 10.72 s | good |
| web_20_1.jpg | 59.2% | 34.9% | 7.0 px | 1 | 6.91 s | good |
| web_21_0.jpg | 42.5% | 61.1% | 13.1 px | 1 | 8.81 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 85.8% | 43.2% | 19.9 px | 1 | 9.84 s | good |
| web_22_0.jpg | 42.7% | 22.7% | 5.6 px | 1 | 9.50 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 8.74 s | good |
| web_23_0.jpg | 66.1% | 66.4% | 15.5 px | 2 | 13.25 s | good |
| web_23_1.jpg | 31.1% | 45.9% | 9.8 px | 1 | 16.67 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.2% | 41.5% | 8.5 px | 1 | 11.94 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.9% | 37.6% | 8.2 px | 1 | 17.17 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.0% | 23.5% | 5.1 px | 1 | 12.15 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.5% | 23.9% | 5.4 px | 1 | 12.85 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.8% | 50.7% | 11.6 px | 1 | 11.31 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 7.68 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 39.7% | 22.0% | 4.6 px | 1 | 7.37 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 32.3% | 42.5% | 9.4 px | 1 | 11.88 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.7% | 41.9% | 9.0 px | 1 | 12.49 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.5% | 3.6 px | 1 | 12.21 s | good |
| web_31_0.jpg | 83.1% | 49.7% | 14.5 px | 1 | 14.01 s | good |
| web_31_1.jpg | 21.8% | 41.5% | 8.6 px | 1 | 7.46 s | good |
| web_33_0.jpg | 8.1% | 37.2% | 8.4 px | 1 | 15.64 s | good |
| web_33_1.jpg | 32.9% | 27.9% | 6.0 px | 1 | 7.04 s | good |
| web_35_0.jpg | 26.6% | 13.0% | 2.7 px | 1 | 10.93 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.5% | 40.8% | 9.2 px | 1 | 16.64 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 39.1% | 55.7% | 6.4 px | 3 | 7.82 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 18.80 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 15.5% | 45.4% | 12.0 px | 1 | 6.53 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 44.4% | 29.4% | 6.7 px | 1 | 7.69 s | check: Item and background are similar in colour, so edges may be soft |
| web_39_0.jpg | 44.4% | 39.8% | 8.2 px | 3 | 14.19 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 8.13 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.4% | 6.8 px | 5 | 9.05 s | good |
| web_40_1.jpg | 4.5% | 26.8% | 5.6 px | 1 | 20.72 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 35.9% | 38.3% | 6.3 px | 2 | 7.13 s | good |
| web_43_0.jpg | 43.4% | 24.0% | 5.2 px | 1 | 7.97 s | good |
| web_43_1.jpg | 49.7% | 42.6% | 8.3 px | 1 | 6.96 s | good |
| web_44_0.jpg | 42.4% | 42.1% | 5.6 px | 5 | 11.96 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.6% | 33.3% | 6.7 px | 1 | 13.07 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.1% | 8.2 px | 2 | 6.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 34.4% | 46.1% | 8.2 px | 1 | 10.84 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 6.67 s | good |
| web_46_1.jpg | 45.5% | 35.1% | 6.4 px | 2 | 13.49 s | check: Some background may be left between parts of the item |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 16.82 s | good |
| web_48_1.jpg | 31.9% | 30.7% | 6.5 px | 1 | 13.17 s | good |
| web_49_0.jpg | 18.7% | 39.5% | 7.4 px | 2 | 17.96 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.4% | 42.7% | 8.8 px | 1 | 12.46 s | good |
| web_50_0.jpg | 2.9% | 20.8% | 4.4 px | 1 | 18.55 s | good |
| web_50_1.jpg | 32.9% | 30.1% | 7.8 px | 4 | 12.84 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.3% | 35.5% | 7.7 px | 1 | 11.87 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.9% | 48.3% | 9.9 px | 1 | 12.56 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 9.9% | 46.2% | 8.0 px | 1 | 16.62 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_0.jpg | 46.2% | 56.3% | 11.8 px | 1 | 12.05 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 15.0% | 50.3% | 10.0 px | 1 | 11.46 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 11.4% | 2.4 px | 1 | 10.61 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 11.01 s | good |
| web_58_0.jpg | 62.1% | 61.8% | 13.0 px | 1 | 12.28 s | good |
| web_60_0.jpg | 13.2% | 40.1% | 8.5 px | 1 | 16.98 s | check: Item and background are similar in colour, so edges may be soft |
| web_60_1.jpg | 19.2% | 37.6% | 7.5 px | 1 | 10.90 s | good |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9021 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.903 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.91 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
