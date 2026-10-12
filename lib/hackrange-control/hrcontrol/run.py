"""Run a command without a shell, with a time limit, and never raise.

Every command the control panel runs goes through here: arguments are a list,
so nothing a request sends ever reaches a shell, and a command that hangs is
cut off rather than hanging the page.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import subprocess

DOCKER = "docker"


def run(cmd: list[str], timeout: int = 20) -> tuple[int, str]:
    """Return (exit code, combined output).  Exit code 124 means it timed out."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timed out"
    except OSError as exc:
        return 127, str(exc)
