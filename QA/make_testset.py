"""Builds Clearcut's ground-truth test scenes.

Each scene is a product made from a real photographic material (CC0 Poly Haven scans),
lit with simple shading, placed on a real photographic surface with its own contact shadow,
then "photographed": lens softness, sensor noise and JPEG compression, like an iPhone.
Because we build the scene, the exact answer is known:

  photo.jpg   what the camera saw
  alpha.png   the true cutout (partial values at soft edges)
  fg.png      the product's true colours (no background mixed in)

Deterministic: same seed, same scenes. Textures are cached in QA/.texture_cache.

  python3 QA/make_testset.py OUTDIR
"""
import io, json, math, os, sys, urllib.request
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

UA = {"User-Agent": "Clearcut-private-build/1.0 (personal app)"}
CACHE = os.path.join(os.path.dirname(__file__), ".texture_cache")
SS = 3  # supersampling for exact anti-aliased truth


def texture(pid, res="1k"):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{pid}_{res}.jpg")
    if not os.path.exists(path):
        files = json.load(urllib.request.urlopen(urllib.request.Request(f"https://api.polyhaven.com/files/{pid}", headers=UA)))
        url = files["Diffuse"][res]["jpg"]["url"]
        data = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300).read()
        open(path, "wb").write(data)
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def tile(tex, w, h, scale=1.0):
    t = Image.fromarray((tex * 255).astype(np.uint8))
    if scale != 1.0:
        t = t.resize((max(8, int(t.width * scale)), max(8, int(t.height * scale))), Image.LANCZOS)
    tw, th = t.size
    canvas = Image.new("RGB", (w, h))
    for y in range(0, h, th):
        for x in range(0, w, tw):
            canvas.paste(t, (x, y))
    return np.asarray(canvas, dtype=np.float32) / 255.0


def tint(tex, rgb, amount=1.0):
    lum = tex.mean(axis=2, keepdims=True)
    lum = lum / max(1e-3, lum.mean())
    target = np.array(rgb, dtype=np.float32)[None, None, :] * lum
    return np.clip(tex * (1 - amount) + target * amount, 0, 1)


def mask_from_drawing(w, h, draw_fn):
    big = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    draw_fn(d, SS)
    small = big.resize((w, h), Image.BOX)
    return np.asarray(small, dtype=np.float32) / 255.0


def shading(mask, strength=0.35, highlight=None):
    """Rounded look: darker towards the edges, optional soft highlight."""
    inside = mask > 0.5
    d = ndimage.distance_transform_edt(inside)
    d = d / max(1.0, np.percentile(d[inside], 95) if inside.any() else 1.0)
    shade = 1 - strength * (1 - np.clip(d, 0, 1)) ** 2
    if highlight is not None:
        hx, hy, hr, ha = highlight
        yy, xx = np.mgrid[0:mask.shape[0], 0:mask.shape[1]]
        g = np.exp(-(((xx - hx) ** 2 + (yy - hy) ** 2) / (2 * hr * hr)))
        shade = shade + ha * g
    return shade[..., None]


def photograph(fg, alpha, bg, seed, lens=0.7, shadow=(0.38, 0.012, 0.004)):
    """Composite with a contact shadow, then lens blur, noise and JPEG."""
    h, w = alpha.shape
    L = max(w, h)
    rng = np.random.default_rng(seed)
    s_amt, s_blur, s_off = shadow
    sh = ndimage.gaussian_filter(alpha, s_blur * L)
    sh = ndimage.shift(sh, (s_off * L, s_off * L * 0.6), order=1)
    contact = ndimage.gaussian_filter(alpha, 0.0015 * L)
    occl = np.clip(s_amt * sh + 0.35 * contact, 0, 0.85)
    bg_lin = bg ** 2.2 * (1 - occl[..., None])
    fg_lin = fg ** 2.2
    a = alpha[..., None]
    img = fg_lin * a + bg_lin * (1 - a)
    # lens: the same softness applies to what the true edge looks like
    img = np.stack([ndimage.gaussian_filter(img[..., c], lens) for c in range(3)], axis=2)
    alpha_true = np.clip(ndimage.gaussian_filter(alpha, lens), 0, 1)
    img = img ** (1 / 2.2)
    img = img + rng.normal(0, 0.008, img.shape) * (0.6 + 0.4 * img)
    img = np.clip(img, 0, 1)
    return img, alpha_true


def save_case(out, name, img, alpha, fg, meta):
    d = os.path.join(out, name)
    os.makedirs(d, exist_ok=True)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, "photo.jpg"), quality=93, subsampling=0)
    Image.fromarray((alpha * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, "alpha.png"))
    Image.fromarray((np.clip(fg, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(d, "fg.png"))
    json.dump(meta, open(os.path.join(d, "meta.json"), "w"), indent=1)
    print("made", name, img.shape[1], "x", img.shape[0], flush=True)


def shirt(d, s, W, H):
    cx, top = W * 0.5, H * 0.18
    pts = [(cx - 0.12 * W, top), (cx - 0.05 * W, top + 0.03 * H), (cx + 0.05 * W, top + 0.03 * H), (cx + 0.12 * W, top),
           (cx + 0.30 * W, top + 0.10 * H), (cx + 0.25 * W, top + 0.24 * H), (cx + 0.17 * W, top + 0.19 * H),
           (cx + 0.18 * W, top + 0.66 * H), (cx - 0.18 * W, top + 0.66 * H), (cx - 0.17 * W, top + 0.19 * H),
           (cx - 0.25 * W, top + 0.24 * H), (cx - 0.30 * W, top + 0.10 * H)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=255)
    d.ellipse([(cx - 0.05 * W) * s, (top - 0.01 * H) * s, (cx + 0.05 * W) * s, (top + 0.05 * H) * s], fill=0)


def main(out):
    os.makedirs(out, exist_ok=True)
    cases = []

    # 1. Dark navy shirt on white plaster: dark on light, large garment, 12 MP.
    W, H = 4032, 3024
    a = mask_from_drawing(W, H, lambda d, s: shirt(d, s, W, H))
    fg = tint(tile(texture("cotton_jersey"), W, H, 0.6), (0.10, 0.14, 0.30)) * shading(a, 0.25)
    bg = tile(texture("white_stucco"), W, H, 2.0)
    img, at = photograph(fg, a, bg, 1)
    save_case(out, "01_navy_shirt_on_white", img, at, fg, {"what": "dark garment on light surface, 12 MP"})

    # 2. White leather pouch on off-white linen: light on light.
    W, H = 2400, 1800
    a = mask_from_drawing(W, H, lambda d, s: d.rounded_rectangle([0.30 * W * s, 0.28 * H * s, 0.70 * W * s, 0.72 * H * s], radius=0.06 * W * s, fill=255))
    fg = tint(tile(texture("leather_white"), W, H, 1.0), (0.93, 0.92, 0.90)) * shading(a, 0.12)
    bg = tint(tile(texture("rough_linen"), W, H, 0.5), (0.90, 0.88, 0.84), 0.7)
    img, at = photograph(fg, a, bg, 2, shadow=(0.25, 0.010, 0.003))
    save_case(out, "02_white_on_white", img, at, fg, {"what": "light product on light surface"})

    # 3. Black leather wallet on dark wood: dark on dark.
    a = mask_from_drawing(W, H, lambda d, s: d.rounded_rectangle([0.32 * W * s, 0.30 * H * s, 0.68 * W * s, 0.70 * H * s], radius=0.03 * W * s, fill=255))
    fg = tint(tile(texture("brown_leather"), W, H, 1.0), (0.07, 0.065, 0.06)) * shading(a, 0.2, (0.45 * W, 0.4 * H, 0.08 * W, 0.08))
    bg = tile(texture("dark_wood"), W, H, 1.2) * 0.75
    img, at = photograph(fg, a, bg, 3)
    save_case(out, "03_black_on_dark_wood", img, at, fg, {"what": "dark product on dark surface"})

    # 4. Watch with two thin straps on linen: protrusions.
    def watch(d, s):
        cx, cy, r = 0.5 * W, 0.5 * H, 0.09 * W
        d.rectangle([(cx - 0.022 * W) * s, (cy - 0.40 * H) * s, (cx + 0.022 * W) * s, (cy + 0.40 * H) * s], fill=255)
        d.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s], fill=255)
        d.rectangle([(cx + r - 0.005 * W) * s, (cy - 0.012 * H) * s, (cx + r + 0.018 * W) * s, (cy + 0.012 * H) * s], fill=255)
    a = mask_from_drawing(W, H, watch)
    fg = tint(tile(texture("brown_leather"), W, H, 0.8), (0.42, 0.24, 0.12)) * shading(a, 0.3, (0.48 * W, 0.47 * H, 0.04 * W, 0.15))
    bg = tile(texture("rough_linen"), W, H, 0.5)
    img, at = photograph(fg, a, bg, 4)
    save_case(out, "04_watch_thin_straps", img, at, fg, {"what": "thin straps and a crown: protrusions"})

    # 5. Fine chain necklace with pendant on marble: fine detail.
    def chain(d, s):
        pts = [(0.5 * W + 0.28 * W * math.cos(t), 0.30 * H + 0.45 * H * math.sin(t)) for t in np.linspace(0.15 * math.pi, 0.85 * math.pi, 300)]
        d.line([(x * s, y * s) for x, y in pts], fill=255, width=int(5 * s))
        d.ellipse([(0.5 * W - 0.025 * W) * s, (0.73 * H) * s, (0.5 * W + 0.025 * W) * s, (0.73 * H + 0.06 * W) * s], fill=255)
    a = mask_from_drawing(W, H, chain)
    gold = np.ones((H, W, 3), np.float32) * np.array([0.80, 0.62, 0.30], np.float32)
    fg = gold * shading(a, 0.35, (0.5 * W, 0.76 * H, 0.01 * W, 0.4))
    bg = tile(texture("marble_01"), W, H, 1.6)
    img, at = photograph(fg, a, bg, 5, lens=0.6, shadow=(0.3, 0.004, 0.002))
    save_case(out, "05_fine_chain_on_marble", img, at, fg, {"what": "5 px chain: fine detail"})

    # 6. Mug with a handle (background showing through the handle) on oak.
    def mug(d, s):
        d.rounded_rectangle([0.33 * W * s, 0.25 * H * s, 0.58 * W * s, 0.78 * H * s], radius=0.02 * W * s, fill=255)
        d.ellipse([0.53 * W * s, 0.36 * H * s, 0.70 * W * s, 0.64 * H * s], fill=255)
        d.ellipse([0.575 * W * s, 0.42 * H * s, 0.655 * W * s, 0.58 * H * s], fill=0)
    a = mask_from_drawing(W, H, mug)
    fg = np.ones((H, W, 3), np.float32) * np.array([0.78, 0.35, 0.22], np.float32) * shading(a, 0.3, (0.40 * W, 0.40 * H, 0.05 * W, 0.12))
    bg = tile(texture("wood_table_001"), W, H, 1.3)
    img, at = photograph(fg, a, bg, 6)
    save_case(out, "06_mug_handle_gap", img, at, fg, {"what": "background visible through the handle"})

    # 7. Reflective bottle on concrete: highlights that resemble the background.
    def bottle(d, s):
        d.rounded_rectangle([0.42 * W * s, 0.30 * H * s, 0.58 * W * s, 0.85 * H * s], radius=0.03 * W * s, fill=255)
        d.rectangle([0.475 * W * s, 0.14 * H * s, 0.525 * W * s, 0.32 * H * s], fill=255)
    a = mask_from_drawing(W, H, bottle)
    xx = np.linspace(0, 1, W)[None, :].repeat(H, 0)
    metal = 0.35 + 0.55 * np.abs(np.sin((xx - 0.42) / 0.16 * math.pi * 1.5))
    fg = np.stack([metal * 0.80, metal * 0.82, metal * 0.85], axis=2).astype(np.float32)
    bg = tile(texture("concrete_floor_02"), W, H, 1.2)
    img, at = photograph(fg, a, bg, 7)
    save_case(out, "07_reflective_bottle", img, at, fg, {"what": "metallic bands near background brightness"})

    # 8. Fuzzy knit edge: genuinely soft boundary (partial alpha in the truth).
    a0 = mask_from_drawing(W, H, lambda d, s: d.ellipse([0.30 * W * s, 0.25 * H * s, 0.70 * W * s, 0.75 * H * s], fill=255))
    rng = np.random.default_rng(8)
    fuzz = ndimage.gaussian_filter(rng.random((H, W)).astype(np.float32), 1.2)
    edge = ndimage.gaussian_filter(a0, 6)
    a = np.clip(a0 * 0.0 + np.clip((edge - 0.5) * 3 + 0.5 + (fuzz - 0.5) * 1.5, 0, 1), 0, 1)
    a = np.where(edge > 0.98, 1, np.where(edge < 0.02, 0, a)).astype(np.float32)
    fg = tint(tile(texture("cotton_jersey"), W, H, 0.4), (0.85, 0.55, 0.62)) * shading(a, 0.15)
    bg = tile(texture("concrete_floor_02"), W, H, 1.2) * 0.9
    img, at = photograph(fg, a, bg, 8)
    save_case(out, "08_fuzzy_knit_edge", img, at, fg, {"what": "soft fibrous edge that should stay soft"})

    # 9. Sunglasses: two frames joined by a thin bridge, gaps between.
    def glasses(d, s):
        for cx in (0.38, 0.62):
            d.ellipse([(cx - 0.10) * W * s, 0.38 * H * s, (cx + 0.10) * W * s, 0.62 * H * s], fill=255)
        d.rectangle([0.47 * W * s, 0.43 * H * s, 0.53 * W * s, 0.455 * H * s], fill=255)
        d.line([(0.28 * W * s, 0.45 * H * s), (0.12 * W * s, 0.40 * H * s)], fill=255, width=int(10 * s))
        d.line([(0.72 * W * s, 0.45 * H * s), (0.88 * W * s, 0.40 * H * s)], fill=255, width=int(10 * s))
    a = mask_from_drawing(W, H, glasses)
    fg = np.ones((H, W, 3), np.float32) * np.array([0.10, 0.09, 0.08], np.float32) * shading(a, 0.2, (0.36 * W, 0.45 * H, 0.03 * W, 0.6))
    bg = tile(texture("oak_veneer_01"), W, H, 1.0)
    img, at = photograph(fg, a, bg, 9)
    save_case(out, "09_sunglasses_gaps", img, at, fg, {"what": "thin arms and bridge, narrow gaps"})

    # 10. Pale wood comb with many narrow teeth on light linen.
    def comb(d, s):
        d.rounded_rectangle([0.25 * W * s, 0.30 * H * s, 0.75 * W * s, 0.42 * H * s], radius=0.02 * W * s, fill=255)
        for i in range(24):
            x = 0.265 * W + i * 0.0205 * W
            d.rectangle([x * s, 0.41 * H * s, (x + 0.011 * W) * s, 0.70 * H * s], fill=255)
    a = mask_from_drawing(W, H, comb)
    fg = tile(texture("fine_grained_wood"), W, H, 0.6) * shading(a, 0.15)
    bg = tint(tile(texture("rough_linen"), W, H, 0.5), (0.86, 0.84, 0.80), 0.6)
    img, at = photograph(fg, a, bg, 10)
    save_case(out, "10_comb_narrow_teeth", img, at, fg, {"what": "24 narrow teeth with gaps"})


def big_scene(out):
    # 11. A 24-megapixel photo (iPhone 15 and later default): garment on linen, for export size and memory.
    W, H = 5712, 4284
    a = mask_from_drawing(W, H, lambda d, s: shirt(d, s, W, H))
    fg = tint(tile(texture("cotton_jersey"), W, H, 0.8), (0.55, 0.12, 0.14)) * shading(a, 0.25)
    bg = tile(texture("rough_linen"), W, H, 0.7)
    img, at = photograph(fg, a, bg, 11)
    save_case(out, "11_red_shirt_24mp", img, at, fg, {"what": "24 MP export check"})


if __name__ == "__main__":
    big_scene(sys.argv[1] if len(sys.argv) > 1 else "QA/testset")
    main(sys.argv[1] if len(sys.argv) > 1 else "QA/testset")
