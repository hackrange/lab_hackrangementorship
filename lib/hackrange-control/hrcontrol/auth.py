"""Who may use the control panel.

The panel asks for the lab login: user student and the current lab password,
the one show_information.sh prints.  A session ends when the password changes,
after 12 hours, or at sign out.  Five wrong passwords from one address lock it
out for five minutes.

nginx sets X-HR-Door itself and overwrites anything a browser sent, so a
request cannot claim a trusted door.  The panel listens on a Unix socket, so
nginx is the only thing on the machine that can reach it at all.

The grace window exists because of a trap peculiar to this course.  Starting a
lab rotates the lab password, and a session is deliberately tied to the
password so that rotating it logs everyone out.  Without a grace window a
student who pressed Start would be signed out by their own click, mid start,
and would not even be able to read the new password the panel was about to
show them.  So the session that asked for the start, and only that one, is
allowed to follow the password it caused to change: it is re-tied to the new
password the first time it is seen afterwards.  A session that did not ask for
anything is still dropped by a rotation, which is what makes "hackrange-lab
reset" from the terminal an effective way to evict somebody.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import threading
import time

from . import labinfo

SESSION_HOURS = 12
MAX_FAILURES = 5
LOCKOUT_SECONDS = 300
GRACE_SECONDS = 900

_sessions: dict[str, tuple[float, str]] = {}   # token -> (expires, password fingerprint)
_failures: dict[str, list[float]] = {}         # client address -> failure times
_grace: dict[str, float] = {}                  # token -> may follow a rotation until
_lock = threading.Lock()


def _fingerprint(password: str) -> str:
    return hashlib.sha256(("hackrange-mentorship-control:" + password).encode()).hexdigest()


def locked_out(client: str) -> bool:
    now = time.time()
    with _lock:
        recent = [t for t in _failures.get(client, []) if now - t < LOCKOUT_SECONDS]
        _failures[client] = recent
        return len(recent) >= MAX_FAILURES


def login(client: str, username: str, password: str) -> str | None:
    """A session token for the right login, or None."""
    if locked_out(client):
        return None
    current = labinfo.access_password()
    # compare_digest on both halves, and & rather than "and", so a wrong
    # username and a wrong password take the same time to refuse.
    ok = bool(current) and bool(hmac.compare_digest(username, "student")
                                & hmac.compare_digest(password, current))
    if not ok:
        with _lock:
            _failures.setdefault(client, []).append(time.time())
        return None
    token = secrets.token_urlsafe(32)
    with _lock:
        _failures.pop(client, None)
        _sessions[token] = (time.time() + SESSION_HOURS * 3600, _fingerprint(current))
    return token


def logout(token: str) -> None:
    with _lock:
        _sessions.pop(token, None)
        _grace.pop(token, None)


def allow_rotation(token: str) -> None:
    """This session asked for something that rotates the password, so let it
    follow the change rather than being signed out by its own click."""
    if not token:
        return
    with _lock:
        if token in _sessions:
            _grace[token] = time.time() + GRACE_SECONDS


def valid(token: str) -> bool:
    if not token:
        return False
    with _lock:
        entry = _sessions.get(token)
        if not entry:
            return False
        expires, fp = entry
        now = time.time()
        if now > expires:
            _sessions.pop(token, None)
            _grace.pop(token, None)
            return False
        current = _fingerprint(labinfo.access_password())
        if fp == current:
            return True
        if _grace.get(token, 0) > now:
            # Re-tie it to the password it caused to change, once.
            _sessions[token] = (expires, current)
            _grace.pop(token, None)
            return True
        _sessions.pop(token, None)
        _grace.pop(token, None)
        return False
