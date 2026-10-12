#!/usr/bin/env bash
# Point this checkout at the place it is published.
#
#   scripts/retarget.sh github   github.com/hackrange/lab_hackrangementorship
#   scripts/retarget.sh gitlab   git.hackrange.com/trice/lab_hackrangementorship
#
# The lab is published in two repositories.  Everything in them is identical
# except the addresses a student is given: the repository an install updates
# itself from, and the one line command printed in install.sh and the README.
# Getting that wrong is quiet and annoying - a student who installed from one
# host would be told to run a command pointing at the other, and an update
# would pull from a repository they may not be able to reach.
#
# So this is the only thing that differs, and it is set by running this rather
# than by hand editing three files and missing one.
#
# Author: Tim Rice - tim.j.rice@hackrange.com
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?usage: retarget.sh github|gitlab}"

case "$TARGET" in
    github)
        clone="https://github.com/hackrange/lab_hackrangementorship.git"
        # GitHub serves a file's contents from a different hostname entirely.
        raw="https://raw.githubusercontent.com/hackrange/lab_hackrangementorship"
        ;;
    gitlab)
        clone="https://git.hackrange.com/trice/lab_hackrangementorship.git"
        # GitLab serves a raw file from "/-/raw/<branch>/<path>".  Verified
        # against the existing repository on this host rather than assumed: the
        # shape some other forges use, "/raw/branch/<branch>/<path>", answers
        # 404 here, and a one line command built that way would fail for every
        # student who used it.
        raw="https://git.hackrange.com/trice/lab_hackrangementorship/-/raw"
        ;;
    *) printf 'Unknown target: %s  (github or gitlab)\n' "$TARGET" >&2; exit 1 ;;
esac

python3 - "$HERE" "$clone" "$raw" <<'PY'
import pathlib, re, sys
here, clone, raw = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]

p = here/'install.sh'; s = p.read_text()
s = re.sub(r'REPO_URL="\$\{HR_REPO_URL:-[^}]*\}"', f'REPO_URL="${{HR_REPO_URL:-{clone}}}"', s)
s = re.sub(r'RAW_URL="\$\{HR_RAW_URL:-[^}]*\}"',  f'RAW_URL="${{HR_RAW_URL:-{raw}}}"', s)
# The comment at the top of the file shows the command too.
s = re.sub(r'(#   curl -fsSL )\S+(/install\.sh \| sudo bash)', rf'\1{raw}/main\2', s)
p.write_text(s)

p = here/'README.md'; s = p.read_text()
s = re.sub(r'curl -fsSL \S+/install\.sh \| sudo bash',
           f'curl -fsSL {raw}/main/install.sh | sudo bash', s)
p.write_text(s)
print(f"pointed at {clone}")
PY
