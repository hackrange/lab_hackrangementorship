"""The labs of this course, read from the one file that defines them.

config/labs.conf is what the launcher, the status display, the rehearsal and
now the panel all read, so a lab added there appears here with no code change.
A row is:

    key|image|proto|caps|companion|weeks|title|web

Read on each request rather than cached, so editing the catalog and reloading
the page is enough to see the change.

Author: Tim Rice - tim.j.rice@hackrange.com
"""

from __future__ import annotations

from .const import CATALOG, LOGINS

# What each lab is, in a sentence, for the card.  The catalog's title says
# which weeks' material it holds; this says what the student does in it, which
# is what someone deciding what to open wants to know.
WHAT = {
    "kali": "A terminal.  Read a machine's own addressing, subnets and IPv6, "
            "and watch what it is talking to.",
    "netlab": "A terminal you are meant to break and mend: DNS, routing, the "
              "firewall, and hardening an inherited server.",
    "analyst": "A desktop with six inconsistent audit exports and a "
               "spreadsheet.  Reconcile them, then hunt shadow SaaS and AI.",
    "splunk": "A desktop running Splunk on a real intrusion's telemetry.  "
              "Search it, reconstruct what happened, then write detections.",
    "webapp": "A terminal with a deliberately vulnerable web app and all of "
              "its source, to review with an AI beside you.",
    "webapp-gui": "A desktop with the same app, a scanner beside it on a "
                  "private network, and the tools to test it as an attacker would.",
    "cloud": "A terminal holding a misconfigured cloud account to audit, with "
             "findings to record as you go.",
}


# What to tell a student when a lab is not the machine's own processor.
#
# Six of the seven labs are built for both, and run natively wherever they are
# installed.  Splunk publishes no ARM build for Linux at all, so on an Apple
# Silicon or other ARM machine that one image is built and run as x86 under
# emulation, and every instruction inside it is translated as it runs.  Saying
# so on the card is the difference between a student who knows why their lab
# is slow and one who thinks they have broken something.
EMULATED = {
    "splunk": "Splunk publishes no ARM build, so on this machine this one lab "
              "runs as x86 under emulation.  It is slow to start, and slow "
              "enough through the lab's own browser to be painful.  Open "
              "Splunk from the browser you are already using instead, at the "
              "address on this card.",
}
GENERIC_EMULATED = ("This lab is built for a different processor from this "
                    "machine, so it runs under emulation and will be slow.")


def notice(lab: dict, is_emulated: bool) -> str:
    """The plain warning a card carries, or "" when there is nothing to say."""
    if not is_emulated:
        return ""
    return EMULATED.get(lab.get("key", ""), GENERIC_EMULATED)

def _web(field: str) -> list[dict]:
    """The web apps inside a lab, as [{"port", "label"}]."""
    out = []
    if not field or field == "-":
        return out
    for spec in field.split(","):
        spec = spec.strip()
        if not spec:
            continue
        port, _, label = spec.partition("/")
        if not port.isdigit():
            continue
        out.append({"port": int(port), "label": label or "the lab's web app"})
    return out


def labs() -> list[dict]:
    """Every lab, in the order a student meets them."""
    rows = []
    try:
        with open(CATALOG) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                f = line.split("|")
                if len(f) < 7:
                    continue
                rows.append({
                    "key": f[0], "image": f[1], "proto": f[2], "caps": f[3],
                    "companion": "" if f[4] == "-" else f[4],
                    "weeks": f[5], "title": f[6],
                    "web": _web(f[7] if len(f) > 7 else ""),
                    "what": WHAT.get(f[0], ""),
                })
    except OSError:
        return []
    return rows


def by_key() -> dict:
    return {lab["key"]: lab for lab in labs()}


def logins() -> dict:
    """{lab key: [{"group", "label", "value", "secret", "note"}]}.

    The same file "hackrange-lab env" reads, so the card in the panel and the
    terminal cannot tell a student two different passwords.
    """
    out: dict = {}
    try:
        with open(LOGINS) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                f = line.split("|")
                if len(f) < 6:
                    continue
                out.setdefault(f[0], []).append({
                    "group": f[1], "label": f[2], "value": f[3],
                    "secret": f[4] == "1", "note": "" if f[5] == "-" else f[5],
                })
    except OSError:
        return {}
    return out
