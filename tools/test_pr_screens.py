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
        self.assertTrue(body.startswith(pr_screens.MARKER + "\n"))
        body = run("comment", out, "https://img", "https://run", "ipad")
        self.assertTrue(body.startswith(pr_screens.IPAD_MARKER + "\n"))
        self.assertIn('<img src="https://img/after/02-Eintrag.png" width="320">', body)


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

    def test_line_moved_by_a_pixel_is_the_same(self):
        # Text edges and toggle outlines land a fraction of a point off between runs.
        line = lambda top: [((x, y), (0, 0, 0)) for x in range(40) for y in range(top, top + 4)]
        self.assertTrue(pr_screens.same(self.png("a.png", line(3)), self.png("b.png", line(4))))
        self.assertFalse(pr_screens.same(self.png("a.png", line(3)), self.png("b.png")), "a line appearing is a change")

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

    def test_ipad_screens_have_their_own_comment(self):
        ipad = {"changes": [["landscape-2-Statistik.png", "changed"], ["portrait-5-Neu.png", "new"]],
                "total": 11, "base": 10}
        body = pr_screens.comment(ipad, "https://raw/x/12/ipad", "https://run/1", ipad=True)
        self.assertTrue(body.startswith(pr_screens.IPAD_MARKER))
        # publish_pr_screens.sh finds a device's comment by its first line, with startswith.
        self.assertFalse(pr_screens.IPAD_MARKER.startswith(pr_screens.MARKER))
        self.assertFalse(pr_screens.MARKER.startswith(pr_screens.IPAD_MARKER))
        self.assertIn("### iPad screenshots", body)
        self.assertIn("2 of 11 iPad screens look different", body)
        self.assertIn('| landscape-2-Statistik | <img src="https://raw/x/12/ipad/before/landscape-2-Statistik.png" '
                      'width="320"> | <img src="https://raw/x/12/ipad/after/landscape-2-Statistik.png" width="320"> |',
                      body)
        self.assertIn("| portrait-5-Neu (new) | — |", body)
        self.assertIn("(https://run/1)", body)
        self.assertNotIn(pr_screens.TOUR, body)  # the hint is for the iPhone tour
        body = pr_screens.comment({"changes": [], "total": 10, "base": 10}, "u", "r", ipad=True)
        self.assertIn("No visible change on the 10 iPad screens.", body)
        self.assertNotIn(pr_screens.TOUR, body)

    def test_tour_without_screens(self):
        # A tour that took nothing says so, whatever the base branch gave, and gives no tour hint.
        for summary in ({"changes": [], "total": 0, "base": 0},
                        {"changes": [["01-Tagebuch.png", "gone"]], "total": 0, "base": 1}):
            for ipad in (False, True):
                body = pr_screens.comment(summary, "u", "r", ipad=ipad)
                self.assertIn(f"No {'iPad' if ipad else 'iPhone'} screens could be taken on this pull request", body)
                self.assertNotIn("base branch", body)
                self.assertNotIn("<img", body)
                self.assertNotIn(pr_screens.TOUR, body)


class PublishTests(unittest.TestCase):
    """tools/publish_pr_screens.sh against a local screens repo and a stand-in for gh."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.remote = os.path.join(t, "app-screens.git")
        subprocess.run(["git", "init", "-q", "--bare", self.remote], check=True)
        with open(os.path.join(t, "gitconfig"), "w") as f:
            f.write(f'[url "{self.remote}"]\n\tinsteadOf = git@github.com:ravench/app-screens.git\n')
        os.makedirs(os.path.join(t, "bin"))
        self.gh_log = os.path.join(t, "gh.log")
        gh = os.path.join(t, "bin", "gh")
        with open(gh, "w") as f:  # logs each call; lists no comments yet
            f.write(f'#!/bin/sh\necho "$@" >> {self.gh_log}\n')
        os.chmod(gh, 0o755)
        self.env = dict(os.environ, HOME=os.path.join(t, "home"), GIT_CONFIG_GLOBAL=os.path.join(t, "gitconfig"),
                        PATH=os.path.join(t, "bin") + os.pathsep + os.environ["PATH"], GH_TOKEN="x",
                        REPO="ravench/schiesstagebuch", PR="122", HEAD_SHA="abc", RUN_URL="https://run",
                        SCREENS_REPO="ravench/app-screens", SCREENS_BRANCH="schiesstagebuch/pr-screens",
                        SCREENS_DEPLOY_KEY="key")

    def tearDown(self):
        self.tmp.cleanup()

    def publish(self, name, *device):
        changed = tempfile.mkdtemp(dir=self.tmp.name)
        for side in ("before", "after"):
            write(os.path.join(changed, side), name, side.encode())
        with open(os.path.join(changed, "changes.json"), "w") as f:
            json.dump({"changes": [[name, "changed"]], "total": 3, "base": 3}, f)
        subprocess.run(["bash", os.path.join(ROOT, "tools", "publish_pr_screens.sh"), changed, *device],
                       cwd=self.tmp.name, env=self.env, check=True, capture_output=True)

    def files(self):
        return subprocess.run(["git", "--git-dir", self.remote, "ls-tree", "-r", "--name-only",
                               "schiesstagebuch/pr-screens"], check=True, capture_output=True, text=True).stdout.split()

    def test_devices_keep_their_own_folders_and_comments(self):
        self.publish("01-Tagebuch.png")
        self.publish("portrait-2-Statistik.png", "ipad")
        self.publish("05-Statistik.png")  # a newer iPhone run replaces only the iPhone screens
        self.assertEqual(self.files(), ["122/after/05-Statistik.png", "122/before/05-Statistik.png",
                                        "122/ipad/after/portrait-2-Statistik.png",
                                        "122/ipad/before/portrait-2-Statistik.png"])
        with open(self.gh_log) as f:
            calls = f.read()
        self.assertIn(f'startswith("{pr_screens.MARKER}")', calls)
        self.assertIn(f'startswith("{pr_screens.IPAD_MARKER}")', calls)
        self.assertEqual(calls.count("-F body=@comment.md"), 3)  # no comment found, so each posts one
        with open(os.path.join(self.tmp.name, "comment.md")) as f:
            body = f.read()
        self.assertIn("https://raw.githubusercontent.com/ravench/app-screens/", body)
        self.assertIn("/122/after/05-Statistik.png", body)


class WorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, ".github", "workflows", "build.yml")) as f:
            cls.workflow = f.read()
        cls.build = cls.workflow.split("\n  build:\n")[1].split("\n  ipad-screens:\n")[0]
        cls.ipad = cls.workflow.split("\n  ipad-screens:\n")[1]
        with open(os.path.join(ROOT, "tools", "publish_pr_screens.sh")) as f:
            cls.publish = f.read()

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
        self.assertEqual(self.build.count("-only-testing:SchiesstagebuchUITests/PRScreensTests"), 2)
        self.assertIn("fetch-depth: 2", self.build)
        self.assertIn("git checkout -q HEAD^1", self.build)
        self.assertIn('cp "$SCREENS/PRScreensTests.swift" SchiesstagebuchUITests/', self.build)
        self.assertIn("status_bar", self.build)

    def test_ipad_screens_in_their_own_job(self):
        # One simulator per runner: an iPad booted next to the iPhone overloaded the runner, and
        # one after the other made the build job 14 minutes longer.
        self.assertNotIn("IPAD", self.build)
        self.assertNotIn("IPadScreensTests", self.build)
        self.assertIn("needs: changes", self.ipad)
        self.assertIn("if: needs.changes.outputs.screens == 'true'", self.ipad)
        self.assertRegex(self.ipad, r"runs-on: macos-2[6-9]")
        self.assertIn("fetch-depth: 2", self.ipad)
        # The iPad boots while the app compiles, so the first tour meets a settled simulator.
        self.assertLess(self.ipad.index('xcrun simctl boot "$IPAD"'), self.ipad.index("xcodebuild build-for-testing"))

    def test_ipad_tours_head_and_base_with_the_same_tour(self):
        head = self.ipad.split("name: Screens of this pull request")[1].split("- name:")[0]
        base = self.ipad.split("name: Screens of the base branch")[1].split("- name:")[0]
        self.assertIn('-resultBundlePath "$SCREENS/after.xcresult"', head)
        self.assertIn("status_bar", head)
        self.assertIn("git checkout -q HEAD^1", base)
        self.assertIn('cp "$SCREENS/IPadScreensTests.swift" SchiesstagebuchUITests/', base)
        self.assertIn("continue-on-error: true", base)
        self.assertLess(base.index('xcrun simctl uninstall "$IPAD" ch.giotta.schiesstagebuch'),
                        base.index('-resultBundlePath "$SCREENS/before.xcresult"'))
        self.assertEqual(self.ipad.count("-only-testing:SchiesstagebuchUITests/IPadScreensTests"), 2)

    def test_ipad_screens_compared_and_commented(self):
        compare = self.ipad.split("name: Compare")[1].split("- uses:")[0]
        self.assertIn('sips -r 270 "$f"', compare)  # landscape screens upright, as in ipad-screens.yml
        self.assertIn("pr_screens.py changes before after changed", compare)
        self.assertIn("name: ipad-screens", self.ipad)
        self.assertIn("bash publish_pr_screens.sh changed ipad", self.ipad)
        self.assertTrue(self.build.rstrip().endswith("bash publish_pr_screens.sh changed"))

    def test_tools_copied_before_the_base_checkout(self):
        for job in (self.build, self.ipad):
            copy = job.split("name: Screens of this pull request")[1].split("- name:")[0]
            for tool in ("tools/pr_screens.py", "tools/ipad_screens.py", "tools/publish_pr_screens.sh"):
                self.assertIn(tool, copy)

    def test_comments_once_per_pull_request_and_device(self):
        for job in (self.build, self.ipad):
            self.assertIn("pull-requests: write", job)
        self.assertIn('startswith(\\"$MARKER\\")', self.publish)
        self.assertIn("MARKER=$(head -1 comment.md)", self.publish)
        self.assertIn("PATCH", self.publish)

    def test_images_go_to_app_screens_with_a_deploy_key(self):
        # The images stay out of this repo's history: ravench/app-screens holds them.
        for job in (self.build, self.ipad):
            comment = job.split("name: Comment on the pull request")[1]
            self.assertIn("SCREENS_REPO: ravench/app-screens", comment)
            self.assertIn("SCREENS_BRANCH: ${{ github.event.repository.name }}/pr-screens", comment)
            self.assertIn("secrets.SCREENS_DEPLOY_KEY", comment)
            self.assertIn("github.event.pull_request.head.repo.full_name == github.repository", comment)
        self.assertIn('git remote add origin "git@github.com:${SCREENS_REPO}.git"', self.publish)
        self.assertIn("https://raw.githubusercontent.com/${SCREENS_REPO}/", self.publish)
        # Each device replaces only its own screens in the pull request's folder.
        self.assertIn('DEST="$PR${DEVICE:+/$DEVICE}"', self.publish)
        self.assertIn('rm -rf "$DEST/before" "$DEST/after"', self.publish)
        self.assertNotIn('rm -rf "$PR"', self.publish)
        self.assertNotIn("contents: write", self.workflow)

    def test_publish_script_parses(self):
        subprocess.run(["bash", "-n", os.path.join(ROOT, "tools", "publish_pr_screens.sh")], check=True)

    def test_tour_exists_and_matches_the_comment_hint(self):
        self.assertTrue(os.path.exists(os.path.join(ROOT, pr_screens.TOUR)))


if __name__ == "__main__":
    unittest.main()
