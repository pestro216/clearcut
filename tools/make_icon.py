import numpy as np
from PIL import Image, ImageDraw, ImageFilter
S = 4096
k = S / 1024
def P(pts): return [(x * k, y * k) for x, y in pts]
paper = (241, 237, 228)
cloth = (150, 62, 38)     # terracotta, like a madder-dyed cotton
cloth_dark = (118, 46, 28)
# flat-laid shirt, front view, sleeves angled down and out
body = [(392, 232), (446, 214), (512, 252), (578, 214), (632, 232),   # shoulders and neck
        (742, 296), (842, 610), (770, 640), (690, 420),               # right sleeve
        (690, 812), (334, 812),                                       # hem
        (334, 420), (254, 640), (182, 610), (282, 296)]               # left sleeve
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon(P(body), fill=255)
# lifted shadow: offset down, softened
sh = mask.filter(ImageFilter.GaussianBlur(28 * k))
sh = Image.fromarray(np.roll(np.asarray(sh), int(22 * k), axis=0))
near = Image.fromarray(np.roll(np.asarray(mask.filter(ImageFilter.GaussianBlur(8 * k))), int(7 * k), axis=0))
base = np.ones((S, S, 3), np.float32) * np.array(paper, np.float32) / 255
lin = base ** 2.2
dens = 0.62 * np.asarray(sh, np.float32) / 255
dens = 1 - (1 - dens) * (1 - 0.40 * np.asarray(near, np.float32) / 255)
lin = lin * (1 - dens[..., None])
img = Image.fromarray((np.clip(lin ** (1 / 2.2), 0, 1) * 255 + 0.5).astype(np.uint8))
d = ImageDraw.Draw(img)
d.polygon(P(body), fill=cloth)
# placket and collar band in a deeper tone, sleeve seams as fine lines
d.polygon(P([(498, 252), (526, 252), (522, 812), (502, 812)]), fill=cloth_dark)
d.polygon(P([(446, 214), (512, 252), (578, 214), (566, 236), (512, 270), (458, 236)]), fill=cloth_dark)
for a, b in [((334, 420), (360, 300)), ((690, 420), (664, 300))]:
    d.line(P([a, b]), fill=cloth_dark, width=int(7 * k))
for y in (330, 430, 530, 630, 730):
    d.ellipse(P([(504, y - 7), (520, y + 7)]), fill=paper)
img = img.resize((1024, 1024), Image.LANCZOS)
img.save("icon.png")
img.resize((120, 120), Image.LANCZOS).save("small.png")
