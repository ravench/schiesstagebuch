"""Unit tests for tools/pr_screens.py and the PR screens in the Build workflow.

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

import pr_screens

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RT = "com.apple.CoreSimulator.SimRuntime.iOS-"


def write(folder, name, data):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, name), "wb") as f:
        f.write(data)


class PickIphoneTests(unittest.TestCase):
    def test_newest_runtime_and_plain_pro(self):
        simctl = {"devices": {
            RT + "18-5": [{"name": "iPhone 16 Pro", "udid": "OLD", "isAvailable": True}],
            RT + "26-0": [
                {"name": "iPad Pro 13-inch (M5)", "udid": "IPAD", "isAvailable": True},
                {"name": "iPhone 17", "udid": "PLAIN", "isAvailable": True},
                {"name": "iPhone 17 Pro Max", "udid": "MAX", "isAvailable": True},
                {"name": "iPhone 17 Pro", "udid": "PRO", "isAvailable": True},
            ],
        }}
        self.assertEqual(pr_screens.pick_iphone(simctl), "PRO")

    def test_skips_unavailable_and_needs_an_iphone(self):
        simctl = {"devices": {RT + "26-0": [
            {"name": "iPhone 17 Pro", "udid": "GONE", "isAvailable": False},
            {"name": "iPhone 17", "udid": "OK", "isAvailable": True},
        ]}}
        self.assertEqual(pr_screens.pick_iphone(simctl), "OK")
        with self.assertRaises(ValueError):
            pr_screens.pick_iphone({"devices": {RT + "26-0": [{"name": "iPad (A16)", "udid": "X"}]}})


class ChangesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.before = os.path.join(self.tmp.name, "before")
        self.after = os.path.join(self.tmp.name, "after")
        write(self.before, "01-Tagebuch.png", b"same")
        write(self.after, "01-Tagebuch.png", b"same")
        write(self.before, "02-Eintrag.png", b"old")
        write(self.after, "02-Eintrag.png", b"new")
        write(self.before, "03-Weg.png", b"x")
        write(self.after, "04-Neu.png", b"y")

    def tearDown(self):
        self.tmp.cleanup()

    def test_only_differing_screens(self):
        self.assertEqual(pr_screens.changes(self.before, self.after),
                         [("02-Eintrag.png", "changed"), ("03-Weg.png", "gone"), ("04-Neu.png", "new")])

    def test_missing_base_shows_everything_as_new(self):
        missing = os.path.join(self.tmp.name, "nothing")
        self.assertEqual([s for _, s in pr_screens.changes(missing, self.after)], ["new"] * 3)

    def test_collect_copies_changed_screens_only(self):
        out = os.path.join(self.tmp.name, "out")
        summary = pr_screens.collect(self.before, self.after, out)
        self.assertEqual(sorted(os.listdir(os.path.join(out, "before"))), ["02-Eintrag.png", "03-Weg.png"])
        self.assertEqual(sorted(os.listdir(os.path.join(out, "after"))), ["02-Eintrag.png", "04-Neu.png"])
        self.assertEqual(summary["total"], 3)
        with open(os.path.join(out, "changes.json")) as f:
            self.assertEqual(json.load(f)["changes"][0], ["02-Eintrag.png", "changed"])

    def test_cli_writes_comment(self):
        out = os.path.join(self.tmp.name, "out")
        script = os.path.join(ROOT, "tools", "pr_screens.py")
        run = lambda *args: subprocess.run([sys.executable, script, *args], check=True, capture_output=True, text=True).stdout
        run("changes", self.before, self.after, out)
        body = run("comment", out, "https://img", "https://run")
        self.assertIn('<img src="https://img/after/02-Eintrag.png"', body)
        self.assertNotIn("iPad", body)
        # The iPad screens, as the Build job compares them, go below the iPhone ones.
        write(os.path.join(self.tmp.name, "before-ipad"), "landscape-2-Statistik.png", b"old")
        write(os.path.join(self.tmp.name, "after-ipad"), "landscape-2-Statistik.png", b"new")
        run("changes", os.path.join(self.tmp.name, "before-ipad"), os.path.join(self.tmp.name, "after-ipad"),
            os.path.join(out, "ipad"))
        body = run("comment", out, "https://img", "https://run")
        self.assertLess(body.index("02-Eintrag"), body.index("#### iPad"))
        self.assertIn('<img src="https://img/ipad/after/landscape-2-Statistik.png" width="320">', body)


try:
    from PIL import Image
except ImportError:
    Image = None


@unittest.skipUnless(Image, "needs Pillow (installed by the workflow's Compare step)")
class SameTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmp.cleanup()

    def png(self, name, changes=(), size=(40, 40)):
        img = Image.new("RGB", size, (240, 240, 245))
        for xy, colour in changes:
            img.putpixel(xy, colour)
        path = os.path.join(self.tmp.name, name)
        img.save(path)
        return path

    def test_faint_noise_is_the_same(self):
        noise = [((x, 3), (250, 245, 250)) for x in range(40)]
        self.assertTrue(pr_screens.same(self.png("a.png"), self.png("b.png", noise)))

    def test_visible_change_differs(self):
        text = [((x, y), (0, 0, 0)) for x in range(10) for y in range(5)]
        self.assertFalse(pr_screens.same(self.png("a.png"), self.png("b.png", text)))

    def test_other_size_differs(self):
        self.assertFalse(pr_screens.same(self.png("a.png"), self.png("b.png", size=(40, 41))))


class CommentTests(unittest.TestCase):
    def test_table_with_before_and_after(self):
        summary = {"changes": [["02-Eintrag.png", "changed"], ["04-Neu.png", "new"], ["03-Weg.png", "gone"]],
                   "total": 9, "base": 9}
        body = pr_screens.comment(summary, "https://raw/x/12", "https://run/1")
        self.assertTrue(body.startswith(pr_screens.MARKER))
        self.assertIn("3 of 9 iPhone screens look different", body)
        self.assertIn('| 02-Eintrag | <img src="https://raw/x/12/before/02-Eintrag.png" width="250"> | '
                      '<img src="https://raw/x/12/after/02-Eintrag.png" width="250"> |', body)
        self.assertIn('| 04-Neu (new) | — | <img src="https://raw/x/12/after/04-Neu.png"', body)
        self.assertIn("| 03-Weg (gone) | <img", body)
        self.assertIn("(https://run/1)", body)

    def test_no_change_points_to_the_tour(self):
        body = pr_screens.comment({"changes": [], "total": 9, "base": 9}, "u", "r")
        self.assertIn("No visible change on the 9 iPhone screens", body)
        self.assertIn(pr_screens.TOUR, body)
        self.assertNotIn("<img", body)

    def test_says_when_base_failed(self):
        body = pr_screens.comment({"changes": [["01-Tagebuch.png", "new"]], "total": 1, "base": 0}, "u", "r")
        self.assertIn("iPhone screens of the base branch could not be taken", body)

    def test_ipad_screens_below_the_iphone_ones(self):
        iphone = {"changes": [], "total": 15, "base": 15}
        ipad = {"changes": [["landscape-2-Statistik.png", "changed"], ["portrait-5-Neu.png", "new"]],
                "total": 11, "base": 10}
        body = pr_screens.comment(iphone, "https://raw/x/12", "https://run/1", ipad)
        iphone_part, ipad_part = body.split("#### iPad")
        self.assertIn("No visible change on the 15 iPhone screens", iphone_part)
        self.assertIn(pr_screens.TOUR, iphone_part)
        self.assertIn("2 of 11 iPad screens look different", ipad_part)
        self.assertIn('| landscape-2-Statistik | <img src="https://raw/x/12/ipad/before/landscape-2-Statistik.png" '
                      'width="320"> | <img src="https://raw/x/12/ipad/after/landscape-2-Statistik.png" width="320"> |',
                      ipad_part)
        self.assertIn("| portrait-5-Neu (new) | — |", ipad_part)
        self.assertIn("(https://run/1)", ipad_part)

    def test_ipad_without_change_or_screens(self):
        iphone = {"changes": [["01-Tagebuch.png", "changed"]], "total": 15, "base": 15}
        body = pr_screens.comment(iphone, "u", "r", {"changes": [], "total": 10, "base": 10})
        self.assertIn("No visible change on the 10 iPad screens.", body)
        self.assertNotIn(pr_screens.TOUR, body)  # the hint is for a tour without changes
        # A tour that took nothing says so, whatever the base branch gave.
        for ipad in ({"changes": [], "total": 0, "base": 0}, {"changes": [["portrait-1-Tagebuch.png", "gone"]],
                                                             "total": 0, "base": 1}):
            body = pr_screens.comment(iphone, "u", "r", ipad).split("#### iPad")[1]
            self.assertIn("No iPad screens could be taken on this pull request", body)
            self.assertNotIn("base branch", body)
            self.assertNotIn("<img", body)
        body = pr_screens.comment({"changes": [], "total": 0, "base": 0}, "u", "r")
        self.assertIn("No iPhone screens could be taken", body)
        self.assertNotIn(pr_screens.TOUR, body)


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            cls.workflow = f.read()

    def test_runs_on_gui_pull_requests(self):
        self.assertIn("pull_request:", self.workflow)
        self.assertIn("SCREENS_TOUR: ${{ needs.changes.outputs.screens }}", self.workflow)
        self.assertIn("env.SCREENS_TOUR == 'true'", self.workflow)
        self.assertRegex(self.workflow, r"runs-on: macos-2[6-9]")

    def test_reuses_the_build_and_its_simulator(self):
        # No second Mac runner: the tour runs on the Build job's build, without compiling it again.
        self.assertFalse(os.path.exists(os.path.join(ROOT, ".github", "workflows", "pr-screens.yml")))
        self.assertNotIn("xcodebuild test ", self.workflow)
        self.assertIn('xcrun simctl boot "$UDID"', self.workflow)

    def test_tours_start_without_the_tests_data(self):
        self.assertEqual(self.workflow.count('xcrun simctl uninstall "$UDID" ch.giotta.schiesstagebuch'), 2)

    def test_tours_head_and_base_with_the_same_tour(self):
        self.assertEqual(self.workflow.count("-only-testing:SchiesstagebuchUITests/PRScreensTests"), 2)
        self.assertIn("fetch-depth: 2", self.workflow)
        self.assertIn("git checkout -q HEAD^1", self.workflow)
        self.assertIn('cp "$SCREENS/PRScreensTests.swift" "$SCREENS/IPadScreensTests.swift" SchiesstagebuchUITests/',
                      self.workflow)
        self.assertIn("status_bar", self.workflow)

    def test_ipad_screens_on_base_and_head_one_simulator_at_a_time(self):
        # An iPad booted next to the iPhone overloaded the runner and changed the iPhone's screens.
        self.assertNotIn("IPAD", self.workflow.split("name: iPad screens")[0])
        ipad = self.workflow.split("name: iPad screens")[1].split("- name:")[0]
        self.assertLess(ipad.index('xcrun simctl shutdown "$UDID"'), ipad.index('xcrun simctl boot "$IPAD"'))
        self.assertIn('"$SCREENS/ipad_screens.py" pick-ipad', ipad)
        self.assertIn("status_bar", ipad)
        # The base build from the step before, then this pull request built again on top of it.
        self.assertIn("steps.base.outputs.built", ipad)
        self.assertIn('echo "built=true" >> "$GITHUB_OUTPUT"', self.workflow.split("name: Screens of the base branch")[1])
        before, after = ipad.index("before-ipad.xcresult"), ipad.index("after-ipad.xcresult")
        between = ipad[before:after]
        self.assertIn("git checkout -q -f ${{ github.sha }}", between)
        self.assertIn("xcodebuild build-for-testing", between)
        self.assertIn('xcrun simctl uninstall "$IPAD" ch.giotta.schiesstagebuch', between)
        self.assertEqual(ipad.count("-only-testing:SchiesstagebuchUITests/IPadScreensTests"), 2)
        # A failed base tour costs only its screens; a failed tour of this pull request fails the job.
        self.assertIn('"$SCREENS/before-ipad.xcresult" \\\n              CODE_SIGNING_ALLOWED=NO | xcpretty || true', ipad)
        self.assertTrue(ipad.rstrip().endswith("CODE_SIGNING_ALLOWED=NO | xcpretty"))

    def test_ipad_screens_compared_and_commented(self):
        compare = self.workflow.split("name: Compare")[1].split("- uses:")[0]
        self.assertIn("for side in after before after-ipad before-ipad", compare)
        self.assertIn('sips -r 270 "$f"', compare)  # landscape screens upright, as in ipad-screens.yml
        self.assertIn("pr_screens.py changes before-ipad after-ipad changed/ipad", compare)
        self.assertIn("${{ env.SCREENS }}/after-ipad", self.workflow)
        self.assertIn("cp -R ../changed/before ../changed/after ../changed/ipad", self.workflow)

    def test_comments_once_per_pull_request(self):
        self.assertIn("pull-requests: write", self.workflow)
        self.assertIn(pr_screens.MARKER, self.workflow)
        self.assertIn("PATCH", self.workflow)

    def test_images_go_to_app_screens_with_a_deploy_key(self):
        # The images stay out of this repo's history: ravench/app-screens holds them.
        comment = self.workflow.split("name: Comment on the pull request")[1]
        self.assertIn("SCREENS_REPO: ravench/app-screens", comment)
        self.assertIn("SCREENS_BRANCH: ${{ github.event.repository.name }}/pr-screens", comment)
        self.assertIn("secrets.SCREENS_DEPLOY_KEY", comment)
        self.assertIn('git remote add origin "git@github.com:${SCREENS_REPO}.git"', comment)
        self.assertIn("https://raw.githubusercontent.com/${SCREENS_REPO}/", comment)
        self.assertNotIn("contents: write", self.workflow)

    def test_tour_exists_and_matches_the_comment_hint(self):
        self.assertTrue(os.path.exists(os.path.join(ROOT, pr_screens.TOUR)))


if __name__ == "__main__":
    unittest.main()
