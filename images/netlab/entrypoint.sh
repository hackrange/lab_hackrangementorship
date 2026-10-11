#!/bin/bash
# Set the student password from the broker-supplied env, then run sshd.
# named is deliberately NOT started here: launching their own DNS server is part
# of the lesson, and they use "lab-dns start" to do it.
# Author: Tim Rice
set -e

if [ -n "${LAB_PASSWORD}" ]; then
    echo "student:${LAB_PASSWORD}" | chpasswd
else
    # No password supplied means the account stays locked.  The broker always
    # supplies one; this is just a safe default.
    passwd -l student >/dev/null 2>&1 || true
fi

exec /usr/sbin/sshd -D -e
