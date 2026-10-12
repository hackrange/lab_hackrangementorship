# Lean Kali SSH lab image for disposable, browser-based command practice.
# Guacamole (guacd) connects to this over SSH and gives the student a terminal.
# The broker sets a random password for the "student" user at launch via
# LAB_PASSWORD, so no credential is baked into the image.
#
# Three layers on purpose: the base, the entrypoint, and one RUN that does all
# the rest. Every extra RUN or COPY is another layer carried on disk on every
# lab node, so config files are written here rather than copied in.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive
COPY entrypoint.sh /usr/local/bin/lab-entrypoint

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server openssh-client sshpass ca-certificates tini sudo \
      less nano vim procps iproute2 iputils-ping \
      coreutils util-linux file binutils bash-completion man-db \
      dnsutils curl wget whois netcat-traditional \
      rsync tar gzip bzip2 xz-utils zstd zip unzip \
      cron at \
      python3 python3-pip python3-venv python-is-python3 python3-requests \
      fdisk parted gdisk e2fsprogs xfsprogs dosfstools lvm2 \
      xxd info psmisc htop tree acl plocate tealdeer rsyslog dbus \
 && rm -rf /var/lib/apt/lists/* \
 && chmod +x /usr/local/bin/lab-entrypoint \
 && mkdir -p /run/sshd \
 && useradd -m -s /bin/bash student \
 # The lab user has sudo (the learner is auto-connected and does not know the
 # random password, so it is passwordless here). Real Kali prompts for it.
 && usermod -aG sudo student \
 && printf 'student ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/student \
 && chmod 440 /etc/sudoers.d/student \
 # Logging for the log lessons.  There is no systemd, so the entrypoint starts
 # journald on its own and rsyslog reads the journal into the classic text
 # files (/var/log/syslog, /var/log/auth.log), which is the Kali layout.  adm
 # and systemd-journal let the student read both without sudo, as on a real
 # Kali install.
 && usermod -aG adm,systemd-journal student \
 && printf '%s\n' \
      'module(load="imjournal" StateFile="imjournal.state")' \
      'global(workDirectory="/var/spool/rsyslog" compatibility.defaults.secure="strict")' \
      '$FileOwner root' \
      '$FileGroup adm' \
      '$FileCreateMode 0640' \
      '*.*;auth,authpriv.none -/var/log/syslog' \
      'auth,authpriv.*        /var/log/auth.log' \
    > /etc/rsyslog.conf \
 && mkdir -p /var/spool/rsyslog \
 # tldr (tealdeer) fetches its pages from GitHub, which the lab cannot reach,
 # so the student's page cache is downloaded here at build time.
 && su student -c 'tldr --update' \
 # Real systemd, when the broker runs this image under Sysbox (see the
 # entrypoint).  Enable the services the runc branch starts by hand.  journald
 # must not read /dev/kmsg: Sysbox's cannot be polled and journald exits on
 # it.  The kernel file system mounts cannot happen in a container, so mask
 # them rather than boot "degraded".  tmp.mount is masked so /tmp stays on
 # disk, as it does under runc.
 && systemctl enable ssh cron atd rsyslog \
 && systemctl mask sys-kernel-config.mount sys-kernel-debug.mount sys-kernel-tracing.mount tmp.mount \
 # A few of today's events, logged at boot (by the unit below under systemd,
 # by the entrypoint under runc), so the live log and the journal already hold
 # errors and warnings for the log lessons' grep and -p err commands to find.
 && printf '%s\n' \
      '#!/bin/sh' \
      '# Log some of today'"'"'s events for the log lessons to search.' \
      'logger -t backup.sh -p user.notice "starting nightly copy of /home/student to /srv/backup"' \
      'logger -t backup.sh -p user.err "error: /srv/backup is not mounted, skipping copy"' \
      'logger -t webapp -p user.warning "warning: response time 2140ms for GET /reports"' \
      'logger -t webapp -p user.err "error: database connection refused (127.0.0.1:5432)"' \
      'logger -t webapp -p user.notice "database connection restored"' \
    > /usr/local/bin/lab-seed-journal \
 && chmod 755 /usr/local/bin/lab-seed-journal \
 && printf '%s\n' \
      '[Unit]' \
      'Description=Log sample events for the log lessons' \
      'After=rsyslog.service systemd-journald.service' \
      '[Service]' \
      'Type=oneshot' \
      'ExecStart=/usr/local/bin/lab-seed-journal' \
      '[Install]' \
      'WantedBy=multi-user.target' \
    > /etc/systemd/system/lab-seed-journal.service \
 && systemctl enable lab-seed-journal \
 && mkdir -p /etc/systemd/journald.conf.d \
 && printf '[Journal]\nReadKMsg=no\n' > /etc/systemd/journald.conf.d/lab.conf \
 # sshd: no root login, password auth on (the broker sets a random one).
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 # systemd's OSC-context shell integration emits terminal escape sequences
 # (machineid/bootid/type=command markers) that Guacamole's terminal does not
 # interpret, so they print as garbage. Remove them for a clean shell.
 && rm -f /etc/profile.d/80-systemd-osc-context.sh /etc/profile.d/70-systemd-shell-extra.sh \
 # Give the SSH login session a UTF-8 locale so the Kali prompt's box-drawing
 # characters render instead of showing as garbage. The Docker ENV LANG only
 # covers container processes, not the PAM login shell sshd spawns.
 && printf 'LANG=C.UTF-8\n' > /etc/default/locale \
 && (grep -q '^LANG=' /etc/environment 2>/dev/null || echo 'LANG=C.UTF-8' >> /etc/environment) \
 # Make "vi" the full vim. Left alone, vi is vim-tiny in "compatible" mode,
 # where 'backspace' is empty and backspace refuses to cross the start of the
 # insert, the line, or an autoindent, which reads as a broken editor. The sed
 # is belt and braces for anyone who runs vim.tiny by name.
 && update-alternatives --set vi /usr/bin/vim.basic \
 # vim-runtime ships 11MB of interface translations. The courses are US
 # English only, so they are dead weight on every lab node.
 && rm -rf /usr/share/vim/vim*/lang \
 && { [ ! -f /etc/vim/vimrc.tiny ] || sed -i 's/^set compatible/set nocompatible\nset backspace=indent,eol,start/' /etc/vim/vimrc.tiny; } \
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
      '" A short key-code timeout keeps arrow keys responsive over a remote' \
      '" terminal without swallowing a bare Escape.' \
      'set ttimeout' \
      'set ttimeoutlen=100' \
      '" Python indentation is syntax, so a stray tab is a bug, not a style nit.' \
      'autocmd FileType python setlocal expandtab tabstop=4 shiftwidth=4 softtabstop=4' \
    > /etc/vim/vimrc.local \
 # Text pasted from the browser arrives as raw LF characters. nano reads LF as
 # ^J, and ^J is bound by default to "Justify", which reflows the paragraph and
 # replaces its line breaks with single spaces, so a pasted block of code lands
 # as one run-on line. Binding ^J to Enter makes a pasted newline a newline.
 # Appended, because nano's "include" directive is only for syntax files.
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
    >> /etc/nanorc \
 && printf 'Welcome to your Kali practice lab.\nThis machine is temporary.  Anything you do here is wiped when the session ends.\n\n' > /etc/motd

# The broker runs images with this label under Sysbox on nodes that have it.
LABEL lab.init="systemd"
# systemd's clean-shutdown signal.  Under runc, tini forwards it to sshd, which
# exits on it just as it would on SIGTERM.
STOPSIGNAL SIGRTMIN+3
EXPOSE 22
# The entrypoint is PID 1 and execs either systemd or tini, so both stay PID 1.
ENTRYPOINT ["/usr/local/bin/lab-entrypoint"]
