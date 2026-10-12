#!/bin/bash
# Set the student password from the broker-supplied env, start dbus, run xrdp.
# Author: Tim Rice - tim.j.rice@hackrange.com
set -e

if [ -n "${LAB_PASSWORD}" ]; then
    echo "student:${LAB_PASSWORD}" | chpasswd
else
    passwd -l student >/dev/null 2>&1 || true
fi

mkdir -p /run/dbus
rm -f /run/dbus/pid
dbus-daemon --system --fork 2>/dev/null || true

# xrdp-sesman must be up before xrdp accepts a session.
/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
