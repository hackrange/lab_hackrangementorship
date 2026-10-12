#!/usr/bin/env bash
# The last step: tell the student how to start.
#
# The DevSecOps Local Lab provisions accounts on a Git server and a package
# registry here.  This course has no such services: every lab is a self
# contained machine, so there is nothing to create an account on and the only
# thing left to do is show the way in.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "Your lab is ready"

# The SSH host keys a lab is given, so connecting to one never greets the
# student with "REMOTE HOST IDENTIFICATION HAS CHANGED".  Made once and reused
# by every lab: a fresh container would otherwise bring new keys each time.
install -d -m 700 "$HR_ETC/ssh"
for t in rsa ecdsa ed25519; do
    [ -s "$HR_ETC/ssh/ssh_host_${t}_key" ] && continue
    quiet ssh-keygen -q -t "$t" -N '' -f "$HR_ETC/ssh/ssh_host_${t}_key" ||
        warn "Could not create the $t host key."
done
chmod 600 "$HR_ETC/ssh"/ssh_host_*_key 2>/dev/null || true
chmod 644 "$HR_ETC/ssh"/ssh_host_*_key.pub 2>/dev/null || true

printf '\n'
bash "$HR_ROOT/show_information.sh" 2>/dev/null || true
printf '\n'
say "The labs of this course:"
printf '\n'
grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$HR_CATALOG" | \
    awk -F'|' '{printf "      %-12s weeks %-6s %s\n", $1, $6, $7}'
printf '\n'
say "Start the one your lesson names, for example:"
printf '\n      hackrange-lab start kali\n\n'
say "And when you are working a challenge:"
printf '\n      hackrange-lab check          mark your own findings\n'
printf '      hackrange-lab env            the lab'"'"'s usernames and passwords\n'
printf '      hackrange-lab list           every lab, and the weeks it is for\n\n'
