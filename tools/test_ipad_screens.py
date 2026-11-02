"""Unit tests for tools/ipad_screens.py and the iPad screens workflow.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import json
import os
import re
import tempfile
import unittest

import ipad_screens

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RT = "com.apple.CoreSimulator.SimRuntime.iOS-"


class PickIpadTests(unittest.TestCase):
    def test_newest_runtime_and_largest_ipad(self):
        simctl = {"devices": {
            RT + "18-5": [{"name": "iPad Pro 13-inch (M4)", "udid": "OLD", "isAvailable": True}],
            RT + "26-0": [
                {"name": "iPhone 17", "udid": "PHONE", "isAvailable": True},
                {"name": "iPad (A16)", "udid": "SMALL", "isAvailable": True},
                {"name": "iPad Pro 11-inch (M5)", "udid": "PRO11", "isAvailable": True},
                {"name": "iPad Pro 13-inch (M5)", "udid": "PRO13", "isAvailable": True},
            ],
        }}
        self.assertEqual(ipad_screens.pick_ipad(simctl), "PRO13")

    def test_any_ipad_when_no_pro(self):
        simctl = {"devices": {RT + "26-1": [{"name": "iPad Air 11-inch (M3)", "udid": "AIR"}]}}
        self.assertEqual(ipad_screens.pick_ipad(simctl), "AIR")

    def test_skips_unavailable_and_other_platforms(self):
        simctl = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.watchOS-26-0": [{"name": "iPad Fake", "udid": "WATCH"}],
            RT + "26-0": [{"name": "iPad Pro 13-inch (M5)", "udid": "BROKEN", "isAvailable": False},
                          {"name": "iPad mini (A17 Pro)", "udid": "MINI", "isAvailable": True}],
        }}
        self.assertEqual(ipad_screens.pick_ipad(simctl), "MINI")

    def test_no_ipad(self):
        with self.assertRaises(ValueError):
            ipad_screens.pick_ipad({"devices": {RT + "26-0": [{"name": "iPhone 17", "udid": "X"}]}})


class RenameTests(unittest.TestCase):
    def test_strips_xcresult_suffix(self):
        self.assertEqual(ipad_screens.screenshot_name("portrait-1-Tagebuch_0_6F9619FF-8B86-D011-B42D-00C04FC964FF.png"),
                         "portrait-1-Tagebuch.png")
        self.assertEqual(ipad_screens.screenshot_name("landscape-4-Einstellungen.png"), "landscape-4-Einstellungen.png")
        self.assertEqual(ipad_screens.screenshot_name("a b/c"), "a_b_c.png")

    def test_copies_from_manifest(self):
        with tempfile.TemporaryDirectory() as tmp:
            raw, out = os.path.join(tmp, "raw"), os.path.join(tmp, "out")
            os.makedirs(raw)
            manifest = [{"testIdentifier": "IPadScreensTests/testPortrait()", "attachments": [
                {"exportedFileName": "A.png", "suggestedHumanReadableName": "portrait-2-Statistik_0_6F9619FF-8B86-D011-B42D-00C04FC964FF.png"},
                {"exportedFileName": "B.png", "suggestedHumanReadableName": "portrait-2-Statistik_1_7F9619FF-8B86-D011-B42D-00C04FC964FF.png"},
                {"exportedFileName": "C.png"},
            ]}]
            for name in ("A.png", "B.png", "C.png"):
                with open(os.path.join(raw, name), "w") as f:
                    f.write(name)
            with open(os.path.join(raw, "manifest.json"), "w") as f:
                json.dump(manifest, f)
            names = ipad_screens.rename(raw, out)
            self.assertEqual(names, ["C.png", "portrait-2-Statistik-2.png", "portrait-2-Statistik.png"])
            with open(os.path.join(out, "portrait-2-Statistik.png")) as f:
                self.assertEqual(f.read(), "A.png")


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, ".github", "workflows", "ipad-screens.yml")) as f:
            cls.workflow = f.read()
        with open(os.path.join(ROOT, "project.yml")) as f:
            cls.project = f.read()
        with open(os.path.join(ROOT, "SchiesstagebuchUITests", "IPadScreensTests.swift")) as f:
            cls.uitest = f.read()

    def test_runs_by_hand_on_ios_26(self):
        self.assertIn("workflow_dispatch:", self.workflow)
        self.assertRegex(self.workflow, r"runs-on: macos-2[6-9]")

    def test_uses_screens_scheme_on_an_ipad(self):
        self.assertIn("-scheme SchiesstagebuchScreens", self.workflow)
        self.assertIn("ipad_screens.py pick-ipad", self.workflow)
        self.assertIn("SchiesstagebuchScreens:", self.project)

    def test_uploads_screenshots_even_after_a_failure(self):
        upload = self.workflow.split("actions/upload-artifact@")[1]
        self.assertIn("if: always()", upload)
        self.assertIn("name: ipad-screens", upload)

    def test_normal_scheme_skips_ui_tests(self):
        normal = self.project.split("  Schiesstagebuch:\n    build:")[1].split("SchiesstagebuchScreens:")[0]
        self.assertNotIn("SchiesstagebuchUITests", normal)

    def test_ui_test_uses_sample_data_and_both_orientations(self):
        self.assertIn('"-screenshotData"', self.uitest)
        with open(os.path.join(ROOT, "Schiesstagebuch", "Services", "ScreenshotData.swift")) as f:
            self.assertIn('launchArgument = "-screenshotData"', f.read())
        self.assertIn(".portrait", self.uitest)
        self.assertRegex(self.uitest, r"\.landscape(Left|Right)")

    def test_ui_test_covers_every_tab(self):
        with open(os.path.join(ROOT, "Schiesstagebuch", "App", "SchiesstagebuchApp.swift")) as f:
            app = f.read()
        tabs = re.findall(r'\.tabItem \{ Label\("([^"]+)"', app)
        listed = re.search(r"static let tabs = \[([^\]]*)\]", self.uitest).group(1)
        # The licence tab only appears once a card is entered; the sample data has none.
        for tab in tabs:
            if tab != "SSV-Lizenz":
                self.assertIn(f'"{tab}"', listed)


if __name__ == "__main__":
    unittest.main()
