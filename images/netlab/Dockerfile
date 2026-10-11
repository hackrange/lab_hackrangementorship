# Networking and infrastructure lab box.
#
# Backs the mentorship's networking week (DNS, routing, the Linux firewall) and
# its infrastructure-weakness week (NFS exports, SSH hardening, listening
# services).  The student runs their own BIND9 server, writes real zone files,
# queries them with dig, reads and edits the routing table, builds iptables and
# nftables rulesets, audits NFS exports, and hardens an sshd config.
#
# NFS note: the kernel NFS server cannot run here.  rpc.nfsd needs to mount the
# nfsd filesystem, which requires SYS_ADMIN, and this image is never granted it.
# What DOES work without privilege, and is what an assessor actually does, is
# writing and reading the export table (exportfs) and enumerating exports over
# RPC (showmount).  Mounting a share needs SYS_ADMIN too, so the lessons teach
# the impact of a bad export rather than pretending to mount one.
#
# This image is launched with the broker's 'netlab' capability profile, which
# returns NET_RAW (tcpdump, ping) and NET_ADMIN (iptables, ip route).  The broker
# only allows that profile with net_mode=none, so the box is isolated and a
# student can only ever reconfigure their own container's network namespace.
#
# There is no systemd here, so "systemctl start named" does not work and would
# only confuse a learner.  A lab-dns helper is provided instead, and the lessons
# teach that command.
#
# Author: Tim Rice
FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bind9 bind9-utils bind9-dnsutils \
      nfs-common nfs-kernel-server rpcbind \
      iptables nftables iproute2 iputils-ping traceroute tcpdump \
      openssh-server openssh-client ca-certificates tini sudo \
      less nano vim procps file bash-completion man-db \
      curl wget netcat-traditional socat whois \
      python3 python-is-python3 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd \
 && useradd -m -s /bin/bash student \
 && usermod -aG sudo student \
 && printf 'student ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/student \
 && chmod 440 /etc/sudoers.d/student \
 # Kali's sudoers sets secure_path to "/usr/sbin:/usr/bin:/sbin:/bin", which does
 # NOT include /usr/local/bin, so "sudo lab-dns start" fails with "command not
 # found" even though running it as root works.  Put the local directories back so
 # the lab helpers are reachable either way.
 && printf 'Defaults secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"\n' \
      > /etc/sudoers.d/secure_path \
 && chmod 440 /etc/sudoers.d/secure_path \
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 # systemd's OSC shell integration prints escape-sequence garbage in the
 # Guacamole terminal.
 && rm -f /etc/profile.d/80-systemd-osc-context.sh /etc/profile.d/70-systemd-shell-extra.sh \
 && printf 'LANG=C.UTF-8\n' > /etc/default/locale \
 && (grep -q '^LANG=' /etc/environment 2>/dev/null || echo 'LANG=C.UTF-8' >> /etc/environment) \
 # Debian ships iptables via the nft backend by default.  The lessons teach both,
 # so pin the legacy backend for the iptables lesson and let nft be its own tool;
 # otherwise "iptables -L" and "nft list ruleset" show confusingly linked output.
 && (update-alternatives --set iptables /usr/sbin/iptables-legacy || true) \
 && (update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy || true)

# named's default logging goes to syslog, which does not exist in a container,
# so everything it says after it daemonizes is thrown away.  That includes the
# reason a zone failed to load, which is the one thing a student debugging a
# silent zone actually needs.  Point it at a file instead, the way a real server
# is configured anyway.  The directory is created bind-owned below; if named
# cannot open this file it refuses to start, so the two must stay in step.
RUN printf '%s\n' \
      '' \
      '// Log to a file: there is no syslog in this lab, and zone-loading errors' \
      '// are otherwise invisible.  Read it with: lab-dns log' \
      'logging {' \
      '    channel lab_file {' \
      '        file "/var/log/bind/named.log" versions 2 size 5m;' \
      '        severity info;' \
      '        print-time yes;' \
      '        print-category yes;' \
      '    };' \
      '    category default { lab_file; };' \
      '    // This box is deliberately isolated, so named cannot reach the root' \
      '    // servers and says so about forty times at every start.  That noise' \
      '    // buries the one line a student is actually looking for.' \
      '    category lame-servers { null; };' \
      '    category edns-disabled { null; };' \
      '};' \
      >> /etc/bind/named.conf

# Helpers: run the student's own BIND9 and NFS enumeration without systemd.

COPY lab-dns.sh /usr/local/bin/lab-dns
COPY lab-nfs.sh /usr/local/bin/lab-nfs
COPY entrypoint.sh /usr/local/bin/lab-entrypoint
RUN chmod +x /usr/local/bin/lab-dns /usr/local/bin/lab-nfs /usr/local/bin/lab-entrypoint \
 # The student edits zone files, so the bind config must be writable by them.
 && chown -R student:student /etc/bind \
 # ...but that recursive chown also takes rndc.key away from the bind account
 # named drops to, so every start logs "rndc.key: permission denied".  Nothing
 # in the lessons uses rndc, but now that the log is readable, that line is the
 # first thing a student sees while debugging something unrelated.  Give the key
 # back to bind; the student never needs to read it.
 && chown bind:bind /etc/bind/rndc.key \
 && chmod 640 /etc/bind/rndc.key \
 && mkdir -p /var/lib/bind /var/log/bind \
 && chown -R bind:bind /var/lib/bind /var/log/bind \
 # The MOTD is INFORMATIONAL, not instructional.  This image backs several
 # lessons, and only some of them run a DNS server, so telling every student to
 # "run lab-dns start" sends them off doing something their lesson never asked
 # for.  Quotes around a command also get typed literally by beginners, so the
 # commands are listed bare, on their own lines.
 && printf '%s\n' \
      'Welcome to your networking lab.' \
      'This machine is temporary.  Anything you do here is wiped when the session ends.' \
      '' \
      'Follow your lesson.  It will tell you what to run and when.' \
      '' \
      'Available on this box when a lesson calls for it:' \
      '  lab-dns          start / stop / restart / status / check your own DNS server' \
      '  lab-nfs          start / status / export / show  the NFS export table' \
      '  dig, host        look up DNS records' \
      '  ip               addresses, routes, links' \
      '  iptables, nft    the firewall' \
      '  ss               what is listening on this box' \
      '' \
      > /etc/motd

# Make "vi" the full vim: left alone it is vim-tiny in "compatible" mode, where
# 'backspace' is empty and backspace refuses to cross the start of the insert,
# the line, or an autoindent, which reads as a broken editor.  nano is worse: a
# paste from the browser arrives as raw LF, which nano reads as ^J and binds to
# "Justify", so pasted code lands reflowed into one run-on line.  One RUN, and
# the config written inline rather than copied in, to keep the layer count down.
RUN update-alternatives --set vi /usr/bin/vim.basic \
 && { [ ! -f /etc/vim/vimrc.tiny ] || sed -i 's/^set compatible/set nocompatible\nset backspace=indent,eol,start/' /etc/vim/vimrc.tiny; } \
 # vim-runtime ships 11MB of interface translations.  The courses are US
 # English only, so they are dead weight on every lab node.
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
    >> /etc/nanorc

EXPOSE 22 53
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/lab-entrypoint"]
