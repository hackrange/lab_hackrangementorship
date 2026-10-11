#!/bin/bash
# startup script baked into web-01 (readable by anything on the instance, and
# by anything that can reach the metadata service)
apt-get update -y
export DB_HOST=nimbuspay-db.internal
export DB_USER=appuser
export DB_PASSWORD='Sup3r-Pr0d-DB-Pw!'                       # FLAG-hardcoded-secret-in-user-data
export AWS_ACCESS_KEY_ID=AKIA5NIMBUSPAY0WEB01
export AWS_SECRET_ACCESS_KEY='wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
systemctl start nimbuspay-web
