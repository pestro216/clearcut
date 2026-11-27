"""Side-by-side comparison of two quality runs, photo by photo, for deciding whether a change ships.

  python3 tools/compare_runs.py RUN_A RUN_B [OUTDIR]

RUN_A, RUN_B  quality run numbers (as on the qa-results branch: runs/<number>), A the build we
              have, B the candidate. Run `git fetch origin qa-results` first.
OUTDIR        default QA/compare/<A>-vs-<B> (not kept in git).

Writes index.html: for every scene (real photos first), the finished render from each run next to
each other, and every measure with the better side marked. Scenes whose reference is a real photo
(R_...) decide; made-up scenes are a safety net.
"""
import html
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
# (key, label, higher is better, decimals)
MEASURES = [("iou", "Outline overlap", True, 4), ("boundaryF", "Edge position", True, 3),
            ("bandMAE", "Edge transparency error", False, 3), ("missedItem", "Item cut away", False, 4),
            ("keptBackground", "Background left", False, 4), ("edgeDeltaE", "Edge colour error", False, 2),
            ("edgeDeltaE95", "Worst edge spots", False, 2), ("gradient", "Feathering (gradient)", False, 2),
            ("connectivity", "Blotches (connectivity)", False, 2)]


def git_show(path):
    r = subprocess.run(["git", "-C", ROOT, "show", f"origin/qa-results:{path}"], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def run_scores(run):
    raw = git_show(f"runs/{run}/results.json")
    if raw is None:
        sys.exit(f"No results for run {run} on qa-results (try: git fetch origin qa-results)")
    return {name: m.get("new", {}) for name, m in json.loads(raw)["scores"].items()}


def main(a, b, out):
    sa, sb = run_scores(a), run_scores(b)
    os.makedirs(out, exist_ok=True)
    names = sorted(set(sa) | set(sb), key=lambda n: (not n.startswith("R_"), n))
    wins = {"A": 0, "B": 0}
    rows = []
    for name in names:
        imgs = []
        for run in (a, b):
            data = git_show(f"runs/{run}/finished_{name}.jpg")
            fn = f"{run}_{name}.jpg"
            if data:
                open(os.path.join(out, fn), "wb").write(data)
                imgs.append(f'<figure><img src="{html.escape(fn)}" loading="lazy"><figcaption>Run {run}</figcaption></figure>')
            else:
                imgs.append(f"<figure><div class=missing>No image</div><figcaption>Run {run}</figcaption></figure>")
        cells = []
        for key, label, up, dp in MEASURES:
            va, vb = sa.get(name, {}).get(key), sb.get(name, {}).get(key)
            if va is None or vb is None:
                cells.append(f"<tr><td>{label}</td><td>{'' if va is None else round(va, dp)}</td><td>{'' if vb is None else round(vb, dp)}</td><td></td></tr>")
                continue
            tol = 10 ** -dp
            verdict = ""
            if abs(va - vb) > tol:
                better_b = (vb > va) if up else (vb < va)
                verdict = "B better" if better_b else "A better"
                if name.startswith("R_"):
                    wins["B" if better_b else "A"] += 1
            cls = {"B better": "b", "A better": "a"}.get(verdict, "")
            cells.append(f"<tr class={cls}><td>{label}</td><td>{va:.{dp}f}</td><td>{vb:.{dp}f}</td><td>{verdict}</td></tr>")
        kind = "Real photo" if name.startswith("R_") else "Made-up scene"
        rows.append(f"<section><h2>{html.escape(name)} <small>{kind}</small></h2><div class=pair>{''.join(imgs)}</div>"
                    f"<table><tr><th>Measure</th><th>Run {a} (A)</th><th>Run {b} (B)</th><th></th></tr>{''.join(cells)}</table></section>")
    page = f"""<!doctype html><html><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Clearcut run {a} vs {b}</title><style>
:root{{--paper:#f3f1ec;--ink:#1c1b19;--muted:#6b6961;--line:#d6d1c9;--a:#9e521a;--b:#2f6b3a}}
body{{margin:0;background:var(--paper);color:var(--ink);font:15px/1.45 -apple-system,system-ui,sans-serif;padding:16px}}
h1{{font-size:22px}} h2{{font-size:17px;margin:28px 0 8px}} small{{color:var(--muted);font-weight:400}}
.pair{{display:grid;grid-template-columns:1fr 1fr;gap:10px}} figure{{margin:0}} img{{width:100%;border:1px solid var(--line)}}
figcaption{{color:var(--muted);font-size:13px}} .missing{{aspect-ratio:4/3;border:1px dashed var(--line)}}
table{{border-collapse:collapse;margin-top:8px;width:100%;max-width:720px}} td,th{{border-bottom:1px solid var(--line);padding:4px 8px;text-align:left}}
tr.a td:last-child{{color:var(--a)}} tr.b td:last-child{{color:var(--b)}}
</style></head><body><h1>Run {a} (A, current) against run {b} (B, candidate)</h1>
<p>Real photos: B better on {wins['B']} measures, A better on {wins['A']}. Real photos are listed first and decide; look at every image, not only the numbers.</p>
{''.join(rows)}</body></html>"""
    open(os.path.join(out, "index.html"), "w").write(page)
    print(f"wrote {out}/index.html ({len(names)} scenes; real photos: B better {wins['B']}, A better {wins['A']})")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    a, b = sys.argv[1], sys.argv[2]
    main(a, b, sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, "QA", "compare", f"{a}-vs-{b}"))
