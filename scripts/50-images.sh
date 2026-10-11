#!/usr/bin/env bash
# Build the course's lab images on this machine.
#
# Every image is built here rather than pulled, so a student needs no account
# anywhere and nothing private.  The sources are in images/, and config/labs.conf
# says which lab each one serves.
#
# One image cannot be built for ARM: Splunk Enterprise has no ARM build for
# Linux at all (Splunk's own requirements list x86_64, PowerPC, SPARC and
# s390x, and exclude ARM for Enterprise).  So on an ARM machine the Splunk lab
# is built and run as x86_64 under emulation.  That is slower, and it is the
# only way those lessons can run on Apple Silicon at all.
#
# Author: Tim Rice
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step "Building the lab images"

ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

# Emulation for the one image that is x86 only.  binfmt teaches the kernel to
# run an x86 program by handing it to qemu, which is what lets an amd64 Splunk
# image run on an ARM machine at all.
if [ "$ARCH" != amd64 ]; then
    if ! [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
        say "Setting up x86 emulation (the Splunk labs are x86 only)..."
        # The package has three names depending on the release: Ubuntu 26.04
        # arm64 has no qemu-user-static at all, only qemu-user-binfmt and
        # qemu-user, and asking for the wrong one prints "has no installation
        # candidate" and installs nothing.  Try each, quietly, and judge by
        # whether the handler appears rather than by what apt said.
        for pkg in qemu-user-static qemu-user-binfmt qemu-user; do
            [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ] && break
            quiet apt-get install -y -qq "$pkg" binfmt-support 2>/dev/null || true
        done
        # Failing that, the handler can be registered from a container.  This
        # is tried SECOND but it is the one that usually works, so no warning
        # is printed until both have been tried: an earlier version announced
        # "the Splunk labs will not build" and was then contradicted a second
        # later by this very line succeeding.
        if ! [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
            quiet docker run --privileged --rm tonistiigi/binfmt --install amd64 || true
        fi
        if [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
            ok "x86 emulation is ready"
        else
            warn "Could not set up x86 emulation, so the Splunk labs (weeks 8 to 10)"
            warn "will not build on this machine.  Everything else will."
        fi
    else
        ok "x86 emulation is already set up"
    fi
fi

# build <dir> <tag> [platform]
build() {
    local dir="$1" tag="$2" platform="${3:-}" args=()
    [ -n "$platform" ] && args+=(--platform "$platform")
    say "Building $tag${platform:+ ($platform)}..."
    if ! quiet docker build "${args[@]}" -t "$tag" "$HR_ROOT/images/$dir"; then
        die "Could not build $tag.  The full output is in $HR_LOG"
    fi
    ok "$tag"
}

# The DAST scanner for the Week 11 challenge is built from its public source,
# then the lab sidecar is layered on top of it.  The hosted labs pull a
# prebuilt image from a private registry that a student cannot reach.
build_dast() {
    local src="$HR_ETC/src/nextgen-dast"
    install -d -m 755 "$HR_ETC/src"
    if [ -d "$src/.git" ]; then
        quiet git -C "$src" fetch -q --depth 1 origin "$DAST_REF" || true
        quiet git -C "$src" checkout -q -f FETCH_HEAD || true
    else
        rm -rf "$src"
        quiet git clone -q --depth 1 -b "$DAST_REF" "$DAST_REPO" "$src" ||
            die "Could not fetch the DAST scanner source from $DAST_REPO"
    fi
    say "Building $DAST_BASE_IMAGE from source..."
    quiet docker build -t "$DAST_BASE_IMAGE" "$src" ||
        die "Could not build $DAST_BASE_IMAGE.  The full output is in $HR_LOG"
    ok "$DAST_BASE_IMAGE"
    # The sidecar adds its own database and a seeded admin login, so the
    # student has a working scanner with nothing to set up.
    build nextgen-dast-lab "$DAST_LAB_IMAGE"
}

build kali-lab-ssh            "$KALI_SSH_IMAGE"
build netlab                  "$NETLAB_IMAGE"
build analyst-lab             "$ANALYST_IMAGE"
build webapp-lab              "$WEBAPP_IMAGE"
build cloud-audit-lab         "$CLOUD_AUDIT_IMAGE"
build mentorship-webapp-gui   "$WEBAPP_GUI_IMAGE"
build_dast

# Splunk last: it is the largest download by far, so a failure here does not
# cost the student every other lab.
if [ "$ARCH" = amd64 ]; then
    build splunk-lab "$SPLUNK_IMAGE"
elif [ -e /proc/sys/fs/binfmt_misc/qemu-x86_64 ]; then
    say "Building the Splunk labs as x86 under emulation; this takes a while."
    build splunk-lab "$SPLUNK_IMAGE" linux/amd64
else
    warn "Skipping the Splunk labs: this machine is $ARCH and x86 emulation is not available."
    warn "Weeks 8 to 10 will not run here.  Everything else will."
fi
