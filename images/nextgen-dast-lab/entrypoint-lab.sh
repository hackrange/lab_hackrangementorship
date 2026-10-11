#!/bin/bash
# Bring up a self-contained nextgen-dast: local MariaDB, then the app.
#
#   1. init the datadir (ephemeral; fresh every launch)
#   2. start mariadbd on 127.0.0.1:3306
#   3. create the pentest DB + user
#   4. reset.py applies the schema and seeds the admin/student login
#   5. exec uvicorn on 0.0.0.0:8888 so the Kali box reaches it as http://dast:8888
#
# Author: Tim Rice
set -e

DATADIR=/var/lib/mysql

# 1. Initialise the datadir if this is a fresh container.
if [ ! -d "$DATADIR/mysql" ]; then
  mkdir -p "$DATADIR"
  chown -R mysql:mysql "$DATADIR"
  mariadb-install-db --user=mysql --datadir="$DATADIR" \
      --auth-root-authentication-method=normal --skip-test-db >/dev/null 2>&1
fi
mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

# 2. Start the database in the background.
mariadbd --user=mysql --datadir="$DATADIR" \
         --bind-address=127.0.0.1 --port=3306 \
         >/var/log/mariadb-lab.log 2>&1 &

# Wait for the socket to answer before touching it.
for _ in $(seq 1 120); do
  mariadb-admin --protocol=socket ping >/dev/null 2>&1 && break
  sleep 0.5
done

# 3. Database + application user (idempotent).
mariadb --protocol=socket <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL

# 4. Schema + admin/student seed. reset.py reads DB_* and ADMIN_* from the env.
mkdir -p /data
python /app/scripts/reset.py || echo "[lab] reset.py returned nonzero; continuing"

# reset.py only sets the legacy is_admin flag; the app authorizes on `role`,
# which defaults to 'readonly'. Grant the lab admin full rights so a student can
# actually launch scans, not just browse.
mariadb --protocol=socket "${DB_NAME}" \
  -e "UPDATE users SET role='superadmin' WHERE username='${ADMIN_USERNAME}';" \
  || echo "[lab] could not set admin role; continuing"

# 5. Hand off to the app, listening on every interface so the pair network sees it.
cd /app
exec python -m uvicorn server:app --host 0.0.0.0 --port 8888
