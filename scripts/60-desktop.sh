#!/usr/bin/env bash
# The web desktop: the way a student opens a lab in a browser.
#
# Guacamole and guacd, behind nginx with this machine's own certificate.  That
# is the whole of it: unlike the DevSecOps Local Lab there is no Git server,
# registry, scanner or cluster to run, because every lab in this course is
# self contained.
#
# Author: Tim Rice
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "Setting up the web desktop"

install -d -m 755 "$HR_ETC"
getent group hackrange-mentorship-guac >/dev/null || groupadd --system hackrange-mentorship-guac
HR_GUAC_GID="$(getent group hackrange-mentorship-guac | cut -d: -f3)"

( umask 077
  cat > "$HR_ETC/desktop.env" <<EOF
# Written by the installer.  Read by docker compose.
GUACAMOLE_IMAGE=$GUACAMOLE_IMAGE
GUACD_IMAGE=$GUACD_IMAGE
HR_GUAC_GID=$HR_GUAC_GID
EOF
)

# The web desktop's login file must exist before its service starts.  A first
# install makes the first password here; every lab start makes a new one.
[ -s "$HR_ETC/guacamole/user-mapping.xml" ] || quiet hackrange-access rotate ||
    die "Could not make the lab password."

# The branding extension Guacamole loads at start.  Packaged with fixed
# timestamps so an unchanged brand produces an identical file and the container
# is only restarted when the branding really changed.
brand_jar="$HR_ETC/guacamole/extensions/hackrange-branding.jar"
install -d -m 750 "$HR_ETC/guacamole/extensions"
chown root:hackrange-mentorship-guac "$HR_ETC/guacamole/extensions"
python3 - "$HR_ROOT/config/guacamole-branding" "$brand_jar.new" <<'PY' || die "Could not package the web desktop's branding."
import sys, zipfile, pathlib
src, out = pathlib.Path(sys.argv[1]), sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in sorted(p for p in src.rglob('*') if p.is_file()):
        zi = zipfile.ZipInfo(str(f.relative_to(src)), date_time=(1980, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = 0o644 << 16
        z.writestr(zi, f.read_bytes())
PY
brand_changed=0
if ! cmp -s "$brand_jar.new" "$brand_jar" 2>/dev/null; then
    mv "$brand_jar.new" "$brand_jar"; brand_changed=1
else
    rm -f "$brand_jar.new"
fi
chown root:hackrange-mentorship-guac "$brand_jar"; chmod 640 "$brand_jar"

say "Starting the web desktop..."
quiet docker compose --env-file "$HR_ETC/desktop.env" \
    -f "$HR_ROOT/config/compose.yml" -p hackrange-mentorship up -d ||
    die "The web desktop would not start.  See: sudo docker compose -p hackrange-mentorship logs"
[ "$brand_changed" = 1 ] && quiet docker restart hackrange-mentorship-guacamole || true

# ---------------------------------------------------------------- nginx

step "Putting the web desktop on this machine's address"

install -d -m 755 /etc/nginx/conf.d /etc/nginx/modules-enabled /etc/nginx/mentorship-brand
install -m 644 "$HR_ROOT/config/nginx/mentorship-hostcheck.conf"    /etc/nginx/conf.d/mentorship-hostcheck.conf
install -m 644 "$HR_ROOT/config/nginx/mentorship-access.conf"       /etc/nginx/conf.d/mentorship-access.conf
install -m 644 "$HR_ROOT/config/nginx/mentorship-private-only.conf" /etc/nginx/mentorship-private-only.conf
# The stream block belongs at the top level of nginx's configuration, which on
# Ubuntu is modules-enabled.  "99" sorts it after the line loading the module.
install -m 644 "$HR_ROOT/config/nginx/mentorship-stream.conf" /etc/nginx/modules-enabled/99-mentorship-stream.conf
install -m 644 "$HR_ROOT/config/guacamole-branding/images/favicon-64.png" \
               "$HR_ROOT/config/guacamole-branding/images/favicon-144.png" /etc/nginx/mentorship-brand/
quiet hackrange-access cert || die "Could not make the web desktop's certificate."

# Reload rather than restart: a restart cuts every open lab session.
if systemctl is-active --quiet nginx; then
    quiet nginx -t || die "The web server configuration is not valid.  See: sudo nginx -t"
    quiet systemctl reload nginx || die "Could not reload the web server."
else
    quiet nginx -t || die "The web server configuration is not valid.  See: sudo nginx -t"
    quiet systemctl enable --now nginx || die "Could not start the web server."
fi

# Verified against the lab CA, not with --insecure: checking the certificate is
# part of checking that the door works.
lab_up() { curl -fsS -o /dev/null --cacert "$LABTLS/lab-ca.crt" --resolve "$(hostname -s):$HR_WEB_PORT:127.0.0.1" "$1" 2>/dev/null \
             || curl -fsS -o /dev/null --cacert "$LABTLS/lab-ca.crt" "$1"; }
wait_for 120 "the web desktop" lab_up "https://127.0.0.1:$HR_WEB_PORT/guacamole/" ||
    die "The web desktop (https://127.0.0.1:$HR_WEB_PORT) is not answering.  See: sudo docker logs hackrange-mentorship-guacamole"
ok "the web desktop answers at https://127.0.0.1:$HR_WEB_PORT"
