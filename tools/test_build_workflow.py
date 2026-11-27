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

    def test_every_ui_test_class_runs_in_ci(self):
        # The Build job names the UI test classes one by one; a new class must be added there (the two
        # tours run as the PR screens instead).
        text = BUILD.read_text()
        listed = set(re.findall(r"-only-testing:SchiesstagebuchUITests/(\w+)", text))
        folder = BUILD.parent.parent.parent / "SchiesstagebuchUITests"
        # Every XCTestCase, whatever it is called: a class named differently, or not final, never ran
        # and nothing said so (review 2026-11-27).
        classes = {m for f in folder.glob("*.swift") for m in re.findall(r"class (\w+)\s*:\s*XCTestCase\b", f.read_text())}
        self.assertEqual(classes - {"PRScreensTests", "IPadScreensTests"}, listed - {"PRScreensTests", "IPadScreensTests"})

    def test_reading_jobs_get_a_read_only_token(self):
        text = BUILD.read_text()
        for job in ("lint", "tools"):
            body = text[text.index(f"  {job}:\n"):]
            body = body[:re.search(r"\n  [a-z-]+:\n", body[1:]).start() + 1]
            self.assertRegex(body, r"permissions:\n\s+contents: read\n", job)


if __name__ == "__main__":
    unittest.main()
