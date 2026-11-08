"""Downloads a varied set of openly licensed clothing and accessory photos for blind testing.

Source: Openverse (api.openverse.org), restricted to CC0, public domain and CC BY / BY-SA, which
allow copying with credit. The manifest records title, creator, licence and source for each photo;
contact sheets made from them keep that credit in the report.

Not committed to the repository: fetched fresh (and cached) on the test Mac.
Usage: python3 QA/fetch_webset.py <output dir> [per query]
"""
import json, os, sys, time, urllib.parse, urllib.request
from io import BytesIO

from PIL import Image

QUERIES = [
    # Tops
    "t-shirt flat lay", "folded shirt", "hoodie product photo", "knitted sweater", "cardigan", "blouse",
    "polo shirt", "tank top", "sequin top", "lace top", "denim jacket", "leather jacket", "fur coat",
    "puffer jacket", "wool coat", "blazer", "waistcoat", "fleece jacket",
    # Bottoms and dresses
    "jeans flat lay", "trousers", "shorts", "skirt", "pleated skirt", "dress on hanger", "summer dress",
    "evening gown", "jumpsuit", "swimsuit",
    # Headwear
    "baseball cap", "beanie hat", "fedora hat", "straw hat", "bucket hat", "flat cap",
    # Footwear
    "sneakers", "trainers white", "leather boots", "ankle boots", "high heels", "sandals",
    "slippers", "football boots", "wellington boots",
    # Accessories
    "handbag", "backpack", "leather belt", "necktie", "scarf", "gloves", "socks", "sunglasses",
    "wristwatch", "necklace", "bow tie",
    # Hard cases
    "white shirt on white background", "black shoes dark background", "fluffy slippers",
    "mohair sweater", "mesh top", "tulle skirt", "children's clothes",
]
LICENCES = "cc0,pdm,by,by-sa"


def get(url, tries=3):
    for k in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Clearcut-QA/1.0 (test set builder)"})
            with urllib.request.urlopen(req, timeout=40) as r:
                return r.read()
        except Exception as e:
            if k == tries - 1:
                raise
            time.sleep(2 + 3 * k)


def main(out, per=2):
    os.makedirs(out, exist_ok=True)
    manifest_path = os.path.join(out, "manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {}
    seen = {m["source"] for m in manifest.values()}
    for qi, q in enumerate(QUERIES):
        have = sum(1 for m in manifest.values() if m["query"] == q)
        if have >= per:
            continue
        params = urllib.parse.urlencode({"q": q, "license": LICENCES, "page_size": 12, "size": "large",
                                         "category": "photograph", "mature": "false"})
        try:
            res = json.loads(get(f"https://api.openverse.org/v1/images/?{params}"))["results"]
        except Exception as e:
            print(f"search failed for {q}: {e}")
            continue
        for r in res:
            if have >= per:
                break
            src = r.get("url")
            if not src or src in seen:
                continue
            try:
                im = Image.open(BytesIO(get(src))).convert("RGB")
            except Exception:
                continue
            if min(im.size) < 700:
                continue
            if max(im.size) > 3000:
                k = 3000 / max(im.size)
                im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            name = f"web_{qi:02d}_{have}.jpg"
            im.save(os.path.join(out, name), quality=92)
            manifest[name] = {"query": q, "title": r.get("title"), "creator": r.get("creator"),
                              "licence": f"{r.get('license')} {r.get('license_version') or ''}".strip(),
                              "source": src, "page": r.get("foreign_landing_url")}
            seen.add(src)
            have += 1
            print(f"{name}: {q}", flush=True)
        time.sleep(1.2)
        json.dump(manifest, open(manifest_path, "w"), indent=1)
    json.dump(manifest, open(manifest_path, "w"), indent=1)
    print(f"{len(manifest)} photos")


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 2)
