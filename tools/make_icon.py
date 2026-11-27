"""Clearcut app icon: a shirt cut along a diagonal. Top left, as photographed on a speckled carpet;
bottom right, cut out on the checkerboard that means "transparent", with a soft shadow.

Usage: python3 tools/make_icon.py  (writes icon.png at 1024 px and small.png at 120 px to check
legibility; copy icon.png to Clearcut/Assets.xcassets/AppIcon.appiconset/). Needs Pillow and numpy.
Version 1 (plain shirt on paper) is in git history before 27 Nov 2026.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4096
k = S / 1024
rng = np.random.default_rng(7)


def P(pts, grow=1.12):
    # Shapes are drawn on a 1024 grid around the centre, enlarged a little to fill the icon.
    return [((512 + (x - 512) * grow) * k, (520 + (y - 520) * grow) * k) for x, y in pts]


cloth = (196, 78, 44)        # terracotta, brighter than v1 so it reads at small sizes
cloth_dark = (150, 54, 30)

# T-shirt, front view: short sleeves, crew neck.
shirt = [(372, 238), (452, 214), (512, 246), (572, 214), (652, 238),
         (842, 352), (780, 478), (700, 438),
         (712, 826), (312, 826),
         (324, 438), (244, 478), (182, 352)]
neck = [(452, 214), (512, 246), (572, 214), (556, 262), (512, 286), (468, 262)]

# --- Before: speckled carpet ---
carpet = np.full((S, S, 3), (122, 116, 106), np.float32)
noise = rng.normal(0, 1, (S // 8, S // 8)).astype(np.float32)
noise = np.asarray(Image.fromarray(noise).resize((S, S), Image.BICUBIC), np.float32)
carpet += noise[..., None] * 10
strands = Image.new("L", (S, S), 0)
ds = ImageDraw.Draw(strands)
for _ in range(9000):
    x, y = rng.uniform(0, S, 2)
    a = rng.uniform(0, np.pi)
    l = rng.uniform(10, 34) * k
    ds.line([(x, y), (x + np.cos(a) * l, y + np.sin(a) * l)], fill=int(rng.uniform(120, 255)), width=int(2.2 * k))
st = np.asarray(strands, np.float32)[..., None] / 255
carpet = carpet * (1 - 0.55 * st) + np.array((214, 208, 196), np.float32) * 0.55 * st

# --- After: checkerboard ---
yy, xx = np.mgrid[0:S, 0:S]
sq = 64 * k
checker = np.where(((xx // sq).astype(int) + (yy // sq).astype(int)) % 2 == 0, 255, 226).astype(np.float32)
checker = np.repeat(checker[..., None], 3, axis=2)

mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon(P(shirt), fill=255)
m = np.asarray(mask, np.float32) / 255


def shadow(img, blur, dx, dy, strength):
    s = mask.filter(ImageFilter.GaussianBlur(blur * k))
    s = np.roll(np.roll(np.asarray(s, np.float32) / 255, int(dy * k), axis=0), int(dx * k), axis=1)
    lin = (img / 255) ** 2.2 * (1 - strength * s[..., None])
    return lin ** (1 / 2.2) * 255


before = shadow(carpet, 4, -14, 12, 0.55)          # harsh, off-centre: a phone photo
after = shadow(checker, 30, 0, 26, 0.38)           # soft, even: the finished look

# The shirt itself, drawn once, then shown duller on the photo side (as a phone photo renders it).
layer = Image.new("RGB", (S, S), cloth)
d = ImageDraw.Draw(layer)
d.polygon(P(neck), fill=cloth_dark)
for a, b in [((324, 438), (348, 300)), ((700, 438), (676, 300))]:
    d.line(P([a, b]), fill=cloth_dark, width=int(8 * k))
d.polygon(P([(313, 790), (711, 790), (712, 826), (312, 826)]), fill=cloth_dark)
fabric = np.asarray(layer, np.float32)
dull = fabric * 0.82 + np.array((122, 116, 106), np.float32) * 0.08

# Diagonal split: top left is the photo, bottom right the cutout.
cut = (xx + yy) < S * 1.0
base = np.where(cut[..., None], before, after)
item = np.where(cut[..., None], dull, fabric)
base = base * (1 - m[..., None]) + item * m[..., None]
img = Image.fromarray(np.clip(base + 0.5, 0, 255).astype(np.uint8))
d = ImageDraw.Draw(img)

# The cut line, crisp white with a thin dark rule beside it so it reads on both halves.
d.line([(S, 0), (0, S)], fill=(40, 36, 32), width=int(16 * k))
d.line([(S, 0), (0, S)], fill=(255, 255, 255), width=int(10 * k))

out = img.resize((1024, 1024), Image.LANCZOS)
out.save("icon.png")
out.resize((120, 120), Image.LANCZOS).save("small.png")
