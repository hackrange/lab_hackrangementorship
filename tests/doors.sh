#!/usr/bin/env bash
# Check the way IN to a lab, from where the student stands.
#
# rehearse.sh checks the labs themselves, in throwaway containers on their own
# network.  Everything between the student and a lab it never sees: nginx, the
# published ports, the control panel, the web desktop and its sign in.  Three
# faults shipped in that gap, and every one of them was the first thing a
# student touched.
#
#   - Two desktop images carried no sshd, so the SSH door accepted the
#     connection, found nothing behind it and closed it: "Connection closed by
#     <host> port 2223", on labs the course tells them to reach that way.
#   - The web desktop asked for the lab password again, after the panel had
#     just taken it, because nothing carried the session across.
#   - A stale web desktop session served the wrong protocol's connection, so
#     Open gave a window that never connected.
#
# So this runs against a real install and asks the questions in the student's
# order: is the panel there, does my password work, does Open really open, and
# do the two ports the course prints actually answer.
#
# Usage: sudo tests/doors.sh            the lab that is running
#        sudo tests/doors.sh splunk     start that lab first, then check
# Author: Tim Rice - tim.j.rice@hackrange.com
set -uo pipefail

HR_ROOT=/opt/hackrange-mentorship
HR_ETC=/etc/hackrange-mentorship
WEB_PORT=8456
SSH_PORT=2223
RDP_PORT=13489
GUAC_UPSTREAM=18091
GUAC="http://127.0.0.1:$GUAC_UPSTREAM/guacamole"
PANEL="https://127.0.0.1:$WEB_PORT/control"
JAR="$(mktemp)"
PASS=0; FAIL=0

C_G=$'\033[32m'; C_R=$'\033[31m'; C_B=$'\033[1m'; C_O=$'\033[0m'
ok()  { printf '    %s[pass]%s %s\n' "$C_G" "$C_O" "$1"; PASS=$((PASS+1)); }
bad() { printf '    %s[FAIL]%s %s\n' "$C_R" "$C_O" "$1"; [ -n "${2:-}" ] && printf '           %s\n' "$2"; FAIL=$((FAIL+1)); }
head2() { printf '\n  %s%s%s\n' "$C_B" "$1" "$C_O"; }
trap 'rm -f "$JAR"' EXIT

[ "$(id -u)" = 0 ] || { echo "run this with sudo"; exit 1; }

password() { grep -oE '[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}-[a-z0-9]{4}' \
                 "$HR_ETC/access.env" 2>/dev/null | head -1; }
running()  { cat "$HR_ETC/current-lab" 2>/dev/null; }
proto_of() { grep -vE '^\s*#|^\s*$' "$HR_ROOT/config/labs.conf" |
                 awk -F'|' -v k="$1" '$1==k {print $3; exit}'; }
web_of()   { grep -vE '^\s*#|^\s*$' "$HR_ROOT/config/labs.conf" |
                 awk -F'|' -v k="$1" '$1==k {print $8; exit}'; }

# A port the way a client meets it: open it and read what comes back.
banner() { timeout 8 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1; head -c 20 <&3" 2>/dev/null | tr -d '\r'; }
accepts() { timeout 8 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" >/dev/null 2>&1; }

if [ $# -gt 0 ]; then
    echo "starting the $1 lab"
    "$HR_ROOT/bin/hackrange-lab" start "$1" >/dev/null || { echo "could not start $1"; exit 1; }
fi

LAB="$(running)"
[ -n "$LAB" ] || { echo "no lab is running; name one, or start one first"; exit 1; }
PROTO="$(proto_of "$LAB")"
PW="$(password)"
printf '%sThe way in to the %s lab (%s)%s\n' "$C_B" "$LAB" "$PROTO" "$C_O"

head2 "the two ports the course prints"
b="$(banner "$SSH_PORT")"
case "$b" in
    SSH-*) ok "SSH on $SSH_PORT answers ($b)" ;;
    *)     bad "nothing answers SSH on $SSH_PORT" \
               "the student sees 'Connection closed by <host> port $SSH_PORT'" ;;
esac
# A port that accepts is not a desktop that opens, so go as far as a client
# goes: ask for the connection and start the TLS the answer asks for.  That is
# where an xrdp which cannot read its own key fails, and that fault reached a
# student with nothing but "Upstream error" to show for it.
if [ "$PROTO" = rdp ]; then
    out="$(python3 "$HR_ROOT/tests/rdp-handshake.py" "$RDP_PORT" 2>&1)"
    case "$out" in
        confirmed*) ok "Remote Desktop on $RDP_PORT begins a session ($out)" ;;
        *)          bad "Remote Desktop on $RDP_PORT did not begin a session" "$out" ;;
    esac
else
    accepts "$RDP_PORT" && ok "Remote Desktop on $RDP_PORT accepts" \
                        || bad "nothing accepts on Remote Desktop port $RDP_PORT"
fi

head2 "the control panel"
code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 "$PANEL/api/whoami")"
[ "$code" = 200 ] && ok "the panel answers ($code)" || bad "the panel answered '$code'"

code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 -c "$JAR" \
        -X POST -H 'X-HR-Request: 1' -H 'Content-Type: application/json' \
        --data "{\"username\":\"student\",\"password\":\"$PW\"}" "$PANEL/api/login")"
if [ "$code" = 200 ] && grep -q hrm_session "$JAR"; then
    ok "the lab password signs in to the panel"
else
    bad "signing in to the panel gave '$code'" "nothing else here can be checked"
fi

code="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 -b "$JAR" "$PANEL/api/state")"
[ "$code" = 200 ] && ok "the panel reports its state to a signed in student" \
                  || bad "the panel's state gave '$code'"

head2 "Open the lab, which must not ask for the password again"
# The raw header, not curl's resolved redirect_url: the address carries the
# session after a "#", and resolving it drops the fragment along with it.
loc="$(curl -sk -o /dev/null -D - --max-time 20 -b "$JAR" "$PANEL/open" 2>/dev/null |
       awk 'tolower($1)=="location:" {print $2; exit}' | tr -d '\r')"
case "$loc" in
    *"/guacamole/#/client/"*) ok "Open sends the student at the running lab" ;;
    "")                       bad "Open sent the student nowhere" "no redirect at all" ;;
    *)                        bad "Open sent the student to '$loc'" ;;
esac

want="$([ "$PROTO" = ssh ] && echo terminal || echo desktop)"
ident="$(printf 'Hackrange Mentorship Lab (%s)\0c\0default' "$want" | base64 -w0 | tr -d '=')"
case "$loc" in
    *"/client/$ident"*) ok "it opens the $want connection, which is what this lab speaks" ;;
    *) bad "it opens a connection this lab does not speak" \
           "a $PROTO lab needs the $want connection" ;;
esac

tok="${loc##*token=}"; [ "$tok" = "$loc" ] && tok=""
if [ -z "$tok" ]; then
    bad "Open carries no web desktop session" "the student is asked for the password a second time"
else
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -X POST \
            --data-urlencode "token=$tok" "$GUAC/api/tokens")"
    [ "$code" = 200 ] && ok "the session it carries is a real one, accepted without a password" \
                      || bad "the session it carries was refused ($code)"
fi

head2 "what the web desktop needs on its side"
for c in hackrange-mentorship-guacamole hackrange-mentorship-guacd; do
    s="$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null)"
    [ "$s" = running ] && ok "$c is running" || bad "$c is '$s'"
done
# guacd is what actually dials the lab, from inside its own container, so ask
# it rather than asking the host.  It reaches the lab by the name and port its
# own connection names, which is the only pair worth testing: "Upstream error"
# with everything on the host looking fine is this one hop failing.
MAP="$HR_ETC/guacamole/user-mapping.xml"
gname="$([ "$PROTO" = ssh ] && echo terminal || echo desktop)"
# The hostname and port belonging to THIS lab's connection, not whichever came
# first in the file: the two connections differ in both.
pair="$(awk -v want="Hackrange Mentorship Lab ($gname)" '
    index($0, "name=\"" want "\"") { inside = 1 }
    inside && /name="hostname"/  { h = $0 }
    inside && /name="port"/      { p = $0 }
    inside && /<\/connection>/   { print h "\n" p; exit }
' "$MAP" 2>/dev/null | sed -e 's/.*>\([^<]*\)<.*/\1/' | tr '\n' ' ')"
ghost="$(echo "$pair" | awk '{print $1}')"
gport="$(echo "$pair" | awk '{print $2}')"
if [ -z "$ghost" ] || [ -z "$gport" ]; then
    bad "the web desktop has no connection for this lab" \
        "expected one called 'Hackrange Mentorship Lab ($gname)' in $MAP"
else
    # guacd's own image is Alpine with nothing in it that can open a socket, so
    # the probe borrows the web desktop's image and runs it in guacd's network,
    # which is the position that matters.  That image is always installed here,
    # so this needs nothing fetched.
    gimage="$(docker inspect -f '{{.Config.Image}}' hackrange-mentorship-guacamole 2>/dev/null)"
    if docker run --rm --network "container:hackrange-mentorship-guacd" \
            --entrypoint bash "$gimage" \
            -c "exec 3<>/dev/tcp/$ghost/$gport" >/dev/null 2>&1; then
        ok "guacd reaches the lab at $ghost:$gport, which is what its connection says"
    else
        bad "guacd cannot reach $ghost:$gport" \
            "this is the hop that shows up as 'Upstream error' and nothing else"
    fi
fi

head2 "a lab's own web app, if it has one"
# An emulated lab is given longer, because it needs it and that is not a fault.
# Measured on an ARM machine: Splunk answers 163 seconds after the lab starts,
# where it takes a few seconds natively.  A 180 second wait called that a
# failure once, which is a test too impatient for the thing it was testing.
image="$(grep -vE '^\s*#|^\s*$' "$HR_ROOT/config/labs.conf" |
         awk -F'|' -v k="$LAB" '$1==k {print $2; exit}')"
iarch="$(docker image inspect -f '{{.Architecture}}' "$image" 2>/dev/null)"
case "$(uname -m)" in x86_64) harch=amd64 ;; aarch64|arm64) harch=arm64 ;; *) harch="" ;; esac
tries=90
if [ -n "$iarch" ] && [ -n "$harch" ] && [ "$iarch" != "$harch" ]; then
    tries=240
    printf '    emulated on this machine (%s image, %s host), so it is given longer\n' \
        "$iarch" "$harch"
fi
w="$(web_of "$LAB")"
if [ "$w" = "-" ] || [ -z "$w" ]; then
    ok "$LAB publishes no web app, and none is expected"
else
    port="${w%%/*}"; label="${w##*/}"
    for i in $(seq 1 "$tries"); do
        code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$port/")"
        case "$code" in 2*|3*) break ;; esac
        sleep 2
    done
    case "$code" in
        2*|3*) ok "$label answers on port $port ($code)" ;;
        *)     bad "$label did not answer on port $port ('$code')" ;;
    esac
fi

printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
