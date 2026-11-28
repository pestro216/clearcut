# python3 canvas.py SCENE VARIANT   -> logs IoU of the network with a padded canvas, mapped back to the photo
import sys
from net import *

n, v = sys.argv[1], sys.argv[2]
img, a = load(n)
h, w = img.shape[:2]


def padded(frac, mode, value=None):
    m = int(frac * max(w, h))
    if mode == "const":
        big = cv2.copyMakeBorder(img, m, m, m, m, cv2.BORDER_CONSTANT, value=value)
    else:
        big = cv2.copyMakeBorder(img, m, m, m, m, mode)
    p = run(big)
    p = cv2.resize(p, (big.shape[1], big.shape[0]))
    return p[m:m + h, m:m + w]


def go():
    if v == "plain": return cv2.resize(run(img), (w, h))
    kind, frac = v.split("_")
    frac = float(frac)
    if kind == "reflect": return padded(frac, cv2.BORDER_REFLECT)
    if kind == "replicate": return padded(frac, cv2.BORDER_REPLICATE)
    if kind == "grey": return padded(frac, "const", (128, 128, 128))
    if kind == "white": return padded(frac, "const", (255, 255, 255))
    raise SystemExit("unknown variant")


p = cached(f"{n}_{v}", go)
i, mi, k = iou(p, a)
log(f"{v:16s} {n:36s} IoU {i:.3f} missed {mi:.3f} kept {k:.3f}")
