"""Build the shooting range catalogue from swisstopo swissTLM3D and a hand-made indoor list.

swissTLM3D maps outdoor ranges as a shooting house (building footprint with the use
"Schiessstand") and one target row per distance (TLM_SPORTBAUTE_LIN "Scheibenstand").
Where swisstopo also has a shooting trajectory line, that line gives the firing point
and the target end directly. Otherwise each target row is paired with the shooting
house in front of it. Names ("Thun Guntelsey 300/50/25m") and places come from swisstopo.
Indoor ranges, which swisstopo doesn't map, come from data/indoor-ranges.json, a list
kept by hand in this repository.

    python3 tools/range_catalogue.py latest-gpkg stac-items.json   # prints "<release> <url>"
    python3 tools/range_catalogue.py inspect swisstlm3d.gpkg
    python3 tools/range_catalogue.py build swisstlm3d.gpkg data/indoor-ranges.json out/

The build writes out/ranges.json (for the app) and out/ranges.csv (for checking against
other lists). Licence: swissTLM3D © swisstopo (open data, attribution required). The
indoor list uses no OpenStreetMap data, so no ODbL applies.

Only the standard library is used, so the unit tests run anywhere.
"""
import csv
import json
import math
import os
import re
import sqlite3
import struct
import sys
from datetime import datetime, timezone

ATTRIBUTION = {"swisstopo": "swissTLM3D © swisstopo"}

NOMINAL_DISTANCES = (10, 25, 50, 100, 300)
SNAP_TOLERANCE = 0.12          # measured distance within 12 % of a nominal one snaps to it
MAX_RANGE_DISTANCE = 1100.0    # metres; longer house-to-target pairs are not ranges
MIN_RANGE_DISTANCE = 5.0
ALIGNMENT_DEGREES = 25.0       # house must sit within this angle of the target row's normal
RANGE_CLUSTER_METRES = 150.0   # firing points closer than this belong to one range
PLACE_MATCH_METRES = 10000.0
SWISS_BOUNDS = (45.8, 47.9, 5.9, 10.6)  # lat min/max, lon min/max


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


# swissTLM3D writes "k_W" (kein Wert) where an attribute has no value.
NO_VALUE = {"", "k_w", "k.w.", "kw", "-", "unbekannt", "none", "null"}


def clean_name(name):
    """A swisstopo name worth showing, or "" for empty and generic labels."""
    if name is None:
        return ""
    text = " ".join(str(name).split())
    return "" if text.lower() in NO_VALUE or text.lower() in GENERIC_NAMES else text


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
    places = read_tlm_places(conn, tables)
    conn.close()
    return houses, targets, trajectories, places


def representative_point(geometry):
    kind, coords = geometry
    if kind == "Point":
        return coords[:2]
    if kind == "MultiPoint" and coords:
        return coords[0][:2]
    rings = outer_rings_of(geometry)
    if rings:
        return centroid(rings[0])
    return None


def read_tlm_places(conn, tables):
    """Settlement names (swissTLM3D TLM_SIEDLUNGSNAME) as {"pos", "tags": {"name"}} items."""
    table = find_table(tables, "siedlungsname")
    if not table:
        return []
    geometry_column, columns = tables[table]
    name = find_column(columns, "name")
    if not name:
        return []
    kind = find_column(columns, "objektart")
    kind_sql = f'"{kind}"' if kind else "NULL"
    places = []
    sql = f'SELECT "{name}", {kind_sql}, "{geometry_column}" FROM "{table}" WHERE "{name}" IS NOT NULL'
    for value, objektart, blob in conn.execute(sql):
        geometry = parse_gpkg_geometry(blob)
        position = representative_point(geometry) if geometry else None
        # Only villages and towns ("Ort"); districts and quarters make poor place names.
        if position and str(objektart or "Ort") == "Ort":
            places.append({"pos": position, "tags": {"name": str(value)}})
    return places


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
    # Which names swisstopo gives the range objects themselves, and which settlement kinds exist.
    for needles, attribute, patterns in ((("gebaeude", "footprint"), "nutzung", ("%schiess%",)),
                                         (("sportbaute", "lin"), "objektart", ("%scheiben%",))):
        table = find_table(tables, *needles)
        if not table:
            continue
        column, name = find_column(tables[table][1], attribute), find_column(tables[table][1], "name")
        if not (column and name):
            continue
        rows = conn.execute(f'SELECT "{name}", COUNT(*) FROM "{table}" WHERE "{column}" LIKE ?'
                            ' GROUP BY 1 ORDER BY 2 DESC', patterns).fetchall()
        named = [(value, count) for value, count in rows if clean_name(value)]
        print(f"{table} names: {sum(c for _, c in named)} of {sum(c for _, c in rows)} named", file=out)
        for value, count in rows[:25]:
            print(f"  {value!r}: {count}", file=out)
    places = find_table(tables, "siedlungsname")
    if places and find_column(tables[places][1], "objektart"):
        kind = find_column(tables[places][1], "objektart")
        print(f"{places}.{kind} values:", file=out)
        for value, count in conn.execute(f'SELECT "{kind}", COUNT(*) FROM "{places}" GROUP BY 1'):
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
        lane["house_name"] = house.get("name", "")
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

SAME_NAME_METRES = 500.0  # buildings with the same swisstopo name this close are one range


def name_distances(name):
    """Distances listed at the end of a swisstopo range name: "Thun Guntelsey 300/50/25m" -> [300, 50, 25]."""
    match = re.search(r"(\d+(?:\s*/\s*\d+)*)\s*m\s*$", name or "")
    if not match:
        return []
    return sorted({int(d) for d in re.split(r"\s*/\s*", match.group(1))}, reverse=True)


def house_only_ranges(houses, lanes):
    """Named shooting houses without a target row in front: indoor ranges and missing rows.

    Houses with the same name close together are one range; it has no direction.
    """
    paired = {lane.get("house") for lane in lanes}
    paired_names = [(lane.get("house_name"), lane["firing"]) for lane in lanes if lane.get("house_name")]
    ranges = []
    for house in houses:
        name = house.get("name", "")
        if house["id"] in paired or not name:
            continue
        center = centroid(house["ring"])
        if any(n == name and dist2(p, center) <= SAME_NAME_METRES for n, p in paired_names):
            continue  # another building of a range that is already there
        existing = next((r for r in ranges if r["tlm_name"] == name
                         and dist2(r["firing"], center) <= SAME_NAME_METRES), None)
        if existing:
            continue
        ranges.append({
            "id": "tlm:" + house["id"],
            "firing": center,
            "target": center,
            "bearing": None,
            "altitude": mean_z(house["ring"]),
            "distances": name_distances(name),
            "lanes": [],
            "tlm_name": name,
        })
    return ranges


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
            near = dist2(lanes[i]["firing"], lanes[j]["firing"])
            # swisstopo gives every building of one range the same name, e.g. "Thun Guntelsey 300/50/25m".
            same_name = (lanes[i].get("house_name") and lanes[i].get("house_name") == lanes[j].get("house_name")
                         and near <= SAME_NAME_METRES)
            if same_house or same_name or near <= RANGE_CLUSTER_METRES:
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
        house_names = [lane["house_name"] for lane in members if lane.get("house_name")]
        tlm_name = (max(set(house_names), key=lambda n: (house_names.count(n), n)) if house_names
                    else next((n for lane in sorted(members, key=lambda lane: -lane["measured"])
                               for n in lane["names"]), ""))
        named_distances = name_distances(tlm_name)
        ranges.append({
            "firing": primary["firing"],
            "target": primary["target"],
            "bearing": primary["bearing"],
            "altitude": primary["altitude"],
            # The name lists the official distances ("300/50/25m"); measured ones are the fallback.
            "distances": named_distances or distances,
            "lanes": members,
            "tlm_name": tlm_name,
            "id": "tlm:" + sorted(i for lane in members for i in lane["ids"])[0],
        })
    return ranges


# ---------------------------------------------------------------------------
# Names, places and the indoor list

def place_from_name(name, position, places, radius=15000.0):
    """The town a swisstopo range name starts with ("Thun Guntelsey 300/50/25m" -> "Thun")."""
    lowered = (name or "").lower()
    best = ""
    for place in places:
        town = place["tags"]["name"]
        if len(town) > len(best) and lowered.startswith(town.lower()) \
                and (len(lowered) == len(town) or not lowered[len(town)].isalnum()) \
                and dist2(place["pos"], position) <= radius:
            best = town
    return best


def nearest_place(position, places):
    best = min(places, key=lambda p: dist2(p["pos"], position), default=None)
    if best and dist2(best["pos"], position) <= PLACE_MATCH_METRES:
        return best["tags"]["name"]
    return ""


def name_ranges(ranges, places):
    """Give each swisstopo range its name and place; both come from swisstopo."""
    for rng in ranges:
        rng["place"] = (place_from_name(rng.get("tlm_name"), rng["firing"], places)
                        or nearest_place(rng["firing"], places))
        rng["name"] = rng.get("tlm_name") or f"Schiessanlage {rng['place']}".strip()
        rng["name_source"] = "swisstopo" if rng.get("tlm_name") else "generated"


def manual_ranges(data):
    """Ranges from the hand-made list (data/indoor-ranges.json); checks every entry."""
    ranges, seen = [], set()
    for item in data.get("ranges", []):
        ident, name = item.get("id", ""), (item.get("name") or "").strip()
        if not ident.startswith("manual:") or ident in seen:
            raise ValueError(f"bad or duplicate id: {ident!r}")
        lat, lon = item.get("lat"), item.get("lon")
        if not name or not item.get("place") or not isinstance(lat, (int, float)) \
                or not isinstance(lon, (int, float)):
            raise ValueError(f"{ident}: name, place, lat and lon are required")
        if not (SWISS_BOUNDS[0] <= lat <= SWISS_BOUNDS[1] and SWISS_BOUNDS[2] <= lon <= SWISS_BOUNDS[3]):
            raise ValueError(f"{ident}: position outside Switzerland")
        distances = item.get("distances", [])
        if any(not isinstance(d, int) or d <= 0 for d in distances):
            raise ValueError(f"{ident}: distances must be positive whole metres")
        seen.add(ident)
        ranges.append({
            "id": ident,
            "name": name,
            "place": item["place"],
            "name_source": "manual",
            "indoor": item.get("indoor", True),
            "firing": wgs84_to_lv95(lat, lon),
            "bearing": None,
            "altitude": None,
            "distances": sorted(distances, reverse=True),
            "website": item.get("website", ""),
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
    if rng.get("indoor"):
        record["indoor"] = True
    if rng["lanes"]:
        record["lanes"] = [{
            "distance": lane["distance"],
            "measured": round(lane["measured"], 1),
            "shootingBearing": round(lane["bearing"], 1),
            "source": lane["source"],
        } for lane in sorted(rng["lanes"], key=lambda lane: -lane["measured"])]
    return record


def build(tlm_path, manual_path, out_dir, release=""):
    """manual_path "-" builds from swisstopo alone."""
    houses, targets, trajectories, tlm_places = read_tlm(tlm_path)
    lanes = build_lanes(houses, targets, trajectories)
    ranges = group_lanes(lanes)
    ranges += house_only_ranges(houses, lanes)
    name_ranges(ranges, tlm_places)
    if manual_path != "-":
        with open(manual_path, encoding="utf-8") as f:
            ranges += manual_ranges(json.load(f))
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
        "swisstopo place names": len(tlm_places),
        "ranges from swisstopo": sum(r["id"].startswith("tlm:") for r in ranges),
        "  name from swisstopo": sum(r.get("name_source") == "swisstopo" for r in ranges),
        "  name generated (Schiessanlage <place>)": sum(r.get("name_source") == "generated" for r in ranges),
        "  with place": sum(r["id"].startswith("tlm:") and bool(r["place"]) for r in ranges),
        "  without direction (no target row found)": sum(r["id"].startswith("tlm:") and r["bearing"] is None
                                                          for r in ranges),
        "indoor ranges from the hand-made list": sum(r["id"].startswith("manual:") for r in ranges),
    }
    for name in (300, 100, 50, 25, 10):
        stats[f"ranges with {name} m"] = sum(name in r["distances"] for r in ranges)
    return stats


def write_csv(ranges, path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["id", "name", "place", "latitude", "longitude", "east_lv95", "north_lv95",
                         "altitude", "shooting_bearing", "distances", "measured", "source", "website"])
        for rng in ranges:
            lat, lon = lv95_to_wgs84(*rng["firing"])
            writer.writerow([
                rng["id"], rng["name"], rng["place"], f"{lat:.6f}", f"{lon:.6f}",
                round(rng["firing"][0]), round(rng["firing"][1]),
                "" if rng["altitude"] is None else round(rng["altitude"]),
                "" if rng["bearing"] is None else f"{rng['bearing']:.1f}",
                " ".join(str(d) for d in rng["distances"]),
                " ".join(f"{lane['measured']:.0f}" for lane in rng["lanes"]),
                "+".join(sorted({lane["source"] for lane in rng["lanes"]}))
                or ("manual" if rng["id"].startswith("manual:") else "house"),
                rng.get("website", ""),
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
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
