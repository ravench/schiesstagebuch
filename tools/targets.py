"""Target faces (Scheiben): checks data/targets/*.toml and writes them as JSON for the app.

One TOML file per target face and scoring (A10 and A5 are two files), named after its id,
with the ring diameters from the centre outwards, the score of the centre ring and the source.
The app uses the scores to check single shots as they are typed: a target scored 5 to 1
takes only 0 to 5, one digit, so the entry can move on after each digit. The ISSF faces come from the ISSF General Technical
Rules; Swiss faces follow from SIUS's STYX packages and the SSV rules.

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
    """All target faces in `folder`, sorted by id."""
    targets = []
    for path in sorted(glob.glob(os.path.join(folder, "*.toml"))):
        with open(path, "rb") as f:
            target = tomllib.load(f)
        target["_file"] = os.path.basename(path)
        targets.append(target)
    return targets


def problems(target):
    """What is wrong with one target face, as readable lines; empty when it is fine."""
    found = []
    name = target.get("_file", target.get("id", "?"))
    for key in ("id", "name", "short_name", "distances_m", "top_value", "ring_diameters_mm", "source"):
        if key not in target:
            found.append(f"{name}: {key} missing")
    if found:
        return found
    if target["_file"] != target["id"] + ".toml":
        found.append(f"{name}: file name is not the id {target['id']}")
    rings = target["ring_diameters_mm"]
    lowest = lowest_ring(target)
    if lowest < 1:
        found.append(f"{name}: {len(rings)} ring diameters, but the centre scores only {target['top_value']}")
    if any(b <= a for a, b in zip(rings, rings[1:])) or rings[0] <= 0:
        found.append(f"{name}: ring diameters must grow from the 10 outwards")
    inner = target.get("inner_ten_mm")
    if inner is not None and not 0 < inner < rings[0]:
        found.append(f"{name}: inner ten {inner} mm is not inside the 10 ({rings[0]} mm)")
    if ("black_mm" in target) != ("black_from_ring" in target):
        found.append(f"{name}: black_mm and black_from_ring go together")
    elif "black_mm" in target:
        ring = target["black_from_ring"]
        top = target["top_value"]
        if not lowest <= ring <= top:
            found.append(f"{name}: black from ring {ring}, which the target does not have")
        elif not (rings[top - ring - 1] if ring < top else 0) < target["black_mm"] <= rings[top - ring]:
            # The black may end inside its outermost ring, as on the ISSF 50 m target.
            found.append(f"{name}: black {target['black_mm']} mm does not end in ring {ring} ({rings[top - ring]} mm)")
    if not target["source"].get("title") or not target["source"].get("url"):
        found.append(f"{name}: source needs a title and url")
    return found


def lowest_ring(target):
    """Score of the outermost ring; a shot outside it scores 0."""
    return target["top_value"] - len(target["ring_diameters_mm"]) + 1


def shot_values(target):
    """The whole scores a single shot can have, misses (0) included, highest first.
    Decimal targets also take tenths up to top_value + 0.9."""
    return list(range(target["top_value"], lowest_ring(target) - 1, -1)) + [0]


def app_json(targets):
    """The targets as the app reads them: ids, names, distances and rings, no comments."""
    return [{
        "id": t["id"],
        "name": t["name"],
        "shortName": t["short_name"],
        "distances": t["distances_m"],
        "topValue": t["top_value"],
        "lowestRing": lowest_ring(t),
        "decimal": t.get("decimal", False),
        "ringDiameters": t["ring_diameters_mm"],
        **({"innerTen": t["inner_ten_mm"]} if "inner_ten_mm" in t else {}),
        **({"black": t["black_mm"], "blackFromRing": t["black_from_ring"]} if "black_mm" in t else {}),
        "source": t["source"]["title"] + (f", {t['source']['rule']}" if t["source"].get("rule") else ""),
    } for t in targets]


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
