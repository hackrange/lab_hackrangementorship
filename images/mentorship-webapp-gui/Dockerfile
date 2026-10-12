# The Week 11 challenge desktop: Kali, Burp Suite, Firefox, the vulnerable
# Internal Tools Portal, and an AI, in one box.
#
# The hosted course builds this FROM kali-lab-gui, a 38GB image carrying the
# whole kali-linux-large tool set.  That is right for a hosted lab, where the
# image is built once centrally, and wrong for a student's own machine, where
# it would mean a multi-hour build and a disk requirement past 200GB.  So this
# is the same lesson on a purpose-built desktop: the xfce4 pieces the session
# actually needs, Firefox, Burp, and nothing else.  Roughly 4GB.
#
# xfce4 by hand rather than kali-desktop-xfce for the same reason, with one
# catch learned from the hosted image: kali-defaults is what configures the
# icon and GTK themes, and without it xfce4-panel can come up on an "empty"
# theme and crash, leaving a black desktop with no menu.  So kali-defaults is
# installed explicitly even though the metapackage is not.
#
# The portal is served at http://portal.lab:5000, a real hostname rather than
# localhost, because Firefox refuses to send localhost through a proxy and the
# whole point of the lesson is watching the traffic in Burp.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# One layer: upgrade first (xorgxrdp must match xserver-xorg-core, and a stale
# base has bitten this before), then the desktop, the tools, and Claude Code.
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends \
      sudo wget curl ca-certificates dbus-x11 xinit tini procps iproute2 \
      less vim-tiny nano openssh-server \
      xfce4 xfce4-terminal xfce4-panel xfce4-session xfdesktop4 xfwm4 \
      kali-defaults kali-themes \
      xrdp xorgxrdp xorg \
      firefox-esr burpsuite \
      python3 python3-flask \
      nodejs npm \
      thunar mousepad xdg-utils xclip \
 && npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

# Do not let the CLI self-update on launch in a throwaway lab.
ENV DISABLE_AUTOUPDATER=1

# The student account, the desktop session, and the launchers.  One layer, with
# every config written inline.
RUN useradd -m -s /bin/bash -G sudo student \
 && printf 'student ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/student \
 && chmod 440 /etc/sudoers.d/student \
 && mkdir -p /home/student/Desktop /home/student/app /var/run/sshd \
 # xrdp: Guacamole connects over RDP on the standard 3389.
 #
 # The group membership is spelled out rather than left to the xrdp package's
 # own postinst, which is where it went missing here.  xrdp reads its TLS key
 # as the xrdp user, and Debian grants that by putting xrdp in the ssl-cert
 # group; without it the RDP handshake failed before any password was asked
 # for, guacd reported only "Upstream error", and the lab would not open.
 && usermod -aG ssl-cert xrdp \
 && printf '%s\n' '#!/bin/sh' 'exec startxfce4' > /home/student/.xsession \
 && chmod +x /home/student/.xsession \
 # A desktop terminal must be a LOGIN shell, or the session's own values
 # (LAB_PASSWORD and friends, written to /etc/profile.d at start) are missing
 # and every command a lesson prints silently uses an empty variable.
 && mkdir -p /home/student/.config/xfce4/terminal \
 && printf '%s\n' '[Configuration]' 'CommandLoginShell=TRUE' 'MiscAlwaysShowTabs=FALSE' \
      > /home/student/.config/xfce4/terminal/terminalrc \
 # The portal's hostname is NOT written here.  /etc/hosts cannot be written
 # during a build (the daemon mounts it, and the write fails with exit code 2),
 # and it would be wasted work even if it could: Docker regenerates the file at
 # every container start, so the name is added at run time by portal-wrap.
 # A wrapper so the Claude Code launcher needs no nested quoting.
 && printf '%s\n' '#!/bin/bash' 'cd ~/app 2>/dev/null || true' 'claude' 'exec bash' \
      > /usr/local/bin/claude-launch \
 && chmod +x /usr/local/bin/claude-launch

COPY app.py  /home/student/app/app.py
COPY seed.py /home/student/app/seed.py
COPY portal-wrap.sh /usr/local/bin/portal-wrap
COPY lab-entrypoint.sh /usr/local/bin/lab-entrypoint
COPY desktop-setup.sh /usr/local/bin/lab-desktop-setup

# The launchers.  Every Exec with a multi word argument is QUOTED: the desktop
# spec splits Exec on spaces, so an unquoted --title=Two Words silently breaks
# the launcher and the icon does nothing when a student double clicks it.
RUN chmod +x /usr/local/bin/portal-wrap /usr/local/bin/lab-entrypoint /usr/local/bin/lab-desktop-setup \
 && launcher() { \
      printf '%s\n' '[Desktop Entry]' 'Type=Application' "Name=$2" "Comment=$3" \
        "Exec=$4" "Icon=$5" 'Terminal=false' "Categories=$6" \
        > "/home/student/Desktop/$1.desktop"; \
      chmod +x "/home/student/Desktop/$1.desktop"; \
    } \
 && launcher portal 'Open the Portal (target)' \
      'The vulnerable app to test, at http://portal.lab:5000' \
      'firefox-esr http://portal.lab:5000/' 'firefox-esr' 'Network;' \
 && launcher dast 'Open the DAST tool' \
      'nextgen-dast scanner at http://dast:8888 (admin / student)' \
      'firefox-esr http://dast:8888/' 'firefox-esr' 'Network;' \
 && launcher burp 'Burp Suite' \
      'The web proxy: intercept and replay the portal traffic' \
      'burpsuite' 'burpsuite' 'Network;' \
 && launcher claude 'Claude Code (AI)' \
      'Review the target with an AI; sign in with your own Claude account' \
      'xfce4-terminal "--title=Claude Code" -e claude-launch' \
      'utilities-terminal' 'Development;' \
 && launcher terminal 'Terminal' 'A shell in your lab' \
      'xfce4-terminal' 'utilities-terminal' 'System;' \
 && chown -R student:student /home/student

EXPOSE 3389 22
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/lab-entrypoint"]
