#!/bin/bash
# Start Splunk, set the student's RDP password, run the desktop.
# Author: Tim Rice - tim.j.rice@hackrange.com
set -e
[ -n "${LAB_PASSWORD}" ] && echo "student:${LAB_PASSWORD}" | chpasswd || passwd -l student >/dev/null 2>&1 || true
mkdir -p /run/dbus; rm -f /run/dbus/pid; dbus-daemon --system --fork 2>/dev/null || true
# Splunk in the background; the index is already baked, this just serves it.
# Start Splunk in the BACKGROUND. It takes ~25s, and the broker checks the RDP
# port for readiness within ~12s, so xrdp must come up first. Splunk finishes
# on its own while the student is connecting; the desktop is usable at once and
# Firefox reaches Splunk a few seconds later.
rm -f /opt/splunk/var/run/splunk/splunkd.pid 2>/dev/null
( su splunk -c "/opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt" >/dev/null 2>&1 || true ) &
/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
