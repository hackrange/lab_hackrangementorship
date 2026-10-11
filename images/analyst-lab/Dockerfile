# Analyst desktop: the audit-evidence challenge box.
#
# The "Provide Auditors with Data" challenge asks a student to reconcile six
# exports (CMDB, AD, SCCM, Qualys, CrowdStrike, identity) and prove which
# machines lack antivirus, vulnerability scanning, disk encryption, or an AD
# object.  There are two supported ways to do it, spreadsheet or shell, so this
# box carries LibreOffice Calc and a terminal, matching the two walkthrough
# videos.
#
# Deliberately plain Debian, not Kali.  This is an office task, the student is
# wearing an auditor's hat rather than an attacker's, and the Kali desktop image
# is 28.5GB for a job that needs a spreadsheet.  Plain Debian also avoids the
# gdk-pixbuf "glycin" sandbox problem that made the Kali desktop so painful:
# Debian 12 predates it, so icons and menus simply work.
#
# linuxserver/libreoffice was considered.  It is a good image, but it serves a
# KasmVNC WEB desktop on ports 3000/3001 with no RFB port, so Guacamole cannot
# connect to it without building a new HTTP lab type.  This image speaks RDP on
# 3389 like every other lab here, so it needs no platform changes at all.
#
# The CSVs are baked in rather than fetched at runtime, so the challenge can
# never break again because a web host stopped serving them.
#
# Author: Tim Rice
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

# A minimal Xfce session plus xrdp, and Calc only.  libreoffice-calc pulls the
# shared core but leaves out Writer, Impress, Draw and Base, which is most of
# the weight.  --no-install-recommends keeps out the artwork, sample documents,
# and language packs.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      xfce4-session xfwm4 xfdesktop4 xfce4-panel xfce4-terminal \
      thunar xfce4-settings dbus-x11 x11-xserver-utils \
      xrdp xorgxrdp xorg \
      libreoffice-calc libreoffice-gtk3 \
      fonts-dejavu fonts-liberation \
      sudo tini ca-certificates locales python3 \
      less nano procps iproute2 coreutils gawk sed grep \
 && sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen \
 && locale-gen \
 && apt-get clean && rm -rf /var/lib/apt/lists/* \
 && useradd -m -s /bin/bash student \
 && usermod -aG sudo student \
 && printf 'student ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/student \
 && chmod 440 /etc/sudoers.d/student \
 # /usr/local/bin is missing from Debian's sudo secure_path, which silently
 # breaks "sudo lab-audit-answers".  Same trap as the netlab image.
 && printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' \
      > /etc/sudoers.d/secure_path \
 && chmod 440 /etc/sudoers.d/secure_path \
 # RDP session wiring: xfce4-session is what xrdp expects.
 && printf 'xfce4-session\n' > /home/student/.xsession \
 && chown student:student /home/student/.xsession \
 && printf '#!/bin/sh\nxfce4-session\n' > /etc/xrdp/startwm.sh \
 && chmod +x /etc/xrdp/startwm.sh \
 && adduser xrdp ssl-cert 2>/dev/null || true \
 && mkdir -p /run/dbus \
 # An analyst desktop must never blank or lock mid-exercise.
 && rm -f /etc/xdg/autostart/xfce4-power-manager.desktop \
          /etc/xdg/autostart/xfce4-screensaver.desktop

# The auditor's data set and the answer key.
COPY audit/*.csv /home/student/audit/
COPY audit-answers.sh /usr/local/bin/lab-audit-answers
COPY audit-answers.py /usr/local/bin/lab-audit-answers.py
COPY shadow-answers.sh /usr/local/bin/lab-shadow-answers
COPY README-audit.txt /home/student/audit/README.txt

RUN chmod +x /usr/local/bin/lab-audit-answers /usr/local/bin/lab-audit-answers.py /usr/local/bin/lab-shadow-answers \
 && mkdir -p /home/student/Desktop \
 # Desktop launchers, so a student who has never used Linux can start without
 # touching a terminal.
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Audit Data (CSV files)' \
      'Comment=The six exports you need for the challenge' \
      'Exec=thunar /home/student/audit' 'Icon=folder' 'Terminal=false' \
      'Categories=Utility;' \
      > /home/student/Desktop/audit-data.desktop \
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=LibreOffice Calc' \
      'Comment=Spreadsheet for the audit challenge' \
      'Exec=localc %U' 'Icon=libreoffice-calc' 'Terminal=false' \
      'Categories=Office;Spreadsheet;' \
      > /home/student/Desktop/libreoffice-calc.desktop \
 && printf '%s\n' \
      '[Desktop Entry]' 'Type=Application' 'Name=Terminal' \
      'Comment=Do it the shell way' 'Exec=xfce4-terminal' 'Icon=utilities-terminal' \
      'Terminal=false' 'Categories=System;' \
      > /home/student/Desktop/terminal.desktop \
 && chmod +x /home/student/Desktop/*.desktop \
 && chown -R student:student /home/student

COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod +x /usr/local/bin/lab-entrypoint

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
