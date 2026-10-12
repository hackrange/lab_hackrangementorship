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

# xrdp reads its TLS key as the xrdp user, which Debian allows by putting xrdp
# in the ssl-cert group.  One of these images was built without that
# membership, so xrdp could not read /etc/ssl/private/ssl-cert-snakeoil.key:
# the RDP handshake then failed before any password was asked for, guacd said
# only "Upstream error", and the student met a lab that would not open and no
# reason why.  Group membership is read when xrdp starts, so putting it right
# here is enough, and doing it here means an image already built with the
# fault is cured by starting it.
if getent group ssl-cert >/dev/null 2>&1 && id xrdp >/dev/null 2>&1; then
    id -nG xrdp 2>/dev/null | grep -qw ssl-cert || usermod -aG ssl-cert xrdp 2>/dev/null || true
fi

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


# sshd, so this desktop lab answers a terminal too.
#
# The SSH door on 2223 is published for every lab, and the student is told SSH
# is one of the three ways in.  This image ran no sshd, so nginx accepted the
# connection, found nothing behind it and closed it: "Connection closed by
# <host> port 2223", on a lab they had just been told to reach that way.  It is
# started here rather than exec'd because xrdp is what this container is for,
# and a failure to start a terminal must not take the desktop down with it.
mkdir -p /run/sshd
ssh-keygen -A >/dev/null 2>&1 || true
/usr/sbin/sshd 2>/dev/null || true

# xrdp-sesman must be up before xrdp accepts a session.
/usr/sbin/xrdp-sesman
exec /usr/sbin/xrdp --nodaemon
