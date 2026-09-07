import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "Scripts"

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

bridge = module("quota_bridge", "claude-statusline.py")
installer = module("quota_installer", "install-claude-statusline.py")

class ClaudeStatuslineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.cache = self.root / "bridge with spaces"
        self.config = self.root / "claude"

    def payload(self, percent=23):
        return {"rate_limits": {"five_hour": {"used_percentage": percent, "resets_at": 9999999999}},
                "cwd": "/private/work", "session_id": "secret", "message": "private prompt"}

    def test_only_quota_metadata_is_saved(self):
        bridge.write_snapshot(self.payload(), self.cache, now=100)
        value = json.loads((self.cache / "rate-limits.json").read_text())
        self.assertEqual(set(value), {"receivedAt", "valuesChangedAt", "fiveHour", "sevenDay"})
        self.assertIsNone(value["sevenDay"])
        self.assertEqual((self.cache / "rate-limits.json").stat().st_mode & 0o777, 0o600)

    def test_unchanged_redraw_does_not_rejuvenate_values(self):
        bridge.write_snapshot(self.payload(), self.cache, now=100)
        bridge.write_snapshot(self.payload(), self.cache, now=900)
        value = json.loads((self.cache / "rate-limits.json").read_text())
        self.assertEqual(value["valuesChangedAt"], 100)
        self.assertEqual(value["receivedAt"], 900)
        bridge.write_snapshot(self.payload(24), self.cache, now=950)
        self.assertEqual(json.loads((self.cache / "rate-limits.json").read_text())["valuesChangedAt"], 950)

    def test_absent_or_invalid_data_does_not_fake_zero_or_refresh_age(self):
        bridge.write_snapshot(self.payload(), self.cache, now=100)
        before = (self.cache / "rate-limits.json").read_bytes()
        for data in ({}, {"rate_limits": {}}, self.payload(None), self.payload(-1), self.payload(float("nan")), self.payload(True)):
            self.assertIsNone(bridge.write_snapshot(data, self.cache, now=999))
            self.assertEqual((self.cache / "rate-limits.json").read_bytes(), before)
        self.assertEqual(bridge.write_snapshot(self.payload(0), self.cache, now=1000)["fiveHour"]["usedPercent"], 0)

    def test_install_preserves_other_settings_and_previous_output(self):
        self.config.mkdir()
        previous = {"type": "command", "command": "printf 'my existing status'", "padding": 2, "refreshInterval": 10}
        original = {"statusLine": previous, "permissions": {"allow": ["Read"]}, "theme": "dark"}
        settings = self.config / "settings.json"
        settings.write_text(json.dumps(original))
        installer.configure(self.config, self.cache)
        installed = json.loads(settings.read_text())
        self.assertEqual(installed["permissions"], original["permissions"])
        self.assertEqual(installed["statusLine"]["padding"], 2)
        # Reinstall must not chain the bridge to itself.
        installer.configure(self.config, self.cache)
        result = subprocess.run(installed["statusLine"]["command"], shell=True,
                                input=json.dumps(self.payload()), text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "my existing status")
        self.assertTrue((self.cache / "rate-limits.json").exists())
        installer.configure(self.config, self.cache, uninstall=True)
        self.assertEqual(json.loads(settings.read_text()), original)

    def test_uninstall_does_not_overwrite_a_later_user_change(self):
        installer.configure(self.config, self.cache)
        changed = {"statusLine": {"type": "command", "command": "printf new"}}
        (self.config / "settings.json").write_text(json.dumps(changed))
        installer.configure(self.config, self.cache, uninstall=True)
        self.assertEqual(json.loads((self.config / "settings.json").read_text()), changed)

if __name__ == "__main__":
    unittest.main()
