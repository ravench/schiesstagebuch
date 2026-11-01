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


# Handguns are drawn at roughly real proportions (length about 1.6x height), centred in the box.
g_solid, g_hole = guard(52, 22, 17, 11)
icon("pistol", "Pistole", [
    poly((28, 6), (98, 6), (100, 8), (100, 17), (28, 17)),
    rect(31, 3.5, 4, 2.5), rect(94, 3.5, 3, 2.5),
    rect(44, 17, 54, 5),
    g_solid,
    # Straight grip, about 18 degrees back, flat magazine base, small beavertail.
    poly((28, 17), (51, 17), (51, 22), (46, 44.5), (28.5, 44.5), (33, 21.5), (27, 19)),
    rect(28, 44, 18.5, 2.2),
], [g_hole] + [rect(32 + i * 2.6, 8, 1.2, 7) for i in range(4)])

# Parabellum / Luger (P08, Swiss 06/29): toggle lock, thin barrel, steeply raked grip.
icon("luger", "Parabellum", [
    rect(60, 12.5, 38, 4.2),  # barrel
    rect(94.5, 10, 2.5, 2.6),
    rect(42, 10.5, 20, 9),  # receiver
    rect(31, 8, 22, 4.5), circle(32, 10.2, 3.6), circle(52, 10.2, 2.4),  # toggle
    # Frame and grip as one piece, so the grip grows out of the frame.
    "M29.5 11 L64 11 L64 22 L50.5 22 Q44 33 40 44.5 L27 44.5 Q27.5 40 29 36 Q32.5 26 29.5 17 Z",
    "M48 22 L62 22 Q63 31 56 32 Q50 32.5 46 28 Z",
], ["M50 22 L60 22 Q60.5 29 55.5 29.5 Q51.5 29.8 48.5 26.5 Z", rect(34, 9, 16, 1)])

g_solid, g_hole = guard(38, 23, 15, 11)
icon("revolver", "Revolver", [
    rect(60, 9, 40, 6), rect(95, 6, 3, 3), rect(60, 15, 26, 3),
    poly((42, 6), (60, 6), (61, 8), (61, 22), (60, 24), (42, 24), (41, 22), (41, 8)),
    poly((28, 7), (42, 7), (42, 24), (34, 24), (27, 15)),
    poly((26, 9), (28, 3), (32, 4), (31, 9)),
    # Grip angles down and back from the frame, with a rounded butt.
    "M28 13 L42 22 Q38 30 36 38 Q34 46 28 46 Q20 46 20.5 39 Q21.5 27 24.5 18 Q25.5 13 28 13 Z",
    g_solid,
], [g_hole, rect(44, 10, 15, 2), rect(44, 18, 15, 2)])

g_solid, g_hole = guard(50, 20, 14, 9)
icon("sport_pistol", "Sportpistole", [
    rect(34, 8, 30, 8),
    rect(40, 9, 64, 6.5),  # barrel
    rect(70, 15.5, 24, 5),  # barrel weight
    rect(36, 5, 6, 3), rect(100, 6, 3, 3),
    rect(44, 16, 26, 4),
    g_solid,
    # Anatomical grip with hand shelf.
    "M30 12 L50 16 L52 22 Q48 30 47 36 L53 40 L51 44 L31 46 Q26 46 26.5 42 Q27.5 32 28.5 24 Q24 20 22 15 Z",
], [g_hole])

# Long guns use roughly real length-to-height ratios (PCC ~3.2, service rifle ~3.8,
# sport/precision ~3.7-4, hunting ~4.4, shotgun ~5.4, muzzleloader ~5.3).
# Barrels are drawn as one continuous piece from action to muzzle.
g_solid, g_hole = guard(46, 21, 13, 8)
icon("pcc", "PCC", [
    poly((14, 12), (36, 13), (36, 22), (18, 28), (14, 28)),
    rect(36, 12, 40, 9),
    rect(76, 13, 28, 7),
    rect(76, 15, 38, 3),  # barrel, continuous through the handguard
    rect(110, 14.5, 5, 4),
    rect(50, 6, 12, 5), rect(53, 10.5, 6, 1.5),
    poly((60, 21), (67, 21), (68, 38), (61, 38)),
    poly((42, 21), (50, 21), (47, 36), (39, 36)),
    g_solid,
], [g_hole, poly((18, 15.5), (32, 16), (32, 20), (20, 24.5), (18, 24.5))]
   + [rect(80 + i * 7, 13.8, 4, 1.4) for i in range(3)])

g_solid, g_hole = guard(42, 22, 12, 8)
icon("service_rifle", "Sturmgewehr", [
    poly((4, 11), (34, 12), (34, 21), (8, 28), (4, 28)),
    rect(34, 12, 40, 10),
    poly((74, 12), (98, 13), (98, 20), (74, 21)),
    rect(74, 15, 44, 3),  # barrel
    rect(116, 14, 8, 5),
    rect(76, 21, 26, 1.8),
    "M56 22 L64 22 Q65 30 70 37 L63 40 Q58 32 56 22 Z",
    poly((38, 22), (46, 22), (43, 36), (35, 36)),
    g_solid,
    rect(36, 8, 5, 4), rect(94, 9, 2.5, 4),
], [g_hole, poly((8, 14.5), (30, 15.3), (30, 18.8), (10, 24.5), (8, 24.5))])

SPORT_STOCK = "M2 13 L8 12.5 L30 14 L52 15 L{fe} 15.5 L{fe} 21.5 L56 21.5 Q51 30 44 30 L39 25 L26 25 L12 27.5 L9.5 32 L4 32 Q2 28 2 24 Z"
THUMBHOLE = "M35 17.5 L48 18 Q46.5 23 41.5 23 L35 22.5 Z"

icon("sport_rifle", "Sportgewehr", [
    SPORT_STOCK.format(fe=92),
    rect(38, 11, 22, 5),
    rect(56, 13, 70, 3.2),  # barrel
    rect(36, 6, 6, 5), rect(118, 8, 6, 5),
    rect(80, 21.5, 4, 5),
], [THUMBHOLE, rect(119.5, 9.5, 3, 2)])

g_solid, g_hole = guard(40, 22, 12, 8)
icon("long_range", "Präzisionsgewehr", [
    poly((2, 13), (36, 13), (36, 23), (28, 27), (12, 27), (2, 31)),
    rect(10, 10.5, 22, 2.5), rect(14, 27, 2.5, 7),
    poly((36, 22), (44, 22), (42, 36), (34, 36)), g_solid,
    rect(36, 13, 28, 9), rect(64, 13.5, 32, 7.5),
    rect(64, 15.5, 56, 2.8),  # barrel
    rect(118, 14, 8, 6),
    rect(52, 22, 9, 8),
    rect(42, 7, 38, 3.4),
    poly((78, 6.5), (88, 5), (94, 5), (94, 12), (88, 12), (78, 10.5)),
    poly((34, 6), (43, 6.6), (43, 10.6), (34, 11.2)),
    rect(58, 4, 5, 3), rect(48, 10.4, 3.5, 2.6), rect(70, 10.4, 3.5, 2.6),
    poly((88, 21), (90.5, 21), (97, 38), (94.5, 38)),
    poly((90, 21), (92.5, 21), (86, 38), (83.5, 38)),
], [g_hole] + [rect(68 + i * 7, 13.9, 4, 1.2) for i in range(4)])

icon("hunting_rifle", "Jagdgewehr", [
    "M2 17 Q20 15 38 16.5 L94 18 L94 23 L60 23 Q54 24.5 50 24.5 Q47 30 43 33 L38 31.5 Q41 27 39 24 L22 29 Q12 34 2 35 Z",
    poly((60, 16.4), (124, 16.8), (124, 18.8), (60, 19.6)),  # barrel
    rect(38, 13.5, 30, 4.5),
    poly((50, 18), (52.5, 18), (49.5, 24), (47, 24)), rect(45.5, 23, 4, 3.5),
    rect(44, 8.6, 28, 3.2),
    poly((70, 8.2), (80, 6.5), (88, 6.5), (88, 13.5), (80, 13.5), (70, 11.8)),
    poly((35, 7.6), (45, 8.2), (45, 12.2), (35, 12.8)),
    rect(50, 11.8, 3, 1.8), rect(64, 11.8, 3, 1.8),
    "M54 23 L63 23 Q62 29 57 29 L54 27.5 Z",
], ["M55.8 23 L61.2 23 Q60.5 27 57.3 27 L55.8 26.3 Z"])

icon("shotgun", "Flinte", [
    rect(48, 12, 76, 2.8), rect(48, 15.2, 76, 2.8), rect(121, 10.8, 2, 1.4),
    rect(34, 11.5, 16, 8.5),
    poly((52, 18), (90, 18), (88, 21.5), (54, 22.5)),
    "M2 19 Q18 16.5 34 12 L36 20 Q33.5 25 30.5 27.5 L26 26 Q24 23.5 22 23.5 Q10 27 2 34 Z",
    "M37 20 L46 20 Q46 26 41 26 L37 24.5 Z",
], ["M38.8 20 L44.2 20 Q44.2 24 41.2 24 L38.8 23.2 Z", rect(36, 13.5, 11, 1)])

icon("airgun", "Luftgewehr", [
    SPORT_STOCK.format(fe=78),
    rect(38, 10.5, 22, 5),
    rect(56, 12.5, 66, 2.8),  # barrel
    "M56 16 L98 16 Q102 16 102 18.8 Q102 21.6 98 21.6 L56 21.6 Z",  # air cylinder
    rect(36, 5.5, 6, 5), rect(114, 7.5, 6, 5),
], [THUMBHOLE, rect(115.5, 9, 3, 2)])

icon("black_powder", "Vorderlader", [
    "M2 22 Q16 19.5 30 17.5 L110 18 L110 21.5 L42 22 Q38 24 36 26 L30 27.5 Q16 30.5 2 33 Z",
    poly((30, 15), (124, 15.6), (124, 18.2), (30, 18.4)),
    rect(44, 22.3, 78, 1.4),
    poly((31, 10.5), (35, 9.5), (38, 15), (34, 15.5)),
    "M38 22 L47 22 Q47 27 42 27 L38 25.5 Z",
    rect(72, 15, 2.2, 7.5), rect(100, 15.2, 2.2, 6.8),
    rect(121, 14, 1.4, 1.8),
], ["M39.8 22 L45.2 22 Q45.2 25.3 42.2 25.3 L39.8 24.6 Z"])

icon("other", "Andere", [ring(64, 24, 21, 17), ring(64, 24, 13, 9), circle(64, 24, 5)])
