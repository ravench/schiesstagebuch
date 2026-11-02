"""Checks the orientations in a built app's Info.plist, as App Store Connect does.

    python3 tools/check_orientations.py path/to/Schiesstagebuch.app/Info.plist

The upload is rejected unless the plain UISupportedInterfaceOrientations key lists
all four orientations (iPad multitasking); the iPhone stays portrait-only.
"""
import plistlib
import sys

ALL = {
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
}
PORTRAIT = {"UIInterfaceOrientationPortrait"}


def problems(info):
    """What App Store Connect (or our iPhone layout) would object to; empty when fine."""
    found = []
    if set(info.get("UISupportedInterfaceOrientations", [])) != ALL:
        found.append("UISupportedInterfaceOrientations must list all four orientations")
    ipad = info.get("UISupportedInterfaceOrientations~ipad")
    if ipad is not None and set(ipad) != ALL:
        found.append("UISupportedInterfaceOrientations~ipad must list all four orientations")
    if set(info.get("UISupportedInterfaceOrientations~iphone", [])) != PORTRAIT:
        found.append("UISupportedInterfaceOrientations~iphone must be portrait only")
    return found


def main(argv):
    if len(argv) != 2:
        sys.exit(__doc__)
    with open(argv[1], "rb") as f:
        found = problems(plistlib.load(f))
    for problem in found:
        print(f"::error::{problem} ({argv[1]})")
    sys.exit(1 if found else 0)


if __name__ == "__main__":
    main(sys.argv)
