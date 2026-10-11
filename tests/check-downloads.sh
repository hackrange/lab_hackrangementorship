#!/usr/bin/env bash
# Prove the things a student's install fetches from the internet are still there.
#
# Every lab image is built on the student's own machine, so the install depends
# on a handful of outside addresses staying reachable.  The fragile one is
# Splunk: the download URL names an exact version AND build hash, and Splunk
# removes old builds from its site.  When that happens the Splunk labs stop
# building for every new student, with no warning and nothing in this
# repository having changed.  This catches it in a few seconds.
#
#   tests/check-downloads.sh
#
# Author: Tim Rice
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$HERE/versions.env"

PASS=0; FAIL=0
ok()  { printf '  \033[32m[pass]\033[0m %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  \033[31m[FAIL]\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; FAIL=$((FAIL+1)); }

# head <url> <label> [expected-min-bytes]
head_ok() {
    local url="$1" label="$2" min="${3:-0}" code len
    code="$(curl -sIL -o /dev/null -w '%{http_code}' --max-time 30 "$url" 2>/dev/null)"
    len="$(curl -sIL --max-time 30 "$url" 2>/dev/null | grep -i '^content-length' | tail -1 | tr -dc 0-9)"
    if [ "$code" != 200 ]; then
        bad "$label" "answered $code: $url"
    elif [ "$min" -gt 0 ] && [ "${len:-0}" -lt "$min" ]; then
        bad "$label" "only ${len:-0} bytes, expected at least $min"
    else
        ok "$label${len:+ ($(( len / 1048576 )) MB)}"
    fi
}

echo "The downloads a first install depends on"
printf '\n'

# Splunk, read from the Dockerfile rather than retyped, so this cannot drift
# from what is actually built.
splunk_url="$(grep -oE 'ARG SPLUNK_URL=\S+' "$HERE/images/splunk-lab/Dockerfile" | cut -d= -f2-)"
if [ -z "$splunk_url" ]; then
    bad "the Splunk download URL is not in images/splunk-lab/Dockerfile"
else
    # It must also be the version versions.env claims, or the two have drifted.
    case "$splunk_url" in
        *"$SPLUNK_VERSION"*"$SPLUNK_BUILD"*)
            ok "versions.env matches the Dockerfile ($SPLUNK_VERSION build $SPLUNK_BUILD)" ;;
        *) bad "versions.env says $SPLUNK_VERSION/$SPLUNK_BUILD but the Dockerfile fetches something else" \
               "$splunk_url" ;;
    esac
    head_ok "$splunk_url" "the Splunk package is still published" 500000000
fi

# The base images every lab is built from.
for ref in kalilinux/kali-rolling:latest debian:12-slim python:3.12-slim; do
    if docker manifest inspect "$ref" >/dev/null 2>&1; then
        ok "$ref can be pulled"
    else
        bad "$ref cannot be pulled" "two or more labs are built from it"
    fi
done

# The web desktop's images, pinned on purpose: 'latest' is published for amd64
# only, so a student on an ARM machine would get no web desktop at all.
for ref in "$GUACAMOLE_IMAGE" "$GUACD_IMAGE"; do
    if docker manifest inspect "$ref" >/dev/null 2>&1; then
        arches="$(docker manifest inspect "$ref" 2>/dev/null | grep -oE '"architecture": *"[a-z0-9]+"' | cut -d'"' -f4 | sort -u | tr '\n' ' ')"
        case "$arches" in
            *arm64*) ok "$ref is published for: $arches" ;;
            *) bad "$ref is published only for: $arches" "an ARM machine would have no web desktop" ;;
        esac
    else
        bad "$ref cannot be pulled"
    fi
done

# The scanner's source, which must stay anonymously cloneable or the Week 11
# challenge cannot be built by a student at all.
# Either a branch or a tag: the installer clones with -b, which takes both, and
# this version of the scanner is published as a BRANCH named 2.1.1.  An earlier
# version of this check looked only under refs/tags and reported the Week 11
# lab as unbuildable when it builds perfectly well.
if GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/true \
   timeout 60 git ls-remote "$DAST_REPO" "refs/heads/$DAST_REF" "refs/tags/$DAST_REF" 2>/dev/null | grep -q .; then
    ok "the scanner source is public and has $DAST_REF"
else
    bad "cannot reach $DAST_REPO at $DAST_REF anonymously" \
        "the Week 11 scanner could not be built on a student's machine"
fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
