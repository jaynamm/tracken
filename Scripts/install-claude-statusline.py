#!/usr/bin/env python3
"""Install/remove the tracken quota bridge while retaining the user's status line."""
import argparse
import datetime
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile


def write_json(path, value):
    fd, temp = tempfile.mkstemp(prefix=".tracken-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, indent=2, ensure_ascii=False)
            stream.write("\n")
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def configure(config_dir, bridge_dir, uninstall=False):
    config_dir.mkdir(parents=True, exist_ok=True)
    bridge_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    settings_file = config_dir / "settings.json"
    settings = json.loads(settings_file.read_text()) if settings_file.exists() else {}
    if not isinstance(settings, dict):
        raise ValueError("Claude settings must be a JSON object")
    bridge_config = bridge_dir / "bridge-config.json"
    saved = json.loads(bridge_config.read_text()) if bridge_config.exists() else {}
    current = settings.get("statusLine")
    installed = isinstance(current, dict) and current.get("command") == saved.get("installedCommand") and bool(saved.get("installedCommand"))
    if uninstall and not installed:
        return "Existing status line is not managed by tracken; left unchanged."
    if settings_file.exists():
        backup = bridge_dir / ("settings-before-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".json")
        shutil.copy2(settings_file, backup)
        backup.chmod(0o600)
    if uninstall:
        previous = saved.get("previousStatusLine")
        if previous is None:
            settings.pop("statusLine", None)
        else:
            settings["statusLine"] = previous
    else:
        script = bridge_dir / "claude-statusline.py"
        shutil.copy2(Path(__file__).with_name("claude-statusline.py"), script)
        script.chmod(0o700)
        previous = saved.get("previousStatusLine") if installed else current
        command = shlex.join([sys.executable, str(script)])
        write_json(bridge_config, {"previousStatusLine": previous, "installedCommand": command})
        settings["statusLine"] = {**(previous if isinstance(previous, dict) else {}), "type": "command", "command": command}
    write_json(settings_file, settings)
    return "Previous status line restored." if uninstall else "Claude status-line bridge installed. Existing output and settings preserved."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config-dir", type=Path, default=Path(os.environ.get("CLAUDE_CONFIG_DIR", str(Path.home() / ".claude"))))
    parser.add_argument("--bridge-dir", type=Path, default=Path.home() / "Library/Application Support/tracken/Claude")
    parser.add_argument("--uninstall", action="store_true")
    args = parser.parse_args()
    print(configure(args.config_dir, args.bridge_dir, args.uninstall))


if __name__ == "__main__":
    main()
