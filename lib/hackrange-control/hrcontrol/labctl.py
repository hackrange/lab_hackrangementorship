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

import platform
import re
import socket
import urllib.error
import urllib.request
import threading
import time

from . import catalog
from .const import (COMPANION_CONTAINER, GUAC_CONTAINER, GUAC_MAPPING,
                    GUAC_UPSTREAM, HACKRANGE_CHECK, HACKRANGE_LAB,
                    LAB_CONTAINER, RDP_INNER, SSH_INNER)
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


_ARCH_CACHE: dict[str, tuple[float, bool]] = {}
ARCH_TTL = 300.0


def emulated(lab: dict) -> bool:
    """Is this lab a different processor from the machine it is running on?

    Asked of the image rather than of the lab's name, so it stays true if
    another lab is ever built for one processor only, and false on a machine
    that runs that image natively.

    Remembered for a few minutes, because the page asks for the whole state
    every few seconds and an image's processor only changes when it is rebuilt.
    """
    image = lab.get("image", "")
    hit = _ARCH_CACHE.get(image)
    now = time.time()
    if hit and now - hit[0] < ARCH_TTL:
        return hit[1]
    here = platform.machine()
    native = {"x86_64": "amd64", "amd64": "amd64",
              "aarch64": "arm64", "arm64": "arm64"}.get(here, here)
    rc, out = run([DOCKER, "image", "inspect", "-f", "{{.Architecture}}", image],
                  timeout=15)
    arch = out.strip() if rc == 0 else ""
    if not arch:
        return False      # not built yet; nothing to say about it
    answer = arch != native
    _ARCH_CACHE[image] = (now, answer)
    return answer

def _port_open(port: int) -> bool:
    """Is the lab's own door answering on this machine yet?"""
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1.5):
            return True
    except OSError:
        return False


def _mapping_has(proto: str) -> bool:
    """Does the web desktop offer a connection for this protocol?

    Both are written at once and never change, so this is really a check that
    the file is there and whole, rather than a race worth watching.  It is
    still worth asking: an empty or half written file is the difference
    between a lab that opens and a login that is refused.
    """
    try:
        with open(GUAC_MAPPING) as fh:
            text = fh.read()
    except OSError:
        return False
    return bool(re.search(r"<protocol>\s*" + re.escape(proto) + r"\s*</protocol>", text))


def _web_answers(port: int) -> bool:
    """Is the lab's own web app serving yet, not merely published?

    A plain socket test is worthless here.  Docker publishes a port by putting
    its own proxy in front of it, and that proxy accepts a connection the
    instant the container exists, long before anything inside is listening.  So
    this asks for a page, and any HTTP reply at all counts: a login redirect, a
    401 or even a 404 all mean something is answering, where nothing answering
    is what we are looking for.
    """
    try:
        urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=3)
        return True
    except urllib.error.HTTPError:
        return True          # it answered, and said no.  Still answering.
    except (urllib.error.URLError, OSError, ValueError):
        return False

def ready(lab: dict) -> bool:
    """Can a student actually open this lab right now?

    Not the same question as "is the container running", which is what this
    used to answer and why the panel offered an Open button a couple of
    minutes before the lab would accept anybody.  Three things have to be true,
    and each of them is false for a while after the container appears:

      - the lab's own door answers.  A desktop lab has to finish starting
        xrdp and an X session, which on an emulated lab takes a while.
      - the web desktop is running AND answering.  It is restarted on every
        lab start, deliberately, to end sessions that still hold the previous
        lab's connection, so for a few seconds it is up and not yet serving.
      - the web desktop offers a connection for this lab's protocol at all,
        which is really a check that its login file is there and whole.

    An emulated lab with a web app of its own has a fourth: that web app has to
    be answering.  For such a lab the card sends the student to their own
    browser rather than to the web desktop, so the thing that must be ready is
    the thing the button opens.  Splunk on an ARM machine answers about three
    minutes after the lab starts, which is a long time to leave a button
    sitting there promising something it cannot yet do.
    """
    inner = SSH_INNER if lab.get("proto") == "ssh" else RDP_INNER
    if not (_port_open(inner)
            and _container_running(GUAC_CONTAINER)
            and _port_open(GUAC_UPSTREAM)
            and _mapping_has(lab.get("proto") or "rdp")):
        return False
    if emulated(lab):
        return all(_web_answers(w["port"]) for w in lab.get("web") or [])
    return True


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
            out[key] = "running" if ready(lab) else "preparing"
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
