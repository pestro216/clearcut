"""Scenes modelled on real photos (6 Nov 2026 test batch).

Garments shot flat on a light grey streaky carpet, often filling the frame or cut off by it:
  12 striped cotton shirt, whole, on carpet          (grey fringe seen around the edges)
  13 leather vest with plaid lining, cropped         (parts of the vest removed)
  14 shirt close-up filling the frame, tape measure  (Apple's model found no item)
  15 shirt hem cut off by the frame                  (item touching the frame edge)
  16 vest close-up, carpet only in the corners       (detail shot)

The carpet is modelled on his: light grey, streaked along one direction, with darker flecks.
Same output format as make_testset.py.

  python3 QA/real_scenes.py OUTDIR
"""
import os, sys, math
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from make_testset import mask_from_drawing, photograph, save_case  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
BACKDROPS = os.path.join(ROOT, "Clearcut", "Backdrops")


def surface(name, W, H, metres_across=0.6, tintrgb=None):
    """A library surface, cropped and scaled so the frame shows `metres_across` of it (library images are 1 m)."""
    im = Image.open(os.path.join(BACKDROPS, name)).convert("RGB")
    side = int(im.width * metres_across)
    side_h = int(side * H / W)
    im = im.crop((0, 0, side, min(im.height, side_h))).resize((W, H), Image.LANCZOS)
    a = np.asarray(im, dtype=np.float32) / 255.0
    if tintrgb is not None:
        lum = a.mean(axis=2, keepdims=True)
        a = np.clip(np.array(tintrgb, np.float32)[None, None] * lum / max(1e-3, lum.mean()), 0, 1)
    return a


def fbm(H, W, seed, scales=(64, 16, 4), weights=(0.6, 0.3, 0.1)):
    rng = np.random.default_rng(seed)
    out = np.zeros((H, W), np.float32)
    for s, wgt in zip(scales, weights):
        small = rng.standard_normal((max(2, H // s + 2), max(2, W // s + 2))).astype(np.float32)
        up = np.asarray(Image.fromarray(small).resize((W, H), Image.BICUBIC))
        out += wgt * up
    return out / max(1e-6, out.std())


def carpet(W, H, seed):
    """Light grey streaky carpet: fibre streaks along x, pile texture, darker flecks, gentle light falloff."""
    rng = np.random.default_rng(seed + 100)
    L = max(W, H)
    base = 0.60
    streak = ndimage.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), (0.0006 * L, 0.012 * L))
    streak /= max(1e-6, streak.std())
    pile = ndimage.gaussian_filter(rng.standard_normal((H, W)).astype(np.float32), 0.0008 * L)
    pile /= max(1e-6, pile.std())
    dots = (rng.random((H, W)) > 0.985).astype(np.float32)
    fleck = np.clip(ndimage.gaussian_filter(ndimage.uniform_filter1d(dots, max(2, int(0.004 * L)), axis=1), 0.7) * 3, 0, 1)
    fall = 1 - 0.10 * fbm(H, W, seed + 7, (900, 400), (0.7, 0.3)) * 0.5
    lum = base * fall * (1 + 0.07 * streak + 0.06 * pile) * (1 - 0.35 * fleck)
    tint = np.array([0.99, 1.0, 1.01], np.float32)
    return np.clip(lum[..., None] * tint[None, None], 0, 1)


def stripes(W, H, seed, vertical=True):
    """Purple and pink striped cotton: uneven stripes, weave, slubs and creases."""
    rng = np.random.default_rng(seed)
    pal = np.array([[0.86, 0.45, 0.70], [0.93, 0.70, 0.86], [0.55, 0.28, 0.62], [0.42, 0.40, 0.75],
                    [0.80, 0.55, 0.82], [0.38, 0.18, 0.45], [0.95, 0.80, 0.92]], np.float32)
    n = W if vertical else H
    idx = np.zeros(n, np.int32)
    pos = 0
    while pos < n:
        wdt = int(rng.uniform(0.012, 0.035) * max(W, H))
        idx[pos:pos + wdt] = rng.integers(0, len(pal))
        pos += wdt
    col = pal[idx]
    img = np.broadcast_to(col[None, :, :], (H, W, 3)).copy() if vertical else np.broadcast_to(col[:, None, :], (H, W, 3)).copy()
    weave = 1 + 0.06 * rng.standard_normal((H, W)).astype(np.float32)
    slub = 1 + 0.05 * ndimage.gaussian_filter1d(rng.standard_normal((H, W)).astype(np.float32), 6, axis=1)
    crease = 1 + 0.10 * fbm(H, W, seed + 1, (180, 60, 20), (0.5, 0.35, 0.15))
    return np.clip(img * (weave * slub * crease)[..., None], 0, 1)


def leather(W, H, seed):
    rng = np.random.default_rng(seed)
    base = np.array([0.36, 0.26, 0.18], np.float32)
    grain = 1 + 0.08 * fbm(H, W, seed, (40, 10, 3), (0.4, 0.4, 0.2))
    mottle = 1 + 0.12 * fbm(H, W, seed + 2, (300, 120), (0.7, 0.3))
    scuff = np.clip(fbm(H, W, seed + 3, (90, 30), (0.6, 0.4)) - 1.6, 0, 1) * 0.6
    img = base[None, None] * (grain * mottle)[..., None] + scuff[..., None] * np.array([0.35, 0.33, 0.30], np.float32)
    img += 0.01 * rng.standard_normal((H, W, 1)).astype(np.float32)
    return np.clip(img, 0, 1)


def plaid(W, H, seed):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    p = max(W, H) * 0.018
    base = np.ones((H, W, 3), np.float32) * np.array([0.86, 0.78, 0.42], np.float32)
    lines = ((np.abs(((xx % p) - p * 0.5)) < p * 0.07) | (np.abs(((yy % p) - p * 0.5)) < p * 0.07)).astype(np.float32)
    fine = ((np.abs((((xx + p * 0.25) % p) - p * 0.5)) < p * 0.03)).astype(np.float32)
    img = base * (1 - 0.65 * lines[..., None]) * (1 - 0.3 * fine[..., None])
    img[..., 2] *= 0.85
    return np.clip(img * (1 + 0.05 * fbm(H, W, seed, (30, 6), (0.6, 0.4)))[..., None], 0, 1)


def ragged(a, seed, amount):
    """Fabric edges are not perfect lines: displace the edge by a few pixels."""
    h, w = a.shape
    n = fbm(h, w, seed, (40, 12, 4), (0.5, 0.35, 0.15))
    d_in = ndimage.distance_transform_edt(a > 0.5)
    d_out = ndimage.distance_transform_edt(a <= 0.5)
    sd = np.where(a > 0.5, d_in, -d_out) + amount * n
    return np.clip(sd + 0.5, 0, 1).astype(np.float32)


def main(out):
    os.makedirs(out, exist_ok=True)

    # 12. Striped shirt laid flat on the timber, whole garment in frame, portrait 12 MP.
    W, H = 3024, 4032
    def shirt(d, s):
        cx = 0.5 * W
        pts = [(cx - 0.16 * W, 0.10 * H), (cx - 0.06 * W, 0.12 * H), (cx + 0.06 * W, 0.12 * H), (cx + 0.16 * W, 0.10 * H),
               (cx + 0.36 * W, 0.20 * H), (cx + 0.42 * W, 0.78 * H), (cx + 0.31 * W, 0.80 * H), (cx + 0.27 * W, 0.40 * H),
               (cx + 0.28 * W, 0.86 * H), (cx - 0.28 * W, 0.86 * H), (cx - 0.27 * W, 0.40 * H), (cx - 0.31 * W, 0.80 * H),
               (cx - 0.42 * W, 0.78 * H), (cx - 0.36 * W, 0.20 * H)]
        d.polygon([(x * s, y * s) for x, y in pts], fill=255)
    a = ragged(mask_from_drawing(W, H, shirt), 12, 2.5)
    fg = stripes(W, H, 12)
    bg = carpet(W, H, 12)
    img, at = photograph(fg, a, bg, 12, lens=1.0, shadow=(0.30, 0.010, 0.003))
    save_case(out, "12_striped_shirt_on_carpet", img, at, fg, {"what": "striped cotton on light grey carpet, like the test batch"})

    # 13. Leather vest, cropped by the top and right of the frame, plaid lining in the armhole and neck.
    W, H = 3024, 4032
    def vest(d, s):
        d.polygon([(x * s, y * s) for x, y in [
            (0.30 * W, -10), (0.70 * W, -10), (0.70 * W, 0.02 * H), (W + 10, 0.02 * H), (W + 10, 0.90 * H),
            (0.10 * W, 0.86 * H), (0.08 * W, 0.30 * H), (0.12 * W, 0.24 * H), (0.22 * W, 0.18 * H), (0.27 * W, 0.08 * H)]], fill=255)
    def lining(d, s):
        # A band of lining showing inside the armhole edge, and a V at the neck.
        d.polygon([(x * s, y * s) for x, y in [
            (0.27 * W, -10), (0.33 * W, -10), (0.30 * W, 0.10 * H), (0.24 * W, 0.20 * H), (0.15 * W, 0.26 * H), (0.12 * W, 0.24 * H),
            (0.22 * W, 0.18 * H), (0.27 * W, 0.08 * H)]], fill=255)
        d.polygon([(x * s, y * s) for x, y in [(0.58 * W, -10), (0.70 * W, -10), (0.66 * W, 0.12 * H), (0.645 * W, 0.12 * H)]], fill=255)
    a = ragged(mask_from_drawing(W, H, vest), 13, 1.5)
    lm = mask_from_drawing(W, H, lining)
    lm = np.minimum(lm, a)
    fg = leather(W, H, 13)
    # pockets: slightly lighter panels with dark stitched borders
    for (x0, y0, x1, y1) in [(0.28, 0.15, 0.40, 0.33), (0.42, 0.15, 0.54, 0.33), (0.14, 0.50, 0.50, 0.80), (0.95, 0.40, 1.02, 0.70)]:
        pm = mask_from_drawing(W, H, lambda d, s: d.rectangle([x0 * W * s, y0 * H * s, x1 * W * s, y1 * H * s], fill=255))
        edge = np.clip(ndimage.gaussian_filter(pm, 2) * (1 - ndimage.gaussian_filter(pm, 2)) * 4, 0, 1)
        fg = fg * (1 + 0.08 * pm[..., None]) * (1 - 0.45 * edge[..., None])
    # zips: gold lines
    zip_ = mask_from_drawing(W, H, lambda d, s: (d.rectangle([0.62 * W * s, 0.0, 0.635 * W * s, 0.86 * H * s], fill=255),
                                                d.rectangle([0.09 * W * s, 0.42 * H * s, 0.62 * W * s, 0.428 * H * s], fill=255)))
    fg = fg * (1 - zip_[..., None]) + zip_[..., None] * np.array([0.72, 0.60, 0.35], np.float32)
    fg = fg * (1 - lm[..., None]) + plaid(W, H, 13) * 0.8 * lm[..., None]
    bg = carpet(W, H, 13)
    img, at = photograph(fg, a, bg, 13, lens=1.0, shadow=(0.30, 0.010, 0.003))
    save_case(out, "13_leather_vest_cropped_lining", img, at, fg,
              {"what": "brown leather on grey carpet, cut off by the frame, grey-yellow plaid lining that belongs to the item"})

    # 14. Close-up: shirt fills most of the frame, grey cloth showing on the right, tape measure across it.
    W, H = 4032, 3024
    def closeup(d, s):
        d.polygon([(x * s, y * s) for x, y in [(-10, -10), (0.74 * W, -10), (0.70 * W, 0.45 * H), (0.76 * W, H + 10), (-10, H + 10)]], fill=255)
    def tape(d, s):
        d.polygon([(x * s, y * s) for x, y in [(0.08 * W, 0.62 * H), (0.92 * W, 0.50 * H), (0.925 * W, 0.555 * H), (0.085 * W, 0.675 * H)]], fill=255)
    sm = ragged(mask_from_drawing(W, H, closeup), 14, 2.5)
    tm = mask_from_drawing(W, H, tape)
    a = np.maximum(sm, tm)
    fg = stripes(W, H, 14, vertical=False)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    along = (xx - 0.08 * W) / (0.84 * W)
    ticks = ((np.abs((along * 60) % 1 - 0.5) < 0.04)).astype(np.float32)
    tape_c = np.ones((H, W, 3), np.float32) * np.array([0.88, 0.70, 0.30], np.float32) * (1 - 0.7 * ticks[..., None])
    fg = fg * (1 - tm[..., None]) + tape_c * tm[..., None]
    bg = carpet(W, H, 14)
    img, at = photograph(fg, a, bg, 14, lens=1.0, shadow=(0.25, 0.008, 0.002))
    save_case(out, "14_shirt_closeup_fills_frame", img, at, fg, {"what": "item fills the frame and touches three edges"})

    # 15. Shirt hem and sleeve cut off by the bottom and left of the frame on timber.
    W, H = 4032, 3024
    def hem(d, s):
        d.polygon([(x * s, y * s) for x, y in [(-10, 0.15 * H), (0.55 * W, 0.10 * H), (0.62 * W, 0.70 * H), (0.80 * W, 0.78 * H),
                                                (0.82 * W, H + 10), (-10, H + 10)]], fill=255)
    a = ragged(mask_from_drawing(W, H, hem), 15, 2.5)
    fg = stripes(W, H, 15)
    bg = carpet(W, H, 15)
    img, at = photograph(fg, a, bg, 15, lens=1.0, shadow=(0.30, 0.010, 0.003))
    save_case(out, "15_shirt_cut_off_by_frame", img, at, fg, {"what": "garment running off two edges of the frame"})

    # 16. Vest close-up: leather and pockets fill the frame, carpet only in two corners, lining at the neck.
    W, H = 3024, 4032
    def vest_close(d, s):
        d.polygon([(x * s, y * s) for x, y in [(0.10 * W, -10), (W + 10, -10), (W + 10, H + 10), (-10, H + 10), (-10, 0.30 * H),
                                                (0.04 * W, 0.18 * H)]], fill=255)
    def neck(d, s):
        d.polygon([(x * s, y * s) for x, y in [(0.10 * W, -10), (0.30 * W, -10), (0.16 * W, 0.20 * H), (0.04 * W, 0.18 * H)]], fill=255)
    a = ragged(mask_from_drawing(W, H, vest_close), 16, 1.5)
    lm = np.minimum(mask_from_drawing(W, H, neck), a)
    fg = leather(W, H, 16)
    for (x0, y0, x1, y1) in [(0.35, 0.20, 0.62, 0.50), (0.66, 0.20, 0.93, 0.50), (0.30, 0.60, 0.80, 0.95)]:
        pm = mask_from_drawing(W, H, lambda d, s: d.rectangle([x0 * W * s, y0 * H * s, x1 * W * s, y1 * H * s], fill=255))
        edge = np.clip(ndimage.gaussian_filter(pm, 3) * (1 - ndimage.gaussian_filter(pm, 3)) * 4, 0, 1)
        fg = fg * (1 + 0.10 * pm[..., None]) * (1 - 0.45 * edge[..., None])
    fg = fg * (1 - lm[..., None]) + plaid(W, H, 16) * 0.8 * lm[..., None]
    bg = carpet(W, H, 16)
    img, at = photograph(fg, a, bg, 16, lens=1.0, shadow=(0.30, 0.010, 0.003))
    save_case(out, "16_vest_closeup_corners", img, at, fg, {"what": "detail shot: leather fills the frame, carpet in the corners"})


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "QA/testset")
