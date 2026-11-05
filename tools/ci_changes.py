"""Does a pull request need the Mac build?

Reads the changed file paths (one per line) on stdin and prints `mac=true` or `mac=false` for
$GITHUB_OUTPUT. Pull requests that change only these files skip the Mac job of the Build
workflow: lint and the Linux tools job still check them, and runners for macOS are scarce.

    gh api repos/OWNER/REPO/pulls/N/files --paginate --jq '.[].filename' | python3 tools/ci_changes.py
"""
import fnmatch
import sys

# fnmatch's * also matches /, so "tools/*" covers the whole folder.
NO_MAC = ["*.md", ".claude/*", ".github/*", "tools/*", ".gitignore", ".swiftlint.yml"]
# Exceptions: the Mac job itself, and the tool it runs on the built app.
NEEDS_MAC = [".github/workflows/build.yml", "tools/check_orientations.py"]


def needs_mac(paths):
    """True unless every path is one the Mac job does not check. No paths: build to be safe."""
    paths = [p.strip() for p in paths if p.strip()]
    if not paths:
        return True
    for path in paths:
        if path in NEEDS_MAC or not any(fnmatch.fnmatch(path, pattern) for pattern in NO_MAC):
            return True
    return False


if __name__ == "__main__":
    print(f"mac={'true' if needs_mac(sys.stdin) else 'false'}")
