#!/bin/bash
# Per-login desktop fixups, run by the session.  Kept separate from the
# entrypoint because these need the student's own session to exist.
# Author: Tim Rice
set -u
mkdir -p "$HOME/.config/xfce4/terminal"
[ -f "$HOME/.config/xfce4/terminal/terminalrc" ] || \
    printf '%s\n' '[Configuration]' 'CommandLoginShell=TRUE' \
      > "$HOME/.config/xfce4/terminal/terminalrc"
exit 0
