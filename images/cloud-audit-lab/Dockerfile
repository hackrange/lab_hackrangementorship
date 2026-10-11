# Cloud security audit lab for Week 12.
#
# The student gets a terminal and an export of a (deliberately misconfigured)
# cloud account in ~/account-export: IAM policies, S3 bucket policies, EC2
# instances + user-data + security groups, the CloudTrail config, and a couple
# of files that were "found lying around". They audit it with grep/jq and Claude
# Code, find the seven-plus real misconfigurations (each carries a FLAG- marker),
# clear the safe decoys, and write it up. No real cloud is needed: auditing an
# account export / infrastructure-as-code is exactly how much of this work is
# done in practice.
#
# SSH-delivered and lean, like webapp-lab. Claude Code needs internet, so the
# lesson runs this lab with net_mode 'full'.
# Author: Tim Rice
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openssh-server ca-certificates tini sudo \
      curl less nano vim procps \
      coreutils gawk sed grep jq awscli \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /run/sshd \
 && useradd -m -s /bin/bash student \
 && usermod -aG sudo student \
 && printf 'student ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/student \
 && chmod 440 /etc/sudoers.d/student \
 && sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
 && sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && printf 'LANG=C.UTF-8\n' > /etc/default/locale

# Claude Code, so the student can point an AI at the export (own-account login;
# the lab has internet for the sign-in and API).
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && npm install -g @anthropic-ai/claude-code \
 && npm cache clean --force \
 && apt-get clean && rm -rf /var/lib/apt/lists/*
ENV DISABLE_AUTOUPDATER=1

COPY export/ /home/student/account-export/
COPY entrypoint.sh /usr/local/bin/lab-entrypoint

RUN chmod +x /usr/local/bin/lab-entrypoint \
 && chown -R student:student /home/student \
 && printf 'You are auditing the NimbusPay cloud account.\nThe export is in ~/account-export (start with its README.txt).\nTools: grep -r, jq, less, aws, and claude (sign in with your own account).\n\n' > /etc/motd

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

EXPOSE 22
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/lab-entrypoint"]
