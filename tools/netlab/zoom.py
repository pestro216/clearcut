# python3 zoom.py SCENE -> compares plain vs plain+zoom crop (as the app does) on edge measures
import sys
from net import *
n = sys.argv[1]
img, a = load(n); h, w = img.shape[:2]
k = 1536 / max(w, h); ww, wh = round(w * k), round(h * k)
plain = cv2.resize(cached(n + "_plain", lambda: run(img)), (ww, wh))
ys, xs = np.where(plain > 0.5)
bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
m = 0.08 * max(bx1 - bx0, by1 - by0)
rx0, ry0 = int(max(0, bx0 - m)), int(max(0, by0 - m)); rx1, ry1 = int(min(ww, bx1 + m)), int(min(wh, by1 + m))
z = plain.copy()
if (rx1 - rx0) * (ry1 - ry0) < 0.8 * ww * wh:
    s = w / ww
    crop = img[int(ry0 * s):int(ry1 * s), int(rx0 * s):int(rx1 * s)]
    d = cv2.resize(cached(n + "_zoomcrop", lambda: run(crop)), (rx1 - rx0, ry1 - ry0))
    yy, xx = np.mgrid[0:ry1 - ry0, 0:rx1 - rx0]
    edge = np.minimum(np.minimum(xx, rx1 - rx0 - 1 - xx), np.minimum(yy, ry1 - ry0 - 1 - yy))
    wgt = np.minimum(1, edge / 6.0)
    z[ry0:ry1, rx0:rx1] = z[ry0:ry1, rx0:rx1] * (1 - wgt) + d * wgt
else:
    log(f"zoom n/a {n}")
A = cv2.resize(a, (ww, wh), interpolation=cv2.INTER_AREA)

def bf(p, A, tol=2):
    P = (p > 0.5).astype(np.uint8); G = (A > 0.5).astype(np.uint8)
    eP = P - cv2.erode(P, np.ones((3, 3), np.uint8)); eG = G - cv2.erode(G, np.ones((3, 3), np.uint8))
    kk = np.ones((2 * tol + 1, 2 * tol + 1), np.uint8)
    prec = (eP & cv2.dilate(eG, kk)).sum() / max(1, eP.sum()); rec = (eG & cv2.dilate(eP, kk)).sum() / max(1, eG.sum())
    return 2 * prec * rec / max(1e-9, prec + rec)

band = cv2.dilate(((A > 0.02) & (A < 0.98)).astype(np.uint8), np.ones((9, 9), np.uint8)) > 0
for name, p in (("plain", plain), ("zoom", z)):
    i, mi, kp = iou(p, A)
    log(f"edge-{name:6s} {n:36s} IoU {i:.4f} BF2 {bf(p, A):.3f} bandMAE {np.abs(p - A)[band].mean():.4f}")
