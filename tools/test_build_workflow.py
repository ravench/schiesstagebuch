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
        # The PR screens rebuild the Screens scheme for the base branch, after the unit tests.
        text = BUILD.read_text()
        before_unit_tests = text[:text.index('"$RUNNER_TEMP/UnitTests.xcresult"')]
        schemes = re.findall(r"xcodebuild build-for-testing \\\s+-project \S+ \\\s+-scheme (\S+)", before_unit_tests)
        self.assertEqual(schemes, ["SchiesstagebuchScreens", "Schiesstagebuch"])

    def test_tests_write_results_for_the_summary(self):
        text = BUILD.read_text()
        for bundle in ("UnitTests", "UITests"):
            self.assertIn(f'-resultBundlePath "$RUNNER_TEMP/{bundle}.xcresult"', text)
        self.assertIn("python3 tools/test_summary.py", text)


if __name__ == "__main__":
    unittest.main()
