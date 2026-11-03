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


def manual_fixture():
    return {"ranges": [
        {"id": "manual:halle", "name": "Indoor Halle", "place": "Riedbach", "lat": 46.9, "lon": 7.5,
         "distances": [10, 25], "website": "https://example.ch"},
        {"id": "manual:keller", "name": "Schiesskeller", "place": "Moos", "lat": 47.1, "lon": 8.2},
    ]}


class NameTests(unittest.TestCase):
    def test_clean_name(self):
        self.assertEqual(rc.clean_name("  Schiessanlage   Fänglen "), "Schiessanlage Fänglen")
        self.assertEqual(rc.clean_name("Schiessstand"), "")
        self.assertEqual(rc.clean_name("stand de tir"), "")
        self.assertEqual(rc.clean_name(None), "")
        self.assertEqual(rc.clean_name("k_W"), "")  # swissTLM3D's "no value"

    def test_swisstopo_name_from_target_rows(self):
        houses = [{"id": "h1", "ring": box(E0, N0), "name": ""}]
        targets = [{"id": "t50", "line": target_row(E0, N0 + 54), "name": "Stand Allmend"},
                   {"id": "t300", "line": target_row(E0, N0 + 304), "name": "Schiessanlage Allmend"}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        rc.name_ranges(ranges, [])
        self.assertEqual(ranges[0]["name"], "Schiessanlage Allmend")  # longest lane's name first


class SwisstopoNameTests(unittest.TestCase):
    def test_name_distances(self):
        self.assertEqual(rc.name_distances("Thun Guntelsey 300/50/25m"), [300, 50, 25])
        self.assertEqual(rc.name_distances("Zuchwil Feldacker 300/150/100/60/50/25m"), [300, 150, 100, 60, 50, 25])
        self.assertEqual(rc.name_distances("Bôle 300m"), [300])
        self.assertEqual(rc.name_distances("Stans Schwybogen 50 / 30 / 25 m"), [50, 30, 25])
        self.assertEqual(rc.name_distances("Schiessanlage Moos"), [])
        self.assertEqual(rc.name_distances(""), [])

    def test_buildings_with_one_name_are_one_range(self):
        # Two shooting houses 200 m apart (300 m and 25 m stand), both named like the range.
        name = "Riedbach Forst 300/25m"
        houses = [{"id": "h300", "ring": box(E0, N0), "name": name},
                  {"id": "h25", "ring": box(E0 + 200, N0), "name": name}]
        targets = [{"id": "t300", "line": target_row(E0, N0 + 304), "name": ""},
                   {"id": "t25", "line": target_row(E0 + 200, N0 + 29), "name": ""}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        self.assertEqual(len(ranges), 1)
        self.assertEqual(ranges[0]["tlm_name"], name)
        self.assertEqual(ranges[0]["distances"], [300, 25])
        self.assertAlmostEqual(ranges[0]["bearing"], 0, delta=0.5)

    def test_name_distances_beat_measured_ones(self):
        houses = [{"id": "h", "ring": box(E0, N0), "name": "Moos 300/50m"}]
        targets = [{"id": "t", "line": target_row(E0, N0 + 4 + 280), "name": ""}]  # measured 280 m
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        self.assertEqual(ranges[0]["distances"], [300, 50])

    def test_house_without_target_row(self):
        houses = [{"id": "paired", "ring": box(E0, N0), "name": "Moos 300m"},
                  {"id": "annex", "ring": box(E0 + 60, N0), "name": "Moos 300m"},
                  {"id": "indoor1", "ring": box(E0 + 5000, N0), "name": "Au Halle 10m"},
                  {"id": "indoor2", "ring": box(E0 + 5030, N0), "name": "Au Halle 10m"},
                  {"id": "unnamed", "ring": box(E0 + 9000, N0), "name": ""}]
        targets = [{"id": "t", "line": target_row(E0, N0 + 304), "name": ""}]
        lanes = rc.lanes_from_pairing(houses, targets)
        extra = rc.house_only_ranges(houses, lanes)
        self.assertEqual([r["tlm_name"] for r in extra], ["Au Halle 10m"])
        self.assertIsNone(extra[0]["bearing"])
        self.assertEqual(extra[0]["distances"], [10])
        self.assertEqual(extra[0]["altitude"], 550)

    def test_place_from_name(self):
        places = [{"pos": (E0 + 3000, N0), "tags": {"name": "Bern"}},
                  {"pos": (E0 + 1000, N0), "tags": {"name": "Riedbach"}},
                  {"pos": (E0 + 900, N0), "tags": {"name": "Ried"}},
                  {"pos": (E0 + 90000, N0), "tags": {"name": "Moos"}}]
        self.assertEqual(rc.place_from_name("Bern-Riedbach Forst 300m", (E0, N0), places), "Bern")
        self.assertEqual(rc.place_from_name("Riedbach Forst 300m", (E0, N0), places), "Riedbach")
        self.assertEqual(rc.place_from_name("Moos 300m", (E0, N0), places), "", "too far away")
        self.assertEqual(rc.place_from_name("Riedli 300m", (E0, N0), places), "", "whole words only")

    def test_place_prefers_the_town_in_the_name(self):
        houses = [{"id": "h", "ring": box(E0, N0), "name": "Kiesen 300m"}]
        targets = [{"id": "t", "line": target_row(E0, N0 + 304), "name": ""}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        tlm_places = [{"pos": (E0 + 100, N0), "tags": {"name": "Aarhus"}},
                      {"pos": (E0 + 2000, N0), "tags": {"name": "Kiesen"}}]
        rc.name_ranges(ranges, tlm_places)
        self.assertEqual(ranges[0]["place"], "Kiesen")
        self.assertEqual(ranges[0]["name"], "Kiesen 300m")


class NamingTests(unittest.TestCase):
    def test_unnamed_range_gets_place_name(self):
        houses = [{"id": "h1", "ring": box(E0, N0)}, {"id": "h9", "ring": box(E0 + 30000, N0)}]
        targets = [{"id": "t300", "line": target_row(E0, N0 + 304)},
                   {"id": "t9", "line": target_row(E0 + 30000, N0 + 54)}]
        ranges = rc.group_lanes(rc.lanes_from_pairing(houses, targets))
        rc.name_ranges(ranges, [{"pos": (E0 + 3000, N0), "tags": {"name": "Musterdorf"}}])
        near = next(r for r in ranges if r["place"])
        self.assertEqual(near["name"], "Schiessanlage Musterdorf")
        self.assertEqual(near["name_source"], "generated")
        far = next(r for r in ranges if not r["place"])
        self.assertEqual(far["name"], "Schiessanlage")  # no place within 10 km


class ManualListTests(unittest.TestCase):
    def test_manual_ranges(self):
        ranges = rc.manual_ranges(manual_fixture())
        self.assertEqual([r["id"] for r in ranges], ["manual:halle", "manual:keller"])
        halle = ranges[0]
        self.assertTrue(halle["indoor"])
        self.assertIsNone(halle["bearing"])
        self.assertEqual(halle["distances"], [25, 10])
        lat, lon = rc.lv95_to_wgs84(*halle["firing"])
        self.assertAlmostEqual(lat, 46.9, delta=1e-4)
        self.assertAlmostEqual(lon, 7.5, delta=1e-4)
        record = rc.range_record(halle)
        self.assertTrue(record["indoor"])
        self.assertEqual(record["website"], "https://example.ch")
        self.assertNotIn("shootingBearing", record)
        self.assertEqual(ranges[1]["distances"], [])

    def test_manual_ranges_reject_bad_entries(self):
        good = manual_fixture()["ranges"][0]
        for bad in ({**good, "id": "osm:node/1"}, {**good, "name": " "}, {**good, "lat": None},
                    {**good, "lat": 48.5}, {**good, "distances": [25.5]}, {**good, "place": ""}):
            with self.assertRaises(ValueError, msg=bad):
                rc.manual_ranges({"ranges": [bad]})
        with self.assertRaises(ValueError):
            rc.manual_ranges({"ranges": [good, good]})

    def test_repository_indoor_list_is_valid(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "indoor-ranges.json")
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        ranges = rc.manual_ranges(data)
        self.assertGreaterEqual(len(ranges), 10)
        for item in data["ranges"]:
            self.assertTrue(item.get("website", "").startswith("https://"), item["id"])
            self.assertTrue(item.get("address"), item["id"])
            self.assertFalse({"osm", "osm_id"} & item.keys(), "positions must not come from OSM")


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
            manual = os.path.join(tmp, "indoor.json")
            with open(manual, "w") as f:
                json.dump(manual_fixture(), f)
            out = os.path.join(tmp, "out")
            stats = rc.build(path, manual, out, "2026-02")
            with open(os.path.join(out, "ranges.json")) as f:
                catalogue = json.load(f)
            with open(os.path.join(out, "ranges.csv")) as f:
                rows = list(csv.DictReader(f))

        self.assertEqual(stats["shooting houses"], 1)
        self.assertEqual(stats["  name from swisstopo"], 1)
        self.assertEqual(stats["  with place"], 1)
        self.assertEqual(stats["indoor ranges from the hand-made list"], 2)
        self.assertEqual(stats["lanes from trajectories"], 1)
        self.assertEqual(catalogue["version"], 1)
        self.assertEqual(catalogue["swissTLM3D"], "2026-02")
        self.assertEqual(list(catalogue["attribution"]), ["swisstopo"])
        tlm = next(r for r in catalogue["ranges"] if r["id"].startswith("tlm:"))
        self.assertEqual(tlm["name"], "Schiessanlage Fänglen")
        self.assertEqual(tlm["place"], "Fänglen")
        self.assertNotIn("website", tlm)
        self.assertNotIn("indoor", tlm)
        self.assertEqual(tlm["distances"], [300, 50])
        self.assertAlmostEqual(tlm["shootingBearing"], 0, delta=0.5)
        self.assertEqual(tlm["altitude"], 550)
        self.assertAlmostEqual(tlm["latitude"], 46.95112, delta=1e-4)
        self.assertEqual({lane["source"] for lane in tlm["lanes"]}, {"pairing", "trajectory"})
        indoor = next(r for r in catalogue["ranges"] if r["id"] == "manual:halle")
        self.assertNotIn("shootingBearing", indoor)
        self.assertTrue(indoor["indoor"])
        self.assertEqual(indoor["place"], "Riedbach")
        self.assertEqual(next(r for r in rows if r["id"] == "manual:halle")["source"], "manual")
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

    def test_round_bearing_stays_below_360(self):
        self.assertEqual(rc.round_bearing(359.96), 0.0)
        self.assertEqual(rc.round_bearing(359.94), 359.9)
        self.assertEqual(rc.round_bearing(12.345), 12.3)
        app = rc.app_catalogue({"ranges": [{"id": "tlm:1", "name": "A", "place": "B", "latitude": 47.0,
                                            "longitude": 8.0, "distances": [50], "shootingBearing": 360.0}]})
        self.assertEqual(app["ranges"][0]["bearing"], 0.0)

    def test_app_catalogue(self):
        def rng(ident, name, place, distances, bearing=10.0):
            return {"id": ident, "name": name, "place": place, "latitude": 46.9, "longitude": 7.4,
                    "distances": distances, "shootingBearing": bearing, "altitude": 500}

        catalogue = {"swissTLM3D": "2026-02", "ranges": [
            rng("tlm:1", "Schiessanlage Moos", "Moos", [300]),
            rng("tlm:2", "Schiessanlage Moos", "Moos", [50, 25]),
            rng("tlm:3", "Schiessanlage Moos", "Moos", [50, 25], bearing=None),
            rng("tlm:4", "Schiessanlage Moos", "Riedbach", [300]),
            rng("tlm:5", "Schiessanlage Au", "Au", []),
            {"id": "manual:x", "name": "Halle", "place": "Au", "latitude": 47.0, "longitude": 8.0,
             "distances": [25], "indoor": True},
        ]}
        app = rc.app_catalogue(catalogue)
        self.assertEqual(app["source"], "Schiessanlagen: swissTLM3D © swisstopo")
        self.assertEqual(app["swissTLM3D"], "2026-02")
        names = [r["name"] for r in app["ranges"]]
        self.assertEqual(names, ["Schiessanlage Moos (300 m)", "Schiessanlage Moos (50/25 m) 1",
                                 "Schiessanlage Moos (50/25 m) 2", "Schiessanlage Moos", "Schiessanlage Au",
                                 "Halle"])
        self.assertEqual(app["ranges"][0], {"id": "tlm:1", "name": "Schiessanlage Moos (300 m)", "place": "Moos",
                                            "lat": 46.9, "lon": 7.4, "distances": [300],
                                            "bearing": 10.0, "alt": 500})
        self.assertNotIn("bearing", app["ranges"][2])
        self.assertEqual(app["ranges"][5], {"id": "manual:x", "name": "Halle", "place": "Au", "lat": 47.0,
                                            "lon": 8.0, "distances": [25], "indoor": True})

    def test_build_without_manual_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "tlm.gpkg")
            self.make_gpkg(path)
            out = os.path.join(tmp, "out")
            stats = rc.build(path, "-", out)
            with open(os.path.join(out, "ranges.json")) as f:
                catalogue = json.load(f)
        self.assertEqual(stats["indoor ranges from the hand-made list"], 0)
        self.assertEqual([r["name"] for r in catalogue["ranges"]], ["Schiessanlage Fänglen"])
        self.assertEqual(list(catalogue["attribution"]), ["swisstopo"])

if __name__ == "__main__":
    unittest.main()
