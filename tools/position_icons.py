"""Shooting position pictograms: a figure with a rifle, facing right, in a 48x48 box.

Writes one template image set per position into Resources/Assets.xcassets (Position-<raw value>),
so the app shows them with Image("Position-prone") in the tint or text colour, menus included.
Limbs are capsules (strokes with round ends); every shape winds the same way, so overlaps join.

    python3 tools/position_icons.py
"""
import json
import math
import os
import re
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Schiesstagebuch", "Resources", "Assets.xcassets")
SIZE = 48
# Points the image takes when not resized: about an SF Symbol at body size, for menus and labels.
POINTS = 22
# Empty space around the drawing, like the side bearings of an SF Symbol.
MARGIN = 2.5
LIMB, BODY, HEAD, GUN = 4.6, 6.2, 4.4, 3.6


def _f(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def capsule(a, b, w):
    """A stroke from a to b, w wide with round ends."""
    (x1, y1), (x2, y2), r = a, b, w / 2
    ang = math.atan2(y2 - y1, x2 - x1)
    pts = [(x2 + r * math.cos(ang - math.pi / 2 + math.pi * i / 12), y2 + r * math.sin(ang - math.pi / 2 + math.pi * i / 12)) for i in range(13)]
    pts += [(x1 + r * math.cos(ang + math.pi / 2 + math.pi * i / 12), y1 + r * math.sin(ang + math.pi / 2 + math.pi * i / 12)) for i in range(13)]
    return "M" + " L".join(f"{_f(x)} {_f(y)}" for x, y in pts) + " Z"


def chain(*pts, w=LIMB):
    return [capsule(pts[i], pts[i + 1], w) for i in range(len(pts) - 1)]


def head(c):
    return capsule(c, (c[0] + 0.01, c[1]), 2 * HEAD)


def rect(x, y, w, h):
    # Same winding as the capsules.
    return f"M{_f(x)} {_f(y)} L{_f(x + w)} {_f(y)} L{_f(x + w)} {_f(y + h)} L{_f(x)} {_f(y + h)} Z"


def rifle(butt, muzzle):
    """Barrel to the muzzle and a thicker stock over the rear 38 %; the butt sits against the shoulder."""
    (x1, y1), (x2, y2) = butt, muzzle
    grip = (x1 + (x2 - x1) * 0.38, y1 + (y2 - y1) * 0.38)
    return [capsule(butt, muzzle, GUN * 0.55), capsule(butt, grip, GUN * 1.25)]


def _icons():
    icons = {}
    # Liegend: legs back on the ground, front elbow down, cheek on the stock.
    sh, hip = (27, 35.5), (13, 40.5)
    icons["prone"] = [head((30.5, 29))] + chain(sh, hip, w=BODY) + chain(hip, (2.5, 43)) + chain(hip, (4.5, 40), (2.5, 43.6)) \
        + chain(sh, (36, 42.5), (40, 32.5)) + rifle((27.5, 34), (47, 31))
    # Kniend: sitting on the rear heel, front elbow on the raised knee.
    sh, hip = (20, 17), (15, 32)
    icons["kneeling"] = [head((22.5, 10))] + chain(sh, hip, w=BODY) + chain(hip, (24, 43), (9, 43)) + chain(hip, (29, 32), (30, 44)) \
        + chain(sh, (28, 29), (32, 17)) + chain(sh, (18, 24), (25, 17.5)) + rifle((21, 17), (46, 15))
    # Stehend: upright, front arm under the rifle.
    sh, hip = (21, 14.5), (19, 28)
    icons["standing"] = [head((23, 7.5))] + chain(sh, hip, w=BODY) + chain(hip, (15.5, 44)) + chain(hip, (23, 44)) \
        + chain(sh, (19, 22), (26, 15.5)) + chain(sh, (27, 22), (33, 15)) + rifle((22, 14.5), (46, 12.5))
    # Aufgelegt: seated on a stool at a table, the rifle on a rest.
    sh, hip = (18, 18), (14, 33)
    icons["rested"] = [head((21, 11))] + chain(sh, hip, w=BODY) + chain(hip, (26, 33), (26, 44)) \
        + chain(sh, (23, 27), (29, 21.5)) + chain(sh, (15, 25), (22, 20)) \
        + [rect(26, 26, 20, 2.6), rect(41, 28.6, 2.6, 15.6), rect(36, 21.8, 4, 4.2), rect(8, 34, 11, 2.4), rect(12.3, 36.4, 2.4, 7.8)] \
        + rifle((19, 18.5), (46, 21.5))
    return icons


ICONS = _icons()


def _points(paths):
    nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", " ".join(paths))]
    return list(zip(nums[::2], nums[1::2]))


def view_box(paths):
    """The same scale for every figure, centred on its drawing with MARGIN on each side, so the
    prone figure sits mid-height like the text next to it and nothing touches its label."""
    pts = _points(paths)
    xs, ys = [x for x, _ in pts], [y for _, y in pts]
    side = SIZE + 2 * MARGIN
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    return f"{_f(cx - side / 2)} {_f(cy - side / 2)} {_f(side)} {_f(side)}"


def svg(paths):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{POINTS}" height="{POINTS}" viewBox="{view_box(paths)}">'
            f'<path fill="#000" d="{" ".join(paths)}"/></svg>\n')


def contents(filename):
    return {"images": [{"filename": filename, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}}


def write(assets=ASSETS):
    # Sets of positions that no longer exist go.
    for old in os.listdir(assets):
        if old.startswith("Position-") and old.removeprefix("Position-").removesuffix(".imageset") not in ICONS:
            shutil.rmtree(os.path.join(assets, old))
    for key, paths in ICONS.items():
        folder = os.path.join(assets, f"Position-{key}.imageset")
        os.makedirs(folder, exist_ok=True)
        name = f"Position-{key}.svg"
        with open(os.path.join(folder, name), "w") as f:
            f.write(svg(paths))
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump(contents(name), f, indent=2)
            f.write("\n")


if __name__ == "__main__":
    write()
    print(f"{len(ICONS)} position icons")
