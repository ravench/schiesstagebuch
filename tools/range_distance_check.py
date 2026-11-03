"""One-off check: how well do swissTLM3D geometries give the true 300 m target distance?

For every 300 m lane it writes the 2D and 3D firing-line-to-target distance, and for a
few sample ranges it fetches SWISSIMAGE (10 cm aerial images, © swisstopo) with the
swissTLM3D house outline and target row drawn on top, so the geometry can be checked
by eye.

    python3 tools/range_distance_check.py swisstlm3d.gpkg out/
"""
import csv
import io
import json
import math
import os
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import range_catalogue as rc  # noqa: E402

SAMPLES = {
    "tlm:1763B245-5B9C-4C43-AB50-6FABE5993FD4": "thun-guntelsey",
    "tlm:08032DA2-3D40-4665-8B80-DE7865715B16": "zuerich-albisguetli",
    "tlm:595358EE-5326-4B1D-B13F-9E99A32A2C8E": "frauenfeld-schollenholz",
    "tlm:214EC227-4C40-440A-9E25-9CF63DB44E15": "liestal-sichtern",
    "tlm:795C7C56-D4DF-46A9-A960-D63270783BF7": "bern-riedbach",
    "tlm:3937B762-D6D6-4C99-ABA1-D1C210FF8221": "hinwil-betzholz",
    "tlm:158C44AA-9B92-4708-96E1-75A474FCEE9D": "ponto-valentino",
    "tlm:0299BD28-C4DD-4F3D-8852-7CFB2962DFB6": "oberdiessbach",
    "tlm:24305C6A-594D-469B-964A-99E2878ED8D3": "agiez",
    "tlm:5150A66F-4995-4DC3-BB7E-17EE8352CAF1": "venthone",
    "tlm:EA205066-998F-4C19-AB79-EE1DBC1A0D23": "le-pont",
    "tlm:62F3D5FD-ABDE-4A9D-BBBF-95D5798A9FDE": "hemmental",
}

WMS = ("https://wms.geo.admin.ch/?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
       "&LAYERS=ch.swisstopo.swissimage&STYLES=&CRS=EPSG:2056&FORMAT=image/jpeg"
       "&BBOX={0},{1},{2},{3}&WIDTH={4}&HEIGHT={5}")


def z_at(points, p):
    """Height of the polyline vertex nearest to p (None without Z)."""
    best = min(points, key=lambda q: rc.dist2(q, p))
    return best[2] if len(best) > 2 else None


def perpendicular(lane_target_line, firing):
    """Distance from the firing point to the (infinite) target row line, i.e. square to the targets."""
    a, b = lane_target_line[0], lane_target_line[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    return abs((firing[0] - a[0]) * dy - (firing[1] - a[1]) * dx) / length, length


def fetch(bbox, px):
    w = h = px
    url = WMS.format(*bbox, w, h)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            print("retry", e)
            time.sleep(2 ** attempt)
    raise RuntimeError(url)


def picture(path, center, size_m, px, house_rings, target_lines, marks):
    from PIL import Image, ImageDraw
    bbox = (center[0] - size_m / 2, center[1] - size_m / 2, center[0] + size_m / 2, center[1] + size_m / 2)
    img = Image.open(io.BytesIO(fetch(bbox, px))).convert("RGB")
    d = ImageDraw.Draw(img)
    scale = px / size_m

    def xy(p):
        return ((p[0] - bbox[0]) * scale, (bbox[3] - p[1]) * scale)

    for ring in house_rings:
        d.line([xy(p) for p in ring], fill=(255, 40, 40), width=2)
    for line in target_lines:
        d.line([xy(p) for p in line], fill=(0, 230, 255), width=2)
    for p in marks:
        x, y = xy(p)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(255, 255, 0), width=2)
    # 5 m scale bar
    d.line([(10, px - 12), (10 + 5 * scale, px - 12)], fill=(255, 255, 255), width=4)
    img.save(path, quality=88)


def main(gpkg, out):
    os.makedirs(out, exist_ok=True)
    houses, targets, trajectories, _ = rc.read_tlm(gpkg)
    lanes = rc.build_lanes(houses, targets, trajectories)
    ranges = rc.group_lanes(lanes)
    house_by_id = {}
    for h in houses:
        house_by_id.setdefault(h["id"], []).append(h["ring"])
    target_by_id = {t["id"]: t["line"] for t in targets}

    rows = []
    for rng in ranges:
        for lane in rng["lanes"]:
            if lane["distance"] != 300 or lane["source"] != "pairing":
                continue
            house_id, target_id = lane["ids"]
            line = target_by_id[target_id]
            ring = min(house_by_id[house_id], key=lambda r: rc.ring_distance(lane["target"], r))
            zf, zt = z_at(ring, lane["firing"]), z_at(line, lane["target"])
            dz = (zt - zf) if zf is not None and zt is not None else None
            d3 = math.hypot(lane["measured"], dz) if dz is not None else None
            perp, row_len = perpendicular(line, lane["firing"])
            rows.append({
                "range": rng["id"], "name": rng["tlm_name"], "house": house_id, "target": target_id,
                "d2": round(lane["measured"], 2), "d3": None if d3 is None else round(d3, 2),
                "dz": None if dz is None else round(dz, 2), "perp": round(perp, 2),
                "row_length": round(row_len, 1),
                "firing_e": round(lane["firing"][0], 2), "firing_n": round(lane["firing"][1], 2),
                "target_e": round(lane["target"][0], 2), "target_n": round(lane["target"][1], 2),
                "house_year": None,
            })
    with open(os.path.join(out, "lanes300.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(len(rows), "300 m lanes")

    samples = []
    for row in rows:
        slug = SAMPLES.get(row["range"])
        if not slug:
            continue
        n = sum(1 for s in samples if s["range"] == row["range"]) + 1
        slug = f"{slug}-{n}"
        rings = house_by_id[row["house"]]
        line = target_by_id[row["target"]]
        firing, target = (row["firing_e"], row["firing_n"]), (row["target_e"], row["target_n"])
        near = [t["line"] for t in targets if rc.dist2(rc.line_midpoint(t["line"]), target) < 60]
        near_houses = [h["ring"] for h in houses if rc.ring_distance(firing, h["ring"]) < 60]
        mid = ((firing[0] + target[0]) / 2, (firing[1] + target[1]) / 2)
        try:
            picture(os.path.join(out, f"{slug}-overview.jpg"), mid, 380, 760, near_houses, near, [firing, target])
            picture(os.path.join(out, f"{slug}-firing.jpg"), firing, 50, 500, near_houses, [], [firing])
            picture(os.path.join(out, f"{slug}-target.jpg"), target, 50, 500, [], near, [target])
        except Exception as e:  # noqa: BLE001
            print("image failed", slug, e)
        row = dict(row, slug=slug, rings=rings, line=line)
        samples.append(row)
    with open(os.path.join(out, "samples.json"), "w", encoding="utf-8") as f:
        json.dump(samples, f, ensure_ascii=False, indent=1)
    print(len(samples), "sample lanes")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
