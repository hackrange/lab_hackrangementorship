#!/bin/bash
# Per-login desktop fixups, run by the session.  Kept separate from the
# entrypoint because these need the student's own session to exist.
# Author: Tim Rice - tim.j.rice@hackrange.com
set -u
mkdir -p "$HOME/.config/xfce4/terminal"
[ -f "$HOME/.config/xfce4/terminal/terminalrc" ] || \
    printf '%s\n' '[Configuration]' 'CommandLoginShell=TRUE' \
      > "$HOME/.config/xfce4/terminal/terminalrc"

# The Xfce menu's Terminal entry asks xfce4-session's helper rather than
# x-terminal-emulator, so with no helpers.rc the student is asked to pick a
# terminal.  Baked into the image too; written here as well so a session that
# predates that image still gets it.
[ -f "$HOME/.config/xfce4/helpers.rc" ] || \
    printf '%s\n' 'TerminalEmulator=xfce4-terminal' \
      > "$HOME/.config/xfce4/helpers.rc"

# Never blank the screen.  xfce4-power-manager is installed for the panel's
# sake and arrives with blanking on, and a desktop that goes black part way
# through an exercise reads as a dead lab.
command -v xset >/dev/null 2>&1 && xset s off -dpms 2>/dev/null
exit 0
