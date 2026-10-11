#!/usr/bin/env python3
"""
Solve the auditor challenge in Python.

Same job as audit-answers.sh, and useful for the same reason: the script IS the
evidence.  Next quarter you re-run it instead of rebuilding a spreadsheet from
memory, and anyone can check your working.

The six exports disagree about everything, which is the actual lesson:

  cmdb.csv                  comma, NO HEADER   host,firstname,lastname
  computer_sid_objects.csv  TILDE, NO HEADER   class~host~fqdn~DN~...
  crowdstrike_output.csv    comma, NO HEADER   host,rfc1918,publicip,os,mac,...
  ecm_hosts.csv             comma, header, CRLF   utc,hn,status,os,bitlocker
  identity.csv              comma, header, CRLF   fname,lname,email,userid
  qualys_data_output_v2.csv comma, header, CRLF   publicip,time,rfc1918,fqdn,hostname,status,os

Three traps live in that data:
  1. Three files have no header, so you cannot look a column up by name.
  2. Some CrowdStrike names carry a numeric prefix: 9137P-2LPLLG4 is the machine
     everyone else calls P-2LPLLG4.
  3. Qualys and AD append a domain, and three files use CRLF, so a stray \\r
     quietly breaks every comparison.

Usage:  python3 audit-answers.py [--dir /home/student/audit] [--list]
Author: Tim Rice
"""

import argparse
import csv
import pathlib
import re
import sys


def normalize(value: str) -> str:
    """Turn one raw hostname field into a key that compares across all six files.

    Every step here exists because some export needed it.  Drop any of them and
    the totals come out wrong while still looking entirely plausible.
    """
    v = (value or "").replace("\r", "").strip().strip('"')
    v = v.split(".")[0]              # A-2NMGCM7.hackrange.net -> A-2NMGCM7
    v = re.sub(r"^\d+", "", v)       # 9137P-2LPLLG4           -> P-2LPLLG4
    return v.lower()


def column(path: pathlib.Path, delimiter: str, field: int, skip_header: bool) -> set:
    """Read one column out of a file and return it normalized and deduplicated."""
    keys = set()
    with path.open(newline="", encoding="utf-8", errors="replace") as fh:
        reader = csv.reader(fh, delimiter=delimiter)
        for i, row in enumerate(reader):
            if skip_header and i == 0:
                continue
            if len(row) <= field:
                continue
            key = normalize(row[field])
            if key:
                keys.add(key)
    return keys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="/home/student/audit")
    ap.add_argument("--list", action="store_true",
                    help="print the offending machine names, not just the counts")
    args = ap.parse_args()
    d = pathlib.Path(args.dir)

    needed = ["cmdb.csv", "computer_sid_objects.csv", "crowdstrike_output.csv",
              "ecm_hosts.csv", "qualys_data_output_v2.csv", "identity.csv"]
    for name in needed:
        if not (d / name).is_file():
            print(f"Missing {d / name}", file=sys.stderr)
            return 1

    # (file, delimiter, hostname field index, has header)
    cmdb   = column(d / "cmdb.csv",                  ",", 0, False)
    ad     = column(d / "computer_sid_objects.csv",  "~", 1, False)
    crowd  = column(d / "crowdstrike_output.csv",    ",", 0, False)
    ecm    = column(d / "ecm_hosts.csv",             ",", 1, True)
    qualys = column(d / "qualys_data_output_v2.csv", ",", 4, True)

    # The population is the UNION of every source.  The CMDB is only the desktop
    # team's paperwork; a machine nobody recorded still exists, and it is exactly
    # the kind an auditor is asking about.
    population = cmdb | ad | crowd | ecm | qualys

    # BitLocker: 1 means compliant.  Anything else, blank included, means we
    # cannot prove the disk is encrypted.
    bitlocker_off = set()
    with (d / "ecm_hosts.csv").open(newline="", encoding="utf-8", errors="replace") as fh:
        for i, row in enumerate(csv.reader(fh)):
            if i == 0 or len(row) < 5:
                continue
            if row[4].replace("\r", "").strip().strip('"') != "1":
                key = normalize(row[1])
                if key:
                    bitlocker_off.add(key)

    no_ecm = population - ecm
    findings = [
        ("Unique computers in the environment", population,       None),
        ("Missing CrowdStrike (no antivirus)",  population - crowd, "no antivirus agent"),
        ("No user assigned (absent from CMDB)", population - cmdb,  "nobody owns it"),
        ("Not seen by Qualys (never scanned)",  population - qualys, "never scanned"),
        ("Not joined to AD",                    population - ad,     "no AD object"),
        ("BitLocker cannot be validated",       bitlocker_off | no_ecm, "encryption unproven"),
        ("Missing from ECM/SCCM",               no_ecm,              "cannot be patched"),
    ]

    print("=" * 62)
    print(" AUDITOR CHALLENGE, ANSWER KEY")
    print("=" * 62)
    for label, items, _ in findings:
        print(f" {label:<46} {len(items):6}")
    print("=" * 62)
    print()
    print("How each number was reached:")
    print("  population = union of ALL five sources, never the CMDB alone")
    print("  missing X  = in the population but absent from X")
    print("  no user    = no CMDB row exists, so nobody owns the machine")
    print("  bitlocker  = flag is not 1, PLUS machines with no SCCM row at all")

    if args.list:
        for label, items, note in findings[1:]:
            print(f"\n--- {label} ({note}) ---")
            for host in sorted(items)[:40]:
                print(" ", host)
            if len(items) > 40:
                print(f"  ... and {len(items) - 40} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
