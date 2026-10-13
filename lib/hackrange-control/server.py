#!/usr/bin/env python3
"""The Hackrange Mentorship Local Lab control panel.

    server.py    serve the panel on /run/hackrange-mentorship/control.sock,
                 which nginx fronts at https://<machine>:8456/control/

The page shows how to get into the lab, how hard the machine and the running
lab are working, and a card for each of the course's labs with buttons to
start it, open it, mark your work in it, and stop it.

Standard library only: nothing to install, nothing to keep patched.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import grp
import json
import os
import re
import socket
import sys
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from hrcontrol import auth, catalog, labctl, labinfo, metrics  # noqa: E402

# A Unix socket, not a TCP port: only root and nginx (group www-data) can open
# it, so nothing else on the machine, and no web page (DNS rebinding reaches
# TCP ports, never sockets), can talk to the panel except through nginx, which
# sets X-HR-Door and X-Real-IP itself.
SOCKET = "/run/hackrange-mentorship/control.sock"
SOCKET_GROUP = "www-data"
STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
STATIC_FILES = {
    "index.html": "text/html; charset=utf-8",
    "app.css": "text/css; charset=utf-8",
    "app.js": "application/javascript; charset=utf-8",
    "logo.png": "image/png",
    "favicon.png": "image/png",
}
COOKIE = "hrm_session"
LAB_ACTION_RE = re.compile(r"^/api/labs/([a-z0-9-]{1,20})/(start|stop|reset|check)$")

SECURITY_HEADERS = {
    "Content-Security-Policy": "default-src 'self'; img-src 'self' data:; style-src 'self'; "
                               "script-src 'self'; connect-src 'self'; frame-ancestors 'none'; "
                               "base-uri 'none'; form-action 'self'",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
}


class Handler(BaseHTTPRequestHandler):
    server_version = "hackrange-mentorship-control"

    # ---- plumbing ----------------------------------------------------------

    def _door(self) -> str:
        # Set by nginx, overwriting anything the browser sent.
        return "lab" if self.headers.get("X-HR-Door") == "lab" else "remote"

    def _client(self) -> str:
        return self.headers.get("X-Real-IP") or "local"

    def address_string(self) -> str:   # a Unix socket has no peer address to log
        return self._client()

    def _token(self) -> str:
        c = SimpleCookie(self.headers.get("Cookie", ""))
        return c[COOKIE].value if COOKIE in c else ""

    def _authorized(self) -> bool:
        return self._door() == "lab" or auth.valid(self._token())

    def _send(self, code: int, body: bytes, ctype: str,
              extra: dict | None = None, cache: bool = False) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "private, max-age=300" if cache else "no-store")
        for k, v in {**SECURITY_HEADERS, **(extra or {})}.items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, payload: dict, extra: dict | None = None) -> None:
        self._send(code, json.dumps(payload).encode(), "application/json", extra)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > 4096:
            return {}
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return {}

    def _is_api_write(self) -> bool:
        """Every change must come from the page's own script: a custom header a
        form on another site cannot send, and JSON."""
        return (self.headers.get("X-HR-Request") == "1"
                and self.headers.get("Content-Type", "").startswith("application/json"))

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("hackrange-control: %s %s\n" % (self._client(), fmt % args))

    # ---- routes ------------------------------------------------------------

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            return self._static("index.html")
        if path.startswith("/static/"):
            return self._static(path[len("/static/"):])
        if path == "/open":
            # Open the running lab, signing the student into the web desktop on
            # the way through so they are not asked for a password they have
            # already given this panel.  Minted per click and never held in the
            # page's state, so a session is not left lying in a polled reply.
            if not self._authorized():
                return self._json(401, {"error": "sign in"})
            running = labinfo.current_lab()
            lab = catalog.by_key().get(running)
            if not lab:
                return self._json(409, {"error": "no lab is running"})
            where = labinfo.desktop_path(lab.get("proto") or "rdp", labinfo.guac_token())
            return self._send(302, b"", "text/plain", {"Location": where})
        if path == "/api/whoami":
            return self._json(200, {"door": self._door(), "authenticated": self._authorized()})
        if path == "/api/state":
            if not self._authorized():
                return self._json(401, {"error": "sign in"})
            return self._json(200, self._state())
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if not self._is_api_write():
            return self._json(403, {"error": "refused"})

        if path == "/api/login":
            if self._door() == "lab":
                return self._json(200, {"ok": True})
            body = self._body()
            if auth.locked_out(self._client()):
                return self._json(429, {"error": "Too many wrong passwords.  "
                                                 "Wait five minutes and try again."})
            token = auth.login(self._client(), str(body.get("username", "")),
                               str(body.get("password", "")))
            if not token:
                return self._json(401, {"error": "That username and password did not work.  "
                                                 "Run show_information.sh on your Ubuntu machine "
                                                 "to see the current password."})
            cookie = (f"{COOKIE}={token}; Path=/control/; Secure; HttpOnly; "
                      f"SameSite=Strict; Max-Age={auth.SESSION_HOURS * 3600}")
            return self._json(200, {"ok": True}, {"Set-Cookie": cookie})

        if path == "/api/logout":
            auth.logout(self._token())
            return self._json(200, {"ok": True},
                              {"Set-Cookie": f"{COOKIE}=; Path=/control/; Secure; HttpOnly; "
                                             "SameSite=Strict; Max-Age=0"})

        m = LAB_ACTION_RE.match(path)
        if m:
            if not self._authorized():
                return self._json(401, {"error": "sign in"})
            key, action = m.group(1), m.group(2)
            if action == "check":
                accepted, message = labctl.check(key)
                return self._json(202 if accepted else 409, {"ok": accepted, "message": message})
            # Stopping a lab deletes it and everything in it, and starting one
            # deletes whatever ran before.  The page has to repeat back which
            # lab it asked about, so a stale click cannot delete a different
            # lab from the one the student was looking at.
            if self._body().get("confirm") != key:
                return self._json(400, {"ok": False, "message": "not confirmed"})
            if action in ("start", "reset"):
                # This click rotates the lab password, and sessions are tied to
                # it.  Let this one session follow the change it asked for,
                # instead of signing the student out mid start.
                auth.allow_rotation(self._token())
            accepted, message = labctl.act(key, action)
            return self._json(202 if accepted else 409, {"ok": accepted, "message": message})

        self._json(404, {"error": "not found"})

    # ---- pieces ------------------------------------------------------------

    def _static(self, name: str) -> None:
        if name not in STATIC_FILES:
            return self._json(404, {"error": "not found"})
        with open(os.path.join(STATIC, name), "rb") as fh:
            self._send(200, fh.read(), STATIC_FILES[name], cache=name != "index.html")

    def _state(self) -> dict:
        snap = metrics.snapshot()
        states = labctl.states()
        errs = labctl.errors()
        logins = catalog.logins()
        running = labinfo.current_lab()
        # The Open link is built for the protocol of the lab that is running,
        # because there is one connection per protocol and opening a terminal
        # lab through the desktop one shows a black window that never connects.
        by_key = catalog.by_key()
        running_proto = (by_key.get(running) or {}).get("proto", "rdp")
        info = labinfo.info(running_proto)
        items = []
        for lab in catalog.labs():
            key = lab["key"]
            state = states.get(key, "unknown")
            live = state in ("running", "starting", "stopping")
            emulated = labctl.emulated(lab)
            items.append({
                "key": key,
                "title": lab["title"],
                "what": lab["what"],
                "weeks": lab["weeks"],
                "proto": lab["proto"],
                "state": state,
                "has_companion": bool(lab["companion"]),
                # Said plainly on the card, because a lab that is slow for a
                # reason the student cannot see looks like a lab that is broken.
                "emulated": emulated,
                "notice": catalog.notice(lab, emulated),
                "usage": metrics.usage_for(labctl.containers_for(key), snap) if live else {},
                # The lab's own web apps, addressed from the student's machine.
                # Only while it runs: the port is published by the container,
                # so the address means nothing when it is not there.
                "web": [{"port": w["port"], "label": w["label"],
                         "url": f"http://{info['host']}:{w['port']}/"}
                        for w in lab["web"]] if state == "running" else [],
                # The lab's own logins, which do not depend on it running: a
                # student deciding whether to start the Splunk lab may well
                # want to see what they will be signing in to it with.
                "logins": logins.get(key, []),
                "error": errs.get(key, ""),
            })
        return {
            "door": self._door(),
            "sampled": snap.get("at", 0),
            "host": snap.get("host", {}),
            "running": running if states.get(running) == "running" else "",
            "busy": labctl.busy_with(),
            "labs": items,
            "info": info,
            "check": labctl.check_status(),
        }


class UnixHTTPServer(ThreadingHTTPServer):
    address_family = socket.AF_UNIX
    daemon_threads = True

    def server_bind(self) -> None:
        os.makedirs(os.path.dirname(SOCKET), mode=0o755, exist_ok=True)
        try:
            os.unlink(SOCKET)
        except FileNotFoundError:
            pass
        old = os.umask(0o117)
        try:
            self.socket.bind(SOCKET)
        finally:
            os.umask(old)
        os.chown(SOCKET, 0, grp.getgrnam(SOCKET_GROUP).gr_gid)
        os.chmod(SOCKET, 0o660)
        self.server_name, self.server_port = "localhost", 0


def main() -> None:
    metrics.start()
    UnixHTTPServer(SOCKET, Handler).serve_forever()


if __name__ == "__main__":
    main()
