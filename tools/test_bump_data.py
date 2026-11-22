"""Tests for tools/bump_data.py: python3 -m unittest discover -s tools -p 'test_*.py'"""
import os, subprocess, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(__file__))
import bump_data  # noqa: E402


class BroughtInTests(unittest.TestCase):
    def test_lists_commits_or_says_the_histories_differ(self):
        with tempfile.TemporaryDirectory() as data:
            def git(*args):
                return subprocess.check_output(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                                               cwd=data, text=True).strip()
            git("init", "-q")
            git("commit", "-q", "--allow-empty", "-m", "first")
            old = git("rev-parse", "HEAD")
            git("commit", "-q", "--allow-empty", "-m", "second")
            new = git("rev-parse", "HEAD")
            git("checkout", "-q", "--orphan", "public")
            git("commit", "-q", "--allow-empty", "-m", "Calibre data")
            public = git("rev-parse", "HEAD")
            self.assertEqual(bump_data.brought_in(old, old, data), f"calibre-data already at {old[:7]}")
            self.assertTrue(bump_data.brought_in(old, new, data).endswith("second"))
            # The public repository started over: the old pointer is not in its history.
            self.assertEqual(bump_data.brought_in(old, public, data),
                             f"calibre-data {old[:7]} -> {public[:7]} (not in one history)")


if __name__ == "__main__":
    unittest.main()
