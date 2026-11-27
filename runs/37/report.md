# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 11.0 s.

Network probe on 01_navy_shirt_on_white: raw output -23.828 to 22.625, mean -4.672; item area 25.6%; one pass 8.08 s.

Generated 2026-11-27T00:00:52Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 16.45 s, compositing and JPEG 3.82 s, JPEG 4.3 MB, peak memory so far 3731 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9991 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 17.28 s | good |
| 02_white_on_white | 0.9974 | 0.993 | 0.174 | 0.26% | 0.00% | 10.76 | 20.69 | 12.23 s | good |
| 03_black_on_dark_wood | 0.9996 | 1.000 | 0.089 | 0.03% | 0.02% | 10.14 | 27.06 | 15.26 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.06 | 17.56 s | good |
| 06_mug_handle_gap | 0.9997 | 1.000 | 0.023 | 0.03% | 0.00% | 1.67 | 5.53 | 13.83 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 23.53 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.13 | 16.44 s | good |
| 09_sunglasses_gaps | 0.9743 | 0.786 | 0.139 | 2.31% | 0.27% | 8.61 | 62.17 | 20.21 s | good |
| 10_comb_narrow_teeth | 0.9020 | 0.903 | 0.105 | 5.55% | 4.70% | 6.91 | 33.86 | 16.78 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9996 | 1.000 | 0.046 | 0.01% | 0.04% | 3.45 | 10.00 | 14.67 s | good |
| 12_striped_shirt_on_carpet | 0.9977 | 0.919 | 0.102 | 0.12% | 0.11% | 8.61 | 29.97 | 9.22 s | good |
| 13_leather_vest_cropped_lining | 0.7978 | 0.384 | 0.373 | 0.00% | 25.34% | 17.17 | 42.84 | 14.58 s | check: The item fills almost the whole frame |

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

Peak memory of the whole benchmark process: 3731 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 50.1% | 28.5% | 7.0 px | 1 | 13.77 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 7.85 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 73.5% | 59.4% | 8.5 px | 1 | 7.07 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 46.1% | 27.5% | 6.8 px | 1 | 7.66 s | good |
| web_05_1.jpg | 78.2% | 43.8% | 7.6 px | 1 | 7.76 s | check: Some background may be left between parts of the item |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 13.57 s | good |
| web_09_1.jpg | 60.6% | 32.1% | 8.1 px | 1 | 12.84 s | good |
| web_10_0.jpg | 38.3% | 46.5% | 10.2 px | 1 | 6.92 s | good |
| web_10_1.jpg | 36.2% | 34.5% | 7.2 px | 1 | 12.20 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 11.9% | 58.4% | 12.1 px | 1 | 17.37 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 23.3% | 61.1% | 9.7 px | 2 | 13.75 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.7% | 41.4% | 9.7 px | 1 | 12.27 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 50.0% | 8.9 px | 1 | 7.43 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 38.4% | 39.3% | 9.1 px | 1 | 18.20 s | good |
| web_14_1.jpg | 17.6% | 37.9% | 6.5 px | 4 | 13.89 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 12.34 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.9% | 36.6% | 9.0 px | 1 | 15.23 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 0.3% | 42.9% | 4.8 px | 4 | 14.03 s | check: Item and background are similar in colour, so edges may be soft |
| web_16_1.jpg | 17.9% | 45.6% | 9.9 px | 1 | 9.79 s | check: Item and background are similar in colour, so edges may be soft |
| web_19_0.jpg | 26.9% | 34.7% | 6.8 px | 1 | 9.68 s | good |
| web_19_1.jpg | 22.0% | 58.4% | 10.3 px | 3 | 9.63 s | good |
| web_20_0.jpg | 16.3% | 51.5% | 10.2 px | 1 | 11.83 s | good |
| web_20_1.jpg | 59.3% | 33.0% | 6.7 px | 1 | 5.91 s | good |
| web_21_0.jpg | 42.8% | 60.6% | 13.6 px | 1 | 6.78 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 87.2% | 37.1% | 19.5 px | 1 | 5.60 s | good |
| web_22_0.jpg | 42.7% | 22.7% | 5.6 px | 1 | 6.52 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 6.48 s | good |
| web_23_0.jpg | 66.6% | 65.7% | 15.4 px | 2 | 10.33 s | good |
| web_23_1.jpg | 47.3% | 53.4% | 14.2 px | 1 | 15.64 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.3% | 41.5% | 8.6 px | 1 | 12.56 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.9% | 37.6% | 8.3 px | 1 | 17.21 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.0% | 23.5% | 5.1 px | 1 | 14.18 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.5% | 23.8% | 5.4 px | 1 | 12.41 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.8% | 50.7% | 11.7 px | 1 | 12.58 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 7.07 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 39.7% | 22.0% | 4.6 px | 1 | 7.38 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 32.3% | 42.5% | 9.4 px | 1 | 13.14 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.7% | 42.0% | 8.9 px | 1 | 13.99 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.5% | 3.6 px | 1 | 13.11 s | good |
| web_31_0.jpg | 83.1% | 49.8% | 14.5 px | 1 | 14.24 s | good |
| web_31_1.jpg | 21.8% | 41.5% | 8.6 px | 1 | 8.06 s | good |
| web_33_0.jpg | 8.1% | 37.2% | 8.4 px | 1 | 19.30 s | good |
| web_33_1.jpg | 32.9% | 27.9% | 6.0 px | 1 | 8.61 s | good |
| web_35_0.jpg | 26.6% | 13.0% | 2.7 px | 1 | 14.94 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.5% | 40.8% | 9.2 px | 1 | 20.73 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 39.1% | 55.6% | 6.4 px | 3 | 8.72 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 20.28 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 18.9% | 51.0% | 13.3 px | 1 | 8.23 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 44.4% | 29.4% | 6.7 px | 1 | 8.76 s | check: Item and background are similar in colour, so edges may be soft |
| web_39_0.jpg | 44.4% | 39.8% | 8.2 px | 3 | 13.79 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 7.85 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.4% | 6.8 px | 5 | 9.07 s | good |
| web_40_1.jpg | 4.5% | 26.8% | 5.6 px | 1 | 20.30 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 35.9% | 38.3% | 6.3 px | 2 | 7.22 s | good |
| web_43_0.jpg | 43.4% | 24.0% | 5.2 px | 1 | 7.79 s | good |
| web_43_1.jpg | 49.7% | 42.6% | 8.3 px | 1 | 8.56 s | good |
| web_44_0.jpg | 42.4% | 42.2% | 5.6 px | 5 | 12.69 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.6% | 33.3% | 6.7 px | 1 | 12.06 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.1% | 8.2 px | 2 | 8.20 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 34.4% | 46.1% | 8.2 px | 1 | 15.93 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 6.88 s | good |
| web_46_1.jpg | 45.5% | 35.1% | 6.4 px | 2 | 12.41 s | check: Some background may be left between parts of the item |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 14.24 s | good |
| web_48_1.jpg | 31.9% | 30.7% | 6.5 px | 1 | 10.23 s | good |
| web_49_0.jpg | 18.9% | 38.5% | 7.6 px | 2 | 16.62 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.4% | 42.7% | 8.8 px | 1 | 11.28 s | good |
| web_50_0.jpg | 2.9% | 20.8% | 4.4 px | 1 | 16.68 s | good |
| web_50_1.jpg | 32.9% | 30.1% | 7.6 px | 4 | 10.49 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.3% | 35.5% | 7.7 px | 1 | 11.31 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.9% | 48.3% | 9.9 px | 1 | 10.54 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 9.9% | 46.2% | 8.0 px | 1 | 15.33 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_0.jpg | 46.2% | 56.3% | 11.8 px | 1 | 13.48 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 15.0% | 50.3% | 10.0 px | 1 | 10.19 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 11.4% | 2.4 px | 1 | 11.56 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 16.04 s | good |
| web_58_0.jpg | 64.9% | 61.3% | 12.6 px | 1 | 16.34 s | good |
| web_60_0.jpg | 13.2% | 40.1% | 8.5 px | 1 | 17.93 s | check: Item and background are similar in colour, so edges may be soft |
| web_60_1.jpg | 19.2% | 37.6% | 7.5 px | 1 | 11.18 s | good |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9020 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.903 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.91 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
