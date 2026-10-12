#!/usr/bin/env bash
# Hackrange Local Lab installer for the Hackrange Mentorship course,
# a cyber security TRAINING lab (deliberately vulnerable code, fake secrets):
# install it only in a disposable virtual machine on a private network.
#
# The one command a student runs, inside their own Ubuntu virtual machine:
#
#   curl -fsSL https://raw.githubusercontent.com/hackrange/lab_hackrangementorship/main/install.sh | sudo bash
#
# It checks the machine, fetches this repository to /opt/hackrange-mentorship, and
# runs the setup steps in scripts/ in order.  Running it again is always safe:
# it finishes a half done install, and on a finished one it updates the lab to
# the latest version of this repository.
#
# Author: Tim Rice - tim.j.rice@hackrange.com

set -Eeuo pipefail

# Where this copy of the lab updates itself from, and the address the one line
# install command uses.  This lab is published in two places, and each copy
# carries its OWN addresses: a student who installed from GitLab must keep
# updating from GitLab, and the command printed back to them has to be one
# they can actually run.  scripts/retarget.sh switches a checkout between them,
# so the two copies differ in these two lines and nothing else.
REPO_URL="${HR_REPO_URL:-https://github.com/hackrange/lab_hackrangementorship.git}"
RAW_URL="${HR_RAW_URL:-https://raw.githubusercontent.com/hackrange/lab_hackrangementorship}"
REPO_BRANCH="${HR_BRANCH:-main}"
HR_ROOT="${HR_ROOT:-/opt/hackrange-mentorship}"

red()  { printf '\e[31m%s\e[0m\n' "$*" >&2; }
bold() { printf '\e[1m%s\e[0m\n' "$*"; }

stop() { printf '\n'; red "$1"; shift; for l in "$@"; do printf '  %s\n' "$l" >&2; done; printf '\n' >&2; exit 1; }

# ---------------------------------------------------------------- where are we

if [ "$(uname -s)" = Darwin ]; then
    stop "This is a Mac, and the lab installs inside an Ubuntu virtual machine." \
         "" \
         "1. Install a free virtual machine app: UTM (https://mac.getutm.app)," \
         "   or VMware Fusion, or Parallels." \
         "2. Create an Ubuntu 24.04 Desktop virtual machine.  On an Apple Silicon" \
         "   Mac (M1 or newer) choose the ARM64 download of Ubuntu; on an Intel" \
         "   Mac choose the normal (amd64) one." \
         "3. Give it the memory, processors and disk listed in the README." \
         "4. Open a terminal INSIDE that virtual machine and run this command again."
fi

if [ "$(uname -s)" != Linux ]; then
    stop "This installer runs on Ubuntu Linux 22.04 or newer, inside a virtual machine." \
         "See the README for how to create one."
fi

if [ "$(id -u)" -ne 0 ]; then
    stop "The installer needs administrator rights.  Run it with sudo:" \
         "" \
         "  curl -fsSL ${RAW_URL}/${REPO_BRANCH}/install.sh | sudo bash"
fi

# shellcheck disable=SC1091
. /etc/os-release
if [ "${ID:-}" != ubuntu ]; then
    stop "This machine runs ${PRETTY_NAME:-an unknown system}, and the lab needs Ubuntu 22.04 or newer." \
         "Other Linux systems may work but are not supported.  Create an Ubuntu virtual machine" \
         "as the README describes, and run the command there."
fi
major="${VERSION_ID%%.*}"
if [ "${major:-0}" -lt 22 ]; then
    stop "This machine runs Ubuntu ${VERSION_ID}, and the lab needs 22.04 or newer." \
         "Upgrade it (sudo do-release-upgrade) or create a new Ubuntu 24.04 virtual machine."
fi

case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) stop "This processor ($(uname -m)) is not supported.  The lab needs a 64 bit Intel/AMD" \
            "(x86_64) or ARM (arm64, including Apple Silicon) virtual machine." ;;
esac

# ---------------------------------------------------------------- fetch the lab

bold "Hackrange Mentorship: the Local Lab"
printf '  A cyber security TRAINING lab: it contains deliberately vulnerable code and\n'
printf '  fake secrets.  Install it only in a disposable virtual machine on a private network.\n'
printf '  Ubuntu %s on %s\n' "$VERSION_ID" "$(uname -m)"

export DEBIAN_FRONTEND=noninteractive
# A new Ubuntu machine installs its own updates soon after it boots, and while
# it does, every other package install is refused.  Wait for it (up to ten
# minutes) instead of failing on a student's first try.
mkdir -p /etc/apt/apt.conf.d
printf 'DPkg::Lock::Timeout "600";\n' > /etc/apt/apt.conf.d/90hackrange-wait-for-lock
if ! command -v git >/dev/null || ! command -v curl >/dev/null; then
    printf '  Installing git and curl first...\n'
    apt-get update -qq >/dev/null
    apt-get install -y -qq git curl ca-certificates >/dev/null
fi

# Run from a checkout when there is one (a developer testing a change), and
# from a fresh fetch of the branch otherwise (every student).
# The installed copy is always brought up to date, which is what
# `hackrange-lab update` relies on.
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$here" ] && [ "$here" != "$HR_ROOT" ] && [ -f "$here/scripts/setup.sh" ] && [ -f "$here/versions.env" ]; then
    HR_ROOT="$here"
elif [ -d "$HR_ROOT/.git" ]; then
    printf '  Updating the lab files in %s...\n' "$HR_ROOT"
    # A lab installed before the repository moved still points at the old
    # address; every update points it at the current one first.
    # The first install cloned one branch only, so name the branch to track
    # too, or a moved or renamed branch never gets a remote ref.
    git -C "$HR_ROOT" remote set-url origin "$REPO_URL"
    git -C "$HR_ROOT" config remote.origin.fetch "+refs/heads/$REPO_BRANCH:refs/remotes/origin/$REPO_BRANCH"
    git -C "$HR_ROOT" fetch -q --depth 1 origin "$REPO_BRANCH"
    git -C "$HR_ROOT" checkout -q -f -B "$REPO_BRANCH" "origin/$REPO_BRANCH"
else
    printf '  Downloading the lab files to %s...\n' "$HR_ROOT"
    git clone -q --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$HR_ROOT"
fi

export HR_ROOT
exec bash "$HR_ROOT/scripts/setup.sh" "$@"
