# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 7.7 s.

Network probe on 01_navy_shirt_on_white: raw output -23.828 to 22.625, mean -4.672; item area 25.6%; one pass 5.81 s.

Generated 2026-11-25T23:02:20Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 21.75 s, compositing and JPEG 5.30 s, JPEG 4.3 MB, peak memory so far 4524 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9991 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 13.94 s | good |
| 02_white_on_white | 0.9974 | 0.993 | 0.174 | 0.26% | 0.00% | 10.76 | 20.69 | 11.70 s | good |
| 03_black_on_dark_wood | 0.9996 | 1.000 | 0.089 | 0.03% | 0.02% | 10.14 | 27.06 | 16.97 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.06 | 19.94 s | good |
| 06_mug_handle_gap | 0.9997 | 1.000 | 0.023 | 0.03% | 0.00% | 1.67 | 5.53 | 10.57 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 20.39 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.13 | 14.33 s | good |
| 09_sunglasses_gaps | 0.9743 | 0.786 | 0.139 | 2.31% | 0.27% | 8.61 | 62.17 | 19.74 s | good |
| 10_comb_narrow_teeth | 0.9021 | 0.903 | 0.105 | 5.55% | 4.70% | 6.91 | 33.85 | 18.46 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9996 | 1.000 | 0.046 | 0.01% | 0.04% | 3.45 | 10.00 | 18.27 s | good |
| 12_striped_shirt_on_carpet | 0.9977 | 0.919 | 0.102 | 0.12% | 0.11% | 8.61 | 29.97 | 8.63 s | good |
| 13_leather_vest_cropped_lining | 0.7966 | 0.338 | 0.373 | 0.15% | 25.34% | 17.17 | 42.84 | 12.48 s | check: The item fills almost the whole frame |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9221 | 0.721 | 0.235 | 5.47% | 3.17% | 14.96 | 37.16 |
| previous app | 0.9473 | 0.877 | 0.127 | 4.84% | 0.44% | 7.21 | 24.16 |
| BiRefNet only | 0.8600 | 0.681 | 0.224 | 1.56% | 1300.86% | 11.66 | 30.59 |
| edges: tight levels | 0.9715 | 0.909 | 0.089 | 0.72% | 2.60% | 5.66 | 23.21 |
| edges: radius 3 | 0.9703 | 0.910 | 0.098 | 0.80% | 2.65% | 6.50 | 23.08 |
| edges: radius 3, tight levels | 0.9703 | 0.910 | 0.082 | 0.80% | 2.65% | 5.22 | 22.86 |
| edges: radius 8, finer eps | 0.9723 | 0.906 | 0.106 | 0.74% | 2.49% | 6.62 | 23.14 |
| new | 0.9715 | 0.909 | 0.107 | 0.72% | 2.60% | 6.91 | 23.19 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 4524 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 50.0% | 30.0% | 10.0 px | 1 | 16.51 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 9.44 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 73.5% | 59.4% | 8.5 px | 1 | 6.47 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 46.1% | 27.5% | 6.8 px | 1 | 7.04 s | good |
| web_05_1.jpg | 78.2% | 43.8% | 7.6 px | 1 | 7.39 s | check: Some background may be left between parts of the item |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 14.55 s | good |
| web_09_1.jpg | 60.6% | 32.1% | 11.9 px | 1 | 15.05 s | good |
| web_10_0.jpg | 38.3% | 46.5% | 10.2 px | 1 | 7.36 s | good |
| web_10_1.jpg | 36.2% | 34.8% | 7.3 px | 1 | 14.05 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 11.3% | 59.6% | 11.6 px | 1 | 23.20 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 23.3% | 61.1% | 9.7 px | 2 | 13.32 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.7% | 41.4% | 9.7 px | 1 | 12.74 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 50.0% | 8.9 px | 1 | 6.73 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 38.3% | 42.6% | 10.1 px | 1 | 19.83 s | good |
| web_14_1.jpg | 17.6% | 37.9% | 6.5 px | 4 | 13.70 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 12.85 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.9% | 36.6% | 9.0 px | 1 | 18.33 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 0.3% | 42.9% | 4.8 px | 4 | 19.40 s | check: Item and background are similar in colour, so edges may be soft |
| web_16_1.jpg | 17.9% | 45.6% | 9.9 px | 1 | 13.56 s | check: Item and background are similar in colour, so edges may be soft |
| web_19_0.jpg | 26.9% | 34.8% | 6.8 px | 1 | 14.06 s | good |
| web_19_1.jpg | 21.7% | 57.9% | 10.4 px | 3 | 13.56 s | good |
| web_20_0.jpg | 16.3% | 51.5% | 10.2 px | 1 | 13.94 s | good |
| web_20_1.jpg | 58.6% | 39.0% | 7.7 px | 1 | 6.45 s | good |
| web_21_0.jpg | 37.2% | 66.7% | 10.1 px | 1 | 6.41 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 83.7% | 57.7% | 22.5 px | 1 | 6.71 s | good |
| web_22_0.jpg | 42.7% | 22.7% | 5.6 px | 1 | 6.72 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 6.39 s | good |
| web_23_0.jpg | 66.0% | 66.3% | 16.0 px | 2 | 12.68 s | good |
| web_23_1.jpg | 30.7% | 48.3% | 10.5 px | 1 | 17.79 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.2% | 41.5% | 8.7 px | 1 | 11.99 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.7% | 39.8% | 8.4 px | 1 | 17.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.0% | 23.5% | 5.1 px | 1 | 11.69 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.5% | 23.9% | 5.4 px | 1 | 11.72 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.8% | 51.0% | 11.4 px | 1 | 12.27 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 7.19 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 39.7% | 22.0% | 4.6 px | 1 | 6.68 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 32.3% | 42.5% | 9.4 px | 1 | 12.88 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.7% | 41.9% | 9.0 px | 1 | 13.43 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.5% | 3.6 px | 1 | 12.43 s | good |
| web_31_0.jpg | 83.0% | 51.8% | 16.9 px | 1 | 12.86 s | good |
| web_31_1.jpg | 21.8% | 41.5% | 8.6 px | 1 | 7.75 s | good |
| web_33_0.jpg | 8.1% | 37.2% | 8.4 px | 1 | 17.62 s | good |
| web_33_1.jpg | 32.9% | 27.9% | 6.0 px | 1 | 7.78 s | good |
| web_35_0.jpg | 26.6% | 13.0% | 2.7 px | 1 | 11.87 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.4% | 41.4% | 9.1 px | 1 | 17.51 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 38.4% | 57.0% | 6.5 px | 3 | 6.14 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 18.27 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 15.5% | 45.4% | 11.9 px | 1 | 6.29 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 44.3% | 29.2% | 7.0 px | 1 | 6.79 s | check: Item and background are similar in colour, so edges may be soft |
| web_39_0.jpg | 44.4% | 39.9% | 8.3 px | 3 | 12.16 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 6.54 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.5% | 6.8 px | 5 | 6.94 s | good |
| web_40_1.jpg | 4.5% | 26.8% | 5.6 px | 1 | 17.68 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 35.9% | 38.3% | 6.3 px | 2 | 6.61 s | good |
| web_43_0.jpg | 43.4% | 24.1% | 5.2 px | 1 | 6.18 s | good |
| web_43_1.jpg | 49.7% | 42.6% | 8.3 px | 1 | 6.78 s | good |
| web_44_0.jpg | 42.4% | 42.5% | 5.6 px | 5 | 11.75 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.6% | 33.3% | 6.7 px | 1 | 11.81 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.1% | 8.2 px | 2 | 6.41 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 34.4% | 46.1% | 8.2 px | 1 | 12.44 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 6.18 s | good |
| web_46_1.jpg | 45.5% | 35.1% | 6.4 px | 2 | 11.61 s | check: Some background may be left between parts of the item |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 19.49 s | good |
| web_48_1.jpg | 31.9% | 30.7% | 6.5 px | 1 | 13.31 s | good |
| web_49_0.jpg | 18.5% | 41.1% | 7.8 px | 2 | 18.71 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.4% | 42.7% | 8.8 px | 1 | 12.37 s | good |
| web_50_0.jpg | 2.9% | 20.8% | 4.4 px | 1 | 19.01 s | good |
| web_50_1.jpg | 32.7% | 30.8% | 7.3 px | 4 | 13.76 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.3% | 35.5% | 7.7 px | 1 | 13.57 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.9% | 48.3% | 9.8 px | 1 | 13.37 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 9.9% | 46.2% | 8.0 px | 1 | 19.25 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_0.jpg | 46.2% | 56.3% | 11.8 px | 1 | 12.94 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 15.0% | 50.3% | 10.0 px | 1 | 13.29 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 11.4% | 2.4 px | 1 | 12.86 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 13.08 s | good |
| web_58_0.jpg | 49.9% | 57.6% | 11.8 px | 1 | 14.02 s | good |
| web_60_0.jpg | 13.2% | 40.1% | 8.6 px | 1 | 19.44 s | check: Item and background are similar in colour, so edges may be soft |
| web_60_1.jpg | 18.6% | 37.7% | 7.5 px | 1 | 12.46 s | good |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9021 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.903 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.91 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
