#!/bin/bash
# Bring up the desktop, the portal, and the session's own values.
#
# Modelled on the hosted desktop image's entrypoint, including the two faults
# it learned the hard way: a stale X display lock from a committed image kills
# the session before the student sees anything, and values exported only to
# this process never reach a desktop terminal, because a terminal opened from
# the desktop is a child of the session manager and not of this script.
#
# Author: Tim Rice
set -e

if [ -n "${LAB_PASSWORD:-}" ]; then
    echo "student:${LAB_PASSWORD}" | chpasswd
else
    passwd -l student >/dev/null 2>&1 || true
fi

# The session's values, where every shell can find them.  /etc/profile.d covers
# a login shell (ssh, and the desktop terminal, which is configured as a login
# shell); /etc/environment covers the rest.  Writing only one of the two is the
# bug that made every lesson's first command run with an empty variable.
{
    echo '# The lab session'"'"'s own values.  Written at start, not baked in.'
    for v in LAB_PASSWORD DAST_URL DAST_USER DAST_PASSWORD PORTAL_URL; do
        printf 'export %s=%s\n' "$v" "$(printf '%q' "$(eval "printf '%s' \"\${$v:-}\"")")"
    done
} > /etc/profile.d/lab-identity.sh
chmod 644 /etc/profile.d/lab-identity.sh
for v in DAST_URL DAST_USER DAST_PASSWORD PORTAL_URL; do
    val="$(eval "printf '%s' \"\${$v:-}\"")"
    [ -n "$val" ] && printf '%s=%s\n' "$v" "$val" >> /etc/environment
done

# A desktop terminal is not a login shell by default, and a browser launched
# from a desktop icon needs xdg-open to resolve to something real.
export BROWSER=/usr/bin/xdg-open

# Stale run state from a committed image: a /tmp/.X11-lock names a pid that is
# very likely alive as something unrelated in a fresh container, so X decides
# display :0 is taken and refuses to start, leaving a lab that boots to nothing.
rm -f /run/xrdp/*.pid /var/run/xrdp/*.pid 2>/dev/null || true
rm -f /tmp/.X*-lock /tmp/.X11-unix/X* 2>/dev/null || true
rm -f /run/xrdp/sockdir/sesman.socket /run/xrdp/sockdir/.sesman.socket.lock 2>/dev/null || true
mkdir -p /run/xrdp /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

# Parts of the Xfce session need a system dbus.
rm -f /run/dbus/pid 2>/dev/null || true
dbus-daemon --system --fork 2>/dev/null || true

# sshd as well, so the same box answers a terminal lesson.
mkdir -p /var/run/sshd
ssh-keygen -A >/dev/null 2>&1 || true
/usr/sbin/sshd 2>/dev/null || true

# The portal the student is here to test.
/usr/local/bin/portal-wrap &

/usr/sbin/xrdp-sesman 2>/dev/null || /usr/sbin/xrdp-sesman --daemon 2>/dev/null || true
sleep 1

exec /usr/sbin/xrdp --nodaemon 2>/dev/null || exec /usr/sbin/xrdp -nodaemon
