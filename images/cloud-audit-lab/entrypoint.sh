#!/bin/bash
# Set the student's password from the broker, make sure the export is owned by
# the student, and run sshd. Author: Tim Rice
set -e
[ -n "${LAB_PASSWORD}" ] && echo "student:${LAB_PASSWORD}" | chpasswd || passwd -l student >/dev/null 2>&1 || true
chown -R student:student /home/student/account-export
exec /usr/sbin/sshd -D -e
