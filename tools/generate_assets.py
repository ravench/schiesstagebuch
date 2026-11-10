#!/usr/bin/env python3
"""Generates Resources/Calibers.json (catalogue + cartridge outlines) and
Resources/WeaponIcons.json from calibre-data/cartridges.py and tools/weapon_icons.py.

    python3 tools/generate_assets.py [--preview preview.html]

Outlines are side views in millimetres, base at the bottom, as SVG path data
(M/L/Z only) so the app can draw them with a tiny parser.
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(__file__))
# The calibre catalogue and the outline drawing live in the calibre-data submodule
# (github.com/ravench/calibre-data), shared with Kaliberfinder and the calibre poster.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "calibre-data"))
from cartridges import CATALOGUE, DISPLAY_ALIASES, PRIMERS, RIMFIRE, BALL, MINIE, PELLET  # noqa: E402
from outline import outline, bullet_profile  # noqa: E402
from weapon_icons import ICONS  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Schiesstagebuch", "Resources")
DATA = os.path.join(ROOT, "calibre-data")

# Measurements that define the chamber. Cartridges that agree on all of them fit the same
# barrel (e.g. .308 Win / 7.62 NATO), so the app suggests the others when one is picked.
CHAMBER_KEYS = ("kind", "rim", "base", "shoulder", "neck", "case", "sh_at", "bullet")


def calibre_data():
    """The calibre-data commit the catalogue is read from and its date, shown in the app's settings."""
    commit, date = subprocess.check_output(["git", "log", "-1", "--format=%H %cI"], cwd=DATA, text=True).split()
    return {"commit": commit, "date": date}


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


# Fills of cases that are not brass (Icons.swift uses the same colours).
CASE_COLOURS = {"copper": "#b87333", "steel": "#6b6a55", "nickel": "#c8cbce", "paper": "#f2ede0", "hybrid": "#e3c16f"}


def preview(calibers, icons, path):
    scale = 3.0
    cells = []
    for c in calibers:
        o = c["outline"]
        w, h = o["width"] * scale, o["height"] * scale
        parts = ""
        if "case" in o:
            parts += f'<path d="{o["case"]}" fill="{"#c0392b" if c["kind"] == "shot" else CASE_COLOURS.get(o.get("caseMaterial"), "#e3c16f")}" stroke="#333" stroke-width="0.25"/>'
        if "head" in o:
            parts += f'<path d="{o["head"]}" fill="{"#a7adb4" if o.get("headMaterial") == "steel" else "#e3c16f"}" stroke="#333" stroke-width="0.25"/>'
        if "bullet" in o:
            fill = {"steel": "#a7adb4", "plastic": "#edede6", "lead": "#8a8c91"}.get(o.get("bulletMaterial"), "#b87333" if "case" in o else "#8a8c91")
            parts += f'<path d="{o["bullet"]}" fill="{fill}" stroke="#333" stroke-width="0.25"/>'
        if "patch" in o:
            parts += f'<path d="{o["patch"]}" fill="#f2ede0" stroke="#333" stroke-width="0.25"/>'
        if "tip" in o:
            parts += f'<path d="{o["tip"]}" fill="{"#cc1a24" if o.get("tipMaterial") == "polymer" else "#8a8c91"}" stroke="#333" stroke-width="0.25"/>'
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
    json.dump({"version": 2, "calibreData": calibre_data(), "calibers": calibers}, open(os.path.join(OUT, "Calibers.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    json.dump({"icons": icons}, open(os.path.join(OUT, "WeaponIcons.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    if "--preview" in sys.argv:
        preview(calibers, icons, sys.argv[sys.argv.index("--preview") + 1])
    print(f"{len(calibers)} calibres, {len(icons)} icons")
