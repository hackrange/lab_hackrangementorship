# Self-contained nextgen-dast for the GenAI web-app challenge (lesson 334).
#
# The shared central nextgen-dast can't reach a portal that lives inside a
# student's ephemeral Kali container, and it would leak every student's scans
# into one instance. So each web-app lab gets its OWN nextgen-dast as a sidecar:
# this image bundles the app AND a local MariaDB, seeds a fixed admin/student
# login, and serves the UI on 0.0.0.0:8888. The broker launches it beside the
# Kali container on a private per-lab network (alias "dast"); it scans the portal
# at http://target:5000. Nothing here is reachable from outside the lab pair.
#
# Everything is ephemeral and deliberately weakly-credentialed on purpose: it is
# a disposable teaching instance, never a real deployment.
#
# Author: Tim Rice
FROM nextgen-dast:2.1.1

ENV DEBIAN_FRONTEND=noninteractive

# A local database so the sidecar is fully self-contained (no external DB).
RUN apt-get update \
 && apt-get install -y --no-install-recommends mariadb-server mariadb-client \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY entrypoint-lab.sh /usr/local/bin/entrypoint-lab
RUN chmod +x /usr/local/bin/entrypoint-lab \
 # The app sets its session cookie Secure, which is correct for a real HTTPS
 # deployment but fatal here: the lab serves the UI over plain http://dast:8888
 # on an isolated single-user network, and a browser silently refuses to store a
 # Secure cookie over HTTP, so the session never persists and login "fails".
 # Drop Secure for the lab so admin/student actually logs in.
 && sed -i 's/httponly=True, secure=True, samesite="strict",/httponly=True, secure=False, samesite="strict",/' /app/server.py \
 && grep -q 'secure=False, samesite="strict"' /app/server.py

# Fixed, disposable settings. The DB password never leaves the container; the
# admin login is the well-known lab credential students are told to use.
ENV DB_HOST=127.0.0.1 \
    DB_PORT=3306 \
    DB_USER=pentest \
    DB_PASSWORD=pentest \
    DB_NAME=pentest \
    ADMIN_USERNAME=admin \
    ADMIN_PASSWORD=student \
    APP_URL=http://dast:8888/ \
    APP_SECRET=lab-only-ephemeral-secret-not-a-real-deployment-0123456789 \
    SECRETS_FILE=/data/.secrets_lab

EXPOSE 8888
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint-lab"]
