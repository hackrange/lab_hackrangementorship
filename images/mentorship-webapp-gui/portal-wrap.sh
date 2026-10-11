#!/bin/bash
# Seed and start the vulnerable Internal Tools Portal.
#
# The hosted image's copy of this script WRAPPED the desktop entrypoint and
# exec'd it at the end, because there it was the container's entrypoint.  Here
# the entrypoint starts this in the background instead, so the exec is gone: the
# two would otherwise call each other forever and the lab would never come up.
#
# The portal answers at http://portal.lab:5000.  That hostname, rather than
# localhost, is what lets Burp see the traffic: Firefox refuses to send
# localhost through a proxy.
#
# Author: Tim Rice
set -e
# Docker regenerates /etc/hosts each start, so the name is added here too.
grep -q 'portal.lab' /etc/hosts 2>/dev/null || echo '127.0.0.1  portal.lab' >> /etc/hosts
su student -c 'python3 /home/student/app/seed.py >/dev/null 2>&1 || true'
exec su student -c 'cd /home/student/app && exec python3 app.py >/home/student/app/server.log 2>&1'
