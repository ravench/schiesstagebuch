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
    if not target["source"].get("title") or not target["source"].get("url"):
        found.append(f"{name}: source needs a title and url")
    return found


def app_json(targets):
    """The targets as the app reads them: ids, names, distances, scoring and rings, no comments."""
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
        src = t["source"]
        entry["source"] = src["title"] + (f", {src['rule']}" if src.get("rule") else "")
        out.append(entry)
    return out


def main(argv):
    targets = load()
    errors = [line for t in targets for line in problems(t)]
    ids = [t.get("id") for t in targets]
    errors += [f"id {i} used twice" for i in sorted(set(ids)) if ids.count(i) > 1]
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
