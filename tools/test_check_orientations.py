"""Unit tests for tools/check_orientations.py.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest

import check_orientations as co

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check_orientations.py")
ALL = sorted(co.ALL)


class OrientationTests(unittest.TestCase):
    def test_accepts_all_plus_portrait_iphone(self):
        info = {"UISupportedInterfaceOrientations": ALL,
                "UISupportedInterfaceOrientations~ipad": ALL,
                "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"]}
        self.assertEqual(co.problems(info), [])

    def test_rejects_portrait_only_plain_key(self):
        # What the first upload had: only the device-specific keys were right.
        info = {"UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"],
                "UISupportedInterfaceOrientations~ipad": ALL,
                "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"]}
        self.assertEqual(len(co.problems(info)), 1)

    def test_rejects_missing_keys(self):
        self.assertEqual(len(co.problems({})), 2)

    def test_rejects_rotating_iphone(self):
        info = {"UISupportedInterfaceOrientations": ALL,
                "UISupportedInterfaceOrientations~iphone": ALL}
        self.assertEqual(len(co.problems(info)), 1)

    def test_command_line_exit_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = os.path.join(tmp, "good.plist")
            bad = os.path.join(tmp, "bad.plist")
            with open(good, "wb") as f:
                plistlib.dump({"UISupportedInterfaceOrientations": ALL,
                               "UISupportedInterfaceOrientations~iphone": ["UIInterfaceOrientationPortrait"]}, f)
            with open(bad, "wb") as f:
                plistlib.dump({"UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait"]}, f)
            self.assertEqual(subprocess.run([sys.executable, SCRIPT, good]).returncode, 0)
            self.assertEqual(subprocess.run([sys.executable, SCRIPT, bad], capture_output=True).returncode, 1)


if __name__ == "__main__":
    unittest.main()
