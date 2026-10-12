"""What the student needs to get into their lab.

Read fresh on every request from the files the installer and hackrange-access
keep current, so the page never shows a password that has since changed.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import base64
import ipaddress
import json
import subprocess
import urllib.error
import urllib.parse
import urllib.request

from .const import (ACCESS_ENV, GUAC_RDP_NAME, GUAC_SSH_NAME, GUAC_UPSTREAM,
                    RDP_PORT, SSH_PORT, STATE, WEB_PORT)


def _read_env(path: str) -> dict:
    out = {}
    try:
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    out[k] = v
    except OSError:
        pass
    return out


def access_password() -> str:
    return _read_env(ACCESS_ENV).get("LAB_ACCESS_PASSWORD", "")


def current_lab() -> str:
    try:
        with open(STATE) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def machine_ip() -> str:
    """This machine's address on its own network, if it is a private one."""
    try:
        out = subprocess.run(["ip", "-4", "route", "get", "1.1.1.1"],
                             capture_output=True, text=True, timeout=5).stdout
        ip = out.split(" src ")[1].split()[0]
        return ip if ipaddress.ip_address(ip).is_private else ""
    except (IndexError, ValueError, OSError, subprocess.SubprocessError):
        return ""


def desktop_url(host: str, proto: str = "rdp") -> str:
    """The address that opens the running lab itself, not the sign in page.

    Guacamole names a session by base64 of "<connection>\\0c\\0<datasource>".
    Building it here rather than asking a student to find it is the whole point
    of an Open button.  There are two connections, one per protocol, and this
    picks the one the running lab speaks: a terminal lab opened through the
    desktop connection shows a black window and never connects.
    """
    name = GUAC_SSH_NAME if proto == "ssh" else GUAC_RDP_NAME
    token = (name + "\0c\0default").encode()
    ident = base64.b64encode(token).decode().rstrip("=")
    return f"https://{host}:{WEB_PORT}/guacamole/#/client/{ident}"


def guac_token() -> str:
    """A web desktop session for the student who is already signed in here.

    They have proved who they are to this panel with the lab password, and the
    web desktop wants the same password again.  Asking twice for one password
    is not security, it is an obstacle, so the panel spends the password on
    their behalf and hands the browser the session it gets back.

    The web desktop takes the query string of the address it is opened at and
    offers it as credentials, so a session passed as "?token=" is adopted
    without a form.  Verified both ways round before it was relied on: the
    token endpoint accepts a bare token as the only credential and answers 200,
    and the page's own script posts the address's parameters to that endpoint.

    Returns "" on any failure, and the caller then opens the sign in page: a
    student who has to type their password is inconvenienced, where one sent to
    a broken address is stuck.
    """
    pw = access_password()
    if not pw:
        return ""
    body = urllib.parse.urlencode({"username": "student", "password": pw}).encode()
    url = f"http://127.0.0.1:{GUAC_UPSTREAM}/guacamole/api/tokens"
    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    try:
        with urllib.request.urlopen(req, timeout=10) as fh:
            token = json.loads(fh.read(8192)).get("authToken", "")
    except (urllib.error.URLError, OSError, ValueError, TypeError):
        return ""
    # Only ever a hex session id.  Checked rather than trusted, because this
    # goes into an address the browser is told to follow.
    return token if token.isalnum() and len(token) <= 128 else ""


def desktop_path(proto: str = "rdp", token: str = "") -> str:
    """The web desktop address as a path, for a redirect from this panel.

    A path rather than a full address, so it works whichever name or address
    the student reached the panel at, including through a tunnel.
    """
    name = GUAC_SSH_NAME if proto == "ssh" else GUAC_RDP_NAME
    ident = base64.b64encode((name + "\0c\0default").encode()).decode().rstrip("=")
    tail = f"?token={urllib.parse.quote(token)}" if token else ""
    return f"/guacamole/#/client/{ident}{tail}"


def info(proto: str = "rdp") -> dict:
    ip = machine_ip()
    host = ip or "127.0.0.1"
    return {
        "machine_ip": ip,
        "username": "student",
        "password": access_password(),
        "web_host": f"https://{host}:{WEB_PORT}",
        "desktop_url": desktop_url(host, proto),
        "ssh_host": f"ssh -p {SSH_PORT} student@{host}",
        "ssh_local": f"ssh -p {SSH_PORT} student@127.0.0.1",
        "rdp_host": f"{host}:{RDP_PORT}",
        "host": host,
    }
