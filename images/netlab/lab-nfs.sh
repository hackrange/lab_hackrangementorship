#!/bin/bash
# Bring up just enough of NFS to study it, in a container with no systemd.
#
# The kernel NFS server (rpc.nfsd) cannot run here: it needs to mount the nfsd
# filesystem, which requires SYS_ADMIN, and lab containers are never granted it.
# rpcbind and rpc.mountd DO run unprivileged, and together they answer showmount,
# which is exactly the enumeration an attacker or an assessor performs against a
# real file server.  So this starts the enumeration surface, not a file server.
#
# Author: Tim Rice
set -u

# Same reason as lab-dns: rpcbind, rpc.mountd, and exportfs all need root, and
# the student's shell is unprivileged.  Re-exec through passwordless sudo so the
# command behaves as the MOTD and the lessons present it.
# Absolute path, because sudo resets PATH to secure_path.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo /usr/local/bin/lab-nfs "$@"
fi

usage() {
    cat <<'USAGE'
Usage: lab-nfs {start|stop|status|export|show}

  start     start rpcbind and rpc.mountd so exports can be enumerated
  stop      stop them
  status    show what is running
  export    re-read /etc/exports and apply it (exportfs -ra)
  show      show the CURRENT effective export options (exportfs -s)

Note: this box cannot serve file data or mount a share.  Both need SYS_ADMIN,
which a disposable lab container does not get.  You can still write exports,
read their effective options, and enumerate them with showmount, which is what
a real review of a file server looks like.
USAGE
}

case "${1:-}" in
    start)
        pgrep -x rpcbind >/dev/null 2>&1 || rpcbind
        sleep 1
        pgrep -x rpc.mountd >/dev/null 2>&1 || rpc.mountd
        sleep 1
        exportfs -ra 2>/dev/null
        echo "rpcbind and rpc.mountd are up.  Try: showmount -e localhost"
        ;;
    stop)
        pkill -x rpc.mountd 2>/dev/null
        pkill -x rpcbind 2>/dev/null
        echo "stopped."
        ;;
    status)
        pgrep -x rpcbind   >/dev/null 2>&1 && echo "rpcbind:    RUNNING" || echo "rpcbind:    stopped"
        pgrep -x rpc.mountd >/dev/null 2>&1 && echo "rpc.mountd: RUNNING" || echo "rpc.mountd: stopped"
        ;;
    export)
        exportfs -ra && echo "exports reloaded." && exportfs -s
        ;;
    show)
        exportfs -s
        ;;
    *)
        usage; exit 1
        ;;
esac
