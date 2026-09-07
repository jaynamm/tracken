#!/usr/bin/env python3
"""Forward an existing status line and save only sanitized quota metadata locally."""
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def quota_window(raw):
    if not isinstance(raw, dict):
        return None
    percent, reset = raw.get("used_percentage"), raw.get("resets_at")
    if not number(percent) or not 0 <= percent <= 100 or not number(reset) or reset <= 0:
        return None
    return {"usedPercent": percent, "resetsAt": reset}


def write_snapshot(payload, directory, now=None):
    now = time.time() if now is None else now
    limits = payload.get("rate_limits")
    if not isinstance(limits, dict):
        return None  # A session before its first response has no quota sample.
    windows = {"fiveHour": quota_window(limits.get("five_hour")),
               "sevenDay": quota_window(limits.get("seven_day"))}
    if not any(windows.values()):
        return None  # Do not turn missing data into zero or refresh its age.
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = directory / "rate-limits.json"
    # Serialize writers from multiple Claude sessions; keep value age when only
    # an unchanged status line is redrawn. No prompts, paths or IDs are saved.
    import fcntl
    with (directory / ".rate-limits.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        previous = {}
        try:
            previous = json.loads(target.read_text())
        except (OSError, ValueError):
            pass
        if not isinstance(previous, dict):
            previous = {}
        same = all(previous.get(key) == value for key, value in windows.items())
        changed = previous.get("valuesChangedAt", now) if same else now
        if not number(changed) or not 0 < changed <= now:
            changed = now
        result = {"receivedAt": now, "valuesChangedAt": changed, **windows}
        fd, temp = tempfile.mkstemp(prefix=".quota-", dir=str(directory))
        try:
            with os.fdopen(fd, "w") as output:
                json.dump(result, output, allow_nan=False)
            os.replace(temp, target)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        return result


def main():
    directory = Path(__file__).resolve().parent
    raw = sys.stdin.buffer.read()
    sample = None
    try:
        payload = json.loads(raw)
        if isinstance(payload, dict):
            sample = write_snapshot(payload, directory)
    except (ValueError, OSError):
        pass  # A cache failure must not break the user's existing status line.
    config = {}
    try:
        config = json.loads((directory / "bridge-config.json").read_text())
    except (OSError, ValueError):
        pass
    if not isinstance(config, dict):
        config = {}
    previous = config.get("previousStatusLine") or {}
    command = previous.get("command") if isinstance(previous, dict) else None
    if command:
        # This command comes only from the user's saved settings, never payload.
        return subprocess.run(command, shell=True, executable="/bin/sh", input=raw).returncode
    parts = []
    for key, label in (("fiveHour", "5h"), ("sevenDay", "7d")):
        value = sample.get(key) if sample else None
        if value and value["resetsAt"] > time.time():
            parts.append(f"{label}: {value['usedPercent']:.0f}%")
    print("tracken | " + (" | ".join(parts) or "waiting for Claude limits"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
