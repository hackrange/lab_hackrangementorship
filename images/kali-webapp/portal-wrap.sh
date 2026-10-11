#!/bin/bash
# Start the vulnerable Internal Tools Portal alongside the Kali desktop, then run
# the normal kali-lab-gui entrypoint. Wrapping (not replacing) the base entrypoint
# keeps all the desktop wiring intact.
#
# The portal is reached at http://portal.lab:5000. That hostname (not localhost)
# matters: Firefox is configured to route it through Burp, and Firefox never
# proxies localhost, so a real name is what makes Burp intercept the traffic.
# Author: Tim Rice
set -e
# Docker regenerates /etc/hosts each start, so add the portal name here.
grep -q 'portal.lab' /etc/hosts 2>/dev/null || echo '127.0.0.1  portal.lab' >> /etc/hosts
# Seed and launch the portal as the student, in the background.
su student -c 'python3 /home/student/app/seed.py >/dev/null 2>&1 || true'
su student -c 'cd /home/student/app && nohup python3 app.py >/home/student/app/server.log 2>&1 &'
# Hand off to the real kali-lab-gui entrypoint (desktop, xrdp, password, etc.).
exec /usr/local/bin/lab-entrypoint "$@"
