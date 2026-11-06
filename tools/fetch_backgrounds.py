"""Builds Clearcut's photographic background library from CC0 photo-scanned surfaces (Poly Haven).

Every surface is a real photograph (diffuse/albedo map of a photoscan), licensed CC0.
Each is prepared to show about TARGET_M metres of real surface across the frame, at the
source's own resolution (never upscaled), so planks, grain and weave sit at a believable
scale under a flatlay product.

  python3 tools/fetch_backgrounds.py preview   # 2K versions of all candidates + contact sheet
  python3 tools/fetch_backgrounds.py final     # full-resolution library into Clearcut/Backdrops
"""
import io, json, os, sys, urllib.request
from PIL import Image

UA = {"User-Agent": "Clearcut-private-build/1.0 (personal app)"}
TARGET_M = 1.0          # metres of surface across the frame
MAX_SIDE = 4800         # pixels; enough for 24 MP iPhone photos when cropped to 4:3
OUT = "Clearcut/Backdrops"

# id, title, group  (curated: clean, flatlay-friendly surfaces)
CANDIDATES = [
    ("rosewood_veneer1", "Rosewood", "Wood"),
    ("wood_table_001", "Table oak", "Wood"),
    ("oak_veneer_01", "Oak veneer", "Wood"),
    ("dark_wood", "Dark wood", "Wood"),
    ("fine_grained_wood", "Fine grain", "Wood"),
    ("kitchen_wood", "Kitchen wood", "Wood"),
    ("wood_floor", "Floorboards", "Wood"),
    ("herringbone_parquet", "Parquet", "Wood"),
    ("marble_01", "Marble", "Stone"),
    ("granite_tile", "Granite", "Stone"),
    ("concrete_floor_02", "Concrete", "Stone"),
    ("brushed_concrete", "Brushed concrete", "Stone"),
    ("painted_concrete", "Painted concrete", "Stone"),
    ("white_stucco", "White stucco", "Plaster"),
    ("plastered_wall_05", "Plaster", "Plaster"),
    ("beige_wall_001", "Beige plaster", "Plaster"),
    ("rough_linen", "Linen", "Fabric"),
    ("hessian_230", "Hessian", "Fabric"),
    ("cotton_jersey", "Cotton jersey", "Fabric"),
    ("waffle_pique_cotton", "Waffle cotton", "Fabric"),
]

def get_json(u):
    return json.load(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=60))

def get_image(u):
    data = urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=600).read()
    Image.MAX_IMAGE_PIXELS = None
    return Image.open(io.BytesIO(data)).convert("RGB")

def prepare(src, size_m):
    """Crop (or seamlessly tile) to TARGET_M metres, never upscaling."""
    w, h = src.size
    px_per_m = w / size_m
    if size_m >= TARGET_M:
        crop = int(round(px_per_m * TARGET_M))
        x0, y0 = (w - crop) // 2, (h - crop) // 2
        img = src.crop((x0, y0, x0 + crop, y0 + crop))
    else:
        # small fabric swatches are seamless tiles: repeat to cover TARGET_M
        reps = TARGET_M / size_m
        tile_px = int(MAX_SIDE / reps) if px_per_m * TARGET_M > MAX_SIDE else w
        tile = src.resize((tile_px, tile_px), Image.LANCZOS) if tile_px != w else src
        n = int(reps) + 1
        canvas = Image.new("RGB", (tile_px * n, tile_px * n))
        for i in range(n):
            for j in range(n):
                canvas.paste(tile, (i * tile_px, j * tile_px))
        side = int(round(tile_px * reps))
        img = canvas.crop((0, 0, side, side))
    if img.size[0] > MAX_SIDE:
        img = img.resize((MAX_SIDE, MAX_SIDE), Image.LANCZOS)
    return img

def main(mode):
    os.makedirs("bg_preview", exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    library, thumbs = [], []
    for pid, title, group in CANDIDATES:
        try:
            info = get_json(f"https://api.polyhaven.com/info/{pid}")
            files = get_json(f"https://api.polyhaven.com/files/{pid}")["Diffuse"]
            size_m = max(info["dimensions"]) / 1000.0
            if mode == "preview":
                res = "2k"
            else:
                res = "8k"
                if files.get("8k") and (8192 / size_m) < MAX_SIDE / TARGET_M and "16k" in files:
                    res = "16k"
            url = files[res]["jpg"]["url"]
            src = get_image(url)
            img = prepare(src, size_m)
            print(f"BG {pid} {res} src={src.size} size_m={size_m:.2f} out={img.size}", flush=True)
            if mode == "preview":
                t = img.resize((300, 300), Image.LANCZOS)
                thumbs.append((pid, t))
            else:
                img.save(f"{OUT}/{pid}.jpg", quality=92, optimize=True)
                img.resize((240, 240), Image.LANCZOS).save(f"{OUT}/thumb-{pid}.jpg", quality=88)
                library.append({"id": pid, "title": title, "group": group, "source": f"https://polyhaven.com/a/{pid}",
                                "licence": "CC0", "metres": TARGET_M, "pixels": img.size[0]})
        except Exception as e:
            print(f"BG {pid} FAILED {e}", flush=True)
    if mode == "preview":
        from PIL import ImageDraw
        cols = 5
        rows = (len(thumbs) + cols - 1) // cols
        sheet = Image.new("RGB", (cols * 310, rows * 330), "white")
        d = ImageDraw.Draw(sheet)
        for i, (pid, t) in enumerate(thumbs):
            x, y = (i % cols) * 310, (i // cols) * 330
            sheet.paste(t, (x + 5, y + 5))
            d.text((x + 8, y + 308), pid, fill=(0, 0, 0))
        sheet.save("bg_preview/contact.jpg", quality=90)
    else:
        with open(f"{OUT}/library.json", "w") as f:
            json.dump({"surfaces": library}, f, indent=2)

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "preview")
