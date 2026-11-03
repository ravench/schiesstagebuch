"""Tests for the shooting range catalogue builder.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import csv
import io
import json
import os
import sqlite3
import struct
import tempfile
import unittest

import range_catalogue as rc

# A spot near Bern in LV95, used as the origin of the synthetic ranges.
E0, N0 = 2600000.0, 1200000.0


def wkb(kind, coords, z=True):
    """ISO WKB (little endian) for Point / LineString / Polygon with Z."""
    base = {"Point": 1, "LineString": 2, "Polygon": 3}[kind]
    out = struct.pack("<BI", 1, base + (1000 if z else 0))

    def pts(points):
        data = struct.pack("<I", len(points))
        for p in points:
            data += struct.pack("<ddd", *p) if z else struct.pack("<dd", *p[:2])
        return data

    if kind == "Point":
        out += struct.pack("<ddd", *coords) if z else struct.pack("<dd", *coords[:2])
    elif kind == "LineString":
        out += pts(coords)
    else:
        out += struct.pack("<I", len(coords)) + b"".join(pts(r) for r in coords)
    return out


def gpkg_blob(kind, coords, envelope=1):
    header = b"GP" + bytes([0, 1 | (envelope << 1)]) + struct.pack("<i", 2056)
    header += b"\0" * {0: 0, 1: 32, 2: 48}[envelope]
    return header + wkb(kind, coords)


def box(e, n, w=20.0, h=8.0, z=550.0):
    """Closed rectangle ring around (e, n)."""
    return [(e - w / 2, n - h / 2, z), (e + w / 2, n - h / 2, z), (e + w / 2, n + h / 2, z),
            (e - w / 2, n + h / 2, z), (e - w / 2, n - h / 2, z)]


def target_row(e, n, width=30.0, z=548.0):
    """East-west target row centred on (e, n), i.e. facing north/south."""
    return [(e - width / 2, n, z), (e + width / 2, n, z)]


class CoordinateTests(unittest.TestCase):
    def test_bern_origin(self):
        lat, lon = rc.lv95_to_wgs84(2600000, 1200000)
        self.assertAlmostEqual(lat, 46.95108, places=4)
        self.assertAlmostEqual(lon, 7.43864, places=4)

    def test_known_point(self):
        # swisstopo search API: "Schiessstand (GR) - Safiental".
        lat, lon = rc.lv95_to_wgs84(2743712.75, 1171775.125)
        self.assertAlmostEqual(lat, 46.681717, delta=2e-5)
        self.assertAlmostEqual(lon, 9.317222, delta=2e-5)

    def test_round_trip(self):
        e, n = rc.wgs84_to_lv95(*rc.lv95_to_wgs84(2683000, 1248000))
        self.assertAlmostEqual(e, 2683000, delta=2)
        self.assertAlmostEqual(n, 1248000, delta=2)

    def test_bearing_cardinal(self):
        self.assertAlmostEqual(rc.true_bearing((E0, N0), (E0, N0 + 300)), 0.0, delta=0.5)
        self.assertAlmostEqual(rc.true_bearing((E0, N0), (E0 + 300, N0)), 90.0, delta=0.5)
        self.assertAlmostEqual(rc.true_bearing((E0, N0), (E0, N0 - 300)), 180.0, delta=0.5)
        self.assertAlmostEqual(rc.true_bearing((E0, N0), (E0 - 300, N0)), 270.0, delta=0.5)

    def test_bearing_removes_grid_convergence(self):
        # Far east of Bern grid north is not true north; the difference is about 1°.
        bearing = rc.true_bearing((2800000, 1180000), (2800000, 1180300))
        self.assertGreater(abs(((bearing + 180) % 360) - 180), 0.5)

    def test_snap_distance(self):
        self.assertEqual(rc.snap_distance(301.4), 300)
        self.assertEqual(rc.snap_distance(270), 300)
        self.assertEqual(rc.snap_distance(52), 50)
        self.assertEqual(rc.snap_distance(24), 25)
        self.assertEqual(rc.snap_distance(10.5), 10)
        self.assertIsNone(rc.snap_distance(200))
        self.assertIsNone(rc.snap_distance(150))

    def test_line_midpoint(self):
        self.assertEqual(rc.line_midpoint([(0, 0), (10, 0), (10, 10)]), (10, 0))
        self.assertEqual(rc.line_midpoint([(0, 0, 1), (4, 0, 1)]), (2, 0))


class GeometryTests(unittest.TestCase):
    def test_point_line_polygon(self):
        self.assertEqual(rc.parse_gpkg_geometry(gpkg_blob("Point", (1, 2, 3))), ("Point", (1, 2, 3)))
        line = [(0, 0, 5), (1, 1, 6)]
        self.assertEqual(rc.parse_gpkg_geometry(gpkg_blob("LineString", line, envelope=0)),
                         ("LineString", line))
        ring = box(0, 0)
        kind, rings = rc.parse_gpkg_geometry(gpkg_blob("Polygon", [ring], envelope=2))
        self.assertEqual(kind, "Polygon")
        self.assertEqual(rings[0], ring)

    def test_multi_and_2d(self):
        body = struct.pack("<BII", 1, 5, 2) + wkb("LineString", [(0, 0), (1, 0)], z=False) \
            + wkb("LineString", [(2, 0), (3, 0)], z=False)
        blob = b"GP\0\x03" + struct.pack("<i", 2056) + b"\0" * 32 + body
        kind, parts = rc.parse_gpkg_geometry(blob)
        self.assertEqual(kind, "MultiLineString")
        self.assertEqual(parts[1], [(2, 0, None), (3, 0, None)])
        self.assertEqual(len(rc.lines_of((kind, parts))), 2)

    def test_ewkb_z_flag(self):
        data = struct.pack("<BI", 1, 0x80000001) + struct.pack("<ddd", 1, 2, 3)
        self.assertEqual(rc.parse_wkb(data)[0], ("Point", (1, 2, 3)))

    def test_empty_and_invalid(self):
        self.assertIsNone(rc.parse_gpkg_geometry(b"GP\0\x21" + b"\0" * 4))
        with self.assertRaises(ValueError):
            rc.parse_gpkg_geometry(b"XX\0\0\0\0\0\0")


class LaneTests(unittest.TestCase):
    def setUp(self):
        # House at the origin, targets 300 m and 50 m north; a second house 1 km east
        # with a 25 m row to its south.
        self.houses = [{"id": "h1", "ring": box(E0, N0)},
                       {"id": "h2", "ring": box(E0 + 1000, N0)}]
        self.targets = [{"id": "t300", "line": target_row(E0, N0 + 4 + 300)},
                        {"id": "t50", "line": target_row(E0 + 5, N0 + 4 + 50)},
                        {"id": "t25", "line": target_row(E0 + 1000, N0 - 4 - 25)}]

    def test_pairing_distance_and_bearing(self):
        lanes = {lane["ids"][1]: lane for lane in rc.lanes_from_pairing(self.houses, self.targets)}
        self.assertEqual(set(lanes), {"t300", "t50", "t25"})
        self.assertEqual(lanes["t300"]["distance"], 300)
        self.assertAlmostEqual(lanes["t300"]["measured"], 300, delta=0.5)
        self.assertAlmostEqual(lanes["t300"]["bearing"], 0, delta=0.5)
        self.assertEqual(lanes["t50"]["distance"], 50)
        self.assertEqual(lanes["t25"]["distance"], 25)
        self.assertAlmostEqual(lanes["t25"]["bearing"], 180, delta=0.5)
        self.assertEqual(lanes["t25"]["house"], "h2")
        self.assertAlmostEqual(lanes["t300"]["altitude"], 550)

    def test_target_row_sideways_to_house_is_not_paired(self):
        # A row running north-south faces east/west, so a house to its south can't shoot at it.
        targets = [{"id": "side", "line": [(E0, N0 + 290, 0), (E0, N0 + 320, 0)]}]
        self.assertEqual(rc.lanes_from_pairing(self.houses[:1], targets), [])

    def test_too_far_is_not_paired(self):
        targets = [{"id": "far", "line": target_row(E0, N0 + 1500)}]
        self.assertEqual(rc.lanes_from_pairing(self.houses, targets), [])

    def test_nearest_facing_house_wins(self):
        houses = self.houses + [{"id": "h3", "ring": box(E0, N0 - 400)}]
        lanes = rc.lanes_from_pairing(houses, [self.targets[0]])
        self.assertEqual(lanes[0]["house"], "h1")

    def test_trajectory_oriented_towards_targets(self):
        # Drawn from the target end back to the house: must be flipped.
        trajectory = {"id": "s1", "line": [(E0, N0 + 304, 548), (E0, N0 + 4, 551)]}
        lanes = rc.build_lanes(self.houses, self.targets, [trajectory])
        lane = next(lane for lane in lanes if lane["source"] == "trajectory")
        self.assertAlmostEqual(lane["bearing"], 0, delta=0.5)
        self.assertEqual(lane["distance"], 300)
        self.assertEqual(lane["altitude"], 551)
        # The 300 m row is explained by the trajectory, so only 50 m and 25 m are paired.
        paired = sorted(lane["ids"][1] for lane in lanes if lane["source"] == "pairing")
        self.assertEqual(paired, ["t25", "t50"])

    def test_trajectory_without_targets_uses_houses(self):
        trajectory = {"id": "s2", "line": [(E0 + 1000, N0 - 54, 0), (E0 + 1000, N0 - 4, 0)]}
        lane = rc.lanes_from_trajectories([trajectory], self.houses, [])[0]
        self.assertAlmostEqual(lane["bearing"], 180, delta=0.5)
        self.assertEqual(lane["distance"], 50)

    def test_grouping(self):
        ranges = rc.group_lanes(rc.lanes_from_pairing(self.houses, self.targets))
        self.assertEqual(len(ranges), 2)
        main = next(r for r in ranges if 300 in r["distances"])
        self.assertEqual(main["distances"], [300, 50])
        self.assertAlmostEqual(main["bearing"], 0, delta=0.5)
        other = next(r for r in ranges if r is not main)
        self.assertEqual(other["distances"], [25])

    def test_unusual_distance_is_rounded(self):
        targets = [{"id": "t200", "line": target_row(E0, N0 + 4 + 198)}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(self.houses, targets))
        self.assertEqual(ranges[0]["distances"], [200])


def overpass_fixture():
    def element(kind, ident, lat, lon, tags, center=False):
        item = {"type": kind, "id": ident, "tags": tags}
        if center:
            item["center"] = {"lat": lat, "lon": lon}
        else:
            item.update(lat=lat, lon=lon)
        return item

    lat_mid, lon_mid = rc.lv95_to_wgs84(E0, N0 + 150)
    lat_town, lon_town = rc.lv95_to_wgs84(E0 + 2000, N0 + 2000)
    lat_indoor, lon_indoor = rc.lv95_to_wgs84(E0 + 5000, N0)
    return {"elements": [
        element("way", 1, lat_mid, lon_mid,
                {"sport": "shooting", "leisure": "pitch", "name": "Schiessanlage Riedbach",
                 "website": "https://example.ch"}, center=True),
        element("way", 2, lat_mid, lon_mid, {"sport": "shooting", "leisure": "pitch"}, center=True),
        element("node", 3, lat_town, lon_town, {"place": "village", "name": "Riedbach"}),
        element("way", 4, lat_indoor, lon_indoor,
                {"sport": "shooting", "shooting": "indoor_range", "name": "Luftgewehr Halle"}, center=True),
        element("way", 5, lat_indoor, lon_indoor,
                {"sport": "shooting", "name": "Luftgewehr Halle"}, center=True),
        element("node", 6, lat_indoor, lon_indoor,
                {"sport": "shooting", "shooting": "paintball", "name": "Paintball"}),
        element("node", 7, lat_indoor, lon_indoor, {"sport": "shooting"}),
    ]}


class NameTests(unittest.TestCase):
    def test_clean_name(self):
        self.assertEqual(rc.clean_name("  Schiessanlage   Fänglen "), "Schiessanlage Fänglen")
        self.assertEqual(rc.clean_name("Schiessstand"), "")
        self.assertEqual(rc.clean_name("stand de tir"), "")
        self.assertEqual(rc.clean_name(None), "")
        self.assertEqual(rc.clean_name("k_W"), "")  # swissTLM3D's "no value"

    def test_swisstopo_name_used_without_osm(self):
        houses = [{"id": "h1", "ring": box(E0, N0), "name": ""}]
        targets = [{"id": "t50", "line": target_row(E0, N0 + 54), "name": "Stand Allmend"},
                   {"id": "t300", "line": target_row(E0, N0 + 304), "name": "Schiessanlage Allmend"}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        rc.match_osm(ranges, [], [])
        self.assertEqual(ranges[0]["name"], "Schiessanlage Allmend")  # longest lane's name first


class OsmTests(unittest.TestCase):
    def test_parse_skips_paintball(self):
        shooting, places = rc.parse_overpass(overpass_fixture())
        self.assertEqual([p["tags"]["name"] for p in places], ["Riedbach"])
        self.assertNotIn("node/6", [s["osm"] for s in shooting])
        self.assertEqual(len(shooting), 5)

    def test_match_and_osm_only(self):
        shooting, places = rc.parse_overpass(overpass_fixture())
        houses = [{"id": "h1", "ring": box(E0, N0)}, {"id": "h9", "ring": box(E0 + 30000, N0)}]
        targets = [{"id": "t300", "line": target_row(E0, N0 + 304)},
                   {"id": "t9", "line": target_row(E0 + 30000, N0 + 54)}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        leftovers = rc.match_osm(ranges, shooting, places)
        named = next(r for r in ranges if r["osm"])
        self.assertEqual(named["name"], "Schiessanlage Riedbach")
        self.assertEqual(named["osm"], "way/1")
        self.assertEqual(named["website"], "https://example.ch")
        self.assertEqual(named["place"], "Riedbach")
        self.assertEqual(named["name_source"], "osm")
        unnamed = next(r for r in ranges if not r["osm"])
        self.assertEqual(unnamed["name"], "Schiessanlage")  # no place within 10 km
        self.assertEqual(unnamed["name_source"], "generated")

        extra = rc.osm_only_ranges(leftovers, places)
        self.assertEqual([r["name"] for r in extra], ["Luftgewehr Halle"])  # merged, unnamed dropped
        self.assertIsNone(extra[0]["bearing"])
        self.assertEqual(extra[0]["place"], "Riedbach")
        self.assertTrue(extra[0]["indoor"])

    def test_swisstopo_place_beats_osm(self):
        shooting, places = rc.parse_overpass(overpass_fixture())
        houses = [{"id": "h1", "ring": box(E0, N0)}]
        targets = [{"id": "t300", "line": target_row(E0, N0 + 304), "name": ""}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        tlm_places = [{"pos": (E0 + 3000, N0), "tags": {"name": "Musterdorf"}}]
        rc.match_osm(ranges, shooting, places, tlm_places)
        self.assertEqual(ranges[0]["place"], "Musterdorf")
        self.assertEqual(ranges[0]["place_source"], "swisstopo")
        self.assertEqual(ranges[0]["name"], "Schiessanlage Riedbach")  # OSM fills the missing name
        self.assertEqual(ranges[0]["name_source"], "osm")


class GeoPackageTests(unittest.TestCase):
    def make_gpkg(self, path):
        conn = sqlite3.connect(path)
        conn.execute("CREATE TABLE gpkg_geometry_columns (table_name TEXT, column_name TEXT)")
        conn.execute('CREATE TABLE tlm_bauten_gebaeude_footprint (fid INTEGER PRIMARY KEY, uuid TEXT,'
                     ' nutzung TEXT, geom BLOB)')
        conn.execute('CREATE TABLE tlm_bauten_sportbaute_lin (fid INTEGER PRIMARY KEY, UUID TEXT,'
                     ' OBJEKTART TEXT, NAME TEXT, geom BLOB)')
        conn.executemany("INSERT INTO gpkg_geometry_columns VALUES (?, 'geom')",
                         [("tlm_bauten_gebaeude_footprint",), ("tlm_bauten_sportbaute_lin",)])
        conn.executemany("INSERT INTO tlm_bauten_gebaeude_footprint (uuid, nutzung, geom) VALUES (?,?,?)", [
            ("{H1}", "Schiessstand", gpkg_blob("Polygon", [box(E0, N0)])),
            ("{H2}", "Wohngebaeude", gpkg_blob("Polygon", [box(E0 + 50, N0)])),
        ])
        conn.executemany("INSERT INTO tlm_bauten_sportbaute_lin (UUID, OBJEKTART, NAME, geom) VALUES (?,?,?,?)", [
            ("{T1}", "Scheibenstand", "Schiessanlage Fänglen",
             gpkg_blob("LineString", target_row(E0, N0 + 304))),
            ("{S1}", "Schusslinie", "Schiessstand",
             gpkg_blob("LineString", [(E0, N0 + 4, 550), (E0, N0 + 54, 549)])),
            ("{L1}", "Laufbahn", None, gpkg_blob("LineString", [(E0, N0, 0), (E0 + 100, N0, 0)])),
        ])
        conn.execute('CREATE TABLE tlm_names_siedlungsname (fid INTEGER PRIMARY KEY, NAME TEXT,'
                     ' OBJEKTART TEXT, geom BLOB)')
        conn.execute("INSERT INTO gpkg_geometry_columns VALUES ('tlm_names_siedlungsname', 'geom')")
        conn.executemany("INSERT INTO tlm_names_siedlungsname (NAME, OBJEKTART, geom) VALUES (?,?,?)", [
            ("Fänglen", "Ort", gpkg_blob("Point", (E0 + 800, N0 + 300, 600))),
            ("Oberfänglen", "Ortsteil", gpkg_blob("Point", (E0 + 10, N0 + 10, 600))),
        ])
        conn.commit()
        conn.close()

    def test_read_tlm(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "tlm.gpkg")
            self.make_gpkg(path)
            houses, targets, trajectories, places = rc.read_tlm(path)
        self.assertEqual([h["id"] for h in houses], ["H1"])
        self.assertEqual([t["id"] for t in targets], ["T1"])
        self.assertEqual([t["id"] for t in trajectories], ["S1"])
        self.assertEqual(targets[0]["name"], "Schiessanlage Fänglen")
        self.assertEqual(trajectories[0]["name"], "")  # generic label dropped
        self.assertEqual(houses[0]["name"], "")
        self.assertEqual([p["tags"]["name"] for p in places], ["Fänglen"])  # Ortsteil skipped

    def test_inspect_lists_values(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "tlm.gpkg")
            self.make_gpkg(path)
            out = io.StringIO()
            rc.inspect_tlm(path, out)
        text = out.getvalue()
        self.assertIn("3 feature tables", text)
        self.assertIn("'Scheibenstand': 1", text)
        self.assertIn("nutzung = 'Schiessstand': 1", text)
        self.assertIn("tlm_bauten_sportbaute_lin names: 1 of 1 named", text)
        self.assertIn("'Ortsteil': 1", text)

    def test_build_writes_json_and_csv(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "tlm.gpkg")
            self.make_gpkg(path)
            osm = os.path.join(tmp, "overpass.json")
            with open(osm, "w") as f:
                json.dump(overpass_fixture(), f)
            out = os.path.join(tmp, "out")
            stats = rc.build(path, osm, out, "2026-02")
            with open(os.path.join(out, "ranges.json")) as f:
                catalogue = json.load(f)
            with open(os.path.join(out, "ranges.csv")) as f:
                rows = list(csv.DictReader(f))

        self.assertEqual(stats["shooting houses"], 1)
        self.assertEqual(stats["  name from swisstopo"], 1)
        self.assertEqual(stats["  name from OSM (no swisstopo name)"], 0)
        self.assertEqual(stats["  place from swisstopo"], 1)
        self.assertEqual(stats["  website from OSM"], 1)
        self.assertEqual(stats["ranges from OSM only"], 1)
        self.assertEqual(stats["  of which indoor"], 1)
        self.assertEqual(stats["lanes from trajectories"], 1)
        self.assertEqual(catalogue["version"], 1)
        self.assertEqual(catalogue["swissTLM3D"], "2026-02")
        self.assertIn("OpenStreetMap", catalogue["attribution"]["osm"])
        self.assertIn("swisstopo", catalogue["attribution"]["swisstopo"])
        tlm = next(r for r in catalogue["ranges"] if r["id"].startswith("tlm:"))
        self.assertEqual(tlm["name"], "Schiessanlage Fänglen")  # swisstopo name beats OSM
        self.assertEqual(tlm["place"], "Fänglen")
        self.assertEqual(tlm["website"], "https://example.ch")
        self.assertEqual(tlm["osm"], "way/1")
        self.assertEqual(tlm["distances"], [300, 50])
        self.assertAlmostEqual(tlm["shootingBearing"], 0, delta=0.5)
        self.assertEqual(tlm["altitude"], 550)
        self.assertAlmostEqual(tlm["latitude"], 46.95112, delta=1e-4)
        self.assertEqual({lane["source"] for lane in tlm["lanes"]}, {"pairing", "trajectory"})
        indoor = next(r for r in catalogue["ranges"] if r["id"].startswith("osm:"))
        self.assertNotIn("shootingBearing", indoor)
        self.assertEqual(len(rows), len(catalogue["ranges"]))
        self.assertEqual(rows[0].keys() >= {"east_lv95", "north_lv95", "shooting_bearing"}, True)

    def test_latest_gpkg(self):
        stac = {"features": [
            {"id": "swisstlm3d_2022-03", "assets": {"a": {"type": "application/x.filegdb+zip",
                                                        "href": "https://x/2022.gdb.zip"}}},
            {"id": "swisstlm3d_2026-02", "assets": {
                "a": {"type": "application/x.shapefile+zip", "href": "https://x/2026.shp.zip"},
                "b": {"type": "application/x.geopackage+zip", "href": "https://x/2026.gpkg.zip"}}},
            {"id": "swisstlm3d_2025-03", "assets": {"b": {"type": "application/x.geopackage+zip",
                                                        "href": "https://x/2025.gpkg.zip"}}},
        ]}
        self.assertEqual(rc.latest_gpkg(stac), ("2026-02", "https://x/2026.gpkg.zip"))
        with self.assertRaises(ValueError):
            rc.latest_gpkg({"features": []})

    def test_overpass_query_covers_switzerland(self):
        self.assertIn('"ISO3166-1"="CH"', rc.OVERPASS_QUERY)
        self.assertIn("sport", rc.OVERPASS_QUERY)
        self.assertIn("place", rc.OVERPASS_QUERY)


if __name__ == "__main__":
    unittest.main()
