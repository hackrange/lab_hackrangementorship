#!/usr/bin/env bash
# The docker options a lab runs with, in ONE place.
#
# The launcher and the rehearsal harness both source this, so a lab cannot be
# tested under one set of capabilities and then handed to a student under
# another.  Keeping two copies is how that happens: the first version of this
# used --cap-drop ALL in both, which is stricter than the hosted broker and
# made every sudo print "unable to send audit message".
#
# These values ARE the hosted broker's, deliberately:
#
#   capabilities  the broker drops exactly five and keeps Docker's other
#                 defaults.  NET_RAW is a default, so a profile that wants it
#                 just stops dropping it; NET_ADMIN is not, so it has to be
#                 added back explicitly or iptables still fails.
#   budgets       512MB/1cpu/256pids for a terminal lab, 3072MB/2cpu/4096pids
#                 for a desktop.  The pids number matters: too low and Firefox
#                 dies with "Compositor thread not started".
#
# Author: Tim Rice

# lab_run_opts <proto> <caps>  ->  prints the docker arguments
lab_run_opts() {
    local proto="$1" caps="$2"
    local drop=(NET_RAW NET_ADMIN SYS_ADMIN SYS_PTRACE SYS_MODULE) add=() c

    case "$caps" in
        offsec) drop=(NET_ADMIN SYS_ADMIN SYS_PTRACE SYS_MODULE) ;;
        netlab) drop=(SYS_ADMIN SYS_PTRACE SYS_MODULE); add=(NET_ADMIN) ;;
    esac

    for c in "${drop[@]}"; do printf -- '--cap-drop %s ' "$c"; done
    for c in "${add[@]}";  do printf -- '--cap-add %s ' "$c"; done

    if [ "$proto" = rdp ]; then
        printf -- '--memory 3072m --cpus 2 --pids-limit 4096 --shm-size 1g '
    else
        printf -- '--memory 512m --cpus 1 --pids-limit 256 '
    fi
}

# The sidecar scanner's own budget, also the broker's.
lab_companion_opts() {
    printf -- '--cap-drop NET_RAW --cap-drop NET_ADMIN --cap-drop SYS_ADMIN '
    printf -- '--cap-drop SYS_PTRACE --cap-drop SYS_MODULE '
    printf -- '--memory 1536m --cpus 1 '
}

# Splunk has no ARM build at all, so on an ARM machine it runs as x86 under
# emulation.  Naming the platform keeps "exec format error" away from a student.
lab_platform_opts() {
    local image="$1"
    [ "$(docker image inspect -f '{{.Architecture}}' "$image" 2>/dev/null)" = amd64 ] \
        && [ "$(uname -m)" != x86_64 ] && printf -- '--platform linux/amd64 '
    return 0
}
