"""Weapon category silhouettes, side view, muzzle to the right, in a 128x48 box.

Each icon has `solids` (filled, union) and optional `holes` (punched out after).
Paths use only absolute M, L, Q, C, Z so the app's parser stays tiny.
"""
import math


def poly(*pts):
    return "M" + " L".join(f"{x:g} {y:g}" for x, y in pts) + " Z"


def rect(x, y, w, h):
    return poly((x, y), (x + w, y), (x + w, y + h), (x, y + h))


def circle_pts(cx, cy, r, n=28, ccw=False):
    pts = [(cx + r * math.cos(2 * math.pi * i / n), cy + r * math.sin(2 * math.pi * i / n)) for i in range(n)]
    return list(reversed(pts)) if ccw else pts


def circle(cx, cy, r):
    return "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in circle_pts(cx, cy, r)) + " Z"


def ring(cx, cy, R, r):
    outer = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in circle_pts(cx, cy, R)) + " Z"
    inner = "M" + " L".join(f"{x:.2f} {y:.2f}" for x, y in circle_pts(cx, cy, r, ccw=True)) + " Z"
    return outer + " " + inner


def guard(x, y, w, h):
    """Trigger guard: solid D shape and its hole."""
    return (f"M{x} {y} L{x + w} {y} Q{x + w} {y + h} {x + w * 0.45} {y + h} L{x} {y + h * 0.75} Z",
            f"M{x + 2.5} {y} L{x + w - 2.5} {y} Q{x + w - 2.5} {y + h - 3} {x + w * 0.45} {y + h - 3} L{x + 2.5} {y + h * 0.6} Z")


ICONS = {}


def icon(key, title, solids, holes=()):
    ICONS[key] = {"title": title, "solids": list(solids), "holes": list(holes)}


g_solid, g_hole = guard(48, 24, 22, 12)
icon("pistol", "Pistole", [
    poly((14, 9), (112, 9), (114, 11), (114, 20), (14, 20)),
    rect(18, 6, 5, 3), rect(106, 6, 4, 3),
    rect(30, 20, 80, 5),
    g_solid,
    "M14 20 L46 20 L50 27 Q44 38 42 47 L20 47 Q22 36 26 28 L14 24 Z",
], [g_hole] + [rect(20 + i * 3, 11, 1.3, 7) for i in range(4)])

g_solid, g_hole = guard(40, 24, 18, 12)
icon("revolver", "Revolver", [
    rect(60, 10, 62, 7), rect(116, 7, 4, 3), rect(62, 17, 30, 3),
    poly((44, 6), (62, 6), (64, 8), (64, 24), (62, 26), (44, 26), (42, 24), (42, 8)),
    poly((24, 8), (44, 8), (44, 24), (30, 24), (22, 16)),
    poly((22, 10), (25, 3), (30, 4), (29, 10)),
    "M22 15 L38 22 Q34 36 38 46 L20 47 Q14 36 18 22 Z",
    g_solid,
], [g_hole, rect(45, 10, 16, 2), rect(45, 20, 16, 2)])

g_solid, g_hole = guard(44, 22, 16, 10)
icon("pcc", "PCC", [
    rect(30, 12, 52, 10), rect(82, 13, 32, 8), rect(112, 15, 10, 4),
    poly((62, 22), (72, 22), (74, 40), (64, 40)),
    poly((40, 22), (51, 22), (47, 40), (36, 40)),
    g_solid,
    poly((2, 12), (32, 12), (32, 22), (12, 30), (2, 30)),
    rect(48, 5, 14, 6), rect(51, 10, 8, 2),
], [g_hole, poly((8, 16), (27, 16), (27, 20), (11, 26), (8, 26)),
    rect(86, 15, 6, 4), rect(95, 15, 6, 4), rect(104, 15, 6, 4)])

g_solid, g_hole = guard(44, 23, 16, 10)
icon("service_rifle", "Sturmgewehr", [
    rect(34, 12, 46, 11), poly((80, 12), (104, 13), (104, 21), (80, 22)),
    rect(104, 15, 16, 3), rect(118, 14, 8, 5), rect(82, 22, 24, 2),
    "M60 23 L70 23 Q72 34 78 42 L69 46 Q62 36 60 23 Z",
    poly((40, 23), (51, 23), (47, 41), (36, 41)),
    g_solid,
    poly((2, 11), (34, 12), (34, 22), (5, 31), (2, 31)),
    rect(36, 7, 7, 5), rect(97, 8, 3, 5),
], [g_hole, poly((7, 15), (30, 15.5), (30, 19.5), (8, 26))])

icon("sport_rifle", "Sportgewehr", [
    "M2 14 L10 12 L30 14 L56 16 L92 18 L92 26 L58 26 Q52 38 42 38 L36 30 L24 30 L12 34 L8 46 L2 46 Z",
    rect(56, 14, 68, 4), rect(38, 11, 26, 5),
    rect(36, 4, 7, 7), rect(116, 7, 7, 7), rect(80, 26, 4, 7),
], ["M35 19 L50 20 Q48 28 42 28 L35 27 Z", rect(117.5, 9, 4, 3)])

g_solid, g_hole = guard(42, 22, 14, 9)
icon("long_range", "Präzisionsgewehr", [
    poly((2, 12), (38, 12), (38, 24), (28, 30), (12, 30), (2, 34)),
    rect(10, 9, 22, 3), rect(14, 30, 3, 10),
    poly((38, 22), (49, 22), (47, 40), (36, 40)), g_solid,
    rect(38, 13, 30, 9), rect(68, 13, 30, 8), rect(98, 15, 22, 3), rect(118, 12.5, 8, 8),
    rect(56, 22, 10, 9),
    rect(42, 5, 40, 4),
    poly((80, 4), (90, 2), (98, 2), (98, 11), (90, 11), (80, 9)),
    poly((34, 3), (44, 4), (44, 10), (34, 11)),
    rect(60, 1, 6, 4), rect(50, 9, 4, 4), rect(74, 9, 4, 4),
    poly((90, 21), (93, 21), (101, 44), (98, 44)),
    poly((92, 21), (95, 21), (88, 44), (85, 44)),
], [g_hole, rect(70, 15, 5, 4), rect(78, 15, 5, 4), rect(86, 15, 5, 4)])

icon("hunting_rifle", "Jagdgewehr", [
    "M2 17 Q20 14 40 16 L96 18 L96 24 L60 24 Q54 26 50 26 Q46 33 42 36 L36 34 Q40 28 38 25 L22 31 Q12 38 2 40 Z",
    poly((94, 15.5), (124, 16.5), (124, 19), (94, 20)),
    rect(40, 13, 30, 5),
    poly((52, 18), (55, 18), (51, 26), (48, 26)), rect(46, 24.5, 4.5, 4),
    rect(46, 6, 30, 4),
    poly((74, 5.5), (84, 3), (92, 3), (92, 12), (84, 12), (74, 10.5)),
    poly((36, 4.5), (47, 5.5), (47, 10.5), (36, 11.5)),
    rect(52, 10, 3, 3.5), rect(70, 10, 3, 3.5),
    "M54 24 L64 24 Q63 31 57 31 L54 29 Z",
], ["M56 24 L62 24 Q61 28.5 57.5 28.5 L56 27.5 Z"])

icon("shotgun", "Flinte", [
    rect(50, 12, 74, 3), rect(50, 15.6, 74, 3), rect(121, 10.6, 2, 1.6),
    rect(34, 11, 18, 10),
    poly((54, 18.6), (92, 18.6), (90, 23), (56, 24)),
    "M2 19 Q20 16 34 12 L36 21 Q33 27 30 30 L25 28 Q23 25 21 25 Q10 29 2 37 Z",
    "M38 21 L48 21 Q48 28 42 28 L38 26 Z",
], ["M40 21 L46 21 Q46 25.5 42.5 25.5 L40 24.5 Z", rect(37, 13, 12, 1.2)])

icon("airgun", "Luftgewehr", [
    "M2 14 L10 12 L30 14 L56 16 L92 18 L92 26 L58 26 Q52 38 42 38 L36 30 L24 30 L12 34 L8 46 L2 46 Z",
    rect(56, 12, 66, 3.5),
    "M56 16.5 L98 16.5 Q102 16.5 102 19.5 Q102 22.5 98 22.5 L56 22.5 Z",
    rect(38, 10, 24, 5),
    rect(36, 3, 7, 7), rect(114, 6, 7, 6),
], ["M35 19 L50 20 Q48 28 42 28 L35 27 Z", rect(115.5, 7.5, 4, 3)])

icon("black_powder", "Vorderlader", [
    "M2 21 Q16 18 30 16 L110 17 L110 21 L42 22 Q38 24 36 26 L30 28 Q16 32 2 39 Z",
    poly((30, 13), (124, 14), (124, 17), (30, 17)),
    rect(44, 22, 78, 1.6),
    poly((31, 8), (35, 7), (38, 13), (34, 14)),
    "M38 22 L48 22 Q48 28 42 28 L38 26 Z",
    rect(72, 13, 2.4, 9), rect(100, 13.5, 2.4, 8),
    rect(121, 11.5, 1.6, 2.5),
], ["M40 22 L46 22 Q46 25.5 42.5 25.5 L40 24.8 Z"])

icon("other", "Andere", [ring(64, 24, 21, 17), ring(64, 24, 13, 9), circle(64, 24, 5)])
