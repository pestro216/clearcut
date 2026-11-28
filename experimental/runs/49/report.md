# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 7.2 s.

Network probe on 01_navy_shirt_on_white: raw output -23.969 to 22.359, mean -4.666; item area 25.6%; one pass 2.66 s.

Generated 2026-11-28T13:43:45Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 9.55 s, compositing and JPEG 4.81 s, JPEG 4.3 MB, peak memory so far 6969 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Gradient | Connectivity | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9988 | 1.000 | 0.071 | 0.00% | 0.12% | 4.32 | 8.71 | 1.12 | 5.98 | 5.55 s | good |
| 02_white_on_white | 0.9976 | 0.997 | 0.170 | 0.24% | 0.00% | 10.47 | 21.08 | 2.05 | 8.50 | 9.96 s | good |
| 03_black_on_dark_wood | 0.9996 | 1.000 | 0.089 | 0.03% | 0.02% | 10.14 | 27.06 | 0.71 | 3.22 | 9.86 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.05 | 0.10 | 0.39 | 8.40 s | good |
| 06_mug_handle_gap | 0.9997 | 1.000 | 0.023 | 0.03% | 0.00% | 1.66 | 5.53 | 0.12 | 0.29 | 5.01 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 1.45 | 4.55 | 6.89 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.14 | 0.29 | 1.26 | 7.99 s | good |
| 09_sunglasses_gaps | 0.1679 | 0.519 | 0.306 | 1.68% | 485.45% | 15.17 | 50.74 | 6.23 | 1652.48 | 5.38 s | good |
| 10_comb_narrow_teeth | 0.9520 | 0.964 | 0.069 | 3.11% | 1.77% | 5.05 | 11.76 | 4.57 | 29.86 | 7.58 s | good |
| 11_red_shirt_24mp | 0.9995 | 1.000 | 0.055 | 0.00% | 0.05% | 3.56 | 9.33 | 1.24 | 6.99 | 8.35 s | good |
| 12_striped_shirt_on_carpet | 0.9976 | 0.919 | 0.103 | 0.12% | 0.11% | 8.62 | 30.21 | 6.40 | 23.43 | 5.60 s | good |
| 13_leather_vest_cropped_lining | 0.7945 | 0.335 | 0.390 | 0.00% | 25.87% | 17.88 | 42.92 | 14.15 | 2382.77 | 12.06 s | check: The item fills almost the whole frame |
| R_columbia_anorak_arms_out_concrete | 0.9889 | 0.607 | 0.229 | 0.05% | 1.08% | 13.10 | 41.87 | 12.54 | 32.76 | 5.29 s | good |
| R_columbia_anorak_front_concrete | 0.9865 | 0.691 | 0.208 | 0.66% | 0.70% | 12.86 | 42.88 | 11.99 | 41.70 | 3.49 s | good |
| R_columbia_cuff_closeup_tape | 0.9326 | 0.353 | 0.303 | 5.06% | 1.80% | 15.12 | 43.16 | 20.05 | 212.38 | 7.01 s | good |
| R_columbia_hem_closeup_tape | 0.9980 | 0.831 | 0.165 | 0.04% | 0.16% | 9.25 | 30.27 | 6.31 | 49.06 | 7.54 s | good |
| R_columbia_side_closeup_tape | 0.4697 | 0.262 | 0.246 | 52.97% | 0.13% | 12.94 | 45.85 | 19.14 | 2187.01 | 4.87 s | good |
| R_michigan_cuff_tape | 0.9891 | 0.788 | 0.156 | 0.81% | 0.28% | 10.31 | 28.68 | 5.50 | 30.69 | 6.93 s | good |
| R_michigan_front_closeup_tape | 0.9953 | 0.678 | 0.152 | 0.02% | 0.45% | 12.40 | 44.88 | 8.56 | 27.54 | 6.58 s | good |
| R_michigan_jacket_back_concrete | 0.9918 | 0.578 | 0.162 | 0.35% | 0.47% | 12.03 | 44.36 | 11.73 | 29.53 | 7.21 s | good |
| R_michigan_jacket_front_open_collar | 0.9938 | 0.663 | 0.149 | 0.04% | 0.58% | 12.07 | 45.56 | 9.81 | 23.77 | 7.19 s | good |
| R_michigan_sleeve_stripes_tape | 0.9984 | 0.925 | 0.108 | 0.04% | 0.12% | 8.53 | 29.79 | 3.14 | 13.89 | 8.17 s | good |
| R_michigan_underarm_closeup | 0.9990 | 0.927 | 0.104 | 0.04% | 0.06% | 7.86 | 26.62 | 2.08 | 8.07 | 5.92 s | good |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9270 | 0.615 | 0.235 | 5.35% | 2.52% | 14.38 | 36.67 |
| previous app | 0.9432 | 0.764 | 0.156 | 5.11% | 0.59% | 9.10 | 29.91 |
| BiRefNet only | 0.8647 | 0.656 | 0.207 | 2.76% | 789.30% | 11.10 | 32.53 |
| edges: tight levels | 0.9236 | 0.783 | 0.137 | 2.85% | 22.60% | 8.32 | 29.65 |
| edges: radius 3 | 0.9233 | 0.789 | 0.143 | 2.86% | 22.62% | 8.98 | 28.83 |
| edges: radius 3, tight levels | 0.9233 | 0.789 | 0.132 | 2.86% | 22.62% | 7.98 | 29.27 |
| edges: radius 8, finer eps | 0.9235 | 0.774 | 0.150 | 2.87% | 22.60% | 9.22 | 29.23 |
| new | 0.9236 | 0.783 | 0.149 | 2.85% | 22.60% | 9.34 | 29.07 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 6969 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 50.3% | 30.1% | 7.1 px | 1 | 8.47 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 4.74 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 73.3% | 59.2% | 8.4 px | 1 | 3.73 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 46.1% | 27.6% | 6.8 px | 1 | 3.87 s | good |
| web_05_1.jpg | 78.2% | 43.8% | 7.6 px | 1 | 3.62 s | check: Some background may be left between parts of the item |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 7.27 s | good |
| web_09_1.jpg | 60.6% | 34.2% | 8.3 px | 1 | 6.49 s | good |
| web_10_0.jpg | 38.3% | 46.5% | 10.2 px | 1 | 4.81 s | good |
| web_10_1.jpg | 36.2% | 34.5% | 7.2 px | 1 | 6.39 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 11.9% | 58.3% | 12.0 px | 1 | 11.81 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 23.9% | 60.6% | 9.8 px | 1 | 7.07 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.7% | 41.4% | 9.7 px | 1 | 6.70 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 49.9% | 8.9 px | 1 | 4.55 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 38.4% | 38.0% | 8.5 px | 1 | 8.33 s | good |
| web_14_1.jpg | 17.5% | 38.8% | 6.2 px | 4 | 5.84 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 6.76 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.9% | 36.6% | 9.0 px | 1 | 8.74 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 0.3% | 43.0% | 4.8 px | 4 | 11.61 s | check: Item and background are similar in colour, so edges may be soft |
| web_16_1.jpg | 17.9% | 45.6% | 9.9 px | 1 | 8.25 s | check: Item and background are similar in colour, so edges may be soft |
| web_19_0.jpg | 26.9% | 35.4% | 6.9 px | 1 | 5.26 s | good |
| web_19_1.jpg | 22.9% | 54.6% | 10.7 px | 3 | 4.76 s | good |
| web_20_0.jpg | 16.3% | 51.6% | 10.2 px | 1 | 8.92 s | good |
| web_20_1.jpg | 59.3% | 34.2% | 7.2 px | 1 | 4.03 s | good |
| web_21_0.jpg | 42.4% | 61.0% | 12.9 px | 1 | 4.68 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 86.8% | 45.6% | 19.1 px | 1 | 3.87 s | good |
| web_22_0.jpg | 42.7% | 22.7% | 5.7 px | 1 | 3.95 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 4.66 s | good |
| web_23_0.jpg | 58.4% | 60.8% | 14.7 px | 2 | 6.57 s | good |
| web_23_1.jpg | 49.5% | 52.6% | 17.7 px | 1 | 7.10 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.2% | 42.5% | 8.7 px | 1 | 4.42 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.9% | 37.7% | 8.2 px | 1 | 8.68 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.1% | 24.8% | 5.4 px | 1 | 3.99 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.7% | 24.4% | 5.4 px | 1 | 3.23 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.8% | 49.6% | 10.4 px | 1 | 5.33 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 3.27 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 39.7% | 21.6% | 4.5 px | 1 | 3.05 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 32.3% | 42.8% | 9.4 px | 1 | 3.52 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.7% | 40.9% | 8.8 px | 1 | 4.03 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.4% | 3.6 px | 1 | 3.58 s | good |
| web_31_0.jpg | 84.0% | 51.0% | 17.6 px | 1 | 5.50 s | good |
| web_31_1.jpg | 21.8% | 41.5% | 8.6 px | 1 | 3.70 s | good |
| web_33_0.jpg | 7.6% | 40.1% | 8.9 px | 2 | 7.62 s | good |
| web_33_1.jpg | 32.9% | 27.8% | 6.0 px | 1 | 2.89 s | good |
| web_35_0.jpg | 26.6% | 13.2% | 2.8 px | 1 | 2.73 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.5% | 40.8% | 9.1 px | 1 | 7.25 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 39.0% | 55.7% | 6.5 px | 3 | 3.38 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 8.29 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 28.2% | 36.4% | 8.0 px | 1 | 4.62 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 44.4% | 29.3% | 6.7 px | 1 | 2.99 s | check: Item and background are similar in colour, so edges may be soft |
| web_39_0.jpg | 42.5% | 47.3% | 6.4 px | 4 | 5.19 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 3.29 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.4% | 6.8 px | 5 | 3.71 s | good |
| web_40_1.jpg | 4.5% | 26.9% | 5.5 px | 1 | 6.34 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 35.9% | 38.3% | 6.3 px | 2 | 2.94 s | good |
| web_43_0.jpg | 43.4% | 24.0% | 5.2 px | 1 | 3.79 s | good |
| web_43_1.jpg | 49.7% | 42.6% | 8.3 px | 1 | 2.88 s | good |
| web_44_0.jpg | 42.4% | 41.4% | 5.6 px | 5 | 4.72 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.8% | 34.0% | 6.8 px | 2 | 3.05 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.2% | 8.2 px | 2 | 3.07 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 34.4% | 45.7% | 8.1 px | 1 | 3.95 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 3.35 s | good |
| web_46_1.jpg | 87.1% | 46.7% | 14.2 px | 1 | 4.78 s | good |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 6.87 s | good |
| web_48_1.jpg | 31.9% | 30.6% | 6.5 px | 1 | 2.92 s | good |
| web_49_0.jpg | 18.7% | 39.2% | 7.4 px | 2 | 7.74 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.3% | 43.8% | 9.1 px | 1 | 3.33 s | good |
| web_50_0.jpg | 50.7% | 32.6% | 6.9 px | 1 | 4.94 s | good |
| web_50_1.jpg | 32.9% | 30.3% | 8.0 px | 4 | 4.59 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.3% | 35.7% | 7.7 px | 1 | 3.21 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.9% | 48.4% | 9.9 px | 1 | 4.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 10.0% | 50.2% | 8.4 px | 1 | 5.20 s | good |
| web_53_0.jpg | 46.2% | 56.3% | 11.9 px | 1 | 6.17 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 15.0% | 50.4% | 10.0 px | 1 | 5.86 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 24.8% | 5.3 px | 1 | 2.84 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 5.12 s | good |
| web_58_0.jpg | 79.2% | 56.1% | 13.5 px | 2 | 5.17 s | good |
| web_60_0.jpg | 65.9% | 53.1% | 16.1 px | 1 | 5.28 s | good |
| web_60_1.jpg | 19.2% | 37.6% | 7.5 px | 1 | 6.07 s | good |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9520 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.964 < 1.000
- 10_comb_narrow_teeth: edge ΔE 5.05 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 09_sunglasses_gaps: IoU 0.1679 < 0.9737
- 09_sunglasses_gaps: boundary F 0.519 < 0.786
- 09_sunglasses_gaps: edge ΔE 15.17 > 8.51
- 09_sunglasses_gaps: kept background rose
