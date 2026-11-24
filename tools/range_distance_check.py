"""One-off check: how well do swissTLM3D geometries give the true firing-line-to-target distance?

Second attempt (2026-11-24). For every target row (TLM_SPORTBAUTE_LIN "Scheibenstand") it
finds the shooting house it is shot from and measures the distance three ways:

* nearest: target row midpoint to the nearest point of the house outline (first attempt),
* square:  that house point to the (infinite) target row line, i.e. square to the targets,
           which is how a range is laid out,
* 3D:      square distance with the height difference from the TLM Z values.

Pairing, which went wrong in the first attempt (a 50 m house in front of a 300 m house),
now prefers a house whose name lists the lane's distance and whose outline lies across
from the target row (lateral overlap), before the nearest one.

The 50 m lanes are the accuracy check: they are almost always laid out at exactly 50 m.

    python3 tools/range_distance_check.py swisstlm3d.gpkg out/
"""
import csv
import io
import json
import math
import os
import statistics
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
import range_catalogue as rc  # noqa: E402

WMS = ("https://wms.geo.admin.ch/?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap"
       "&LAYERS=ch.swisstopo.swissimage&STYLES=&CRS=EPSG:2056&FORMAT=image/jpeg"
       "&BBOX={0},{1},{2},{3}&WIDTH={4}&HEIGHT={5}")

FACING_DEGREES = 25.0
MAX_FRONT = 400.0
MIN_FRONT = 5.0


def z_at(points, p):
    best = min(points, key=lambda q: rc.dist2(q, p))
    return best[2] if len(best) > 2 else None


def row_frame(line):
    """Unit vector along the row and its start point."""
    a, b = line[0], line[-1]
    dx, dy = b[0] - a[0], b[1] - a[1]
    length = math.hypot(dx, dy)
    return (a[0], a[1]), (dx / length, dy / length), length


def square_distance(line, p):
    a, u, _ = row_frame(line)
    return abs((p[0] - a[0]) * u[1] - (p[1] - a[1]) * u[0])


def overlap(line, ring):
    """Share of the target row that has the house straight across from it (0..1)."""
    a, u, length = row_frame(line)
    ts = [(q[0] - a[0]) * u[0] + (q[1] - a[1]) * u[1] for q in ring]
    lo, hi = max(0.0, min(ts)), min(length, max(ts))
    return max(0.0, hi - lo) / length if length else 0.0


def candidates(target, houses):
    line = target["line"]
    mid = rc.line_midpoint(line)
    a, u, length = row_frame(line)
    normal = (-u[1], u[0])
    cos_limit = math.cos(math.radians(FACING_DEGREES))
    out = []
    for h in houses:
        c = rc.centroid(h["ring"])
        vx, vy = mid[0] - c[0], mid[1] - c[1]
        span = math.hypot(vx, vy)
        if span == 0 or span > MAX_FRONT + 80:
            continue
        if abs((vx * normal[0] + vy * normal[1]) / span) < cos_limit:
            continue
        firing = rc.nearest_point_on_ring(mid, h["ring"])
        nearest = rc.dist2(firing, mid)
        if not MIN_FRONT <= nearest <= MAX_FRONT:
            continue
        square = square_distance(line, firing)
        nominal = rc.snap_distance(square) or rc.snap_distance(nearest)
        out.append({
            "house": h, "firing": firing, "nearest": nearest, "square": square, "nominal": nominal,
            "named": nominal in rc.name_distances(h.get("name")),
            "overlap": overlap(line, h["ring"]),
        })
    return out


def choose(cands, short_houses=()):
    """A house whose name lists the distance, then the nearest.

    A house that is the firing house of a 25 or 50 m row is skipped for a longer row when
    another house of the range faces it too: that's a pistol stand in front of the 300 m house.
    """
    if not cands:
        return None
    longer = [c for c in cands if not (c["house"]["id"] in short_houses and (c["nominal"] or 0) >= 100)]
    if len(longer) < len(cands) and any(c["named"] for c in longer):
        cands = longer
    return min(cands, key=lambda c: (not c["named"], c["nearest"]))


LK = "ch.swisstopo.pixelkarte-farbe"
MAP_RES = 0.5  # metres per pixel


def map_line_hits(line, cands):
    """Where the dotted shooting lines of the 1:25 000 map (raster) end at a building.

    From five points along the target row it walks square to the row towards the houses while
    there is a black dot within 3 m to the side (gaps up to 14 m), and stops where it reaches
    solid black (a building). Returns the hit points (LV95) and their distances from the row.
    """
    from PIL import Image
    a, u, length = row_frame(line)
    n = (-u[1], u[0])
    cx = sum(c["firing"][0] for c in cands) / len(cands)
    cy = sum(c["firing"][1] for c in cands) / len(cands)
    if (cx - a[0]) * n[0] + (cy - a[1]) * n[1] < 0:
        n = (-n[0], -n[1])
    pts = [line[0], line[-1]] + [c["firing"] for c in cands]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    size = max(max(xs) - min(xs), max(ys) - min(ys)) + 80
    px = min(2000, int(size / MAP_RES))
    centre = ((max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2)
    bbox = (centre[0] - size / 2, centre[1] - size / 2, centre[0] + size / 2, centre[1] + size / 2)
    img = Image.open(io.BytesIO(fetch(bbox, px, LK))).convert("RGB")
    pix = img.load()
    scale = px / size

    def dark(p):
        x, y = int((p[0] - bbox[0]) * scale), int((bbox[3] - p[1]) * scale)
        if not (0 <= x < px and 0 <= y < px):
            return None
        r, g, b = pix[x, y]
        return max(r, g, b) < 90 and max(r, g, b) - min(r, g, b) < 40

    def solid(p):
        hits = total = 0
        for i in range(-2, 3):
            for j in range(-2, 3):
                d = dark((p[0] + i * 0.4, p[1] + j * 0.4))
                total += 1
                hits += bool(d)
        return hits >= 0.8 * total

    out = []
    for f in (0.2, 0.35, 0.5, 0.65, 0.8):
        p0 = (a[0] + u[0] * f * length, a[1] + u[1] * f * length)
        # The walk follows the dots sideways, since the map's lines aren't always square to the row.
        s, last, dots, off = 6.0, 6.0, 0, 0.0
        while s < MAX_FRONT + 20:
            p = (p0[0] + n[0] * s + u[0] * off, p0[1] + n[1] * s + u[1] * off)
            if dark(p) is None:
                break
            if dots >= 4 and solid(p):
                out.append((p, s))
                break
            found = [k for k in sorted(range(-8, 9), key=abs)
                     if dark((p[0] + u[0] * k * 0.5, p[1] + u[1] * k * 0.5))]
            if found:
                if s - last > 1.0:
                    dots += 1
                    off += found[0] * 0.25
                last = s
            elif s - last > 20:
                break
            s += 0.5
    return out


def map_choice(line, cands):
    """The candidate house the map's shooting lines lead to, and the map distance; (None, None) if unclear."""
    try:
        hits = map_line_hits(line, cands)
    except Exception as e:  # noqa: BLE001
        print("map failed", e)
        return None, None
    votes = {}
    for p, _ in hits:
        c = min(cands, key=lambda c: rc.ring_distance(p, c["house"]["ring"]))
        if rc.ring_distance(p, c["house"]["ring"]) < 15:
            votes[c["house"]["id"]] = votes.get(c["house"]["id"], 0) + 1
    if not votes:
        return None, None
    best_id = max(votes, key=votes.get)
    if votes[best_id] < 2:
        return None, None
    dists = sorted(s for _, s in hits)
    return next(c for c in cands if c["house"]["id"] == best_id), dists[len(dists) // 2]


def stats(values):
    if not values:
        return {}
    v = sorted(values)
    q = statistics.quantiles(v, n=20) if len(v) >= 20 else [v[0]] * 19
    return {
        "n": len(v), "median": round(statistics.median(v), 2), "mean": round(statistics.fmean(v), 2),
        "p5": round(q[0], 2), "p25": round(q[4], 2), "p75": round(q[14], 2), "p95": round(q[18], 2),
    }


def fetch(bbox, px, layer="ch.swisstopo.swissimage"):
    url = WMS.format(*bbox, px, px).replace("ch.swisstopo.swissimage", layer)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            print("retry", e)
            time.sleep(2 ** attempt)
    raise RuntimeError(url)


def picture(path, center, size_m, px, rings, lines, marks):
    from PIL import Image, ImageDraw
    bbox = (center[0] - size_m / 2, center[1] - size_m / 2, center[0] + size_m / 2, center[1] + size_m / 2)
    img = Image.open(io.BytesIO(fetch(bbox, px))).convert("RGB")
    d = ImageDraw.Draw(img)
    scale = px / size_m

    def xy(p):
        return ((p[0] - bbox[0]) * scale, (bbox[3] - p[1]) * scale)

    for ring in rings:
        d.line([xy(p) for p in ring], fill=(255, 40, 40), width=2)
    for line in lines:
        d.line([xy(p) for p in line], fill=(0, 230, 255), width=2)
    for p in marks:
        x, y = xy(p)
        d.ellipse((x - 4, y - 4, x + 4, y + 4), outline=(255, 255, 0), width=2)
    d.line([(10, px - 12), (10 + 5 * scale, px - 12)], fill=(255, 255, 255), width=4)  # 5 m
    img.save(path, quality=88)


def main(gpkg, out):
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "inspect.txt"), "w", encoding="utf-8") as f:
        rc.inspect_tlm(gpkg, f)
    houses, targets, trajectories, _ = rc.read_tlm(gpkg)
    print(len(houses), "house rings,", len(targets), "target rows,", len(trajectories), "trajectories")

    rows, ambiguous = [], []
    cands_by_target = {t["id"]: candidates(t, houses) for t in targets}
    short_houses = set()
    for cands in cands_by_target.values():
        first = choose(cands)
        if first and first["nominal"] in (25, 50) and first["overlap"] >= 0.3:
            short_houses.add(first["house"]["id"])
    for t in targets:
        cands = cands_by_target[t["id"]]
        best = choose(cands, short_houses)
        if best is None:
            continue
        rule = best
        mapped, map_distance = map_choice(t["line"], cands) if len(cands) > 1 else (None, None)
        if mapped is not None:
            best = mapped
        old = min(cands, key=lambda c: c["nearest"])
        line = t["line"]
        mid = rc.line_midpoint(line)
        zf, zt = z_at(best["house"]["ring"], best["firing"]), z_at(line, mid)
        dz = (zt - zf) if zf is not None and zt is not None else None
        _, _, row_len = row_frame(line)
        # swisstopo's own trajectory line ("Schusslinie") ending at this row, if any.
        traj = min((tr for tr in trajectories
                    if min(square_distance(line, tr["line"][0]), square_distance(line, tr["line"][-1])) < 15
                    and min(rc.dist2(tr["line"][0], mid), rc.dist2(tr["line"][-1], mid)) < row_len / 2 + 20),
                   key=lambda tr: min(rc.dist2(tr["line"][0], mid), rc.dist2(tr["line"][-1], mid)), default=None)
        row = {
            "target": t["id"], "house": best["house"]["id"], "name": best["house"].get("name") or "",
            "nominal": best["nominal"], "nearest": round(best["nearest"], 2), "square": round(best["square"], 2),
            "d3": round(math.hypot(best["square"], dz), 2) if dz is not None else None,
            "dz": round(dz, 2) if dz is not None else None,
            "named": best["named"], "overlap": round(best["overlap"], 2), "row_length": round(row_len, 1),
            "candidates": len(cands), "changed": old["house"]["id"] != best["house"]["id"],
            "old_nearest": round(old["nearest"], 2),
            "rule_house": rule["house"]["id"], "map_changed": rule["house"]["id"] != best["house"]["id"],
            "map_found": mapped is not None, "rule_square": round(rule["square"], 2),
            "map_distance": round(map_distance, 1) if map_distance is not None else None,
            "trajectory": round(rc.dist2(traj["line"][0], traj["line"][-1]), 2) if traj else None,
            "firing_e": round(best["firing"][0], 2), "firing_n": round(best["firing"][1], 2),
            "target_e": round(mid[0], 2), "target_n": round(mid[1], 2),
        }
        rows.append(row)
        if len(cands) > 1:
            ambiguous.append({"target": t["id"], "chosen": best["house"]["id"], "cands": [
                {k: (round(v, 2) if isinstance(v, float) else v) for k, v in c.items() if k not in ("house", "firing")}
                | {"house": c["house"]["id"], "name": c["house"].get("name")} for c in cands]})

    with open(os.path.join(out, "lanes.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    with open(os.path.join(out, "ambiguous.json"), "w", encoding="utf-8") as f:
        json.dump(ambiguous, f, ensure_ascii=False, indent=1)

    summary = {}
    for nominal in (10, 25, 50, 100, 300):
        lanes = [r for r in rows if r["nominal"] == nominal]
        summary[nominal] = {
            "lanes": len(lanes),
            "named": sum(r["named"] for r in lanes),
            "pairing_changed": sum(r["changed"] for r in lanes),
            "nearest": stats([r["nearest"] - nominal for r in lanes]),
            "square": stats([r["square"] - nominal for r in lanes]),
            "d3": stats([r["d3"] - nominal for r in lanes if r["d3"] is not None]),
            "trajectory": stats([r["trajectory"] - nominal for r in lanes if r["trajectory"] is not None]),
            "within_0_5": sum(abs(r["square"] - nominal) <= 0.5 for r in lanes),
            "within_1": sum(abs(r["square"] - nominal) <= 1 for r in lanes),
            "within_2": sum(abs(r["square"] - nominal) <= 2 for r in lanes),
            "within_5": sum(abs(r["square"] - nominal) <= 5 for r in lanes),
        }
    with open(os.path.join(out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=1)
    print(json.dumps(summary, indent=1))

    # Hand check: 300 m targets where the candidate houses differ by more than 3 m and the map line
    # wasn't found. Photo and 1:25 000 map side by side, candidates numbered, two lanes per sheet.
    from PIL import Image, ImageDraw
    colours = [(255, 40, 40), (40, 255, 40), (255, 220, 0), (255, 0, 255), (0, 160, 255), (255, 140, 0)]
    todo = []
    for t in targets:
        r = next((x for x in rows if x["target"] == t["id"]), None)
        if not r or r["nominal"] != 300 or r["map_found"]:
            continue
        c3 = [c for c in cands_by_target[t["id"]] if c["nominal"] == 300]
        if len(c3) < 2 or max(c["square"] for c in c3) - min(c["square"] for c in c3) <= 3:
            continue
        todo.append((r, t, sorted(c3, key=lambda c: c["square"])[:6]))
    print(len(todo), "lanes to check by hand")
    with open(os.path.join(out, "handcheck.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["sheet", "lane", "target", "name", "chosen", "candidate", "house", "square"])
        for n, (r, t, c3) in enumerate(todo):
            for k, c in enumerate(c3, 1):
                w.writerow([n // 2 + 1, n + 1, t["id"], r["name"], int(c["house"]["id"] == r["house"]), k,
                            c["house"]["id"], round(c["square"], 1)])

    def panel(layer, mid, size, c3, line, firing_pts):
        bbox = (mid[0] - size / 2, mid[1] - size / 2, mid[0] + size / 2, mid[1] + size / 2)
        img = Image.open(io.BytesIO(fetch(bbox, 600, layer))).convert("RGB")
        d = ImageDraw.Draw(img)
        sc = 600 / size

        def xy(p):
            return ((p[0] - bbox[0]) * sc, (bbox[3] - p[1]) * sc)

        d.line([xy(p) for p in line], fill=(0, 230, 255), width=3)
        for k, c in enumerate(c3):
            col = colours[k % len(colours)]
            d.line([xy(p) for p in c["house"]["ring"]], fill=col, width=2)
            x, y = xy(rc.centroid(c["house"]["ring"]))
            d.rectangle((x - 7, y - 8, x + 7, y + 8), fill=(0, 0, 0))
            d.text((x - 3, y - 6), str(k + 1), fill=col)
        return img

    sheets = {}
    for n, (r, t, c3) in enumerate(todo):
        mid_t = rc.line_midpoint(t["line"])
        cx = sum(c["firing"][0] for c in c3) / len(c3)
        cy = sum(c["firing"][1] for c in c3) / len(c3)
        mid = ((mid_t[0] + cx) / 2, (mid_t[1] + cy) / 2)
        size = max(c["square"] for c in c3) * 1.2
        near = ((cx, cy), 120)
        try:
            a = panel("ch.swisstopo.swissimage", mid, size, c3, t["line"], None)
            b = panel(LK, mid, size, c3, t["line"], None)
            za = panel("ch.swisstopo.swissimage", near[0], near[1], c3, t["line"], None)
            zb = panel(LK, near[0], near[1], c3, t["line"], None)
        except Exception as e:  # noqa: BLE001
            print("image failed", n, e)
            continue
        sheet = Image.new("RGB", (1210, 1290), (0, 0, 0))
        for img, pos in ((a, (0, 40)), (b, (610, 40)), (za, (0, 690)), (zb, (610, 690))):
            sheet.paste(img, pos)
        label = f"lane {n + 1}: {r['name']}  " + "  ".join(f"{k + 1}={c['square']:.0f}m" for k, c in enumerate(c3))
        ImageDraw.Draw(sheet).text((8, 10), label, fill=(255, 255, 255))
        ImageDraw.Draw(sheet).text((8, 655), "close-up 120 m around the houses", fill=(255, 255, 255))
        sheet.save(os.path.join(out, f"hand-{n + 1:03d}.jpg"), quality=80)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
