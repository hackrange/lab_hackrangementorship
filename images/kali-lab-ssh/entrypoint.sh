#!/bin/bash
# Set the student password from the broker-supplied env, then start the lab.
#
# Two ways to run, picked at start:
#  - Under the Sysbox runtime the cgroup file system is writable, so real
#    systemd boots as PID 1 and ssh, cron, atd, journald, and rsyslog run as
#    services.  systemctl and journalctl -u work just as on an installed Kali.
#  - Under plain runc it is read-only and systemd cannot start, so tini runs
#    as PID 1 and this script starts the same daemons by hand.
# Author: Tim Rice
set -e

# A fresh container has no history, so give it the rotated logs a machine that
# has been up a few days would have (syslog.1, syslog.2.gz, syslog.3.gz) for
# the lessons that page, grep, and zgrep through older logs.
seed_day() {
    local day host
    day=$(date -u -d "$1 days ago" +%F)
    host=$(hostname)
    printf '%s\n' \
        "${day}T06:25:01.114201+00:00 ${host} CRON[2211]: (root) CMD (test -x /usr/sbin/anacron || cd / && run-parts --report /etc/cron.daily)" \
        "${day}T07:12:44.502918+00:00 ${host} sshd-session[3120]: Accepted password for student from 10.10.0.15 port 51522 ssh2" \
        "${day}T07:30:02.881310+00:00 ${host} backup.sh[3344]: starting nightly copy of /home/student to /srv/backup" \
        "${day}T07:30:09.004117+00:00 ${host} backup.sh[3344]: error: /srv/backup is not mounted, skipping copy" \
        "${day}T09:41:17.230045+00:00 ${host} sudo[4012]: student : TTY=pts/0 ; PWD=/home/student ; USER=root ; COMMAND=/usr/bin/apt update" \
        "${day}T11:03:55.671402+00:00 ${host} webapp[4501]: warning: response time 2140ms for GET /reports" \
        "${day}T13:18:30.117752+00:00 ${host} webapp[4501]: error: database connection refused (127.0.0.1:5432)" \
        "${day}T13:18:35.120004+00:00 ${host} webapp[4501]: database connection restored" \
        "${day}T17:25:01.300561+00:00 ${host} CRON[5120]: (student) CMD (/home/student/report.sh)" \
        "${day}T22:47:12.904418+00:00 ${host} sshd-session[6230]: Failed password for invalid user admin from 10.10.0.99 port 40112 ssh2"
}

if [ "$1" != "--runc" ]; then
    if [ -n "${LAB_PASSWORD}" ]; then
        echo "student:${LAB_PASSWORD}" | chpasswd
    else
        # No password supplied means the account stays locked (no login).  The
        # broker always supplies one; this is just a safe default.
        passwd -l student >/dev/null 2>&1 || true
    fi

    # Create the live logs up front.  rsyslog would create them as root:adm
    # itself, but under Sysbox its chown fails, leaving them root-only and
    # unreadable to the student, who is in adm as on a real Kali install.
    for f in /var/log/syslog /var/log/auth.log; do
        [ -e "$f" ] || install -m 640 -o root -g adm /dev/null "$f"
    done

    if [ ! -e /var/log/syslog.1 ]; then
        seed_day 1 > /var/log/syslog.1
        seed_day 2 | gzip > /var/log/syslog.2.gz
        seed_day 3 | gzip > /var/log/syslog.3.gz
        chown root:adm /var/log/syslog.1 /var/log/syslog.2.gz /var/log/syslog.3.gz
        chmod 640 /var/log/syslog.1 /var/log/syslog.2.gz /var/log/syslog.3.gz
    fi

    # The password is in this environment.  systemd does not hand its own
    # environment to the services it starts, and the runc branch drops it
    # here, so no student process can read it back.
    unset LAB_PASSWORD
    if mkdir /sys/fs/cgroup/lab-probe 2>/dev/null; then
        rmdir /sys/fs/cgroup/lab-probe
        exec /usr/lib/systemd/systemd
    fi
    exec /usr/bin/tini -- "$0" --runc
fi

# runc: no systemd, so start by hand what its units would have started.

# The scheduling daemons, for the cron/at lessons.
[ -x /usr/sbin/cron ] && /usr/sbin/cron || true
[ -x /usr/sbin/atd ] && /usr/sbin/atd || true

# Logging, for the log lessons.  journald runs standalone (it creates its own
# sockets when systemd does not hand them over), /dev/log points at it so
# syslog() callers such as sshd, sudo, and logger reach the journal, and
# rsyslog copies the journal into /var/log/syslog and /var/log/auth.log.
mkdir -p /run/systemd/journal
# Without systemd-tmpfiles nothing hands the journal to the systemd-journal
# group, so do what its tmpfiles rule does, or the student cannot read it.
mkdir -p /run/log/journal
chown root:systemd-journal /run/log/journal
chmod 2755 /run/log/journal
/usr/lib/systemd/systemd-journald >/dev/null 2>&1 &
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -S /run/systemd/journal/dev-log ] && break
    sleep 0.2
done
ln -sf /run/systemd/journal/dev-log /dev/log
[ -x /usr/sbin/rsyslogd ] && /usr/sbin/rsyslogd || true
/usr/local/bin/lab-seed-journal || true

mkdir -p /run/sshd
exec /usr/sbin/sshd -D
