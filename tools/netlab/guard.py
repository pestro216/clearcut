# python3 guard_v2.py -> the revised acceptCanvas: what the canvas adds is compared with the
# surface left over (both as colour histograms); surface-like where its colour is at least K times
# as common in the leftover surface as in the added region.
import sys
from net import *
from scipy import ndimage
def bins(img): return ((img[..., 0] >> 4).astype(int) << 8) | ((img[..., 1] >> 4).astype(int) << 4) | (img[..., 2] >> 4).astype(int)
def dens(sel, B):
    h = np.bincount(B[sel], minlength=4096).reshape(16, 16, 16).astype(np.float32)
    return ndimage.uniform_filter(h, 3, mode="constant").reshape(-1) / max(1, sel.sum())
def verdict(plain, wide, img, K):
    a = plain > 0.5; b = wide > 0.5; n = a.size
    added = b & ~a; rest = ~a & ~b
    if b.mean() >= 0.97: return "reject-rect", 0
    if (a & b).sum() / max(1, (a | b).sum()) >= 0.9: return "agree", 0
    if added.sum() < 0.01 * n: return "reject-small", 0
    if rest.sum() < 0.02 * n: return "accept-rest", 0
    B = bins(img); dB = dens(rest, B); dA = dens(added, B)
    bb = B[added]; f = ((dB[bb] > K * dA[bb]) & (dB[bb] > 2 / 4096)).mean()
    return ("accept" if f < 0.4 else "reject"), f
normal = ["columbia_anorak_arms_out_concrete", "columbia_anorak_front_concrete", "columbia_cuff_closeup_tape", "michigan_cuff_tape", "michigan_jacket_back_concrete", "michigan_jacket_front_open_collar"]
for K in (0.5,):
    print("K", K)
    for n in scenes():
        img, a = load(n); h, w = img.shape[:2]; k = 1536 / max(w, h); ww, wh = round(w*k), round(h*k)
        small = cv2.resize(img, (ww, wh), interpolation=cv2.INTER_AREA)
        p = cv2.resize(np.load(f"{CACHE}/{n}_plain.npy"), (ww, wh))
        tests = []
        try: tests.append(("grey_0.35", cv2.resize(np.load(f"{CACHE}/{n}_grey_0.35.npy"), (ww, wh)), "accept" if n not in normal else "agree"))
        except FileNotFoundError: pass
        if n in normal:
            top = p.copy(); top[: int(0.4 * wh)] = 1                      # a slab of floor along the top
            tests.append(("slab-top", top, "reject"))
            side = p.copy(); side[:, int(0.75 * ww):] = 1                  # a slab down one side
            tests.append(("slab-side", side, "reject"))
        for name, g, want in tests:
            v, f = verdict(p, g, small, K)
            ok = v.startswith(want)
            print(f"  {'ok ' if ok else 'BAD'} {n:36s} {name:10s} {v:12s} {f:.2f}")
