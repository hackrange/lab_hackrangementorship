# Kali desktop + Burp Suite + the vulnerable Internal Tools Portal, in one box.
#
# For the GenAI web-app challenge: the student gets the full Kali GUI (Burp Suite
# Pro is already licensed in the base image) with the deliberately vulnerable
# portal running locally, and internet access. They browse the app in Firefox,
# intercept and test it with Burp, and can reach a hosted DAST tool over the net.
#
# Built FROM kali-lab-gui so it inherits the whole working desktop (the glycin
# shim, the wallpaper, Burp, the licensing) and shares its layers, so the pushed
# delta is small rather than another 28GB.
#
# The portal is served at http://portal.lab:5000 (a real hostname, so Firefox
# routes it through Burp; Firefox never proxies localhost). Its full source lives
# in ~/app for the student to review.
#
# Author: Tim Rice
FROM kali-lab-gui:latest

ENV DEBIAN_FRONTEND=noninteractive

# python3 is already present; add Flask for the portal, plus Node + Claude Code so
# a student can review the target with an AI from the desktop.  No shared key: the
# student runs `claude` and signs in with their own Claude account (the lab has
# internet for the login + the API).
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3-flask nodejs npm \
 && npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 # A tiny wrapper so the desktop launcher needs no fragile nested quoting: open
 # in the app directory, run claude, and keep the terminal open afterwards.
 && printf '%s\n' '#!/bin/bash' 'cd ~/app 2>/dev/null || true' 'claude' 'exec bash' \
      > /usr/local/bin/claude-launch \
 && chmod +x /usr/local/bin/claude-launch
# Do not let the CLI self-update on launch in a throwaway lab.
ENV DISABLE_AUTOUPDATER=1

COPY app.py  /home/student/app/app.py
COPY seed.py /home/student/app/seed.py
COPY portal-wrap.sh /usr/local/bin/portal-wrap

RUN chmod +x /usr/local/bin/portal-wrap \
 && chown -R student:student /home/student/app \
 # A desktop launcher and a note so the student knows where the target is.
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Open the Portal (target)' \
      'Comment=The vulnerable app to test, at http://portal.lab:5000' \
      'Exec=firefox-esr http://portal.lab:5000/' 'Icon=firefox-esr' \
      'Terminal=false' 'Categories=Network;' \
      > /home/student/Desktop/portal.desktop \
 && chmod +x /home/student/Desktop/portal.desktop \
 && chown student:student /home/student/Desktop/portal.desktop \
 # DAST tool (nextgen-dast) launcher: the sidecar the broker starts beside this
 # lab, reachable on the private pair network as http://dast:8888 (admin/student).
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Open the DAST tool' \
      'Comment=nextgen-dast scanner at http://dast:8888 (admin / student)' \
      'Exec=firefox-esr http://dast:8888/' 'Icon=firefox-esr' \
      'Terminal=false' 'Categories=Network;' \
      > /home/student/Desktop/dast.desktop \
 && chmod +x /home/student/Desktop/dast.desktop \
 && chown student:student /home/student/Desktop/dast.desktop \
 # Claude Code launcher: opens a terminal running `claude`.  The student signs in
 # with their own Claude account; the terminal stays open afterwards.
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Claude Code (AI)' \
      'Comment=Review the target with an AI; sign in with your own Claude account' \
      'Exec=xfce4-terminal --title=Claude-Code -e claude-launch' \
      'Icon=utilities-terminal' 'Terminal=false' 'Categories=Development;' \
      > /home/student/Desktop/claude.desktop \
 && chmod +x /home/student/Desktop/claude.desktop \
 && chown student:student /home/student/Desktop/claude.desktop \
 && printf '%s\n' \
      'TARGET: the Internal Tools Portal is at  http://portal.lab:5000' \
      'Its source is in ~/app/app.py.' '' \
      'Burp Suite is installed and licensed. Set Firefox to proxy through Burp' \
      '(127.0.0.1:8080), browse the portal, and intercept the traffic.' \
      'The portal.lab hostname (not localhost) is what makes Burp see it.' '' \
      'DAST: the nextgen-dast scanner is at  http://dast:8888  (admin / student).' \
      'Point a scan at  http://target:5000  to scan this portal.' '' \
      'AI: run  claude  (or use the Claude Code desktop icon) and sign in with' \
      'your own Claude account to review the source with an AI.' \
      > /home/student/Desktop/README-portal.txt \
 && chown student:student /home/student/Desktop/README-portal.txt

# Wrap the base entrypoint so the portal starts alongside the desktop.
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/portal-wrap"]
