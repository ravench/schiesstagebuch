"""Targets (Scheiben): checks data/targets/*.toml and writes them as JSON for the app.

One TOML file per target and scoring (A10 and A5 are two files), named after its id. Each
says how a single shot is scored, in one of two ways:

- a range: any value from `min` to `max`, e.g. 0 to 10.9 (decimal rifle scoring) or
  0 to 100 (A100 hundredths), typed on the decimal keypad;
- a list of `values`: the only scores a shot can have, e.g. [5, 4, 3, 2, 1, 0] on A5,
  [10, 9, 8, 7, 6, 5, 0] on ISSF rapid fire (numbers only; named zones such as IPSC come later).

These are the templates of Settings › Scheiben in the app, where users also register their
own targets: a range target keeps the decimal keypad and flags values outside it, a list
target shows only its values as buttons and moves on to the next shot after each tap. Ring diameters, the inner ten and the black are optional and only describe
the face. Each file names its source.

The app draws a small icon of each face (Raven 2026-11-17): the rings and the black on a white
card. Targets that are not just rings add `[[shapes]]`, drawn under the rings in file order, in mm
from the scoring centre with y pointing down. The first shape is the card: a filled `rect`, which
also frames the icon. A shape is one of

    rect = [x, y, width, height]     (top left corner; `radius` rounds the corners)
    ellipse = [centre x, centre y, width, height]
    polygon = [[x, y], [x, y], ...]

with a `fill` and/or a `line` colour from COLOURS. `face = "<id>"` draws another target's face
first (A100 looks like A10), then this target's own shapes, rings and black.

    python3 tools/targets.py check
    python3 tools/targets.py json out/Targets.json

Only the standard library is used, so the unit tests run anywhere.
"""
import glob
import json
import os
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "targets")


def load(folder=DATA):
    """All targets in `folder`, sorted by id."""
    targets = []
    for path in sorted(glob.glob(os.path.join(folder, "*.toml"))):
        with open(path, "rb") as f:
            target = tomllib.load(f)
        target["_file"] = os.path.basename(path)
        targets.append(target)
    return targets


def _number(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def scoring_problems(scoring):
    """What is wrong with a [scoring] table; empty when it is fine."""
    if ("max" in scoring) == ("values" in scoring):
        return ["scoring needs either min and max, or values"]
    if "max" in scoring:
        if not (_number(scoring["max"]) and _number(scoring.get("min")) and 0 <= scoring["min"] < scoring["max"]):
            return ["scoring min and max must be numbers with 0 <= min < max"]
        return []
    values = scoring["values"]
    if len(values) < 2 or len(set(values)) != len(values):
        return ["scoring values need at least two different values"]
    if all(_number(v) for v in values):
        return [] if values == sorted(values, reverse=True) else ["scoring values must go from best to worst"]
    # Named values (IPSC zones) come later; the app reads numbers only, and one name would empty its list.
    return ["scoring values must all be numbers"]


COLOURS = ("white", "black", "grey", "green", "khaki", "red", "blue")


def shape_problems(shape):
    """What is wrong with one [[shapes]] entry; empty when it is fine."""
    kinds = [k for k in ("rect", "ellipse", "polygon") if k in shape]
    if len(kinds) != 1:
        return ["a shape needs one of rect, ellipse or polygon"]
    found = []
    if kinds[0] == "polygon":
        points = shape["polygon"]
        if len(points) < 3 or any(len(p) != 2 or not all(_number(v) for v in p) for p in points):
            found.append("a polygon needs at least three [x, y] points")
    else:
        box = shape[kinds[0]]
        if len(box) != 4 or not all(_number(v) for v in box) or box[2] <= 0 or box[3] <= 0:
            found.append(f"a {kinds[0]} needs [x, y, width, height] with a size above 0")
    if "fill" not in shape and "line" not in shape:
        found.append("a shape needs a fill or a line colour")
    found += [f"colour {shape[k]} is not one of {', '.join(COLOURS)}" for k in ("fill", "line")
              if k in shape and shape[k] not in COLOURS]
    if "radius" in shape and (kinds[0] != "rect" or not _number(shape["radius"]) or shape["radius"] < 0):
        found.append("radius is for rects only and must be 0 or more")
    return found


def problems(target):
    """What is wrong with one target, as readable lines; empty when it is fine."""
    name = target.get("_file", target.get("id", "?"))
    found = [f"{name}: {key} missing" for key in ("id", "name", "short_name", "group", "distances_m", "scoring", "source")
             if key not in target]
    if found:
        return found
    if target["_file"] != target["id"] + ".toml":
        found.append(f"{name}: file name is not the id {target['id']}")
    found += [f"{name}: {line}" for line in scoring_problems(target["scoring"])]
    rings = target.get("ring_diameters_mm")
    if rings is not None:
        if not rings or rings[0] <= 0 or any(b <= a for a, b in zip(rings, rings[1:])):
            found.append(f"{name}: ring diameters must grow from the centre outwards")
        else:
            inner = target.get("inner_ten_mm")
            if inner is not None and not 0 < inner < rings[0]:
                found.append(f"{name}: inner ten {inner} mm is not inside the centre ring ({rings[0]} mm)")
            black = target.get("black_mm")
            if black is not None and not 0 < black <= rings[-1]:
                found.append(f"{name}: black {black} mm is larger than the scoring field ({rings[-1]} mm)")
            values = target["scoring"].get("values", [])
            if values and all(_number(v) for v in values) and values[-1] == 0 and len(values) - 1 != len(rings):
                found.append(f"{name}: {len(rings)} rings for {len(values) - 1} scores")
    elif "inner_ten_mm" in target or "black_mm" in target:
        found.append(f"{name}: inner ten and black need ring diameters")
    shapes = target.get("shapes", [])
    for shape in shapes:
        found += [f"{name}: {line}" for line in shape_problems(shape)]
    if shapes and "face" not in target and not ("rect" in shapes[0] and "fill" in shapes[0]):
        found.append(f"{name}: the first shape must be the card, a filled rect")
    if target.get("face") == target["id"]:
        found.append(f"{name}: face names the target itself")
    if not target["source"].get("title") or not target["source"].get("url"):
        found.append(f"{name}: source needs a title and url")
    return found


def face(target, by_id):
    """What the app draws for `target`'s icon: shapes, ring diameters and black, with its `face`
    target's drawn first. None when there is nothing to draw (the app then shows a plain symbol)."""
    base = face(by_id[target["face"]], by_id) if "face" in target else None
    shapes = (base["shapes"] if base else []) + target.get("shapes", [])
    rings = target.get("ring_diameters_mm") or (base["rings"] if base else [])
    black = target.get("black_mm", base.get("black") if base else None)
    if not shapes and not rings:
        return None
    out = {"shapes": shapes, "rings": rings}
    if black is not None:
        out["black"] = black
    return out


def app_json(targets):
    """The targets as the app reads them: ids, names, distances, scoring, rings and face, no comments."""
    by_id = {t["id"]: t for t in targets}
    out = []
    for t in targets:
        s = t["scoring"]
        entry = {
            "id": t["id"],
            "name": t["name"],
            "shortName": t["short_name"],
            "group": t["group"],
            "distances": t["distances_m"],
            "scoring": {"values": s["values"]} if "values" in s else {"min": s["min"], "max": s["max"]},
        }
        for key, app_key in (("ring_diameters_mm", "ringDiameters"), ("inner_ten_mm", "innerTen"), ("black_mm", "black")):
            if key in t:
                entry[app_key] = t[key]
        drawn = face(t, by_id)
        if drawn:
            entry["face"] = drawn
        src = t["source"]
        entry["source"] = src["title"] + (f", {src['rule']}" if src.get("rule") else "")
        out.append(entry)
    return out


def face_reference_problems(targets):
    """Faces that name a target that does not exist, or that go round in a circle."""
    by_id = {t.get("id"): t for t in targets}
    found = []
    for t in targets:
        seen, current = [t.get("id")], t
        while "face" in current:
            ref = current["face"]
            if ref not in by_id:
                found.append(f"{t['_file']}: face {ref} is no target")
                break
            if ref in seen:
                found.append(f"{t['_file']}: faces go round in a circle: {' > '.join(seen + [ref])}")
                break
            seen.append(ref)
            current = by_id[ref]
        else:
            if "face" not in t and not t.get("shapes") and not t.get("ring_diameters_mm"):
                found.append(f"{t['_file']}: nothing to draw: needs rings, shapes or a face")
    return found


def main(argv):
    targets = load()
    errors = [line for t in targets for line in problems(t)]
    ids = [t.get("id") for t in targets]
    errors += [f"id {i} used twice" for i in sorted(set(ids)) if ids.count(i) > 1]
    errors += face_reference_problems(targets)
    for line in errors:
        print(line, file=sys.stderr)
    if errors:
        return 1
    if argv[1:2] == ["json"]:
        with open(argv[2], "w", encoding="utf-8") as f:
            # One target per line: small diffs when a target changes.
            f.write("[\n" + ",\n".join(json.dumps(t, ensure_ascii=False) for t in app_json(targets)) + "\n]\n")
    print(f"{len(targets)} targets fine")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
