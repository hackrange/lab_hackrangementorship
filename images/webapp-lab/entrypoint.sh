#!/bin/bash
# Seed the DB, start the vulnerable app on localhost:5000, set the student's
# password, run sshd. Author: Tim Rice
set -e
[ -n "${LAB_PASSWORD}" ] && echo "student:${LAB_PASSWORD}" | chpasswd || passwd -l student >/dev/null 2>&1 || true
python3 /home/student/app/seed.py >/dev/null 2>&1 || true
chown -R student:student /home/student/app
# app in the background as the student user
su student -c 'cd /home/student/app && nohup python3 app.py >/home/student/app/server.log 2>&1 &'
exec /usr/sbin/sshd -D -e
