"""Helpers for .github/workflows/ipad-screens.yml.

    xcrun simctl list devices available -j | python3 tools/ipad_screens.py pick-ipad
    python3 tools/ipad_screens.py rename <xcresulttool export dir> <out dir>
"""
import json
import os
import re
import shutil
import sys


def _ios_version(runtime):
    # "com.apple.CoreSimulator.SimRuntime.iOS-26-0" -> (26, 0)
    m = re.search(r"iOS-(\d+)(?:-(\d+))?", runtime)
    return (int(m.group(1)), int(m.group(2) or 0)) if m else None


def pick_ipad(simctl):
    """UDID of the largest iPad on the newest iOS runtime in `simctl list devices -j` output."""
    best = None
    for runtime, devices in simctl.get("devices", {}).items():
        version = _ios_version(runtime)
        if version is None:
            continue
        for d in devices:
            name = d.get("name", "")
            if not name.startswith("iPad") or not d.get("isAvailable", True):
                continue
            # Prefer the 13-inch iPad Pro: the widest layout shows the most problems.
            size = 2 if "iPad Pro" in name and "13" in name else 1 if "iPad Pro" in name else 0
            key = (version, size, name)
            if best is None or key > best[0]:
                best = (key, d["udid"])
    if best is None:
        raise ValueError("no iPad simulator available")
    return best[1]


def screenshot_name(human_name):
    """'portrait-1-Tagebuch_0_1A2B…-….png' -> 'portrait-1-Tagebuch.png'."""
    base, ext = os.path.splitext(human_name)
    base = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", base)
    base = re.sub(r"[^\w.-]+", "_", base).strip("_") or "screenshot"
    return base + (ext or ".png")


def rename(raw_dir, out_dir):
    """Copy the exported attachments to out_dir under their attachment names; returns the names."""
    with open(os.path.join(raw_dir, "manifest.json")) as f:
        manifest = json.load(f)
    os.makedirs(out_dir, exist_ok=True)
    names = []
    for test in manifest:
        for a in test.get("attachments", []):
            name = screenshot_name(a.get("suggestedHumanReadableName") or a["exportedFileName"])
            stem, ext = os.path.splitext(name)
            n = 2
            while name in names:
                name = f"{stem}-{n}{ext}"
                n += 1
            shutil.copyfile(os.path.join(raw_dir, a["exportedFileName"]), os.path.join(out_dir, name))
            names.append(name)
    return sorted(names)


def main(argv):
    if argv[1:2] == ["pick-ipad"]:
        print(pick_ipad(json.load(sys.stdin)))
    elif argv[1:2] == ["rename"] and len(argv) == 4:
        for name in rename(argv[2], argv[3]):
            print(name)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
