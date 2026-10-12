"""How hard the machine and the running lab are working.

A background thread samples every few seconds and keeps the latest numbers, so
a page load never waits on `docker stats`, which takes a couple of seconds.

- The machine: processor from /proc/stat, memory from /proc/meminfo (what
  programs really hold, not the page cache), disk for the filesystem the lab
  images live on, and network from /proc/net/dev.
- The lab: `docker stats`.

Network is a RATE, which means it only exists between two samples: the kernel
counts bytes since boot, and a total since boot tells a student nothing about
whether their lab is busy now.  So the first sample after the panel starts has
no rate to report and says so rather than reporting zero, which would read as
"nothing is happening" when the truth is "not measured yet".

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

import os
import shutil
import threading
import time

from .run import DOCKER, run

INTERVAL = 5

# Interfaces that only carry traffic between things on this machine.  Counting
# them would show the lab talking to the web desktop as though it were
# internet traffic, which is the opposite of useful.
SKIP_PREFIXES = ("lo", "docker", "br-", "veth", "virbr", "tun", "tap")

_latest: dict = {"host": {}, "containers": {}, "at": 0}
_lock = threading.Lock()


def _cpu_times() -> tuple[int, int]:
    with open("/proc/stat") as fh:
        parts = [int(x) for x in fh.readline().split()[1:]]
    idle = parts[3] + (parts[4] if len(parts) > 4 else 0)
    return sum(parts), idle


def _memory() -> dict:
    info = {}
    with open("/proc/meminfo") as fh:
        for line in fh:
            key, _, rest = line.partition(":")
            info[key] = int(rest.split()[0]) * 1024
    total = info.get("MemTotal", 0)
    return {"total": total, "used": total - info.get("MemAvailable", 0)}


def _disk() -> dict:
    u = shutil.disk_usage("/var/lib")
    return {"total": u.total, "used": u.used}


def _net_counters() -> tuple[int, int]:
    """(bytes in, bytes out) since boot, over the real interfaces."""
    rx = tx = 0
    try:
        with open("/proc/net/dev") as fh:
            for line in fh.readlines()[2:]:
                name, _, rest = line.partition(":")
                name = name.strip()
                if name.startswith(SKIP_PREFIXES):
                    continue
                f = rest.split()
                if len(f) >= 9:
                    rx += int(f[0])
                    tx += int(f[8])
    except (OSError, ValueError):
        pass
    return rx, tx


def _size(text: str) -> int:
    """'512MiB' or '1.2GiB' or '300kB' as bytes."""
    text = text.strip()
    units = [("KiB", 1024), ("MiB", 1024 ** 2), ("GiB", 1024 ** 3), ("TiB", 1024 ** 4),
             ("kB", 1000), ("MB", 1000 ** 2), ("GB", 1000 ** 3), ("B", 1)]
    for unit, mult in units:
        if text.endswith(unit):
            try:
                return int(float(text[: -len(unit)]) * mult)
            except ValueError:
                return 0
    return 0


def _containers() -> dict:
    rc, out = run([DOCKER, "stats", "--no-stream", "--format",
                   "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"], timeout=30)
    result = {}
    if rc != 0:
        return result
    for line in out.splitlines():
        try:
            name, cpu, mem, netio = line.split("\t")
            rx, _, tx = netio.partition("/")
            result[name] = {"cpu": float(cpu.rstrip("%") or 0), "mem": _size(mem.split("/")[0]),
                            "rx_total": _size(rx), "tx_total": _size(tx)}
        except ValueError:
            continue
    return result


def _loop() -> None:
    cores = os.cpu_count() or 1
    prev_cpu = _cpu_times()
    prev_net = _net_counters()
    prev_cont: dict = {}
    prev_at = time.time()
    while True:
        time.sleep(INTERVAL)
        now_cpu = _cpu_times()
        dt, di = now_cpu[0] - prev_cpu[0], now_cpu[1] - prev_cpu[1]
        prev_cpu = now_cpu

        now_net = _net_counters()
        at = time.time()
        span = max(at - prev_at, 0.001)
        net = {"rx": max(0, int((now_net[0] - prev_net[0]) / span)),
               "tx": max(0, int((now_net[1] - prev_net[1]) / span)),
               "measured": True}
        prev_net = now_net

        containers = _containers()
        # Turn each container's byte totals into a rate the same way.
        for name, c in containers.items():
            was = prev_cont.get(name)
            if was:
                c["rx"] = max(0, int((c["rx_total"] - was["rx_total"]) / span))
                c["tx"] = max(0, int((c["tx_total"] - was["tx_total"]) / span))
                c["measured"] = True
            else:
                c["rx"] = c["tx"] = 0
                c["measured"] = False
        prev_cont = containers
        prev_at = at

        host = {"cpu": round(100.0 * (dt - di) / dt, 1) if dt else 0.0, "cores": cores,
                "memory": _memory(), "disk": _disk(), "load": os.getloadavg()[0], "net": net}
        with _lock:
            _latest.update(host=host, containers=containers, at=at)


def start() -> None:
    threading.Thread(target=_loop, daemon=True).start()


def snapshot() -> dict:
    with _lock:
        return {k: (dict(v) if isinstance(v, dict) else v) for k, v in _latest.items()}


def usage_for(names: list[str], snap: dict) -> dict:
    """Processor (as a share of the whole machine), memory and network for a
    set of containers."""
    cores = snap.get("host", {}).get("cores", 1) or 1
    parts = [snap.get("containers", {}).get(n, {}) for n in names]
    parts = [p for p in parts if p]
    return {"cpu": round(sum(p.get("cpu", 0.0) for p in parts) / cores, 1),
            "mem": sum(p.get("mem", 0) for p in parts),
            "rx": sum(p.get("rx", 0) for p in parts),
            "tx": sum(p.get("tx", 0) for p in parts),
            "measured": any(p.get("measured") for p in parts)}
