"""Starting, stopping and marking a lab, on the student's behalf.

Everything here goes through hackrange-lab and hackrange-check, the same
commands a student would type.  The panel deliberately has no idea how to run
a container: one way of starting a lab means the panel and the terminal cannot
drift apart, and whatever the launcher learns next the panel gets for free.

One lab runs at a time, which is the launcher's rule, not this file's: there is
one web desktop and one connection for it to answer on.  So starting a lab
deletes the one before it, and the panel has to say so before it happens
rather than afterwards.

An action runs in a background thread and the request returns at once, because
starting the Splunk lab takes a couple of minutes and a browser that waits
that long for an answer has already given up.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import threading
import time

from . import catalog
from .const import (COMPANION_CONTAINER, HACKRANGE_CHECK, HACKRANGE_LAB,
                    LAB_CONTAINER)
from .labinfo import current_lab
from .run import DOCKER, run

# Starting the Splunk lab on an ARM machine builds nothing but does wait for
# its desktop, under emulation.  Long enough to be generous, short enough that
# a wedged start eventually reports itself instead of hanging forever.
ACTION_TIMEOUT = 900
CHECK_TIMEOUT = 120

_busy: dict[str, str] = {}      # lab key -> "starting" | "stopping"
_errors: dict[str, str] = {}
_check: dict = {}               # the last "check my work", for the page to show
_lock = threading.Lock()


# ---------------------------------------------------------------- what is true now

def _container_running(name: str) -> bool:
    rc, out = run([DOCKER, "inspect", "-f", "{{.State.Running}}", name], timeout=10)
    return rc == 0 and out.strip() == "true"


def image_present(image: str) -> bool:
    return run([DOCKER, "image", "inspect", image], timeout=15)[0] == 0


def states() -> dict[str, str]:
    """Every lab's state, as the page shows it."""
    running_key = current_lab()
    up = _container_running(LAB_CONTAINER)
    out = {}
    for lab in catalog.labs():
        key = lab["key"]
        if key in _busy:
            out[key] = _busy[key]
        elif key == running_key and up:
            out[key] = "running"
        elif not image_present(lab["image"]):
            out[key] = "not-built"
        else:
            out[key] = "stopped"
    return out


def errors() -> dict[str, str]:
    return dict(_errors)


def check_status() -> dict:
    with _lock:
        return dict(_check)


def busy_with() -> str:
    """The lab an action is running on, or "".  Only one at a time: they all
    take the same container."""
    with _lock:
        return next(iter(_busy), "")


# ---------------------------------------------------------------- doing something

def _finish(key: str, rc: int, out: str) -> None:
    if rc == 0:
        _errors.pop(key, None)
    else:
        # The tail, not the head: the launcher prints the whole login block on
        # success and the reason on failure, and the reason comes last.
        _errors[key] = (out or "it did not work")[-400:]
    with _lock:
        _busy.pop(key, None)


def _work(key: str, action: str) -> None:
    try:
        if action == "start":
            rc, out = run([HACKRANGE_LAB, "start", key], timeout=ACTION_TIMEOUT)
        elif action == "reset":
            rc, out = run([HACKRANGE_LAB, "reset", key], timeout=ACTION_TIMEOUT)
        else:
            rc, out = run([HACKRANGE_LAB, "stop", "-y"], timeout=ACTION_TIMEOUT)
        _finish(key, rc, out)
    except Exception as exc:                      # never leave a lab stuck "starting"
        _finish(key, 1, str(exc))


def act(key: str, action: str) -> tuple[bool, str]:
    """Start, stop or reset a lab in the background.  (accepted, message)."""
    if key not in catalog.by_key() or action not in ("start", "stop", "reset"):
        return False, "unknown lab or action"
    lab = catalog.by_key()[key]
    if action in ("start", "reset") and not image_present(lab["image"]):
        return False, ("This lab's image is not built yet.  Run the installer again: "
                       "sudo /opt/hackrange-mentorship/install.sh")
    with _lock:
        if _busy:
            other = next(iter(_busy))
            return False, f"Already {_busy[other]} the {other} lab.  Wait for that to finish."
        _busy[key] = "stopping" if action == "stop" else "starting"
        state = _busy[key]
    threading.Thread(target=_work, args=(key, action), daemon=True).start()
    return True, state


def _check_work(key: str) -> None:
    rc, out = run([HACKRANGE_CHECK, key], timeout=CHECK_TIMEOUT)
    with _lock:
        _check.update(key=key, state="done", at=int(time.time()),
                      ok=rc == 0, output=out[-8000:])


def check(key: str) -> tuple[bool, str]:
    """Mark the student's work in a lab, in the background: the answer key for
    one of the challenge labs runs inside the lab and is not instant."""
    if key not in catalog.by_key():
        return False, "unknown lab"
    if current_lab() != key or not _container_running(LAB_CONTAINER):
        return False, "Start this lab first: your work is marked inside it."
    with _lock:
        if _check.get("state") == "running":
            return False, "already checking"
        _check.clear()
        _check.update(key=key, state="running", at=int(time.time()), output="", ok=False)
    threading.Thread(target=_check_work, args=(key,), daemon=True).start()
    return True, "checking"


def containers_for(key: str) -> list[str]:
    """The containers a lab's figures should add up: the lab, and the Week 11
    scanner beside it when that lab has one."""
    lab = catalog.by_key().get(key, {})
    names = [LAB_CONTAINER]
    if lab.get("companion"):
        names.append(COMPANION_CONTAINER)
    return names
