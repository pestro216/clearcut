"""Builds reference cutouts from cutouts flattened onto white (e.g. Photoroom exports) and the
original photos they were made from.

  python3 tools/photoroom_reference.py CUTOUTS_DIR ORIGINALS_DIR OUT_DIR

For each white-background cutout:
1. Find its original among ORIGINALS_DIR: SIFT keypoints on the item, matched to each original,
   a similarity transform (scale, rotation, shift) fitted with RANSAC; the original with the most
   consistent matches wins (at least 40). The cutout app usually re-frames the item, so the two
   are not pixel-aligned until this step.
2. Warp the original into the cutout's frame and match its colours to the cutout (a per-channel
   linear fit on solid item pixels), since the app may adjust exposure.
3. Solve transparency per pixel against white: cutout = a * item + (1 - a) * white, so
   a = (white - cutout) . (white - item) / |white - item|^2. Where the item itself is near white
   the equation can't separate item from background; those pixels are counted as unknown.
4. Warp the transparency back onto the original photo's own frame.

Writes, per pair, OUT_DIR/<original name>/ with photo.jpg (upright, no EXIF), alpha.png, fg.png,
meta.json (pairing, match count, unknown share) and check.jpg (the reference over magenta, to
inspect by eye). Screenshots of a photo (black bars above and below) are cropped to the photo.
Needs numpy, Pillow, OpenCV, and pillow-heif for HEIC.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageOps

try:
    import pillow_heif
    pillow_heif.register_heif_opener()
except ImportError:
    pass

MAX_SIDE = 3024


def load(path):
    """Upright RGB as float32 0..1; screenshots are cropped to the photo between black bars."""
    im = np.asarray(ImageOps.exif_transpose(Image.open(path)).convert("RGB"), np.float32) / 255
    rows = np.where(im.mean(axis=(1, 2)) > 0.04)[0]
    if len(rows) and (rows[0] > 20 or rows[-1] < im.shape[0] - 20):
        # Trim status and home bars too: keep the longest run of non-black rows.
        runs, start = [], rows[0]
        for a, b in zip(rows, rows[1:]):
            if b != a + 1:
                runs.append((start, a)); start = b
        runs.append((start, rows[-1]))
        s, e = max(runs, key=lambda r: r[1] - r[0])
        im = im[s:e + 1]
    return im


def grey(im, side):
    k = side / max(im.shape[:2])
    small = cv2.resize(im, (round(im.shape[1] * k), round(im.shape[0] * k)), interpolation=cv2.INTER_AREA)
    return (cv2.cvtColor(small, cv2.COLOR_RGB2GRAY) * 255).astype(np.uint8), k


def item_mask_on_white(im):
    return (np.abs(1 - im).max(axis=2) > 0.06).astype(np.uint8)


def main(cut_dir, orig_dir, out_dir):
    sift = cv2.SIFT_create(nfeatures=4000)
    matcher = cv2.BFMatcher(cv2.NORM_L2)
    originals = {}
    for f in sorted(os.listdir(orig_dir)):
        if f.startswith("."):
            continue
        im = load(os.path.join(orig_dir, f))
        g, k = grey(im, 1400)
        kp, des = sift.detectAndCompute(g, None)
        originals[f] = (im, k, kp, des)
    os.makedirs(out_dir, exist_ok=True)
    summary = []
    for f in sorted(os.listdir(cut_dir)):
        if f.startswith("."):
            continue
        cut = load(os.path.join(cut_dir, f))
        g, kc = grey(cut, 1400)
        mask = cv2.dilate(item_mask_on_white(cv2.resize(cut, (g.shape[1], g.shape[0]))), np.ones((9, 9), np.uint8))
        kp, des = sift.detectAndCompute(g, mask * 255)
        best = None
        for name, (oim, ko, okp, odes) in originals.items():
            if des is None or odes is None or len(okp) < 10:
                continue
            pairs = matcher.knnMatch(des, odes, k=2)
            good = [m for m, n in (p for p in pairs if len(p) == 2) if m.distance < 0.75 * n.distance]
            if len(good) < 12:
                continue
            src = np.float32([okp[m.trainIdx].pt for m in good]) / ko      # original, full-res pixels
            dst = np.float32([kp[m.queryIdx].pt for m in good]) / kc       # cutout, full-res pixels
            M, inl = cv2.estimateAffinePartial2D(src, dst, method=cv2.RANSAC, ransacReprojThreshold=4.0)
            n = int(inl.sum()) if inl is not None else 0
            if M is not None and (best is None or n > best[2]):
                best = (name, M, n)
        if best is None or best[2] < 40:
            print(f"{f}: no original found (best {best[2] if best else 0} matches), skipped")
            summary.append({"cutout": f, "original": None})
            continue
        name, M, n = best
        oim = originals[name][0]
        H, W = cut.shape[:2]
        warped = cv2.warpAffine(oim, M, (W, H), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=(1, 1, 1))
        inside = cv2.warpAffine(np.ones(oim.shape[:2], np.float32), M, (W, H), flags=cv2.INTER_NEAREST) > 0.5
        # Colour match: the cutout app may brighten or warm the photo.
        dist_white = np.abs(1 - cut).max(axis=2)
        solid = (dist_white > 0.25) & inside
        solid = cv2.erode(solid.astype(np.uint8), np.ones((15, 15), np.uint8)).astype(bool)
        F = warped.copy()
        if solid.sum() > 500:
            for c in range(3):
                A = np.stack([warped[..., c][solid], np.ones(solid.sum(), np.float32)], 1)
                coef, *_ = np.linalg.lstsq(A, cut[..., c][solid], rcond=None)
                F[..., c] = np.clip(warped[..., c] * coef[0] + coef[1], 0, 1)
        e = 1 - F
        denom = (e * e).sum(axis=2)
        a = ((1 - cut) * e).sum(axis=2) / np.maximum(denom, 1e-6)
        a = np.clip(a, 0, 1)
        # Where the item is itself near white, the solve is unreliable: fall back to "differs from
        # white at all", and count those pixels as unknown.
        weak = denom < 0.06 ** 2 * 3
        a[weak] = (dist_white[weak] > 0.06).astype(np.float32)
        a[~inside] = (dist_white[~inside] > 0.06).astype(np.float32)
        item_px = max(1, int((a > 0.5).sum()))
        unknown = float((weak & (dist_white > 0.02)).sum()) / item_px
        # Back onto the original's frame.
        Minv = cv2.invertAffineTransform(M)
        ah, aw = oim.shape[:2]
        alpha = cv2.warpAffine(a, Minv, (aw, ah), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT, borderValue=0)
        k = min(1.0, MAX_SIDE / max(aw, ah))
        size = (round(aw * k), round(ah * k))
        photo = cv2.resize(oim, size, interpolation=cv2.INTER_AREA) if k < 1 else oim
        alpha = cv2.resize(alpha, size, interpolation=cv2.INTER_AREA) if k < 1 else alpha
        d = os.path.join(out_dir, os.path.splitext(name)[0] + "_" + os.path.splitext(f)[0])
        os.makedirs(d, exist_ok=True)
        to8 = lambda x: (np.clip(x, 0, 1) * 255 + 0.5).astype(np.uint8)
        Image.fromarray(to8(photo)).save(os.path.join(d, "photo.jpg"), quality=93, subsampling=0)
        Image.fromarray(to8(alpha)).save(os.path.join(d, "alpha.png"))
        Image.fromarray(to8(photo * alpha[..., None])).save(os.path.join(d, "fg.png"))
        check = photo * alpha[..., None] + np.array([1, 0, 1], np.float32) * (1 - alpha[..., None])
        Image.fromarray(to8(check)).resize((size[0] // 3, size[1] // 3)).save(os.path.join(d, "check.jpg"), quality=85)
        scale = float(np.sqrt(abs(np.linalg.det(M[:, :2]))))
        meta = {"what": f"reference from {f} on white, original {name}", "original": name, "cutout": f,
                "matches": n, "scale": round(scale, 3), "unknownShare": round(unknown, 4),
                "size": list(size), "source": "Woolfall stock photo; reference from a white-background cutout"}
        json.dump(meta, open(os.path.join(d, "meta.json"), "w"), indent=1)
        print(f"{f} -> {name}: {n} matches, scale {scale:.3f}, unknown {unknown:.2%}")
        summary.append(meta)
    json.dump(summary, open(os.path.join(out_dir, "summary.json"), "w"), indent=1)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
