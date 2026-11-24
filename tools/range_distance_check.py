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
    """Name lists the distance, house straight across, then nearest.

    A house that is the firing house of a 25 or 50 m row is skipped for a longer row when
    another house of the range faces it too: that's a pistol stand in front of the 300 m house.
    """
    if not cands:
        return None
    longer = [c for c in cands if not (c["house"]["id"] in short_houses and (c["nominal"] or 0) >= 100)]
    if len(longer) < len(cands) and any(c["named"] for c in longer):
        cands = longer
    return min(cands, key=lambda c: (not c["named"], c["overlap"] < 0.3, c["nearest"]))


def stats(values):
    if not values:
        return {}
    v = sorted(values)
    q = statistics.quantiles(v, n=20) if len(v) >= 20 else [v[0]] * 19
    return {
        "n": len(v), "median": round(statistics.median(v), 2), "mean": round(statistics.fmean(v), 2),
        "p5": round(q[0], 2), "p25": round(q[4], 2), "p75": round(q[14], 2), "p95": round(q[18], 2),
    }


def fetch(bbox, px):
    url = WMS.format(*bbox, px, px)
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

    # Aerial crops: a spread of 50 m lanes (typical and off ones), and the 300 m lanes whose pairing changed.
    fifty = sorted((r for r in rows if r["nominal"] == 50), key=lambda r: r["square"])
    picks = []
    if fifty:
        step = max(1, len(fifty) // 12)
        picks += fifty[::step][:12] + fifty[:3] + fifty[-3:]
    picks += [r for r in rows if r["nominal"] == 300 and r["changed"]][:6]
    picks += [r for r in rows if "Riedbach Forst" in r["name"] and r["nominal"] == 300]
    seen = set()
    ring_by_house = {}
    for h in houses:
        ring_by_house.setdefault(h["id"], []).append(h["ring"])
    line_by_target = {t["id"]: t["line"] for t in targets}
    for r in picks:
        if r["target"] in seen:
            continue
        seen.add(r["target"])
        slug = f"{r['nominal']}m-{r['square']:.1f}-{r['target'][:8]}"
        firing, target = (r["firing_e"], r["firing_n"]), (r["target_e"], r["target_n"])
        mid = ((firing[0] + target[0]) / 2, (firing[1] + target[1]) / 2)
        size = max(80, r["square"] * 1.3)
        near = [h["ring"] for h in houses if rc.ring_distance(mid, h["ring"]) < size]
        lines = [t["line"] for t in targets if rc.dist2(rc.line_midpoint(t["line"]), mid) < size]
        try:
            picture(os.path.join(out, f"{slug}-overview.jpg"), mid, size, 800, near, lines, [firing, target])
            picture(os.path.join(out, f"{slug}-firing.jpg"), firing, 40, 500, ring_by_house[r["house"]], [], [firing])
            picture(os.path.join(out, f"{slug}-target.jpg"), target, 40, 500, [], [line_by_target[r["target"]]], [target])
        except Exception as e:  # noqa: BLE001
            print("image failed", slug, e)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
