"""Build the shooting range catalogue from swisstopo swissTLM3D and OpenStreetMap.

swissTLM3D maps outdoor ranges as a shooting house (building footprint with the use
"Schiessstand") and one target row per distance (TLM_SPORTBAUTE_LIN "Scheibenstand").
Where swisstopo also has a shooting trajectory line, that line gives the firing point
and the target end directly. Otherwise each target row is paired with the shooting
house in front of it. OpenStreetMap adds names, websites and the nearest place.

    python3 tools/range_catalogue.py latest-gpkg stac-items.json   # prints "<release> <url>"
    python3 tools/range_catalogue.py overpass-query > query.overpassql
    python3 tools/range_catalogue.py inspect swisstlm3d.gpkg
    python3 tools/range_catalogue.py build swisstlm3d.gpkg overpass.json out/

The build writes out/ranges.json (for the app) and out/ranges.csv (for checking against
other lists). Licences: swissTLM3D © swisstopo; OpenStreetMap data © OpenStreetMap
contributors, ODbL 1.0, so the generated files are ODbL too.

Only the standard library is used, so the unit tests run anywhere.
"""
import csv
import json
import math
import os
import sqlite3
import struct
import sys
from datetime import datetime, timezone

# Overpass query for the OpenStreetMap part. Paintball is not a shooting range in our sense.
OVERPASS_QUERY = """[out:json][timeout:300];
area["ISO3166-1"="CH"][admin_level=2]->.ch;
(
  nwr["sport"~"shooting"](area.ch);
  nwr["leisure"="shooting_ground"](area.ch);
);
out center tags;
node["place"~"^(city|town|village)$"](area.ch);
out tags;
"""

ATTRIBUTION = {
    "swisstopo": "swissTLM3D © swisstopo",
    "osm": "© OpenStreetMap contributors, ODbL 1.0 (https://www.openstreetmap.org/copyright)",
    "licence": "ODbL 1.0 (https://opendatacommons.org/licenses/odbl/1-0/)",
}

NOMINAL_DISTANCES = (10, 25, 50, 100, 300)
SNAP_TOLERANCE = 0.12          # measured distance within 12 % of a nominal one snaps to it
MAX_RANGE_DISTANCE = 1100.0    # metres; longer house-to-target pairs are not ranges
MIN_RANGE_DISTANCE = 5.0
ALIGNMENT_DEGREES = 25.0       # house must sit within this angle of the target row's normal
RANGE_CLUSTER_METRES = 150.0   # firing points closer than this belong to one range
OSM_MATCH_METRES = 200.0       # OSM object within this distance of the line of fire
PLACE_MATCH_METRES = 10000.0
OSM_ONLY_MERGE_METRES = 300.0  # OSM-only objects with the same name this close are one range


# ---------------------------------------------------------------------------
# Coordinates

def lv95_to_wgs84(east, north):
    """swisstopo's approximate formulas, accurate to about 1 m. Returns (lat, lon)."""
    y = (east - 2600000.0) / 1000000.0
    x = (north - 1200000.0) / 1000000.0
    lon = (2.6779094 + 4.728982 * y + 0.791484 * y * x + 0.1306 * y * x * x
           - 0.0436 * y ** 3)
    lat = (16.9023892 + 3.238272 * x - 0.270978 * y * y - 0.002528 * x * x
           - 0.0447 * y * y * x - 0.0140 * x ** 3)
    return lat * 100.0 / 36.0, lon * 100.0 / 36.0


def wgs84_to_lv95(lat, lon):
    """Inverse approximate formulas. Returns (east, north)."""
    phi = (lat * 3600.0 - 169028.66) / 10000.0
    lam = (lon * 3600.0 - 26782.5) / 10000.0
    east = (2600072.37 + 211455.93 * lam - 10938.51 * lam * phi
            - 0.36 * lam * phi * phi - 44.54 * lam ** 3)
    north = (1200147.07 + 308807.95 * phi + 3745.25 * lam * lam + 76.63 * phi * phi
             - 194.56 * lam * lam * phi + 119.79 * phi ** 3)
    return east, north


def true_bearing(start, end):
    """Bearing from start to end (LV95 points), degrees clockwise from true north.

    Computed on WGS84 so grid convergence (up to about 1.5° at the borders) is removed.
    """
    lat1, lon1 = lv95_to_wgs84(start[0], start[1])
    lat2, lon2 = lv95_to_wgs84(end[0], end[1])
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dl = math.radians(lon2 - lon1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return math.degrees(math.atan2(y, x)) % 360.0


def snap_distance(measured):
    """Nominal distance (10/25/50/100/300 m) for a measured one, or None when none fits."""
    for nominal in NOMINAL_DISTANCES:
        if abs(measured - nominal) <= nominal * SNAP_TOLERANCE:
            return nominal
    return None


def dist2(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def point_segment_distance(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    length2 = ax * ax + ay * ay
    if length2 == 0:
        return dist2(p, a)
    t = max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / length2))
    return dist2(p, (a[0] + t * ax, a[1] + t * ay))


def ring_distance(p, ring):
    """Distance from p to the outline of a polygon ring (its nearest edge)."""
    return min(point_segment_distance(p, ring[i], ring[i + 1]) for i in range(len(ring) - 1))


def centroid(points):
    pts = points[:-1] if len(points) > 1 and points[0] == points[-1] else points
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def mean_z(points):
    zs = [p[2] for p in points if len(p) > 2 and p[2] is not None and not math.isnan(p[2])]
    return sum(zs) / len(zs) if zs else None


def line_midpoint(points):
    """Point halfway along a polyline."""
    total = sum(dist2(points[i], points[i + 1]) for i in range(len(points) - 1))
    if total == 0:
        return (points[0][0], points[0][1])
    half, walked = total / 2.0, 0.0
    for i in range(len(points) - 1):
        seg = dist2(points[i], points[i + 1])
        if walked + seg >= half:
            t = (half - walked) / seg
            a, b = points[i], points[i + 1]
            return (a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
        walked += seg
    return (points[-1][0], points[-1][1])


# ---------------------------------------------------------------------------
# GeoPackage geometry (GPKG header + ISO WKB, with or without Z/M)

def parse_gpkg_geometry(blob):
    """Decode a GeoPackage geometry blob into ("Point"|"LineString"|"Polygon"|"Multi…", coords)."""
    if blob is None or len(blob) < 8 or blob[:2] != b"GP":
        raise ValueError("not a GeoPackage geometry")
    flags = blob[3]
    if flags & 0x20:
        return None  # empty geometry
    envelope_sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
    envelope = (flags >> 1) & 0x07
    if envelope not in envelope_sizes:
        raise ValueError("bad envelope indicator")
    geometry, _ = parse_wkb(blob, 8 + envelope_sizes[envelope])
    return geometry


def parse_wkb(data, offset=0):
    order = "<" if data[offset] == 1 else ">"
    raw_type = struct.unpack_from(order + "I", data, offset + 1)[0]
    offset += 5
    has_z = bool(raw_type & 0x80000000)
    has_m = bool(raw_type & 0x40000000)
    raw_type &= 0x0FFFFFFF
    if raw_type >= 3000:
        has_z = has_m = True
    elif raw_type >= 2000:
        has_m = True
    elif raw_type >= 1000:
        has_z = True
    base = raw_type % 1000
    dims = 2 + has_z + has_m

    def point(off):
        values = struct.unpack_from(order + "d" * dims, data, off)
        z = values[2] if has_z else None
        return (values[0], values[1], z), off + 8 * dims

    def points(off):
        count = struct.unpack_from(order + "I", data, off)[0]
        off += 4
        out = []
        for _ in range(count):
            p, off = point(off)
            out.append(p)
        return out, off

    if base == 1:
        p, offset = point(offset)
        return ("Point", p), offset
    if base == 2:
        pts, offset = points(offset)
        return ("LineString", pts), offset
    if base == 3:
        count = struct.unpack_from(order + "I", data, offset)[0]
        offset += 4
        rings = []
        for _ in range(count):
            ring, offset = points(offset)
            rings.append(ring)
        return ("Polygon", rings), offset
    if base in (4, 5, 6):
        count = struct.unpack_from(order + "I", data, offset)[0]
        offset += 4
        parts = []
        for _ in range(count):
            part, offset = parse_wkb(data, offset)
            parts.append(part[1])
        return ({4: "MultiPoint", 5: "MultiLineString", 6: "MultiPolygon"}[base], parts), offset
    raise ValueError(f"unsupported WKB type {raw_type}")


def lines_of(geometry):
    if geometry is None:
        return []
    kind, coords = geometry
    if kind == "LineString":
        return [coords]
    if kind == "MultiLineString":
        return coords
    return []


def outer_rings_of(geometry):
    if geometry is None:
        return []
    kind, coords = geometry
    if kind == "Polygon":
        return [coords[0]] if coords else []
    if kind == "MultiPolygon":
        return [poly[0] for poly in coords if poly]
    return []


# ---------------------------------------------------------------------------
# Reading swissTLM3D

def feature_tables(conn):
    """{table name: (geometry column, [column names])} for every feature table."""
    tables = {}
    for table, column in conn.execute("SELECT table_name, column_name FROM gpkg_geometry_columns"):
        columns = [row[1] for row in conn.execute(f'PRAGMA table_info("{table}")')]
        tables[table] = (column, columns)
    return tables


def find_table(tables, *needles):
    for table in sorted(tables):
        name = table.lower()
        if all(n in name for n in needles):
            return table
    return None


def find_column(columns, name):
    for column in columns:
        if column.lower() == name:
            return column
    return None


def read_features(conn, table, geometry_column, columns, attribute, patterns):
    """Rows of `table` whose `attribute` matches any LIKE pattern: (uuid, value, name, geometry)."""
    uuid_column = find_column(columns, "uuid") or "rowid"
    name_column = find_column(columns, "name")
    name_sql = f'"{name_column}"' if name_column else "NULL"
    where = " OR ".join(f'"{attribute}" LIKE ?' for _ in patterns)
    sql = (f'SELECT "{uuid_column}", "{attribute}", {name_sql}, "{geometry_column}" FROM "{table}"'
           f" WHERE {where}")
    for uuid, value, name, blob in conn.execute(sql, patterns):
        yield str(uuid).strip("{}"), str(value), clean_name(name), parse_gpkg_geometry(blob)


# Labels that only say "shooting range" are no use as a range name.
GENERIC_NAMES = {
    "schiessstand", "schiessanlage", "scheibenstand", "schützenhaus", "schuetzenhaus",
    "schiessplatz", "stand", "stand de tir", "ciblerie", "poligono di tiro", "poligono",
    "bersaglio", "bersagli", "alte schiessstand", "alter schiessstand",
}


def clean_name(name):
    """A swisstopo name worth showing, or "" for empty and generic labels."""
    if name is None:
        return ""
    text = " ".join(str(name).split())
    return "" if text.lower() in GENERIC_NAMES else text


def read_tlm(path):
    """Shooting houses, target rows and trajectory lines from a swissTLM3D GeoPackage."""
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    tables = feature_tables(conn)
    houses, targets, trajectories = [], [], []

    footprint = find_table(tables, "gebaeude", "footprint")
    if footprint:
        geometry_column, columns = tables[footprint]
        use = find_column(columns, "nutzung")
        if use:
            for uuid, _, name, geometry in read_features(conn, footprint, geometry_column, columns,
                                                         use, ["%schiess%", "%schieß%"]):
                for ring in outer_rings_of(geometry):
                    houses.append({"id": uuid, "ring": ring, "name": name})

    sport = find_table(tables, "sportbaute", "lin")
    if sport:
        geometry_column, columns = tables[sport]
        kind = find_column(columns, "objektart")
        if kind:
            for uuid, value, name, geometry in read_features(conn, sport, geometry_column, columns, kind,
                                                             ["%scheiben%", "%schuss%", "%schiess%"]):
                bucket = targets if "scheiben" in value.lower() else trajectories
                for line in lines_of(geometry):
                    bucket.append({"id": uuid, "line": line, "name": name})
    conn.close()
    return houses, targets, trajectories


def inspect_tlm(path, out=sys.stdout):
    """Print the tables and shooting-related values, to check what a release contains."""
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    tables = feature_tables(conn)
    print(f"{len(tables)} feature tables", file=out)
    for table, (geometry_column, columns) in sorted(tables.items()):
        print(f"- {table} ({geometry_column}): {', '.join(columns)}", file=out)
    for table, (_, columns) in sorted(tables.items()):
        for column in columns:
            if column.lower() not in ("objektart", "nutzung", "name", "art"):
                continue
            rows = conn.execute(
                f'SELECT "{column}", COUNT(*) FROM "{table}" WHERE "{column}" LIKE ? OR "{column}" LIKE ?'
                f' OR "{column}" LIKE ? GROUP BY 1 ORDER BY 2 DESC LIMIT 20',
                ("%schiess%", "%scheiben%", "%schuss%")).fetchall()
            for value, count in rows:
                print(f"  {table}.{column} = {value!r}: {count}", file=out)
    sport = find_table(tables, "sportbaute", "lin")
    if sport:
        kind = find_column(tables[sport][1], "objektart")
        if kind:
            print(f"{sport}.{kind} values:", file=out)
            for value, count in conn.execute(f'SELECT "{kind}", COUNT(*) FROM "{sport}" GROUP BY 1'):
                print(f"  {value!r}: {count}", file=out)
    conn.close()


# ---------------------------------------------------------------------------
# Lanes: one firing point, one target row, a distance and a bearing

def make_lane(firing, target, altitude, source, ids, names=()):
    measured = dist2(firing, target)
    return {
        "names": [n for n in names if n],
        "firing": (firing[0], firing[1]),
        "target": (target[0], target[1]),
        "measured": measured,
        "distance": snap_distance(measured),
        "bearing": true_bearing(firing, target),
        "altitude": altitude,
        "source": source,
        "ids": ids,
    }


def lanes_from_trajectories(trajectories, houses, targets):
    """Orient each trajectory line: the end near a target row (or away from a house) is the target."""
    target_mids = [line_midpoint(t["line"]) for t in targets]
    lanes = []
    for trajectory in trajectories:
        line = trajectory["line"]
        a, b = line[0], line[-1]
        if dist2(a, b) < MIN_RANGE_DISTANCE:
            continue

        def near_target(p):
            return min((dist2(p, m) for m in target_mids), default=math.inf)

        def near_house(p):
            return min((ring_distance(p, h["ring"]) for h in houses), default=math.inf)

        if near_target(a) < near_target(b) or (near_target(a) == near_target(b)
                                                and near_house(b) < near_house(a)):
            a, b = b, a
            line = list(reversed(line))
        altitude = line[0][2] if len(line[0]) > 2 else None
        lanes.append(make_lane(a, b, altitude, "trajectory", [trajectory["id"]],
                               [trajectory.get("name", "")]))
    return lanes


def lanes_from_pairing(houses, targets, used_targets=()):
    """Pair each target row with the nearest shooting house that faces it."""
    lanes = []
    cos_limit = math.cos(math.radians(ALIGNMENT_DEGREES))
    house_info = [(h, centroid(h["ring"]), mean_z(h["ring"])) for h in houses]
    for target in targets:
        if target["id"] in used_targets:
            continue
        line = target["line"]
        mid = line_midpoint(line)
        dx, dy = line[-1][0] - line[0][0], line[-1][1] - line[0][1]
        length = math.hypot(dx, dy)
        if length == 0:
            continue
        normal = (-dy / length, dx / length)
        best = None
        for house, center, altitude in house_info:
            vx, vy = mid[0] - center[0], mid[1] - center[1]
            span = math.hypot(vx, vy)
            if span == 0 or span > MAX_RANGE_DISTANCE + 50:
                continue
            if abs((vx * normal[0] + vy * normal[1]) / span) < cos_limit:
                continue
            front = ring_distance(mid, house["ring"])
            if front < MIN_RANGE_DISTANCE or front > MAX_RANGE_DISTANCE:
                continue
            if best is None or front < best[0]:
                best = (front, house, center, altitude)
        if best is None:
            continue
        front, house, center, altitude = best
        # Firing line = point on the house outline nearest to the target row.
        firing = nearest_point_on_ring(mid, house["ring"])
        lane = make_lane(firing, mid, altitude, "pairing", [house["id"], target["id"]],
                         [target.get("name", ""), house.get("name", "")])
        lane["house"] = house["id"]
        lanes.append(lane)
    return lanes


def nearest_point_on_ring(p, ring):
    best, best_d = None, math.inf
    for i in range(len(ring) - 1):
        a, b = ring[i], ring[i + 1]
        ax, ay = b[0] - a[0], b[1] - a[1]
        length2 = ax * ax + ay * ay
        t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / length2))
        q = (a[0] + t * ax, a[1] + t * ay)
        d = dist2(p, q)
        if d < best_d:
            best, best_d = q, d
    return best


def build_lanes(houses, targets, trajectories):
    lanes = lanes_from_trajectories(trajectories, houses, targets)
    # Target rows already explained by a trajectory are not paired again.
    used = set()
    for lane in lanes:
        for target in targets:
            if dist2(line_midpoint(target["line"]), lane["target"]) < 30:
                used.add(target["id"])
    return lanes + lanes_from_pairing(houses, targets, used)


# ---------------------------------------------------------------------------
# Ranges: lanes whose firing points are close together

def group_lanes(lanes):
    parent = list(range(len(lanes)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(lanes)):
        for j in range(i + 1, len(lanes)):
            same_house = lanes[i].get("house") and lanes[i].get("house") == lanes[j].get("house")
            if same_house or dist2(lanes[i]["firing"], lanes[j]["firing"]) <= RANGE_CLUSTER_METRES:
                parent[root(i)] = root(j)
    groups = {}
    for i, lane in enumerate(lanes):
        groups.setdefault(root(i), []).append(lane)

    ranges = []
    for members in groups.values():
        # The primary lane sets position and bearing: the 300 m one, else the longest.
        primary = max(members, key=lambda lane: (lane["distance"] == 300, lane["measured"]))
        distances = sorted({lane["distance"] or round(lane["measured"] / 5) * 5 for lane in members},
                           reverse=True)
        ranges.append({
            "firing": primary["firing"],
            "target": primary["target"],
            "bearing": primary["bearing"],
            "altitude": primary["altitude"],
            "distances": distances,
            "lanes": members,
            "tlm_name": next((n for lane in sorted(members, key=lambda lane: -lane["measured"])
                              for n in lane["names"]), ""),
            "id": "tlm:" + sorted(i for lane in members for i in lane["ids"])[0],
        })
    return ranges


# ---------------------------------------------------------------------------
# OpenStreetMap

def parse_overpass(data):
    """Shooting objects and place nodes from Overpass JSON, positions in LV95."""
    shooting, places = [], []
    for element in data.get("elements", []):
        tags = element.get("tags", {})
        if "lat" in element:
            lat, lon = element["lat"], element["lon"]
        elif "center" in element:
            lat, lon = element["center"]["lat"], element["center"]["lon"]
        else:
            continue
        position = wgs84_to_lv95(lat, lon)
        item = {"osm": f"{element['type']}/{element['id']}", "pos": position, "tags": tags}
        if tags.get("place") in ("city", "town", "village") and "name" in tags:
            places.append(item)
        elif "shooting" in tags.get("sport", "") or tags.get("leisure") == "shooting_ground":
            if tags.get("shooting") == "paintball":
                continue
            shooting.append(item)
    return shooting, places


def nearest_place(position, places):
    best = min(places, key=lambda p: dist2(p["pos"], position), default=None)
    if best and dist2(best["pos"], position) <= PLACE_MATCH_METRES:
        return best["tags"]["name"]
    return ""


def osm_score(item):
    """Prefer named, linked objects that describe the whole site over single lanes."""
    tags = item["tags"]
    return (("name" in tags) * 4 + ("website" in tags or "contact:website" in tags) * 2
            + (tags.get("leisure") in ("sports_centre", "shooting_ground")))


def match_osm(ranges, shooting, places):
    """Give each range a name, place and website; return OSM objects no range claimed."""
    claimed = set()
    for rng in ranges:
        candidates = []
        for item in shooting:
            d = point_segment_distance(item["pos"], rng["firing"], rng["target"])
            if d <= OSM_MATCH_METRES:
                candidates.append((item, d))
                claimed.add(item["osm"])
        named = [(item, d) for item, d in candidates if "name" in item["tags"]]
        best = max(named, key=lambda c: (osm_score(c[0]), -c[1]))[0] if named else None
        rng["place"] = nearest_place(rng["firing"], places)
        if best:
            tags = best["tags"]
            rng["name"] = tags["name"]
            rng["osm"] = best["osm"]
            rng["website"] = tags.get("website") or tags.get("contact:website") or ""
            rng["place"] = tags.get("addr:city") or rng["place"]
        else:
            rng["name"] = rng.get("tlm_name") or f"Schiessanlage {rng['place']}".strip()
            rng["osm"] = ""
            rng["website"] = ""
    return [item for item in shooting if item["osm"] not in claimed]


def osm_only_ranges(items, places):
    """Named OSM ranges without swisstopo geometry (indoor ranges, 10 m, missing target rows)."""
    ranges = []
    for item in sorted(items, key=lambda i: (-osm_score(i), i["osm"])):
        tags = item["tags"]
        if "name" not in tags:
            continue
        if any(r["name"] == tags["name"] and dist2(r["firing"], item["pos"]) <= OSM_ONLY_MERGE_METRES
               for r in ranges):
            continue
        ranges.append({
            "id": "osm:" + item["osm"],
            "name": tags["name"],
            "place": tags.get("addr:city") or nearest_place(item["pos"], places),
            "firing": item["pos"],
            "bearing": None,
            "altitude": None,
            "distances": [],
            "osm": item["osm"],
            "website": tags.get("website") or tags.get("contact:website") or "",
            "lanes": [],
        })
    return ranges


# ---------------------------------------------------------------------------
# Output

def range_record(rng):
    lat, lon = lv95_to_wgs84(*rng["firing"])
    record = {
        "id": rng["id"],
        "name": rng["name"],
        "place": rng["place"],
        "latitude": round(lat, 6),
        "longitude": round(lon, 6),
        "distances": rng["distances"],
    }
    if rng["bearing"] is not None:
        record["shootingBearing"] = round(rng["bearing"], 1)
    if rng["altitude"] is not None:
        record["altitude"] = round(rng["altitude"])
    if rng.get("website"):
        record["website"] = rng["website"]
    if rng.get("osm"):
        record["osm"] = rng["osm"]
    if rng["lanes"]:
        record["lanes"] = [{
            "distance": lane["distance"],
            "measured": round(lane["measured"], 1),
            "shootingBearing": round(lane["bearing"], 1),
            "source": lane["source"],
        } for lane in sorted(rng["lanes"], key=lambda lane: -lane["measured"])]
    return record


def build(tlm_path, overpass_path, out_dir, release=""):
    houses, targets, trajectories = read_tlm(tlm_path)
    lanes = build_lanes(houses, targets, trajectories)
    ranges = group_lanes(lanes)
    with open(overpass_path, encoding="utf-8") as f:
        shooting, places = parse_overpass(json.load(f))
    leftovers = match_osm(ranges, shooting, places)
    ranges += osm_only_ranges(leftovers, places)
    ranges.sort(key=lambda r: (r["place"].lower(), r["name"].lower(), r["id"]))
    records = [range_record(r) for r in ranges]

    os.makedirs(out_dir, exist_ok=True)
    catalogue = {
        "version": 1,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "swissTLM3D": release,
        "attribution": ATTRIBUTION,
        "ranges": records,
    }
    with open(os.path.join(out_dir, "ranges.json"), "w", encoding="utf-8") as f:
        json.dump(catalogue, f, ensure_ascii=False, indent=1)
        f.write("\n")
    write_csv(ranges, os.path.join(out_dir, "ranges.csv"))

    stats = {
        "shooting houses": len(houses),
        "target rows": len(targets),
        "trajectory lines": len(trajectories),
        "lanes": len(lanes),
        "lanes from trajectories": sum(lane["source"] == "trajectory" for lane in lanes),
        "lanes with nominal distance": sum(lane["distance"] is not None for lane in lanes),
        "ranges from swisstopo": sum(r["id"].startswith("tlm:") for r in ranges),
        "  named from OSM": sum(r["id"].startswith("tlm:") and bool(r["osm"]) for r in ranges),
        "  named by swisstopo": sum(bool(r.get("tlm_name")) for r in ranges),
        "  named by swisstopo, no OSM name": sum(bool(r.get("tlm_name")) and not r["osm"] for r in ranges),
        "ranges from OSM only": sum(r["id"].startswith("osm:") for r in ranges),
    }
    for name in (300, 100, 50, 25, 10):
        stats[f"ranges with {name} m"] = sum(name in r["distances"] for r in ranges)
    return stats


def write_csv(ranges, path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name", "place", "latitude", "longitude", "east_lv95", "north_lv95",
                         "altitude", "shooting_bearing", "distances", "measured", "source", "osm"])
        for rng in ranges:
            lat, lon = lv95_to_wgs84(*rng["firing"])
            writer.writerow([
                rng["id"], rng["name"], rng["place"], f"{lat:.6f}", f"{lon:.6f}",
                round(rng["firing"][0]), round(rng["firing"][1]),
                "" if rng["altitude"] is None else round(rng["altitude"]),
                "" if rng["bearing"] is None else f"{rng['bearing']:.1f}",
                " ".join(str(d) for d in rng["distances"]),
                " ".join(f"{lane['measured']:.0f}" for lane in rng["lanes"]),
                "+".join(sorted({lane["source"] for lane in rng["lanes"]})) or "osm",
                rng["osm"],
            ])


STAC_ITEMS = "https://data.geo.admin.ch/api/stac/v0.9/collections/ch.swisstopo.swisstlm3d/items"


def latest_gpkg(stac):
    """(release, url) of the newest swissTLM3D release that has a GeoPackage, from STAC items JSON."""
    found = []
    for item in stac.get("features", []):
        for asset in item.get("assets", {}).values():
            if "geopackage" in asset.get("type", "") or asset.get("href", "").endswith(".gpkg.zip"):
                found.append((item["id"].replace("swisstlm3d_", ""), asset["href"]))
    if not found:
        raise ValueError("no GeoPackage in the STAC items")
    return max(found)


def main(argv):
    if len(argv) >= 2 and argv[0] == "inspect":
        inspect_tlm(argv[1])
        return 0
    if len(argv) >= 4 and argv[0] == "build":
        stats = build(argv[1], argv[2], argv[3], argv[4] if len(argv) > 4 else "")
        for key, value in stats.items():
            print(f"{key}: {value}")
        return 0
    if len(argv) >= 2 and argv[0] == "latest-gpkg":
        with open(argv[1], encoding="utf-8") as f:
            release, url = latest_gpkg(json.load(f))
        print(f"{release} {url}")
        return 0
    if argv[:1] == ["overpass-query"]:
        sys.stdout.write(OVERPASS_QUERY)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
