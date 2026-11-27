"""Adds one real photo and its reference cutout to the real-photo test set (QA/realset/).

  python3 tools/add_real_photo.py ORIGINAL REFERENCE.png NAME "what it is"

ORIGINAL   the photo as taken (JPEG or HEIC; HEIC needs pillow-heif).
REFERENCE  a transparent PNG of the same photo, cut out to the standard we want (for example
           Clearcut's transparent export after touch-up). Its transparency is the reference.
NAME       short folder name, e.g. black_coat_back_carpet.

The photo is turned upright, scaled to at most 3024 px on its long side, and saved fresh, so no
location or camera details are kept. The reference is matched to it. Writes photo.jpg, alpha.png,
fg.png and meta.json, the same format as the made-up scenes, so the bench scores it with every
measure. QA/real_scenes.py copies these into each quality run as scenes named R_<NAME>.
"""
import json
import os
import sys
from datetime import date

from PIL import Image, ImageOps

MAX_SIDE = 3024
ROOT = os.path.join(os.path.dirname(__file__), "..")


def open_any(path):
    if path.lower().endswith((".heic", ".heif")):
        import pillow_heif  # noqa: F401  (registers the HEIC opener)
        pillow_heif.register_heif_opener()
    return Image.open(path)


def main(original, reference, name, what):
    photo = ImageOps.exif_transpose(open_any(original)).convert("RGB")
    ref = ImageOps.exif_transpose(Image.open(reference)).convert("RGBA")
    pa, ra = photo.width / photo.height, ref.width / ref.height
    if abs(pa - ra) > 0.01 * pa:
        sys.exit(f"The reference ({ref.width}x{ref.height}) is not the same shape as the photo "
                 f"({photo.width}x{photo.height}); is it the same picture, uncropped?")
    k = min(1.0, MAX_SIDE / max(photo.size))
    size = (round(photo.width * k), round(photo.height * k))
    photo = photo.resize(size, Image.LANCZOS) if photo.size != size else photo
    ref = ref.resize(size, Image.LANCZOS) if ref.size != size else ref
    alpha = ref.getchannel("A")
    fg = Image.composite(ref.convert("RGB"), Image.new("RGB", size, 0), alpha)

    d = os.path.join(os.environ.get("CLEARCUT_REALSET", os.path.join(ROOT, "QA", "realset")), name)
    os.makedirs(d, exist_ok=True)
    photo.save(os.path.join(d, "photo.jpg"), quality=93, subsampling=0)   # fresh file: no EXIF
    alpha.save(os.path.join(d, "alpha.png"))
    fg.save(os.path.join(d, "fg.png"))
    covered = sum(alpha.histogram()[128:]) / (size[0] * size[1])
    meta = {"what": what, "added": date.today().isoformat(), "source": "Woolfall stock photo",
            "reference": os.path.basename(reference), "size": list(size), "itemShare": round(covered, 3)}
    json.dump(meta, open(os.path.join(d, "meta.json"), "w"), indent=1)
    print(f"added {name}: {size[0]}x{size[1]}, item covers {covered:.0%} of the frame")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    main(*sys.argv[1:])
