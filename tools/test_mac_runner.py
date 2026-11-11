"""Mac jobs run on GitHub's Mac, or on the self-hosted Mac in MAC_RUNNER while the repo is private."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
MAC = "runs-on: ${{ github.event.repository.private && vars.MAC_RUNNER || 'macos-26' }}"


def workflow(name):
    return (WORKFLOWS / name).read_text()


def xcodebuild_builds(text):
    """Each xcodebuild call that builds or tests, with its continuation lines."""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.search(r"xcodebuild (build-for-testing|test-without-building|test|archive|build)\b", line):
            command = [line]
            while command[-1].rstrip().endswith("\\"):
                i += 1
                command.append(lines[i])
            yield "\n".join(command)


def job(text, name):
    """One job of a workflow, up to the next job."""
    return re.split(r"\n  [\w-]+:\n", text.split(f"\n  {name}:\n", 1)[1], 1)[0]


class MacRunnerTests(unittest.TestCase):
    def test_mac_jobs_use_the_self_hosted_mac_only_while_private(self):
        # The repo's own workflows never send a public repo's jobs to that Mac (README).
        mac = []
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for line in path.read_text().splitlines():
                if line.strip().startswith("runs-on:") and "ubuntu" not in line:
                    self.assertEqual(line.strip(), MAC, path.name)
                    mac.append(path.name)
        self.assertGreaterEqual(len(mac), 4, mac)

    def test_nothing_is_left_in_the_runners_home(self):
        # A self-hosted Mac keeps its home folder between runs: keys go to RUNNER_TEMP.
        for path in sorted(WORKFLOWS.glob("*.yml")) + sorted((ROOT / "tools").glob("*.sh")):
            self.assertIsNone(re.search(r"~/|\$HOME\b|\$\{HOME\}", path.read_text()), path.name)
        for text in (workflow("ipad-screens.yml"), (ROOT / "tools" / "publish_pr_screens.sh").read_text()):
            self.assertIn("UserKnownHostsFile='$HOSTS'", text)
        # So do xcodebuild's temporary files in TestFlight.
        testflight = workflow("testflight.yml")
        self.assertLess(testflight.index('echo "TMPDIR=$RUNNER_TEMP" >> "$GITHUB_ENV"'),
                        testflight.index("xcodebuild archive"))

    def test_a_mac_that_keeps_its_state_starts_clean(self):
        # Each simulator is erased before it boots and shut down after the job, whatever happened.
        build = workflow("build.yml")
        for text, var in ((job(build, "build"), "UDID"), (job(build, "ipad-screens"), "IPAD"),
                          (job(workflow("ipad-screens.yml"), "screens"), "UDID")):
            # Shut down first: erase fails on a simulator a crashed run left booted.
            self.assertLess(text.index(f'xcrun simctl shutdown "${var}"'), text.index(f'xcrun simctl erase "${var}"'))
            if f'xcrun simctl boot "${var}"' in text:
                self.assertLess(text.index(f'xcrun simctl erase "${var}"'), text.index(f'xcrun simctl boot "${var}"'))
            last_step = text.rstrip().rsplit("\n      - ", 1)[1]
            self.assertIn("if: always()", last_step)
            self.assertIn(f'xcrun simctl shutdown "${var}"', last_step)
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for line in path.read_text().splitlines():
                if "brew install xcodegen" in line:
                    self.assertIn("command -v xcodegen >/dev/null ||", line, path.name)

    def test_builds_go_to_runner_temp(self):
        # Xcode's default DerivedData is in the home folder, where a self-hosted Mac would keep it.
        builds = 0
        for path in sorted(WORKFLOWS.glob("*.yml")):
            for command in xcodebuild_builds(path.read_text()):
                builds += 1
                self.assertIn("-derivedDataPath", command, f"{path.name}: {command.splitlines()[0].strip()}")
        self.assertGreaterEqual(builds, 5)


if __name__ == "__main__":
    unittest.main()
