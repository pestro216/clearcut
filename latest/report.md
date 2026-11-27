# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 10.6 s.

Network probe on 01_navy_shirt_on_white: raw output -23.828 to 22.625, mean -4.672; item area 25.6%; one pass 7.64 s.

Generated 2026-11-27T12:13:11Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 18.95 s, compositing and JPEG 3.66 s, JPEG 4.3 MB, peak memory so far 5562 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Gradient | Connectivity | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9991 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 0.95 | 5.07 | 19.00 s | good |
| 02_white_on_white | 0.9974 | 0.993 | 0.174 | 0.26% | 0.00% | 10.76 | 20.69 | 2.14 | 8.59 | 14.98 s | good |
| 03_black_on_dark_wood | 0.9996 | 1.000 | 0.089 | 0.03% | 0.02% | 10.14 | 27.06 | 0.71 | 3.23 | 21.09 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.06 | 0.10 | 0.39 | 21.60 s | good |
| 06_mug_handle_gap | 0.9997 | 1.000 | 0.023 | 0.03% | 0.00% | 1.67 | 5.53 | 0.12 | 0.29 | 14.18 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 1.45 | 4.55 | 18.10 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.13 | 0.29 | 1.26 | 13.00 s | good |
| 09_sunglasses_gaps | 0.9743 | 0.786 | 0.139 | 2.31% | 0.27% | 8.61 | 62.17 | 4.17 | 9.09 | 18.74 s | good |
| 10_comb_narrow_teeth | 0.9021 | 0.903 | 0.105 | 5.55% | 4.70% | 6.91 | 33.85 | 8.25 | 58.31 | 20.00 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9996 | 1.000 | 0.046 | 0.01% | 0.04% | 3.45 | 10.00 | 0.94 | 5.12 | 16.78 s | good |
| 12_striped_shirt_on_carpet | 0.9977 | 0.919 | 0.102 | 0.12% | 0.11% | 8.61 | 29.97 | 6.37 | 23.35 | 10.04 s | good |
| 13_leather_vest_cropped_lining | 0.7978 | 0.384 | 0.373 | 0.00% | 25.34% | 17.17 | 42.84 | 13.33 | 2332.20 | 12.35 s | check: The item fills almost the whole frame |
| R_columbia_anorak_arms_out_concrete | 0.9891 | 0.604 | 0.227 | 0.05% | 1.06% | 13.32 | 41.97 | 12.63 | 32.02 | 17.41 s | good |
| R_columbia_anorak_front_concrete | 0.9871 | 0.709 | 0.199 | 0.64% | 0.66% | 12.67 | 42.97 | 11.87 | 40.02 | 13.36 s | good |
| R_columbia_cuff_closeup_tape | 0.9326 | 0.352 | 0.303 | 5.06% | 1.80% | 15.11 | 43.16 | 20.06 | 212.39 | 15.80 s | good |
| R_columbia_hem_closeup_tape | 0.9980 | 0.835 | 0.162 | 0.06% | 0.14% | 9.02 | 29.38 | 6.36 | 51.87 | 12.62 s | good |
| R_columbia_side_closeup_tape | 0.4698 | 0.298 | 0.245 | 52.95% | 0.13% | 12.93 | 45.63 | 18.83 | 2177.36 | 14.53 s | good |
| R_michigan_cuff_tape | 0.9891 | 0.781 | 0.155 | 0.84% | 0.25% | 10.40 | 28.76 | 5.56 | 30.64 | 20.28 s | good |
| R_michigan_front_closeup_tape | 0.9949 | 0.694 | 0.147 | 0.10% | 0.41% | 12.12 | 44.13 | 8.35 | 32.37 | 14.38 s | good |
| R_michigan_jacket_back_concrete | 0.9918 | 0.578 | 0.162 | 0.35% | 0.47% | 12.02 | 44.28 | 11.75 | 29.75 | 12.51 s | good |
| R_michigan_jacket_front_open_collar | 0.9938 | 0.663 | 0.148 | 0.04% | 0.58% | 11.98 | 45.62 | 9.79 | 23.62 | 17.49 s | good |
| R_michigan_sleeve_stripes_tape | 0.3006 | 0.601 | 0.248 | 69.93% | 0.04% | 13.32 | 47.74 | 9.64 | 3546.65 | 17.31 s | check: Item and background are similar in colour, so edges may be soft |
| R_michigan_underarm_closeup | 0.3465 | 0.701 | 0.107 | 65.33% | 0.07% | 7.91 | 28.99 | 6.26 | 2568.13 | 20.78 s | check: Item and background are similar in colour, so edges may be soft |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9270 | 0.615 | 0.235 | 5.35% | 2.52% | 14.38 | 36.67 |
| previous app | 0.9432 | 0.764 | 0.156 | 5.11% | 0.59% | 9.10 | 29.91 |
| BiRefNet only | 0.8455 | 0.672 | 0.197 | 7.88% | 771.09% | 10.65 | 32.27 |
| edges: tight levels | 0.8980 | 0.773 | 0.135 | 8.86% | 1.60% | 8.20 | 31.59 |
| edges: radius 3 | 0.8973 | 0.778 | 0.141 | 8.91% | 1.63% | 8.94 | 31.24 |
| edges: radius 3, tight levels | 0.8973 | 0.778 | 0.131 | 8.91% | 1.63% | 7.90 | 31.37 |
| edges: radius 8, finer eps | 0.8983 | 0.765 | 0.147 | 8.87% | 1.54% | 9.13 | 31.36 |
| new | 0.8980 | 0.773 | 0.147 | 8.86% | 1.60% | 9.29 | 31.34 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 5562 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 50.1% | 28.6% | 8.7 px | 1 | 13.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 7.44 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 73.5% | 59.4% | 8.5 px | 1 | 7.24 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 46.1% | 27.5% | 6.8 px | 1 | 7.30 s | good |
| web_05_1.jpg | 78.2% | 43.8% | 7.6 px | 1 | 8.47 s | check: Some background may be left between parts of the item |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 12.75 s | good |
| web_09_1.jpg | 60.6% | 32.1% | 11.7 px | 1 | 11.93 s | good |
| web_10_0.jpg | 38.3% | 46.5% | 10.2 px | 1 | 7.91 s | good |
| web_10_1.jpg | 36.2% | 34.5% | 7.2 px | 1 | 12.74 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 11.9% | 58.4% | 12.0 px | 1 | 18.28 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 23.3% | 61.1% | 9.7 px | 2 | 15.37 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.7% | 41.4% | 9.7 px | 1 | 14.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 50.0% | 8.9 px | 1 | 6.70 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 38.4% | 39.3% | 9.1 px | 1 | 17.59 s | good |
| web_14_1.jpg | 17.6% | 37.9% | 6.5 px | 4 | 12.76 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 13.22 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.9% | 36.6% | 9.0 px | 1 | 20.14 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 0.3% | 42.9% | 4.8 px | 4 | 20.53 s | check: Item and background are similar in colour, so edges may be soft |
| web_16_1.jpg | 17.9% | 45.6% | 9.9 px | 1 | 14.23 s | check: Item and background are similar in colour, so edges may be soft |
| web_19_0.jpg | 26.9% | 34.8% | 6.8 px | 1 | 12.02 s | good |
| web_19_1.jpg | 22.0% | 58.4% | 10.3 px | 3 | 10.59 s | good |
| web_20_0.jpg | 16.3% | 51.5% | 10.2 px | 1 | 9.85 s | good |
| web_20_1.jpg | 59.2% | 36.4% | 7.5 px | 1 | 5.40 s | good |
| web_21_0.jpg | 42.4% | 61.1% | 13.0 px | 1 | 6.27 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 83.7% | 57.4% | 21.1 px | 1 | 7.46 s | good |
| web_22_0.jpg | 42.7% | 22.7% | 5.6 px | 1 | 8.50 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 7.60 s | good |
| web_23_0.jpg | 66.0% | 66.3% | 16.0 px | 2 | 12.14 s | good |
| web_23_1.jpg | 30.9% | 47.3% | 10.4 px | 1 | 18.04 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.2% | 41.5% | 8.5 px | 1 | 12.94 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.9% | 37.6% | 8.2 px | 1 | 18.80 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.0% | 23.5% | 5.1 px | 1 | 11.80 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.5% | 23.9% | 5.4 px | 1 | 12.01 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.8% | 51.0% | 11.5 px | 1 | 12.07 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 7.04 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 39.7% | 22.0% | 4.6 px | 1 | 6.36 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 32.3% | 42.5% | 9.4 px | 1 | 11.66 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.7% | 41.9% | 9.0 px | 1 | 12.41 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.5% | 3.6 px | 1 | 11.21 s | good |
| web_31_0.jpg | 83.0% | 51.8% | 16.9 px | 1 | 12.14 s | good |
| web_31_1.jpg | 21.8% | 41.5% | 8.6 px | 1 | 7.76 s | good |
| web_33_0.jpg | 8.1% | 37.2% | 8.4 px | 1 | 17.84 s | good |
| web_33_1.jpg | 32.9% | 27.9% | 6.0 px | 1 | 8.34 s | good |
| web_35_0.jpg | 26.6% | 13.0% | 2.7 px | 1 | 13.40 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.5% | 40.8% | 9.2 px | 1 | 21.32 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 39.0% | 55.7% | 6.5 px | 3 | 8.11 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 20.22 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 15.5% | 45.4% | 12.0 px | 1 | 8.59 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 44.4% | 29.4% | 6.7 px | 1 | 8.45 s | check: Item and background are similar in colour, so edges may be soft |
| web_39_0.jpg | 44.4% | 39.8% | 8.3 px | 3 | 16.13 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 8.81 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.4% | 6.8 px | 5 | 8.80 s | good |
| web_40_1.jpg | 4.5% | 26.8% | 5.6 px | 1 | 22.79 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 35.9% | 38.3% | 6.3 px | 2 | 8.57 s | good |
| web_43_0.jpg | 43.4% | 24.0% | 5.2 px | 1 | 8.66 s | good |
| web_43_1.jpg | 49.7% | 42.6% | 8.3 px | 1 | 9.05 s | good |
| web_44_0.jpg | 42.4% | 42.5% | 5.6 px | 5 | 15.34 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.6% | 33.3% | 6.7 px | 1 | 15.83 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.1% | 8.2 px | 2 | 8.45 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 34.4% | 46.1% | 8.2 px | 1 | 15.75 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 9.16 s | good |
| web_46_1.jpg | 45.5% | 35.1% | 6.4 px | 2 | 16.33 s | check: Some background may be left between parts of the item |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 23.73 s | good |
| web_48_1.jpg | 31.9% | 30.7% | 6.5 px | 1 | 15.46 s | good |
| web_49_0.jpg | 18.7% | 39.5% | 7.4 px | 2 | 22.78 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.4% | 42.7% | 8.8 px | 1 | 15.25 s | good |
| web_50_0.jpg | 2.9% | 20.8% | 4.4 px | 1 | 21.16 s | good |
| web_50_1.jpg | 32.9% | 30.3% | 8.0 px | 4 | 14.07 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.3% | 35.5% | 7.7 px | 1 | 14.91 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.9% | 48.3% | 9.9 px | 1 | 13.75 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 9.9% | 46.2% | 8.0 px | 1 | 19.39 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_0.jpg | 46.2% | 56.3% | 11.8 px | 1 | 13.85 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 15.0% | 50.3% | 10.0 px | 1 | 14.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 11.4% | 2.4 px | 1 | 14.21 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 13.80 s | good |
| web_58_0.jpg | 59.0% | 60.2% | 12.5 px | 1 | 15.36 s | good |
| web_60_0.jpg | 13.2% | 40.1% | 8.5 px | 1 | 20.82 s | check: Item and background are similar in colour, so edges may be soft |
| web_60_1.jpg | 19.2% | 37.6% | 7.5 px | 1 | 13.74 s | good |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9021 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.903 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.91 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
