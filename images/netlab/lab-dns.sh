#!/bin/bash
# Start, stop, and check BIND9 in a container that has no systemd.
#
# "systemctl start named" is what every tutorial on the internet tells a learner
# to run, and it fails here because there is no init system.  Rather than teach a
# workaround mid-lesson, this wraps the few things a student actually needs.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
set -u

# The student is logged in as an unprivileged user, but named needs root: it
# creates /run/named and calls setgid() when dropping to the bind account.  The
# lab account has passwordless sudo, so re-exec through it rather than making
# every lesson and the MOTD say "sudo lab-dns ...".  Without this, start fails
# with "setgid(): Operation not permitted", which tells a learner nothing useful.
# Use the absolute path, not "$0": sudo resets PATH to secure_path, so a bare
# name would not be found.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo /usr/local/bin/lab-dns "$@"
fi

CONF=/etc/bind/named.conf
PIDFILE=/run/named/named.pid

# Two different logs, because named writes to two different places.  Anything it
# says BEFORE it daemonizes (a config it cannot parse) goes to stderr and is
# caught in LOG.  Everything after that, zone loading included, goes to the file
# channel declared in named.conf.
LOG=/var/log/lab-named.log
NAMEDLOG=/var/log/bind/named.log

usage() {
    cat <<'USAGE'
Usage: lab-dns {start|stop|restart|status|zones|log|check|checkzone <zone> <file>}

  start              start the DNS server
  stop               stop it
  restart            stop then start (do this after editing a zone file)
  status             is it running, and on what
  zones              which configured zones are actually ANSWERING  <- start here
                     if a lookup returns nothing
  log                show what named said when it started
  template           write a starter lab.local zone AND declare it, so you do
                     not have to paste multi-line text into an editor
  check              validate named.conf syntax
  checkzone Z FILE   validate a zone file, e.g.
                     lab-dns checkzone lab.local /etc/bind/db.lab.local
USAGE
}

# Cached output of "named-checkconf -z", which reads the same config and loads
# the same zone files named does, and reports exactly why any of them failed.
CHECKZ=
checkz() {
    [ -n "$CHECKZ" ] || CHECKZ=$(named-checkconf -z "$CONF" 2>&1)
    printf '%s\n' "$CHECKZ"
}

# Why is this zone not loaded?  Telling a student to go and read a log, when we
# can already answer the question, wastes the moment they are actually paying
# attention.  Ask named-checkconf rather than parsing the log: it gives the same
# reason, and it also catches the case where the zone file has since been fixed
# but named is still running the old config.
# Prints an indented explanation and returns 0, or prints nothing and returns 1
# when it genuinely cannot tell.
zone_reason() {
    local z=$1 fail file detail
    fail=$(checkz | grep -F "zone $z/" | grep -F 'failed:' | head -1)
    if [ -z "$fail" ]; then
        if checkz | grep -F "zone $z/" | grep -q 'loaded serial'; then
            echo "              The zone file is valid now, so named is still running the"
            echo "              config it started with.  Fix:  lab-dns restart"
            return 0
        fi
        return 1
    fi
    # Strip the "zone lab.local/IN: " prefix; the zone name is already above.
    echo "              named said: ${fail#*: }"
    # A syntax error inside the zone file gets its own line naming the file AND
    # the line number, which is the single most useful thing to hand a student.
    # It does not mention the zone, so tie it back by the file path.
    file=$(printf '%s\n' "$fail" | sed -E 's/.*master file (.+) failed:.*/\1/')
    if [ -n "$file" ] && [ "$file" != "$fail" ]; then
        detail=$(checkz | grep -F "$file:" | head -1)
        [ -n "$detail" ] && echo "              $detail"
    fi
    return 0
}

# Which zones are declared in the config, and is named actually answering for
# them?  A zone that fails to load does not stop named, and the failure is not
# printed anywhere the student is looking, so every lookup just returns nothing
# with no explanation.  This makes both the failure and its cause visible.
zone_report() {
    local zones z soa found=0 explained=0
    zones=$(grep -rhoE '^[[:space:]]*zone[[:space:]]+"[^"]+"' \
                /etc/bind/named.conf /etc/bind/named.conf.local 2>/dev/null \
            | sed -E 's/.*"([^"]+)".*/\1/' \
            | grep -vE '^(\.|localhost|127\.in-addr\.arpa|0\.in-addr\.arpa|255\.in-addr\.arpa)$' \
            | sort -u)
    if [ -z "$zones" ]; then
        echo "No custom zones are declared in /etc/bind/named.conf.local."
        echo "A zone FILE on its own is not enough: named only serves a zone that"
        echo "is also declared there with a zone { ... } block."
        return
    fi
    for z in $zones; do
        soa=$(dig @127.0.0.1 +short +time=2 +tries=1 SOA "$z" 2>/dev/null)
        if [ -n "$soa" ]; then
            echo "  OK       $z  is loaded and answering"
            found=$((found + 1))
        else
            echo "  NOT LOADED  $z  is declared but not answering"
            zone_reason "$z" && explained=$((explained + 1))
        fi
    done
    if [ "$found" -eq 0 ] && [ "$explained" -eq 0 ]; then
        echo
        echo "Nothing is answering.  Check, in this order:"
        echo "  1. lab-dns log            what named complained about at startup"
        echo "  2. lab-dns checkzone ZONE FILE   is the zone file itself valid"
        echo "  3. is the file path in named.conf.local the real path"
    fi
}

running() { pgrep -x named >/dev/null 2>&1; }

case "${1:-}" in
    start)
        if running; then echo "named is already running."; exit 0; fi
        mkdir -p /run/named && chown bind:bind /run/named
        : > "$LOG"
        # Start each run with an empty named log so "lab-dns log" shows this
        # start and not a previous one.  It has to stay writable by the bind
        # account named drops to, or named refuses to start at all.
        mkdir -p "$(dirname "$NAMEDLOG")"
        : > "$NAMEDLOG" && chown bind:bind "$NAMEDLOG"
        # -u bind drops privileges, matching how it runs on a real server.
        # Capture startup output: without syslog in a container it is otherwise
        # thrown away, and zone errors are exactly what a student needs to see.
        if named -u bind -c "$CONF" 2>>"$LOG"; then
            sleep 1
            if running; then
                echo "named started."
                # A zone that fails to load does NOT stop named, so say so plainly
                # rather than letting every lookup silently return nothing.
                echo "zones:"
                zone_report
            else
                echo "named failed to start.  Run 'lab-dns check' and look for a typo."
                [ -s "$LOG" ] && { echo "--- named said ---"; cat "$LOG"; }
                exit 1
            fi
        else
            echo "named failed to start.  Run 'lab-dns check'."
            [ -s "$LOG" ] && { echo "--- named said ---"; cat "$LOG"; }
            exit 1
        fi
        ;;
    zones)
        running || { echo "named is STOPPED.  Start it first: lab-dns start"; exit 1; }
        zone_report
        ;;
    template)
        # Pasting a multi-line block into a terminal editor over a browser
        # session mangles it into one line, which produces a broken zone and a
        # very confusing debugging session.  Write the starter file directly
        # instead; the student still reads and edits it, which is the point.
        ZF=/etc/bind/db.lab.local
        if [ -e "$ZF" ]; then
            echo "$ZF already exists; not overwriting."
            echo "Delete it first if you want a fresh copy:  sudo rm $ZF"
        else
            cat > "$ZF" <<'ZONE'
$TTL 3600
@   IN  SOA ns1.lab.local. admin.lab.local. (
            2026072101  ; serial
            3600        ; refresh
            600         ; retry
            604800      ; expire
            86400 )     ; negative TTL
@       IN  NS      ns1.lab.local.
ns1     IN  A       10.10.10.10
www     IN  A       10.10.10.20
mail    IN  A       10.10.10.30
@       IN  MX  10  mail.lab.local.
docs    IN  CNAME   www.lab.local.
ZONE
            echo "wrote $ZF"
        fi
        if grep -q '"lab.local"' /etc/bind/named.conf.local 2>/dev/null; then
            echo "lab.local is already declared in named.conf.local."
        else
            cat >> /etc/bind/named.conf.local <<'DECL'

zone "lab.local" {
    type master;
    file "/etc/bind/db.lab.local";
};
DECL
            echo "declared lab.local in /etc/bind/named.conf.local"
        fi
        echo
        echo "Now read both files so you know what you have:"
        echo "  cat $ZF"
        echo "  cat /etc/bind/named.conf.local"
        echo "Then:  lab-dns restart"
        ;;
    log)
        shown=0
        if [ -s "$LOG" ]; then
            echo "--- startup errors ---"; cat "$LOG"; shown=1
        fi
        if [ -s "$NAMEDLOG" ]; then
            echo "--- named log ---"; cat "$NAMEDLOG"; shown=1
        fi
        if [ "$shown" -eq 0 ]; then
            echo "(named has logged nothing; is it running?  lab-dns status)"
        fi
        ;;
    stop)
        running || { echo "named is not running."; exit 0; }
        pkill -x named && sleep 1
        echo "named stopped."
        ;;
    restart)
        "$0" stop >/dev/null 2>&1
        sleep 1
        "$0" start
        ;;
    status)
        if running; then
            echo "named is RUNNING (pid $(pgrep -x named | head -1))"
            # named opens one socket per CPU thread, so a raw ss listing repeats
            # every address once per core.  Show each listening address once.
            echo "listening on:"
            { ss -lnu 2>/dev/null | awk '$5 ~ /:53$/ {print "  udp  " $5}'
              ss -lnt 2>/dev/null | awk '$4 ~ /:53$/ {print "  tcp  " $4}'
            } | sort -u
        else
            echo "named is STOPPED"
        fi
        ;;
    check)
        named-checkconf "$CONF" && echo "named.conf syntax is OK."
        ;;
    checkzone)
        [ $# -eq 3 ] || { usage; exit 1; }
        named-checkzone "$2" "$3"
        ;;
    *)
        usage; exit 1
        ;;
esac
