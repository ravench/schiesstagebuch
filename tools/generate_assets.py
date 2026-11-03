#!/usr/bin/env python3
"""Generates Resources/Calibers.json (catalogue + cartridge outlines) and
Resources/WeaponIcons.json from tools/cartridges.py and tools/weapon_icons.py.

    python3 tools/generate_assets.py [--preview preview.html]

Outlines are side views in millimetres, base at the bottom, as SVG path data
(M/L/Z only) so the app can draw them with a tiny parser.
"""
import json, math, os, sys

sys.path.insert(0, os.path.dirname(__file__))
from cartridges import CATALOGUE, DISPLAY_ALIASES, PRIMERS, RIMLESS, RIMMED, BELTED, RIMFIRE, SHOT, BALL, MINIE, PELLET, SPITZER, ROUND, FLAT, PATCHED
from weapon_icons import ICONS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Schiesstagebuch", "Resources")
N = 14  # samples per curve


def case_profile(s):
    """Right half of the case, bottom to top, as (radius, height)."""
    rim, base, case = s["rim"] / 2, s["base"] / 2, s["case"]
    k = s["kind"]
    if k in (RIMMED, RIMFIRE):
        h = 1.1 if k == RIMFIRE else 1.5
        pts = [(rim, 0), (rim, h), (base, h)]
    else:
        groove = base * 0.82
        pts = [(rim, 0), (rim, 1.3), (groove, 1.3), (groove, 2.6), (base, 3.3)]
        if k == BELTED:
            pts[-1] = (rim, 3.3)
            pts += [(rim, 6.2), (base * 0.985, 6.2)]
    top = s["neck"] / 2
    if s["shoulder"]:
        sh = s["shoulder"] / 2
        run = max(0.8, (sh - top) / math.tan(math.radians(32)))
        sh_at = min(s["sh_at"], case - run - 1.2)
        pts += [(sh, sh_at), (top, sh_at + run), (top, case)]
    else:
        pts += [(top, case)]
    return pts


def bullet_profile(r, y0, top, profile):
    """Right half of the exposed bullet from (r, y0) to the tip at `top`."""
    e = top - y0
    if profile == SPITZER:
        cyl, tip, f = 0.32, 0.05, lambda t: (1 - t ** 1.7) ** 0.8
    elif profile == ROUND:
        cyl, tip, f = 0.22, 0.16, lambda t: math.sqrt(max(0, 1 - t * t))
    elif profile == PATCHED:
        # Long parallel body, then a blunt round nose. The steel cap sits a paper's thickness
        # (about 0.06 mm) inside the patched body, so the outline steps in where the paper ends.
        band, cap = PATCH_BAND * e, r - 0.06
        pts = [(r, y0), (r, y0 + band), (cap, y0 + band)]
        start = y0 + 0.40 * e
        for i in range(1, N + 1):
            t = i / N
            pts.append((max(cap * 0.14, cap * math.sqrt(max(0, 1 - t * t))), start + t * (top - start)))
        return pts + [(0, top)]
    else:
        cyl, tip, f = 0.30, 0.55, lambda t: math.sqrt(max(0, 1 - t * t))
    start = y0 + cyl * e
    pts = [(r, y0), (r, start)]
    for i in range(1, N + 1):
        t = i / N
        pts.append((max(r * tip, r * f(t)), start + t * (top - start)))
    if pts[-1][0] > 0.001:
        pts.append((0, top))
    return pts


# Share of the exposed bullet that shows the paper patch (GP 1890), from the case mouth up.
PATCH_BAND = 0.26


def patch_profile(r, y0, top):
    """Right half of the paper band of a PATCHED bullet, drawn over the bullet."""
    return [(r, y0), (r, y0 + PATCH_BAND * (top - y0))]


def mirror(right):
    """Closed polygon from a right half profile (x >= 0)."""
    left = [(-x, y) for x, y in reversed(right) if x > 0.0001]
    return right + left


def to_path(poly, height, half_width):
    d = []
    for i, (x, y) in enumerate(poly):
        d.append(f"{'M' if i == 0 else 'L'}{x + half_width:.2f} {height - y:.2f}")
    return " ".join(d) + " Z"


def outline(s):
    k = s["kind"]
    width = max(s["rim"], s["base"], s["bullet"])
    hw = width / 2
    H = s["oal"]
    paths = {}
    if k == SHOT:
        r, rim, L = s["base"] / 2, s["rim"] / 2, s["case"]
        head = 0.2 * L
        hull = [(r * 0.98, 1.5), (r * 0.98, L - 2.2), (r * 0.8, L - 0.6), (r * 0.35, L)]
        paths["case"] = to_path(mirror(hull), H, hw)
        paths["head"] = to_path(mirror([(rim, 0), (rim, 1.5), (r, 1.5), (r, head)]), H, hw)
    elif k == BALL:
        r = s["bullet"] / 2
        circ = [(r * math.sin(math.pi * i / (2 * N)), r - r * math.cos(math.pi * i / (2 * N))) for i in range(0, 2 * N + 1)]
        circ[0] = (0.0001, 0)
        paths["bullet"] = to_path(mirror(circ), H, hw)
    elif k == MINIE:
        r, L = s["bullet"] / 2, s["oal"]
        right = [(r * 0.94, 0), (r, 1.0)] + bullet_profile(r, 0.45 * L, L, ROUND)[0:]
        paths["bullet"] = to_path(mirror(right), H, hw)
    elif k == PELLET:
        r, L = s["bullet"] / 2, s["oal"]
        right = [(r, 0), (r * 0.9, 0.18 * L), (r * 0.6, 0.5 * L), (r * 0.62, 0.58 * L), (r, 0.66 * L)]
        right += [(max(0.15 * r, r * math.cos(math.pi / 2 * i / N)), 0.66 * L + 0.34 * L * math.sin(math.pi / 2 * i / N)) for i in range(1, N + 1)]
        right.append((0, L))
        paths["bullet"] = to_path(mirror(right), H, hw)
    else:
        prof = case_profile(s)
        paths["case"] = to_path(mirror(prof), H, hw)
        if s["oal"] > s["case"] + 0.1:
            paths["bullet"] = to_path(mirror(bullet_profile(s["bullet"] / 2, s["case"], s["oal"], s["profile"])), H, hw)
            if s["profile"] == PATCHED:
                # The bullet path is the whole silhouette (steel cap colour); the paper band goes on top.
                paths["patch"] = to_path(mirror(patch_profile(s["bullet"] / 2, s["case"], s["oal"])), H, hw)
                paths["bulletMaterial"] = "steel"
    return {"width": round(width, 2), "height": round(H, 2), **paths}


# Measurements that define the chamber. Cartridges that agree on all of them fit the same
# barrel (e.g. .308 Win / 7.62 NATO), so the app suggests the others when one is picked.
CHAMBER_KEYS = ("kind", "rim", "base", "shoulder", "neck", "case", "sh_at", "bullet")


def dimension_groups():
    """Calibre name -> group id (first name of the group) for cartridges with identical measurements."""
    groups = {}
    for _, items in CATALOGUE:
        for s in items:
            groups.setdefault(tuple(s[k] for k in CHAMBER_KEYS), []).append(s["name"])
    return {name: names[0] for names in groups.values() if len(names) > 1 for name in names}


def build():
    calibers = []
    groups = dimension_groups()
    for category, items in CATALOGUE:
        for s in items:
            item = {"id": s["name"], "name": s["name"], "category": category,
                    "aliases": s["aliases"], "displayAliases": DISPLAY_ALIASES.get(s["name"], []),
                    "kind": s["kind"], "outline": outline(s)}
            if s["name"] in groups:
                item["dimensionGroup"] = groups[s["name"]]
            calibers.append(item)
    names = {c["name"] for c in calibers}
    unknown = set(DISPLAY_ALIASES) - names
    assert not unknown, f"DISPLAY_ALIASES for unknown calibres: {unknown}"
    # Primer data is used by the Kaliberfinder app, which shares this file.
    centrefire = {s["name"] for _, items in CATALOGUE for s in items if s["kind"] not in (RIMFIRE, BALL, MINIE, PELLET)}
    assert set(PRIMERS) == centrefire, f"PRIMERS mismatch: {set(PRIMERS) ^ centrefire}"
    icons = [{"id": k, **v} for k, v in ICONS.items()]
    return calibers, icons


def preview(calibers, icons, path):
    scale = 3.0
    cells = []
    for c in calibers:
        o = c["outline"]
        w, h = o["width"] * scale, o["height"] * scale
        parts = ""
        if "case" in o:
            parts += f'<path d="{o["case"]}" fill="{"#c0392b" if c["kind"] == "shot" else "#e3c16f"}" stroke="#333" stroke-width="0.25"/>'
        if "head" in o:
            parts += f'<path d="{o["head"]}" fill="#e3c16f" stroke="#333" stroke-width="0.25"/>'
        if "bullet" in o:
            fill = "#a7adb4" if o.get("bulletMaterial") == "steel" else "#b87333"
            parts += f'<path d="{o["bullet"]}" fill="{fill}" stroke="#333" stroke-width="0.25"/>'
        if "patch" in o:
            parts += f'<path d="{o["patch"]}" fill="#f2ede0" stroke="#333" stroke-width="0.25"/>'
        cells.append(f'<div class=c><svg width="{w}" height="{h}" viewBox="0 0 {o["width"]} {o["height"]}">{parts}</svg><span>{c["name"]}</span></div>')
    icon_cells = []
    for i in icons:
        solids = "".join(f'<path d="{d}"/>' for d in i["solids"])
        holes = "".join(f'<path d="{d}" fill="black"/>' for d in i.get("holes", []))
        icon_cells.append(f'''<div class=i><svg width="256" height="96" viewBox="0 0 128 48">
<mask id="m{i["id"]}"><rect width="128" height="48" fill="white"/>{holes}</mask>
<g fill="#222" mask="url(#m{i["id"]})">{solids}</g></svg><span>{i["title"]}</span></div>''')
    html = f"""<!doctype html><meta charset=utf-8><style>body{{font:11px sans-serif;background:#fff}}
.g{{display:flex;flex-wrap:wrap;align-items:flex-end;gap:10px}}.c{{display:flex;flex-direction:column;align-items:center;width:90px}}
.c span{{text-align:center;margin-top:4px}}.i{{display:inline-flex;flex-direction:column;align-items:center;margin:8px;border:1px solid #eee}}</style>
<div>{''.join(icon_cells)}</div><div class=g>{''.join(cells)}</div>"""
    open(path, "w").write(html)


if __name__ == "__main__":
    calibers, icons = build()
    os.makedirs(OUT, exist_ok=True)
    json.dump({"version": 2, "calibers": calibers}, open(os.path.join(OUT, "Calibers.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    json.dump({"icons": icons}, open(os.path.join(OUT, "WeaponIcons.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    if "--preview" in sys.argv:
        preview(calibers, icons, sys.argv[sys.argv.index("--preview") + 1])
    print(f"{len(calibers)} calibres, {len(icons)} icons")
