"""Generates Clearcut's bundled backdrop photos (top-down surfaces for flatlays)."""
import sys
import numpy as np
from scipy import ndimage
from PIL import Image

N = 2560
rng = np.random.default_rng(7)
OUT = sys.argv[1] if len(sys.argv) > 1 else "out"


def value_noise(shape, cells, seed, order=3):
    """Smooth noise: random grid of `cells` upsampled with cubic interpolation."""
    r = np.random.default_rng(seed)
    cy, cx = max(2, int(cells[0])), max(2, int(cells[1]))
    g = r.random((cy + 3, cx + 3))
    z = ndimage.zoom(g, ((shape[0] + 3 * shape[0] / cy) / (cy + 3), (shape[1] + 3 * shape[1] / cx) / (cx + 3)), order=order)
    return z[: shape[0], : shape[1]]


def fbm(shape, base_cells, octaves, seed, gain=0.5, aspect=(1, 1)):
    total = np.zeros(shape)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        c = base_cells * (2 ** o)
        total += amp * value_noise(shape, (c * aspect[0], c * aspect[1]), seed + o * 101)
        norm += amp
        amp *= gain
    return total / norm


def ramp(t, stops):
    """Map 0..1 to colours given [(pos, (r,g,b)), ...]."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    pos = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, pos, [s[1][c] for s in stops])
    return out


def save(name, rgb, dither=1.2):
    rgb = rgb + rng.normal(0, dither, rgb.shape)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
    img.save(f"{OUT}/{name}.jpg", quality=90, optimize=True, progressive=False)
    img.resize((240, 240), Image.LANCZOS).save(f"{OUT}/thumbs/{name}.jpg", quality=88)


# ---------- wood ----------
def wood(name, stops, plank_px=520, ring_freq=16, seed=1, seam=0.7, sheen=0.0):
    h = w = N
    out = np.zeros((h, w, 3))
    y0 = 0
    k = 0
    while y0 < h:
        ph = int(plank_px * (0.9 + 0.2 * rng.random()))
        y1 = min(h, y0 + ph)
        sh = (y1 - y0, w)
        s = seed * 1000 + k * 17
        yy = np.arange(sh[0])[:, None] / sh[0]
        # gently wandering growth rings (flat-sawn look), few and soft
        warp = fbm(sh, 2, 3, s, gain=0.45, aspect=(1, 0.18)) - 0.5
        rings = np.sin((yy + warp * 0.9) * ring_freq * (0.8 + 0.4 * rng.random()) * np.pi)
        rings = ndimage.gaussian_filter(rings, (2.0, 6.0))
        rings = 0.5 + 0.5 * np.tanh(rings * 1.2)
        # long straight fibres, the dominant real-wood texture
        fib = ndimage.gaussian_filter(rng.normal(0, 1, sh), (0.7, 40))
        fib = fib / (fib.std() + 1e-6)
        fib2 = ndimage.gaussian_filter(rng.normal(0, 1, sh), (2.5, 120))
        fib2 = fib2 / (fib2.std() + 1e-6)
        tone = fbm(sh, 1.5, 3, s + 5, aspect=(1, 0.6))
        t = 0.48 + 0.16 * (rings - 0.5) + 0.06 * fib + 0.07 * fib2 + 0.22 * (tone - 0.5)
        t += (rng.random() - 0.5) * 0.14
        col = ramp(t, stops)
        out[y0:y1] = col
        if y1 < h:
            g = np.exp(-((np.arange(-4, 5)) / 1.6) ** 2)
            for i, v in enumerate(g):
                yy_ = y1 - 4 + i
                if 0 <= yy_ < h:
                    out[yy_] *= 1 - (1 - seam) * v
        jx = rng.integers(400, w - 400)
        for i, v in enumerate(np.exp(-((np.arange(-3, 4)) / 1.2) ** 2)):
            out[y0:y1, jx - 3 + i] *= 1 - (1 - seam) * v
        y0 = y1
        k += 1
    sheen_map = fbm((h, w), 1.2, 2, seed + 77)
    out = out * (0.96 + 0.08 * sheen_map[..., None])
    save(name, out)


# ---------- marble ----------
def marble(name, base, vein, seed, vein_amt=0.85, scale=1.0, warmth=(0, 0, 0), dark=False):
    sh = (N, N)
    yy, xx = np.mgrid[0:N, 0:N] / N
    turb = fbm(sh, 1.6, 4, seed, gain=0.42)
    fine = fbm(sh, 6, 3, seed + 1, gain=0.5)
    phase = (xx * 0.7 + yy * 1.0) * np.pi * 2.2 * scale + turb * 7.0 + fine * 0.9
    d = np.abs(np.sin(phase))
    width = 0.5 + 1.0 * fbm(sh, 2, 3, seed + 4)
    core = np.exp(-(d / (0.035 * width)) ** 2)
    halo = np.exp(-(d / (0.16 * width)) ** 2) * 0.28
    fade = np.clip((fbm(sh, 1.5, 3, seed + 6) - 0.28) * 2.2, 0, 1)
    veins = (core + halo) * fade
    # sparse secondary hairline veins
    phase2 = (xx * 1.3 - yy * 0.4) * np.pi * 3.0 * scale + fbm(sh, 2, 4, seed + 8, gain=0.45) * 8.0
    d2 = np.abs(np.sin(phase2))
    hair = np.exp(-(d2 / 0.012) ** 2) * np.clip((fbm(sh, 1.5, 2, seed + 10) - 0.55) * 3, 0, 1) * 0.55
    veins = ndimage.gaussian_filter(veins + hair, 0.8)
    cloud = fbm(sh, 2.5, 6, seed + 9, gain=0.5)
    base_c = np.array(base, float)[None, None, :] * (0.95 + 0.08 * cloud[..., None]) + np.array(warmth)[None, None, :]
    vein_c = np.array(vein, float)[None, None, :]
    a = np.clip(veins * vein_amt, 0, 1)[..., None]
    out = base_c * (1 - a) + vein_c * a
    grain = ndimage.gaussian_filter(rng.normal(0, 1, sh), 0.8)
    out *= (1 + 0.012 * grain[..., None])
    save(name, out)


# ---------- concrete / stone ----------
def concrete(name, tone, seed, contrast=1.0, pores=True):
    sh = (N, N)
    blot = fbm(sh, 3, 5, seed, gain=0.55)
    mid = fbm(sh, 20, 4, seed + 5, gain=0.55)
    fine = rng.normal(0, 1, sh)
    fine = ndimage.gaussian_filter(fine, 0.7)
    t = (blot - 0.5) * 0.22 * contrast + (mid - 0.5) * 0.10 * contrast + fine * 0.035 * contrast
    out = np.array(tone, float)[None, None, :] * (1 + t[..., None])
    if pores:
        p = rng.random(sh) > 0.9993
        p = ndimage.binary_dilation(p, iterations=2)
        p = ndimage.gaussian_filter(p.astype(float), 1.2)
        out *= (1 - 0.45 * p[..., None])
        light = rng.random(sh) > 0.9985
        light = ndimage.gaussian_filter(light.astype(float), 0.9)
        out *= (1 + 0.6 * light[..., None])
    save(name, out)


def plaster(name, tone, seed):
    sh = (N, N)
    blot = fbm(sh, 2, 6, seed, gain=0.6)
    trowel = fbm(sh, 6, 4, seed + 4, gain=0.5, aspect=(0.4, 1.4))
    fine = ndimage.gaussian_filter(rng.normal(0, 1, sh), 0.6)
    t = (blot - 0.5) * 0.12 + (trowel - 0.5) * 0.08 + fine * 0.012
    out = np.array(tone, float)[None, None, :] * (1 + t[..., None])
    save(name, out)


def linen(name, tone, seed):
    sh = (N, N)
    yy, xx = np.mgrid[0:N, 0:N]
    jx = fbm(sh, 40, 3, seed, aspect=(8, 0.2)) - 0.5
    jy = fbm(sh, 40, 3, seed + 1, aspect=(0.2, 8)) - 0.5
    weft = np.sin((yy + jx * 6) * 2 * np.pi / 6.0)
    warp = np.sin((xx + jy * 6) * 2 * np.pi / 6.0)
    slub_x = fbm(sh, 30, 3, seed + 2, aspect=(12, 0.15))
    slub_y = fbm(sh, 30, 3, seed + 3, aspect=(0.15, 12))
    checker = ((yy // 6 + xx // 6) % 2) * 2 - 1
    weave = np.where(checker > 0, weft * (0.7 + 0.6 * slub_x), warp * (0.7 + 0.6 * slub_y))
    weave = ndimage.gaussian_filter(weave, 0.7)
    blot = fbm(sh, 3, 4, seed + 7)
    t = weave * 0.06 + (blot - 0.5) * 0.06
    out = np.array(tone, float)[None, None, :] * (1 + t[..., None])
    save(name, out)


def paper(name, tone, seed):
    sh = (N, N)
    fib = ndimage.gaussian_filter(rng.normal(0, 1, sh), 1.0)
    fib2 = fbm(sh, 60, 3, seed, gain=0.6)
    blot = fbm(sh, 2, 4, seed + 2)
    t = fib * 0.018 + (fib2 - 0.5) * 0.03 + (blot - 0.5) * 0.04
    out = np.array(tone, float)[None, None, :] * (1 + t[..., None])
    save(name, out, dither=0.8)


def terrazzo(name, base, chips, seed):
    sh = (N, N)
    out = np.array(base, float)[None, None, :] * (1 + (fbm(sh, 3, 4, seed) - 0.5)[..., None] * 0.06)
    r = np.random.default_rng(seed)
    yy, xx = np.ogrid[:N, :N]
    for _ in range(700):
        cx, cy = r.integers(0, N), r.integers(0, N)
        rad = r.choice([6, 9, 13, 18, 26], p=[0.3, 0.3, 0.2, 0.13, 0.07])
        col = np.array(chips[r.integers(0, len(chips))], float) * (0.9 + 0.2 * r.random())
        x0, x1, y0, y1 = max(0, cx - rad * 2), min(N, cx + rad * 2), max(0, cy - rad * 2), min(N, cy + rad * 2)
        sy, sx = np.ogrid[y0:y1, x0:x1]
        ang = r.random() * np.pi
        dx, dy = sx - cx, sy - cy
        u = dx * np.cos(ang) + dy * np.sin(ang)
        v = -dx * np.sin(ang) + dy * np.cos(ang)
        m = (np.abs(u) / rad) ** 1.3 + (np.abs(v) / (rad * (0.5 + 0.5 * r.random()))) ** 1.3 < 1
        out[y0:y1, x0:x1][m] = col
    out = ndimage.gaussian_filter(out, (0.6, 0.6, 0))
    save(name, out)


def studio(name, top, bottom, seed):
    yy, xx = np.mgrid[0:N, 0:N] / N
    t = np.clip((yy - 0.15) / 0.85, 0, 1) ** 1.3
    col = np.array(top, float)[None, None, :] * (1 - t[..., None]) + np.array(bottom, float)[None, None, :] * t[..., None]
    d = np.sqrt((xx - 0.5) ** 2 + (yy - 0.42) ** 2)
    light = np.clip(1 - d / 0.75, 0, 1) ** 1.6
    col *= (0.93 + 0.1 * light[..., None])
    save(name, col, dither=1.0)


if __name__ == "__main__":
    import os
    os.makedirs(f"{OUT}/thumbs", exist_ok=True)
    which = sys.argv[2:] or ["all"]
    jobs = {
        "studio-white": lambda: studio("studio-white", (250, 249, 247), (226, 224, 221), 1),
        "studio-warm": lambda: studio("studio-warm", (244, 238, 228), (219, 209, 194), 2),
        "studio-grey": lambda: studio("studio-grey", (224, 225, 227), (184, 186, 190), 3),
        "studio-blush": lambda: studio("studio-blush", (246, 230, 224), (226, 200, 191), 4),
        "studio-sage": lambda: studio("studio-sage", (228, 234, 225), (196, 206, 192), 5),
        "wood-cherry": lambda: wood("wood-cherry", [(0, (78, 30, 16)), (0.45, (128, 54, 30)), (0.75, (160, 78, 44)), (1, (182, 98, 58))], seed=11),
        "wood-oak": lambda: wood("wood-oak", [(0, (122, 84, 48)), (0.45, (172, 128, 82)), (0.8, (204, 162, 112)), (1, (222, 186, 136))], seed=12),
        "wood-walnut": lambda: wood("wood-walnut", [(0, (36, 22, 14)), (0.45, (70, 44, 28)), (0.8, (102, 68, 44)), (1, (124, 86, 58))], seed=13),
        "wood-whitewash": lambda: wood("wood-whitewash", [(0, (168, 160, 150)), (0.45, (206, 200, 191)), (0.8, (228, 224, 216)), (1, (240, 237, 231))], seed=14, seam=0.72),
        "marble-white": lambda: marble("marble-white", (238, 237, 234), (112, 114, 120), 21, vein_amt=0.7),
        "marble-warm": lambda: marble("marble-warm", (234, 226, 214), (146, 120, 96), 22, vein_amt=0.6, scale=0.9),
        "marble-black": lambda: marble("marble-black", (30, 30, 32), (214, 212, 208), 29, vein_amt=0.85, scale=1.1),
        "concrete-light": lambda: concrete("concrete-light", (196, 194, 189), 31),
        "concrete-dark": lambda: concrete("concrete-dark", (106, 106, 104), 32, contrast=1.2),
        "plaster": lambda: plaster("plaster", (226, 216, 202), 41),
        "linen": lambda: linen("linen", (214, 204, 186), 51),
        "linen-grey": lambda: linen("linen-grey", (176, 176, 172), 52),
        "paper-kraft": lambda: paper("paper-kraft", (190, 152, 108), 61),
        "terrazzo": lambda: terrazzo("terrazzo", (232, 228, 220), [(186, 92, 70), (60, 64, 70), (200, 196, 188), (150, 160, 150), (226, 184, 120)], 71),
    }
    for k, f in jobs.items():
        if "all" in which or k in which:
            f()
            print("made", k)
