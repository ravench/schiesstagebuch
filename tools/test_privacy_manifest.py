"""The app's privacy manifest matches what the code does (Schiesstagebuch/Resources/PrivacyInfo.xcprivacy).

    python3 -m unittest discover -s tools -p 'test_*.py'
"""
import os
import plistlib
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MANIFEST = os.path.join(ROOT, "Schiesstagebuch", "Resources", "PrivacyInfo.xcprivacy")

# Required-reason APIs Apple lists, with a pattern that finds their use in Swift.
REQUIRED_REASON_APIS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"creationDate|[mM]odificationDate|\bstat\(",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|systemFreeSize|statfs",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}


def swift_code():
    parts = []
    for base, _, files in os.walk(os.path.join(ROOT, "Schiesstagebuch")):
        for name in files:
            if name.endswith(".swift"):
                with open(os.path.join(base, name)) as f:
                    parts.append(f.read())
    return "\n".join(parts)


class PrivacyManifestTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(MANIFEST, "rb") as f:
            cls.manifest = plistlib.load(f)
        cls.code = swift_code()

    def test_no_tracking_and_nothing_collected(self):
        self.assertIs(self.manifest["NSPrivacyTracking"], False)
        self.assertEqual(self.manifest["NSPrivacyTrackingDomains"], [])
        self.assertEqual(self.manifest["NSPrivacyCollectedDataTypes"], [])

    def test_every_used_required_reason_api_is_declared(self):
        declared = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
                    for entry in self.manifest["NSPrivacyAccessedAPITypes"]}
        for api, pattern in REQUIRED_REASON_APIS.items():
            if re.search(pattern, self.code):
                self.assertIn(api, declared, f"{api} used in code but not in PrivacyInfo.xcprivacy")
                self.assertTrue(declared[api], f"{api} declared without a reason")
            else:
                self.assertNotIn(api, declared, f"{api} declared but not used")


if __name__ == "__main__":
    unittest.main()
