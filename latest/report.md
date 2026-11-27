# Cutout quality report

Cutout network: BiRefNet Lite 1024 (Core ML, CPU), loaded in 8.4 s.

Network probe on 01_navy_shirt_on_white: raw output -23.969 to 22.359, mean -4.666; item area 25.6%; one pass 3.09 s.

Generated 2026-11-27T18:33:48Z. Lower is better for errors; higher for IoU and boundary F.


## Full-resolution export check

11_red_shirt_24mp: 5712 x 4284 in, 5712 x 4284 out (same size), cutout 13.43 s, compositing and JPEG 4.34 s, JPEG 4.3 MB, peak memory so far 7254 MB.
## Shipping method by scene

| Scene | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% | Gradient | Connectivity | Time | Confidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 01_navy_shirt_on_white | 0.9992 | 1.000 | 0.063 | 0.00% | 0.08% | 4.04 | 8.85 | 0.95 | 5.06 | 11.16 s | good |
| 02_white_on_white | 0.9976 | 0.997 | 0.170 | 0.24% | 0.00% | 10.47 | 21.08 | 2.05 | 8.50 | 8.83 s | good |
| 03_black_on_dark_wood | 0.9996 | 1.000 | 0.089 | 0.03% | 0.02% | 10.14 | 27.06 | 0.71 | 3.22 | 10.41 s | check: Item and background are similar in colour, so edges may be soft |
| 04_watch_thin_straps | 0.9985 | 1.000 | 0.017 | 0.00% | 0.15% | 2.37 | 7.05 | 0.10 | 0.39 | 8.65 s | good |
| 06_mug_handle_gap | 0.9997 | 1.000 | 0.023 | 0.03% | 0.00% | 1.66 | 5.53 | 0.12 | 0.29 | 5.44 s | good |
| 07_reflective_bottle | 0.9956 | 0.975 | 0.107 | 0.04% | 0.40% | 5.62 | 17.14 | 1.45 | 4.55 | 7.45 s | good |
| 08_fuzzy_knit_edge | 0.9985 | 0.998 | 0.047 | 0.12% | 0.02% | 3.56 | 13.14 | 0.29 | 1.26 | 5.80 s | good |
| 09_sunglasses_gaps | 0.9744 | 0.786 | 0.138 | 2.31% | 0.26% | 8.67 | 62.17 | 4.16 | 9.03 | 10.91 s | good |
| 10_comb_narrow_teeth | 0.9129 | 0.916 | 0.101 | 4.47% | 4.65% | 6.62 | 32.64 | 7.45 | 51.53 | 8.45 s | check: Some background may be left between parts of the item |
| 11_red_shirt_24mp | 0.9994 | 1.000 | 0.083 | 0.00% | 0.06% | 4.82 | 10.02 | 1.67 | 11.87 | 11.91 s | good |
| 12_striped_shirt_on_carpet | 0.9976 | 0.919 | 0.103 | 0.12% | 0.11% | 8.62 | 30.21 | 6.40 | 23.43 | 6.15 s | good |
| 13_leather_vest_cropped_lining | 0.7945 | 0.335 | 0.390 | 0.00% | 25.87% | 17.88 | 42.92 | 14.15 | 2382.77 | 8.32 s | check: The item fills almost the whole frame |
| R_columbia_anorak_arms_out_concrete | 0.9890 | 0.604 | 0.227 | 0.05% | 1.06% | 13.32 | 41.97 | 12.64 | 32.06 | 10.25 s | good |
| R_columbia_anorak_front_concrete | 0.9871 | 0.709 | 0.199 | 0.63% | 0.67% | 12.67 | 42.95 | 11.86 | 40.01 | 7.52 s | good |
| R_columbia_cuff_closeup_tape | 0.9326 | 0.353 | 0.303 | 5.06% | 1.80% | 15.12 | 43.16 | 20.05 | 212.38 | 8.91 s | good |
| R_columbia_hem_closeup_tape | 0.9980 | 0.837 | 0.162 | 0.06% | 0.14% | 9.05 | 29.49 | 6.36 | 51.63 | 8.00 s | good |
| R_columbia_side_closeup_tape | 0.4697 | 0.262 | 0.246 | 52.97% | 0.13% | 12.94 | 45.85 | 19.14 | 2187.01 | 7.96 s | good |
| R_michigan_cuff_tape | 0.9927 | 0.779 | 0.143 | 0.48% | 0.25% | 10.15 | 27.33 | 5.44 | 24.29 | 10.77 s | good |
| R_michigan_front_closeup_tape | 0.9949 | 0.693 | 0.147 | 0.09% | 0.42% | 12.13 | 44.22 | 8.37 | 32.22 | 8.91 s | good |
| R_michigan_jacket_back_concrete | 0.9918 | 0.578 | 0.162 | 0.35% | 0.47% | 12.02 | 44.28 | 11.75 | 29.76 | 7.42 s | good |
| R_michigan_jacket_front_open_collar | 0.9938 | 0.663 | 0.148 | 0.04% | 0.58% | 11.97 | 45.60 | 9.79 | 23.61 | 9.56 s | good |
| R_michigan_sleeve_stripes_tape | 0.2982 | 0.609 | 0.252 | 70.16% | 0.05% | 13.45 | 47.74 | 9.66 | 3558.90 | 10.03 s | check: Item and background are similar in colour, so edges may be soft |
| R_michigan_underarm_closeup | 0.3465 | 0.701 | 0.107 | 65.33% | 0.07% | 7.92 | 29.00 | 6.26 | 2568.13 | 10.66 s | check: Item and background are similar in colour, so edges may be soft |

## Methods compared (mean over scenes)

| Method | IoU | Boundary F | Edge alpha error | Missed item | Kept background | Edge ΔE | Edge ΔE 95% |
|---|---|---|---|---|---|---|---|
| Apple model only | 0.9270 | 0.615 | 0.235 | 5.35% | 2.52% | 14.38 | 36.67 |
| previous app | 0.9432 | 0.764 | 0.156 | 5.11% | 0.59% | 9.10 | 29.91 |
| BiRefNet only | 0.8452 | 0.668 | 0.197 | 7.89% | 771.13% | 10.68 | 32.33 |
| edges: tight levels | 0.8983 | 0.770 | 0.137 | 8.81% | 1.62% | 8.27 | 31.61 |
| edges: radius 3 | 0.8978 | 0.775 | 0.143 | 8.82% | 1.67% | 9.01 | 31.11 |
| edges: radius 3, tight levels | 0.8978 | 0.775 | 0.132 | 8.82% | 1.67% | 7.94 | 31.34 |
| edges: radius 8, finer eps | 0.8987 | 0.762 | 0.149 | 8.83% | 1.56% | 9.21 | 31.27 |
| new | 0.8983 | 0.770 | 0.149 | 8.81% | 1.62% | 9.36 | 31.28 |

**No cutout produced** (Apple's model found no subject; the app keeps these as originals and flags them): 05_fine_chain_on_marble, 14_shirt_closeup_fills_frame, 15_shirt_cut_off_by_frame, 16_vest_closeup_corners. Not included in the means above.

Peak memory of the whole benchmark process: 7254 MB.

## Real photos (no reference mask)

| Photo | Item area | Soft edge share | Edge width | Pieces | Time | Confidence |
|---|---|---|---|---|---|---|
| web_03_0.jpg | 50.1% | 28.9% | 8.8 px | 1 | 6.92 s | check: Item and background are similar in colour, so edges may be soft |
| web_03_1.jpg | 54.6% | 53.6% | 11.7 px | 1 | 4.19 s | good |
| web_04_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_04_1.jpg | 73.3% | 59.2% | 8.4 px | 1 | 3.21 s | check: Item and background are similar in colour, so edges may be soft |
| web_05_0.jpg | 46.1% | 27.6% | 6.8 px | 1 | 3.77 s | good |
| web_05_1.jpg | 78.2% | 43.8% | 7.6 px | 1 | 4.28 s | check: Some background may be left between parts of the item |
| web_09_0.jpg | 59.9% | 32.7% | 6.9 px | 1 | 6.05 s | good |
| web_09_1.jpg | 60.6% | 32.2% | 11.9 px | 1 | 5.87 s | good |
| web_10_0.jpg | 38.3% | 46.5% | 10.2 px | 1 | 3.75 s | good |
| web_10_1.jpg | 36.2% | 34.5% | 7.2 px | 1 | 6.35 s | check: Some background may be left between parts of the item |
| web_11_0.jpg | 11.9% | 58.3% | 12.0 px | 1 | 10.69 s | check: Item and background are similar in colour, so edges may be soft |
| web_11_1.jpg | 23.3% | 61.0% | 9.7 px | 2 | 9.33 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_0.jpg | 58.7% | 41.4% | 9.7 px | 1 | 5.71 s | check: Item and background are similar in colour, so edges may be soft |
| web_12_1.jpg | 65.6% | 49.9% | 8.9 px | 1 | 3.66 s | check: Some background may be left between parts of the item |
| web_14_0.jpg | 38.4% | 39.3% | 9.0 px | 1 | 8.29 s | good |
| web_14_1.jpg | 17.6% | 37.9% | 6.5 px | 4 | 6.54 s | check: Some background may be left between parts of the item |
| web_15_0.jpg | 72.1% | 38.7% | 6.4 px | 1 | 5.87 s | check: Some background may be left between parts of the item |
| web_15_1.jpg | 8.9% | 36.6% | 9.0 px | 1 | 8.48 s | check: Some background may be left between parts of the item |
| web_16_0.jpg | 0.3% | 43.0% | 4.8 px | 4 | 7.84 s | check: Item and background are similar in colour, so edges may be soft |
| web_16_1.jpg | 17.9% | 45.6% | 9.9 px | 1 | 6.18 s | check: Item and background are similar in colour, so edges may be soft |
| web_19_0.jpg | 26.9% | 34.8% | 6.8 px | 1 | 7.73 s | good |
| web_19_1.jpg | 22.0% | 58.5% | 10.4 px | 3 | 6.58 s | good |
| web_20_0.jpg | 16.3% | 51.6% | 10.2 px | 1 | 7.14 s | good |
| web_20_1.jpg | 59.3% | 34.2% | 7.2 px | 1 | 3.30 s | good |
| web_21_0.jpg | 42.4% | 61.0% | 12.9 px | 1 | 3.96 s | check: Item and background are similar in colour, so edges may be soft |
| web_21_1.jpg | 86.8% | 45.6% | 19.1 px | 1 | 3.53 s | good |
| web_22_0.jpg | 42.7% | 22.7% | 5.7 px | 1 | 3.11 s | good |
| web_22_1.jpg | 38.4% | 15.8% | 4.2 px | 1 | 3.46 s | good |
| web_23_0.jpg | 66.2% | 66.7% | 16.4 px | 2 | 5.66 s | good |
| web_23_1.jpg | 31.0% | 48.6% | 10.8 px | 1 | 8.01 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_0.jpg | 26.2% | 41.4% | 8.5 px | 1 | 5.91 s | check: Item and background are similar in colour, so edges may be soft |
| web_24_1.jpg | 10.9% | 37.7% | 8.2 px | 1 | 7.18 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_0.jpg | 18.0% | 23.5% | 5.1 px | 1 | 6.77 s | check: Item and background are similar in colour, so edges may be soft |
| web_25_1.jpg | 18.5% | 23.9% | 5.4 px | 1 | 5.80 s | check: Item and background are similar in colour, so edges may be soft |
| web_27_0.jpg | 72.8% | 49.6% | 10.4 px | 1 | 4.90 s | check: Some background may be left between parts of the item |
| web_27_1.jpg | 17.7% | 37.4% | 8.1 px | 1 | 3.64 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_0.jpg | 39.7% | 21.6% | 4.5 px | 1 | 2.74 s | check: Item and background are similar in colour, so edges may be soft |
| web_28_1.jpg | 32.3% | 42.5% | 9.4 px | 1 | 5.04 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_0.jpg | 27.7% | 41.8% | 8.9 px | 1 | 5.34 s | check: Item and background are similar in colour, so edges may be soft |
| web_30_1.jpg | 28.1% | 15.5% | 3.6 px | 1 | 5.41 s | good |
| web_31_0.jpg | 83.1% | 51.7% | 17.1 px | 1 | 4.22 s | good |
| web_31_1.jpg | 21.8% | 41.5% | 8.6 px | 1 | 2.59 s | good |
| web_33_0.jpg | 7.6% | 40.1% | 8.9 px | 2 | 5.74 s | good |
| web_33_1.jpg | 32.9% | 27.8% | 6.0 px | 1 | 2.52 s | good |
| web_35_0.jpg | 26.6% | 13.0% | 2.7 px | 1 | 4.44 s | check: Item and background are similar in colour, so edges may be soft |
| web_35_1.jpg | 10.5% | 40.8% | 9.1 px | 1 | 6.15 s | check: Some background may be left between parts of the item |
| web_37_0.jpg | 39.0% | 55.7% | 6.5 px | 3 | 3.36 s | check: Some background may be left between parts of the item |
| web_37_1.jpg | 17.2% | 41.5% | 8.2 px | 1 | 8.51 s | check: Some background may be left between parts of the item |
| web_38_0.jpg | 28.3% | 38.4% | 8.5 px | 1 | 5.58 s | check: Item and background are similar in colour, so edges may be soft |
| web_38_1.jpg | 44.4% | 29.3% | 6.7 px | 1 | 3.77 s | check: Item and background are similar in colour, so edges may be soft |
| web_39_0.jpg | 44.3% | 40.1% | 8.4 px | 3 | 5.44 s | check: Some background may be left between parts of the item |
| web_39_1.jpg | 32.3% | 31.1% | 6.5 px | 3 | 3.60 s | check: Item and background are similar in colour, so edges may be soft |
| web_40_0.jpg | 22.6% | 50.4% | 6.8 px | 5 | 4.57 s | good |
| web_40_1.jpg | 4.5% | 26.9% | 5.5 px | 1 | 8.78 s | good |
| web_41_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_42_0.jpg | 35.9% | 38.3% | 6.3 px | 2 | 3.08 s | good |
| web_43_0.jpg | 43.4% | 24.0% | 5.2 px | 1 | 3.01 s | good |
| web_43_1.jpg | 49.7% | 42.6% | 8.3 px | 1 | 3.22 s | good |
| web_44_0.jpg | 42.4% | 41.4% | 5.6 px | 5 | 5.54 s | check: Some background may be left between parts of the item |
| web_44_1.jpg | 36.7% | 33.3% | 6.7 px | 1 | 5.03 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_0.jpg | 21.9% | 33.2% | 8.2 px | 2 | 2.92 s | check: Item and background are similar in colour, so edges may be soft |
| web_45_1.jpg | 34.4% | 46.1% | 8.2 px | 1 | 7.01 s | check: Some background may be left between parts of the item |
| web_46_0.jpg | 29.6% | 20.4% | 5.1 px | 1 | 3.47 s | good |
| web_46_1.jpg | 45.6% | 35.1% | 6.4 px | 2 | 5.22 s | check: Some background may be left between parts of the item |
| web_47_0.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_47_1.jpg | none | | | | | Nothing to remove, the item fills the photo |
| web_48_0.jpg | 11.0% | 18.2% | 3.8 px | 1 | 7.17 s | good |
| web_48_1.jpg | 31.9% | 30.7% | 6.5 px | 1 | 5.11 s | good |
| web_49_0.jpg | 18.7% | 39.2% | 7.4 px | 2 | 7.34 s | check: Some background may be left between parts of the item |
| web_49_1.jpg | 27.4% | 42.9% | 8.8 px | 1 | 6.68 s | good |
| web_50_0.jpg | 2.9% | 20.8% | 4.4 px | 1 | 7.83 s | good |
| web_50_1.jpg | 32.9% | 30.3% | 8.0 px | 4 | 5.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_51_0.jpg | 29.3% | 35.5% | 7.7 px | 1 | 4.42 s | check: Some background may be left between parts of the item |
| web_52_0.jpg | 68.9% | 48.4% | 9.9 px | 1 | 5.67 s | check: Item and background are similar in colour, so edges may be soft |
| web_52_1.jpg | 9.9% | 46.2% | 8.0 px | 1 | 6.77 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_0.jpg | 46.2% | 56.3% | 11.9 px | 1 | 5.00 s | check: Item and background are similar in colour, so edges may be soft |
| web_53_1.jpg | 15.0% | 50.4% | 10.0 px | 1 | 5.55 s | check: Item and background are similar in colour, so edges may be soft |
| web_54_0.jpg | 33.2% | 11.4% | 2.4 px | 1 | 5.90 s | good |
| web_54_1.jpg | 44.0% | 37.9% | 8.0 px | 1 | 6.00 s | good |
| web_58_0.jpg | 59.0% | 60.3% | 12.6 px | 1 | 6.42 s | good |
| web_60_0.jpg | 13.2% | 40.0% | 8.5 px | 1 | 7.49 s | check: Item and background are similar in colour, so edges may be soft |
| web_60_1.jpg | 19.2% | 37.6% | 7.5 px | 1 | 5.32 s | good |

**Regression check: FAILED**

- 10_comb_narrow_teeth: IoU 0.9129 < 0.9871
- 10_comb_narrow_teeth: boundary F 0.916 < 1.000
- 10_comb_narrow_teeth: edge ΔE 6.62 > 2.92
- 10_comb_narrow_teeth: missed item rose
- 10_comb_narrow_teeth: kept background rose
