# python3 guard.py -> verdict of Segmenter.acceptCanvas (Python mirror) for each cached canvas result
from net import *
from scipy import ndimage
def bins(img): return ((img[..., 0] >> 4).astype(int) << 8) | ((img[..., 1] >> 4).astype(int) << 4) | (img[..., 2] >> 4).astype(int)
def smooth(hist):
    h = hist.reshape(16, 16, 16).astype(np.float32)
    return ndimage.uniform_filter(h, 3, mode="constant").reshape(-1) * 27 / max(1, hist.sum()) / 27
def accept(plain, wide, img):
    a = plain > 0.5; b = wide > 0.5
    inter = (a & b).sum(); uni = (a | b).sum(); added = b & ~a; rest = ~a & ~b; n = a.size
    if b.mean() >= 0.97: return False, "rectangle"
    if uni and inter / uni >= 0.9: return False, "agree"
    if added.sum() < 0.01 * n: return False, "small"
    if rest.sum() < 0.02 * n: return True, "rest<2%"
    B = bins(img)
    dB = smooth(np.bincount(B[rest], minlength=4096)); dF = smooth(np.bincount(B[b], minlength=4096))
    # item reference: what both agree is item, plus what the wide pass adds, judged against the surface
    bb = B[added]
    surf = (dB[bb] > 3 * dF[bb]) & (dB[bb] > 2 / 4096)
    mean = np.maximum(1, img[rest].mean(0)); ratio = img[added] / mean
    lo, hi = ratio.min(1), ratio.max(1)
    shadow = (lo > 0.2) & (hi < 0.97) & (hi - lo < 0.12)
    fs = (surf | shadow).mean()
    f = surf.mean()
    return bool(f < 0.4), f"colour-only {f:.2f} with-shadow {fs:.2f}"
for n in scenes():
    img, a = load(n); h, w = img.shape[:2]; k = 1536 / max(w, h); ww, wh = round(w*k), round(h*k)
    small = cv2.resize(img, (ww, wh), interpolation=cv2.INTER_AREA)
    p = cv2.resize(np.load(f"{CACHE}/{n}_plain.npy"), (ww, wh))
    for v in ("grey_0.35", "grey_1.0", "replicate_0.35", "white_0.5"):
        try: g = cv2.resize(np.load(f"{CACHE}/{n}_{v}.npy"), (ww, wh))
        except FileNotFoundError: continue
        A = cv2.resize(a, (ww, wh)); good = iou(g, A)[0] > iou(p, A)[0] + 0.01
        print(f"{n:36s} {v:15s} accept {accept(p, g, small)}  (better? {good})")
