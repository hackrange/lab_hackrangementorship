# Splunk investigation lab: "Operation Quiet Vendor".
#
# A blue-team lab. The student gets a desktop with Firefox and a local Splunk
# instance preloaded with synthetic telemetry for a single intrusion, told
# across nine log sources, and reconstructs what happened.
#
# Delivery is RDP, exactly like analyst-lab, so it needs no platform changes:
# Guacamole connects to xrdp, the student opens Firefox to the local Splunk.
# A web reverse-proxy lab type was considered and rejected as a large platform
# change for one lab; the desktop path reuses everything that already works.
#
# The telemetry is generated and INGESTED at build time, so the Splunk index is
# baked into the image layers and the lab is searchable the moment Splunk starts.
# Volumes are tiny (about half a megabyte) so Splunk Free's 500MB/day limit is
# never a factor. Splunk is switched to the Free license, which removes the login
# and the trial clock, so a student lands straight in the search app.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV SPLUNK_HOME=/opt/splunk
# Pinned Splunk release, fetched from HackRange's own copy first.
#
# Splunk removes old builds from their site, and the URL names an exact version
# AND build hash.  When a build is withdrawn, this image stops building for
# every new student with nothing in this repository having changed, which is a
# miserable thing to debug.  So the mirror is tried first and Splunk's own CDN
# is the fallback, and either way the file is checked against the hash below
# before it is installed, so neither source has to be trusted.
ARG SPLUNK_DEB=splunk-9.3.2-d8bb32809498-linux-2.6-amd64.deb
ARG SPLUNK_URL=https://hackrange.com/downloads/splunk-9.3.2-d8bb32809498-linux-2.6-amd64.deb
ARG SPLUNK_URL_FALLBACK=https://download.splunk.com/products/splunk/releases/9.3.2/linux/splunk-9.3.2-d8bb32809498-linux-2.6-amd64.deb
ARG SPLUNK_SHA256=37ed62ff0e93b94fd79f5ac624c82525a0e097fa7af4194083dc584bf8e983c3

# Desktop + browser, matching analyst-lab. python3 is used only at build time to
# generate the telemetry.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xfce4-session xfwm4 xfdesktop4 xfce4-panel xfce4-terminal \
      thunar xfce4-settings dbus-x11 x11-xserver-utils \
      xrdp xorgxrdp xorg firefox-esr \
      sudo tini ca-certificates locales curl python3 procps \
      less nano iproute2 coreutils gawk sed grep net-tools \
      openssh-server \
 && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash student \
 && usermod -aG sudo student \
 && printf 'student ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/student \
 && chmod 440 /etc/sudoers.d/student \
 && printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' \
      > /etc/sudoers.d/secure_path \
 && chmod 440 /etc/sudoers.d/secure_path \
 && printf 'xfce4-session\n' > /home/student/.xsession \
 && chown student:student /home/student/.xsession \
 && printf '#!/bin/sh\nxfce4-session\n' > /etc/xrdp/startwm.sh \
 && chmod +x /etc/xrdp/startwm.sh \
 && adduser xrdp ssl-cert 2>/dev/null || true \
 # sshd, so this desktop lab answers a terminal as well.
 #
 # Every lab publishes the SSH door on 2223, and the student is told SSH is one
 # of the three ways in.  This image had no sshd at all, so nginx accepted the
 # connection, found nothing behind it and closed it again: "Connection closed
 # by <host> port 2223", on a lab the student had just been told to reach that
 # way.  It also gives them scp, which is how work leaves a disposable lab.
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && mkdir -p /run/sshd \
 && mkdir -p /run/dbus \
 && rm -f /etc/xdg/autostart/xfce4-power-manager.desktop \
          /etc/xdg/autostart/xfce4-screensaver.desktop

# Install Splunk from the pinned .deb, run it as a dedicated splunk user.
RUN useradd -m -r -d "$SPLUNK_HOME" splunk 2>/dev/null || true \
 && { curl -fsSL --retry 3 -o /tmp/splunk.deb "$SPLUNK_URL" \
      || curl -fsSL --retry 3 -o /tmp/splunk.deb "$SPLUNK_URL_FALLBACK"; } \
 && echo "$SPLUNK_SHA256  /tmp/splunk.deb" | sha256sum -c - \
 && dpkg -i /tmp/splunk.deb \
 && rm -f /tmp/splunk.deb \
 && chown -R splunk:splunk "$SPLUNK_HOME"

# Generate the telemetry, then ingest it into per-source indexes at build time.
COPY gen_telemetry.py /opt/gen_telemetry.py
COPY inputs.conf "$SPLUNK_HOME/etc/system/local/inputs.conf"
COPY props.conf  "$SPLUNK_HOME/etc/system/local/props.conf"
RUN mkdir -p /opt/quietvendor/data \
 && python3 /opt/gen_telemetry.py --out /opt/quietvendor/data \
 && chown -R splunk:splunk /opt/quietvendor "$SPLUNK_HOME/etc/system/local" \
 # First start: accept the license, set a throwaway admin password, let the
 # monitored inputs index the data, then stop cleanly so the index is baked.
 && su splunk -c "$SPLUNK_HOME/bin/splunk start --accept-license --answer-yes --no-prompt --seed-passwd Changeme123" \
 && sleep 25 \
 && su splunk -c "$SPLUNK_HOME/bin/splunk stop" \
 # Licensing: Splunk auto-provisions a download-trial license on first start.
 # Its expiry is RELATIVE (60 days from THIS container's start), and lab
 # containers are ephemeral, so every fresh lab gets a clean 60-day window and
 # the trial never expires in a session. Its 500MB/day quota matches Free and is
 # never approached (~0.5MB of data). Modern Splunk requires a login regardless
 # of license, so the credentials are shown prominently on the desktop instead.
 # Boot-start so the entrypoint just launches it.
 && "$SPLUNK_HOME/bin/splunk" enable boot-start -user splunk --accept-license --answer-yes --no-prompt 2>/dev/null || true

# Firefox opens on the Splunk search app; a desktop launcher too.
RUN mkdir -p /home/student/.mozilla/firefox/lab.default /home/student/Desktop \
 && printf '%s\n' \
      '[Profile0]' 'Name=lab' 'IsRelative=1' 'Path=lab.default' 'Default=1' \
      '[General]' 'StartWithLastProfile=1' \
      > /home/student/.mozilla/firefox/profiles.ini \
 && printf 'user_pref("browser.startup.homepage", "http://localhost:8000/en-US/app/search/search");\n' \
      > /home/student/.mozilla/firefox/lab.default/user.js \
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Splunk  (log in: admin / Changeme123)' \
      'Comment=The SIEM with the incident data' \
      'Exec=firefox-esr http://localhost:8000/en-US/app/search/search' \
      'Icon=firefox-esr' 'Terminal=false' 'Categories=Network;' \
      > /home/student/Desktop/splunk.desktop \
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Terminal' \
      'Exec=xfce4-terminal' 'Icon=utilities-terminal' 'Terminal=false' 'Categories=System;' \
      > /home/student/Desktop/terminal.desktop \
 && printf '%s\n' \
      'SPLUNK LOGIN' '============' '' \
      'Open the Splunk icon (Firefox is already pointed at it).' \
      'When it asks you to sign in:' '' \
      '    Username:  admin' \
      '    Password:  Changeme123' '' \
      'Then set the time range to "All time" and start hunting.' \
      > /home/student/Desktop/READ-ME-Splunk-login.txt \
 && chmod +x /home/student/Desktop/*.desktop \
 && chown -R student:student /home/student

COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod +x /usr/local/bin/lab-entrypoint

# Splunk rejects overlayfs for its index db ("unusable filesystem"), so put
# /opt/splunk/var on a volume: Docker backs it with a real filesystem (ext4),
# which validatedb accepts. An anonymous volume is copied from the baked image
# content on first start, so the pre-indexed data comes along and the lab is
# searchable immediately. AutoRemove cleans the anonymous volume with the lab.
VOLUME /opt/splunk/var

# The image ships no editor but nano, so install vim, and fix the two ways a
# lab terminal editor misbehaves.
#
# Text pasted from the browser arrives as raw LF characters.  nano reads LF as
# ^J, which it binds to "Justify", so a pasted block of code lands reflowed into
# one run-on line with its newlines replaced by single spaces.  Appended,
# because nano's "include" directive is only for syntax files.
RUN apt-get update \
 && apt-get install -y --no-install-recommends vim \
 && rm -rf /var/lib/apt/lists/* \
 # Point "vi" at full vim rather than vim-tiny, which runs in "compatible"
 # mode where backspace refuses to cross the start of the insert, the line, or
 # an autoindent.  vim-runtime's 11MB of interface translations go: the courses
 # are US English only.
 && update-alternatives --set vi /usr/bin/vim.basic \
 && rm -rf /usr/share/vim/vim*/lang \
 && printf '%s\n' \
      '" Sane vim defaults for the browser-based lab terminal, sourced by' \
      '" /etc/vim/vimrc so they apply to vi and vim alike.' \
      '"' \
      '" Own the configuration outright rather than inheriting defaults.vim,' \
      '" which loads after this file and would re-enable mouse reporting,' \
      '" costing the browser terminal its click-and-drag text selection.' \
      'let g:skip_defaults_vim = 1' \
      'set nocompatible' \
      'set backspace=indent,eol,start' \
      'syntax on' \
      'filetype plugin indent on' \
      'set ruler' \
      'set showcmd' \
      'set incsearch' \
      'set hlsearch' \
      'set wildmenu' \
      'set scrolloff=3' \
      'set history=200' \
      'set display=truncate' \
      'set mouse=' \
      'set ttimeout' \
      'set ttimeoutlen=100' \
      '" Python indentation is syntax, so a stray tab is a bug, not a style nit.' \
      'autocmd FileType python setlocal expandtab tabstop=4 shiftwidth=4 softtabstop=4' \
    > /etc/vim/vimrc.local \
 && printf '%s\n' \
      '' \
      '## Lab terminal defaults.' \
      '## A paste from the browser arrives as LF, which nano reads as ^J and' \
      '## binds to Justify, reflowing pasted code into one run-on line.' \
      'bind ^J enter main' \
      '## Code is not prose: never hard-wrap what is typed or pasted.' \
      'unset breaklonglines' \
      '## Four spaces per tab, written as spaces, which is what Python expects.' \
      '## Auto-indent stays off: with it on, pasting indented code compounds' \
      '## the indentation line by line.' \
      'set tabsize 4' \
      'set tabstospaces' \
      'unset autoindent' \
    >> /etc/nanorc

EXPOSE 3389
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/lab-entrypoint"]
