#!/usr/bin/env bash
# Step 40: this machine's own lab certificate authority.
#
# The lab services speak HTTPS with a certificate from a private CA, and every
# tool in the lab trusts that CA, so no lesson ever tells a student to pass -k
# or --insecure.  The hosted course has one CA for its shared node.  A Local
# Lab makes its own, here, and its private key never leaves this machine.
#
# The CA is made once.  The service certificate is renewed when it is within a
# month of expiring, which a re-run of the installer takes care of.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
# shellcheck source=lib.sh
. "$HR_ROOT/scripts/lib.sh"

step "Creating the lab certificate authority"

CA_DIR="$HR_ETC/ca"
install -d -m 700 "$CA_DIR"
install -d -m 755 "$LABTLS"

if [ ! -s "$CA_DIR/lab-ca.key" ] || [ ! -s "$CA_DIR/lab-ca.crt" ]; then
    # Name constraints: this CA can vouch only for the lab's own names and for
    # private addresses, never for a real website.  A student is asked to trust
    # it on their own computer (see the README), so even a stolen copy of its
    # key could not be used to impersonate their bank or their email.
    host="$(hostname -s | tr 'A-Z' 'a-z')"
    case "$host" in *[!a-z0-9-]*|'') host=localhost ;; esac
    printf '%s\n' "$host" > "$CA_DIR/permitted-host"
    nc="critical,permitted;DNS:lab,permitted;DNS:localhost,permitted;DNS:$host"
    for r in 10.0.0.0/255.0.0.0 172.16.0.0/255.240.0.0 192.168.0.0/255.255.0.0 100.64.0.0/255.192.0.0 \
             127.0.0.0/255.0.0.0 169.254.0.0/255.255.0.0; do
        nc="$nc,permitted;IP:$r"
    done
    quiet openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 3650 \
        -keyout "$CA_DIR/lab-ca.key" -out "$CA_DIR/lab-ca.crt" \
        -subj "/C=US/O=Hackrange Labs/CN=Hackrange Local Lab CA ($(hostname -s))" \
        -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" \
        -addext "subjectKeyIdentifier=hash" \
        -addext "nameConstraints=$nc" || die "Could not create the lab CA."
    chmod 600 "$CA_DIR/lab-ca.key"
    rm -f "$LABTLS/lab-access.crt"            # a new CA needs a new certificate
    say "new CA created"
fi

# No service certificate here.  This course runs no lab services: the only
# certificate is the web desktop's, and hackrange-access issues that one, for
# whatever addresses this machine has at the time (they can change, and a
# certificate naming a stale address is a warning in the student's browser).

# Every place that needs the public CA certificate.  The key stays in $CA_DIR.
install -d -m 755 "$LABTLS"
install -m 644 "$CA_DIR/lab-ca.crt" "$LABTLS/lab-ca.crt"
# Trusted by this machine, so curl and a browser ON the machine see no warning.
# Named for this course so it does not collide with the DevSecOps Local Lab's.
install -m 644 "$CA_DIR/lab-ca.crt" /usr/local/share/ca-certificates/hackrange-mentorship-ca.crt
quiet update-ca-certificates

ok "lab CA $(openssl x509 -noout -fingerprint -sha256 -in "$CA_DIR/lab-ca.crt" | cut -d= -f2 | cut -c1-23)..."
