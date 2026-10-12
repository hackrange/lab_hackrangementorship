"""What the student needs to get into their lab.

Read fresh on every request from the files the installer and hackrange-access
keep current, so the page never shows a password that has since changed.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import base64
import ipaddress
import subprocess

from .const import (ACCESS_ENV, GUAC_CONNECTION, RDP_PORT, SSH_PORT, STATE,
                    WEB_PORT)


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


def desktop_url(host: str) -> str:
    """The address that opens the running lab itself, not the sign in page.

    Guacamole names a session by base64 of "<connection>\\0c\\0<datasource>".
    Building it here rather than asking the student to find it is the whole
    point of an Open button, and it is the same for every lab because the
    connection's name is fixed.
    """
    token = (GUAC_CONNECTION + "\0c\0default").encode()
    ident = base64.b64encode(token).decode().rstrip("=")
    return f"https://{host}:{WEB_PORT}/guacamole/#/client/{ident}"


def info() -> dict:
    ip = machine_ip()
    host = ip or "127.0.0.1"
    return {
        "machine_ip": ip,
        "username": "student",
        "password": access_password(),
        "web_host": f"https://{host}:{WEB_PORT}",
        "desktop_url": desktop_url(host),
        "ssh_host": f"ssh -p {SSH_PORT} student@{host}",
        "ssh_local": f"ssh -p {SSH_PORT} student@127.0.0.1",
        "rdp_host": f"{host}:{RDP_PORT}",
        "host": host,
    }
