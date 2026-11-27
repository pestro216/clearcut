"""Clearcut app icon: a shirt cut along a diagonal. Top left, as photographed on a plain grey floor;
bottom right, cut out on the checkerboard that means "transparent", with a soft shadow.

Version 3 (27 Nov 2026), drawn to read at home-screen size (60 px) and smaller: plain background instead
of carpet strands, big checker squares, a thick cut line, a larger shirt. Also makes the dark and tinted
versions iOS shows when someone picks a dark or tinted home screen.

Usage: python3 tools/make_icon.py [output folder]  (default: the AppIcon set in Clearcut/Assets.xcassets).
Writes icon.png, icon-dark.png, icon-tinted.png (1024 px, no transparency) and preview.png (all three at
180, 60, 40 and 29 px, for checking; not part of the app). Needs Pillow and numpy.
Versions 1 and 2 are in git history.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4096
k = S / 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), "..", "Clearcut", "Assets.xcassets", "AppIcon.appiconset")


def P(pts, grow=1.16):
    # Shapes are drawn on a 1024 grid around the centre, enlarged to fill the icon.
    return [((512 + (x - 512) * grow) * k, (532 + (y - 532) * grow) * k) for x, y in pts]


# T-shirt, front view: short sleeves, crew neck.
shirt = [(372, 238), (452, 214), (512, 246), (572, 214), (652, 238),
         (842, 352), (780, 478), (700, 438),
         (712, 826), (312, 826),
         (324, 438), (244, 478), (182, 352)]
neck = [(452, 214), (512, 246), (572, 214), (556, 262), (512, 286), (468, 262)]
seams = [((324, 438), (348, 300)), ((700, 438), (676, 300))]
hem = [(313, 790), (711, 790), (712, 826), (312, 826)]

STYLES = {
    # floor, checker light/dark, shirt, shirt detail, line, line edge, shadow strength
    "icon": dict(floor=(128, 121, 111), chk=(255, 208), cloth=(204, 80, 44), detail=(150, 54, 30),
                 line=(255, 255, 255), edge=(46, 40, 36), shade=(0.5, 0.36)),
    "icon-dark": dict(floor=(52, 49, 46), chk=(82, 60), cloth=(214, 92, 56), detail=(150, 54, 30),
                      line=(236, 232, 226), edge=(20, 18, 16), shade=(0.6, 0.5)),
    # Tinted: greys only. iOS colours it by brightness, so the shirt is lightest.
    "icon-tinted": dict(floor=(40, 40, 40), chk=(70, 24), cloth=(236, 236, 236), detail=(150, 150, 150),
                        line=(200, 200, 200), edge=(0, 0, 0), shade=(0.6, 0.5)),
}

yy, xx = np.mgrid[0:S, 0:S]
cut = (xx + yy) < S  # top left: the photo; bottom right: the cutout
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon(P(shirt), fill=255)
m = np.asarray(mask, np.float32)[..., None] / 255
rng = np.random.default_rng(7)
grain = np.asarray(Image.fromarray(rng.normal(0, 1, (S // 64, S // 64)).astype(np.float32))
                   .resize((S, S), Image.BICUBIC), np.float32)[..., None]


def shadow(img, blur, dx, dy, strength):
    s = mask.filter(ImageFilter.GaussianBlur(blur * k))
    s = np.roll(np.roll(np.asarray(s, np.float32) / 255, int(dy * k), axis=0), int(dx * k), axis=1)
    lin = (img / 255) ** 2.2 * (1 - strength * s[..., None])
    return lin ** (1 / 2.2) * 255


def draw(st):
    floor = np.full((S, S, 3), st["floor"], np.float32) + grain * 4  # barely-there unevenness
    sq = 1024 / 5 * k  # five squares across: still reads as a checkerboard at 40 px
    a, b = st["chk"]
    checker = np.where(((xx // sq).astype(int) + (yy // sq).astype(int)) % 2 == 0, a, b).astype(np.float32)
    checker = np.repeat(checker[..., None], 3, axis=2)

    before = shadow(floor, 4, -14, 12, st["shade"][0])   # harsh, off-centre: a phone photo
    after = shadow(checker, 30, 0, 26, st["shade"][1])   # soft, even: the finished look

    layer = Image.new("RGB", (S, S), st["cloth"])
    d = ImageDraw.Draw(layer)
    d.polygon(P(neck), fill=st["detail"])
    for p, q in seams:
        d.line(P([p, q]), fill=st["detail"], width=int(10 * k))
    d.polygon(P(hem), fill=st["detail"])
    fabric = np.asarray(layer, np.float32)
    dull = fabric * 0.78 + np.array(st["floor"], np.float32) * 0.1  # the shirt as a phone photo shows it

    base = np.where(cut[..., None], before, after)
    item = np.where(cut[..., None], dull, fabric)
    img = Image.fromarray(np.clip(base * (1 - m) + item * m + 0.5, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    d.line([(S, 0), (0, S)], fill=st["edge"], width=int(34 * k))
    d.line([(S, 0), (0, S)], fill=st["line"], width=int(22 * k))
    return img.resize((1024, 1024), Image.LANCZOS)


def rounded(img, size):
    small = img.resize((size, size), Image.LANCZOS)
    r = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(r).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.225), fill=255)
    return small, r.resize((size, size), Image.LANCZOS)


icons = {name: draw(st) for name, st in STYLES.items()}
for name, img in icons.items():
    img.save(os.path.join(OUT, name + ".png"))

# Preview sheet: each version at 180, 60, 40 and 29 px on a light and a dark wallpaper.
sizes = [180, 60, 40, 29]
sheet = Image.new("RGB", (2 * (sum(sizes) + 40 * 5), 3 * 220), (220, 228, 236))
ImageDraw.Draw(sheet).rectangle([sheet.width // 2, 0, sheet.width, sheet.height], fill=(28, 28, 30))
for row, img in enumerate(icons.values()):
    for half in (0, 1):
        x = half * sheet.width // 2 + 40
        for s in sizes:
            small, rmask = rounded(img, s)
            sheet.paste(small, (x, row * 220 + 20 + (180 - s)), rmask)
            x += s + 40
sheet.save(os.path.join(OUT, "preview.png") if len(sys.argv) > 1 else "preview.png")
