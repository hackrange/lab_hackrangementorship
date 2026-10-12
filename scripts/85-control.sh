#!/usr/bin/env bash
# Step 85: the control panel.
#
# The panel is the student's way in: it shows their login, how hard the machine
# is working, and a card for each of the course's seven labs with buttons to
# start it, open it, mark their work and end it.  It is at
# https://<this machine>:8456/control/, which is also where the root of that
# address now goes.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
# shellcheck source=lib.sh
. "$HR_ROOT/scripts/lib.sh"

step "Setting up the lab control panel"

CONTROL=/usr/local/lib/hackrange-mentorship/control

install -d -m 755 /usr/local/lib/hackrange-mentorship "$CONTROL"
cp -a "$HR_ROOT/lib/hackrange-control/." "$CONTROL/"
find "$CONTROL" -name '__pycache__' -prune -exec rm -rf {} +
chmod -R go-w "$CONTROL"

# The socket's directory, so the panel does not have to be root to make it on
# a machine where /run is a tmpfs wiped at every boot.  systemd would do this
# with RuntimeDirectory, but the panel also runs straight from a terminal when
# someone is working on it.
install -d -m 755 /run/hackrange-mentorship

install -m 644 "$HR_ROOT/config/systemd/hackrange-mentorship-control.service" \
               /etc/systemd/system/hackrange-mentorship-control.service
systemctl daemon-reload
quiet systemctl enable hackrange-mentorship-control.service
quiet systemctl restart hackrange-mentorship-control.service ||
    die "The control panel would not start.  See: sudo journalctl -u hackrange-mentorship-control"

# nginx already carries the /control/ door (config/nginx/mentorship-access.conf,
# installed in step 60), so there is nothing to install here.  It is reloaded
# anyway: on a first install nginx read that file before this socket existed.
if systemctl is-active --quiet nginx; then
    quiet nginx -t || die "The web server configuration is not valid.  See: sudo nginx -t"
    quiet systemctl reload nginx || die "Could not reload the web server."
fi

# Asking the panel itself, through nginx, rather than just checking that the
# service is "active": a panel that starts and then fails every request is
# exactly the kind of thing that reaches a student otherwise.
panel_up() {
    curl -fsS -o /dev/null --unix-socket /run/hackrange-mentorship/control.sock \
        http://localhost/api/whoami
}
wait_for 60 "the control panel" panel_up ||
    die "The control panel is not answering.  See: sudo journalctl -u hackrange-mentorship-control"

ok "the control panel answers (https://<this machine>:$HR_WEB_PORT/control/)"
