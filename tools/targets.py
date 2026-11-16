"""Targets (Scheiben): checks data/targets/*.toml and writes them as JSON for the app.

One TOML file per target and scoring (A10 and A5 are two files), named after its id. Each
says how a single shot is scored, in one of two ways:

- a range: any value from 0 up to `max` in steps of `step`, e.g. 0 to 10.9 in tenths
  (decimal rifle scoring) or 0 to 100 (A100 hundredths);
- a list of `values`: the only scores a shot can have, e.g. [5, 4, 3, 2, 1, 0] on A5,
  [10, 9, 8, 7, 6, 5, 0] on ISSF rapid fire, or zone names like ["A", "C", "D", "M"].

The app checks single shots against this as they are typed, and offers only the values a
target allows. Ring diameters, the inner ten and the black are optional and only describe
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
        return ["scoring needs either max and step, or values"]
    if "max" in scoring:
        if not (_number(scoring["max"]) and _number(scoring.get("step")) and 0 < scoring["step"] <= scoring["max"]):
            return ["scoring max and step must be numbers with 0 < step <= max"]
        steps = scoring["max"] / scoring["step"]
        if abs(steps - round(steps)) > 1e-9:
            return [f"scoring max {scoring['max']} is not a whole number of steps of {scoring['step']}"]
        return []
    values = scoring["values"]
    if len(values) < 2 or len(set(values)) != len(values):
        return ["scoring values need at least two different values"]
    if all(_number(v) for v in values):
        return [] if values == sorted(values, reverse=True) else ["scoring values must go from best to worst"]
    if all(isinstance(v, str) and v for v in values):
        return []
    return ["scoring values must be all numbers or all names"]


def problems(target):
    """What is wrong with one target, as readable lines; empty when it is fine."""
    name = target.get("_file", target.get("id", "?"))
    found = [f"{name}: {key} missing" for key in ("id", "name", "short_name", "distances_m", "scoring", "source")
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
            "distances": t["distances_m"],
            "scoring": {"values": s["values"]} if "values" in s else {"max": s["max"], "step": s["step"]},
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
            json.dump(app_json(targets), f, ensure_ascii=False, indent=1)
            f.write("\n")
    print(f"{len(targets)} targets fine")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
