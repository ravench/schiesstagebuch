"""Checks on the Build workflow (.github/workflows/build.yml)."""
import re
import unittest
from pathlib import Path

BUILD = Path(__file__).resolve().parent.parent / ".github" / "workflows" / "build.yml"


class BuildWorkflowTests(unittest.TestCase):
    def test_unit_test_scheme_is_built_last(self):
        # Building the app for the Screens scheme after the unit test scheme removes
        # SchiesstagebuchTests.xctest from the app, and test-without-building can't load it
        # (main, 2026-11-05).
        schemes = re.search(r"for SCHEME in ([^;]+);", BUILD.read_text()).group(1).split()
        self.assertEqual(schemes[-1], "Schiesstagebuch")
        self.assertIn("SchiesstagebuchScreens", schemes)


if __name__ == "__main__":
    unittest.main()
