#!/usr/bin/env python3
"""Begin a Remote Desktop connection, the way a client does.

A port that accepts is not a desktop that opens.  The fault that reached a
student was exactly this gap: xrdp was running and listening, and could not
read its own TLS key, because the image had been built without putting the xrdp
user in Debian's ssl-cert group.  Every check anyone had written passed, the
web desktop reported only "Upstream error", and the lab would not open with no
reason given.

So this does what a client does and no more: ask for a connection, read the
answer, and then start the TLS the answer asks for.  If the server cannot read
its key, TLS is where it fails, and that is the whole point of coming this far.
Nothing is sent that could log anybody in, and no password is involved.

Usage: rdp-handshake.py <port> [host]
Author: Tim Rice - tim.j.rice@hackrange.com
"""

import socket
import ssl
import struct
import sys

# TPKT header (19 bytes in all), an X.224 connection request, and the RDP
# negotiation request that says this client can speak TLS or CredSSP.
REQUEST = bytes.fromhex("030000130ee00000000000") + bytes.fromhex("0100080003000000")


def main() -> int:
    port = int(sys.argv[1])
    host = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    try:
        sock = socket.create_connection((host, port), 15)
    except OSError as exc:
        print(f"no-connection {exc}")
        return 1
    sock.settimeout(15)
    try:
        sock.sendall(REQUEST)
        head = sock.recv(4)
        if len(head) < 4 or head[0] != 3:
            print("not-rdp")
            return 1
        want = struct.unpack(">H", head[2:4])[0] - 4
        body = b""
        while len(body) < want:
            chunk = sock.recv(want - len(body))
            if not chunk:
                break
            body += chunk
        if len(body) < 7 or body[1] != 0xD0:
            print("no-connection-confirm")
            return 1
        chosen = None
        if len(body) >= 15 and body[7] == 2:
            chosen = struct.unpack("<I", body[11:15])[0]
        if chosen is None:
            # An older server may confirm without a negotiation response and
            # then speak the original protocol, which is a working desktop.
            print("confirmed plain")
            return 0
        if chosen not in (1, 2):
            print(f"confirmed protocol={chosen}")
            return 0
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        try:
            with context.wrap_socket(sock) as tls:
                print(f"confirmed tls={tls.version()}")
                return 0
        except (ssl.SSLError, OSError) as exc:
            print(f"tls-failed {exc}")
            return 1
    except OSError as exc:
        print(f"broke-off {exc}")
        return 1
    finally:
        try:
            sock.close()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
