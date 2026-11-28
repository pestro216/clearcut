import sys, os, time
S = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "QA", ".research")
sys.path.insert(0, S + "/py")
import numpy as np, cv2, onnxruntime as ort

REAL = os.path.join(S, "..", "realset")
CACHE = S + "/cache"
_sess = None
MEAN = np.array([0.485, 0.456, 0.406], np.float32); STD = np.array([0.229, 0.224, 0.225], np.float32)


def sess():
    global _sess
    if _sess is None:
        o = ort.SessionOptions(); o.intra_op_num_threads = 4
        o.enable_cpu_mem_arena = False; o.enable_mem_pattern = False
        _sess = ort.InferenceSession(S + "/model/model.onnx", o)
    return _sess


def scenes():
    return sorted(d for d in os.listdir(REAL) if os.path.isdir(os.path.join(REAL, d)))


def load(name):
    img = cv2.cvtColor(cv2.imread(f"{REAL}/{name}/photo.jpg"), cv2.COLOR_BGR2RGB)
    a = cv2.imread(f"{REAL}/{name}/alpha.png", cv2.IMREAD_UNCHANGED)
    if a.ndim == 3: a = a[..., -1] if a.shape[2] == 4 else a[..., 0]
    return img, a.astype(np.float32) / 255


def run(rgb, side=1024):
    """Probability 0..1 at side x side, input squashed to the square like the app."""
    x = cv2.resize(rgb, (side, side), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
    x = ((x - MEAN) / STD).transpose(2, 0, 1)[None]
    t = time.time()
    out = sess().run(None, {"input_image": np.ascontiguousarray(x)})[0][0, 0]
    run.last = time.time() - t
    if out.min() < 0 or out.max() > 1: out = 1 / (1 + np.exp(-out))
    return out.astype(np.float32)


def cached(key, fn):
    p = f"{CACHE}/{key}.npy"
    if os.path.exists(p): return np.load(p)
    v = fn(); np.save(p, v); return v


def iou(p, a, t=0.5):
    P = p > t; A = a > 0.5
    return (P & A).sum() / max(1, (P | A).sum()), (A & ~P).sum() / max(1, A.sum()), (P & ~A).sum() / max(1, (~A).sum())


def log(line):
    print(line, flush=True)
    with open(S + "/results.txt", "a") as f: f.write(line + "\n")
