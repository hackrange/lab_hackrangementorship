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
# Clear the run state left behind by the PREVIOUS life of this container.
# Docker restarts a container after a reboot or a crash with its writable layer
# intact, so the pid file xrdp-sesman wrote before the machine went down is
# still sitting there.  sesman reads it, says "xrdp-sesman is already running",
# and exits; the restart policy then loops on that forever, so the lab never
# comes back from a reboot and the only cure was deleting the container by
# hand.  None of this state is worth keeping across a restart, so none is kept.
rm -f /run/xrdp/*.pid /var/run/xrdp/*.pid 2>/dev/null || true
rm -f /run/xrdp/sockdir/sesman.socket /run/xrdp/sockdir/.sesman.socket.lock 2>/dev/null || true
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
mkdir -p /run/xrdp /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
