#!/usr/bin/env python3
"""
Operation Quiet Vendor: synthetic telemetry for the Splunk investigation lab.

Writes one file per source into an output directory. Splunk ingests each into
its own sourcetype at image build time, so the index is baked into the layers
and the lab starts fast.

The design goal is that the intrusion is REAL but not obvious: every malicious
event sits in a stream of ordinary, believable background traffic, and three
red herrings look suspicious but are innocent. A student reconstructs the story
by correlating across sources, which is the whole skill.

Timestamps are fixed to a single incident day (see INCIDENT_DAY). The lab tells
students to search "All time", because a baked index cannot know when the lab is
being run. Volumes are modest so Splunk Free's 500MB/day limit is never touched.

Deterministic: a fixed seed reproduces every file byte for byte.
Author: Tim Rice
"""

import argparse
import pathlib
import random
from datetime import datetime, timedelta

SEED = 20260722
INCIDENT_DAY = datetime(2026, 6, 15)   # a Monday
DOMAIN = "hackrange"
FQDN = "hackrange.net"

# ---- cast of the drama ------------------------------------------------------
JUMP_HOST = "JUMP01"
FILE_SERVER = "FS01"
DC = "DC01"
VPN_HOST = "VPN01"
# The compromised third-party account (an MSP contractor, ties to Week 6).
VENDOR_USER = "svc-northwind"          # vendor service/VPN account
VENDOR_IP_NORMAL = "203.0.113.40"      # the MSP's normal egress
VENDOR_IP_ATTACK = "45.132.192.77"     # the attacker's VPS, a new ASN
# The service account they Kerberoast and pivot with.
SVC_ACCOUNT = "svc-sqlbackup"
# The unsanctioned SaaS the data goes to (ties to Week 7).
EXFIL_DOMAIN = "filedropzone.io"
EXFIL_IP = "185.199.110.153"

INTERNAL = ["10.20.5.11", "10.20.5.24", "10.20.6.7", "10.20.6.31", "10.20.7.5",
            "10.20.7.42", "10.20.8.15", "10.20.8.90"]
STAFF = ["a.klein", "b.moore", "c.diaz", "e.novak", "f.rossi", "g.haas",
         "h.tan", "i.watts", "k.obrien", "l.frost", "n.reed", "o.sharma"]
HOSTS = ["WKS-101", "WKS-102", "WKS-114", "WKS-120", "WKS-133", "WKS-140",
         JUMP_HOST, FILE_SERVER, DC, VPN_HOST]

rng = random.Random(SEED)


def ts(base, jitter_sec=0):
    t = base + timedelta(seconds=jitter_sec)
    return t.strftime("%Y-%m-%dT%H:%M:%S")


def business_second(day, hour_lo=8, hour_hi=18):
    return day + timedelta(hours=rng.randint(hour_lo, hour_hi),
                           minutes=rng.randint(0, 59), seconds=rng.randint(0, 59))


class Sink:
    def __init__(self, out, name):
        self.rows = []
        self.path = out / name

    def add(self, when, line):
        self.rows.append((when, line))

    def flush(self):
        # Sort by time so the file reads chronologically, like a real log.
        self.rows.sort(key=lambda r: r[0])
        with self.path.open("w") as fh:
            for _, line in self.rows:
                fh.write(line + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="/mnt/build/data")
    args = ap.parse_args()
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    win = Sink(out, "windows_security.log")     # key=value Windows events
    sysmon = Sink(out, "sysmon.log")
    vpn = Sink(out, "vpn.log")
    dns = Sink(out, "dns.log")
    proxy = Sink(out, "proxy.log")
    fw = Sink(out, "firewall.log")
    linux = Sink(out, "linux_auth.log")
    web = Sink(out, "webserver.log")
    mail = Sink(out, "mail_gateway.log")

    def wevt(host, eid, when, **kv):
        parts = [f'timestamp={ts(when)}', f'Computer={host}', f'EventCode={eid}']
        parts += [f'{k}={v}' for k, v in kv.items()]
        win.add(when, " ".join(parts))

    # ========================================================================
    # BACKGROUND NOISE across the incident day and the days around it, so the
    # incident is not the only thing in the index.
    # ========================================================================
    for d in range(-2, 1):
        day = INCIDENT_DAY + timedelta(days=d)
        # normal logons
        for _ in range(rng.randint(120, 180)):
            u = rng.choice(STAFF)
            h = rng.choice(HOSTS[:6])
            when = business_second(day)
            wevt(h, 4624, when, LogonType=2, TargetUserName=u,
                 IpAddress=rng.choice(INTERNAL), AuthenticationPackage="Kerberos")
        # a few failed logons (fat fingers)
        for _ in range(rng.randint(8, 16)):
            wevt(rng.choice(HOSTS[:6]), 4625, business_second(day),
                 TargetUserName=rng.choice(STAFF), IpAddress=rng.choice(INTERNAL),
                 Status="0xC000006A")
        # normal process creation
        for _ in range(rng.randint(200, 300)):
            when = business_second(day)
            h = rng.choice(HOSTS[:6])
            img = rng.choice([r"C:\Windows\System32\cmd.exe",
                              r"C:\Program Files\Microsoft Office\WINWORD.EXE",
                              r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
                              r"C:\Program Files\Google\Chrome\chrome.exe"])
            wevt(h, 4688, when, NewProcessName=img, SubjectUserName=rng.choice(STAFF))
        # normal DNS
        for _ in range(rng.randint(300, 400)):
            when = business_second(day)
            name = rng.choice(["outlook.office365.com", "teams.microsoft.com",
                               "www.google.com", "github.com", "salesforce.com",
                               "cdn.jsdelivr.net", "windowsupdate.com"])
            dns.add(when, f'{ts(when)} client={rng.choice(INTERNAL)} query={name} type=A rcode=NOERROR')
        # normal proxy
        for _ in range(rng.randint(250, 350)):
            when = business_second(day)
            host = rng.choice(["outlook.office365.com", "teams.microsoft.com",
                               "salesforce.com", "github.com", "zoom.us"])
            proxy.add(when, f'{ts(when)} user={rng.choice(STAFF)} src={rng.choice(INTERNAL)} '
                            f'method=GET dest={host} bytes_out={rng.randint(300,3000)} '
                            f'bytes_in={rng.randint(800,60000)} status=200')
        # normal vendor VPN: the MSP connects during the day, reaches only the jump host
        for _ in range(rng.randint(2, 4)):
            when = business_second(day, 9, 17)
            vpn.add(when, f'{ts(when)} action=connect user={VENDOR_USER} src_ip={VENDOR_IP_NORMAL} '
                          f'asn=AS64500 country=US assigned_ip=10.20.99.20 result=success')
            # and only talks to the jump host
            fw.add(when, f'{ts(when)} src=10.20.99.20 dst={JUMP_HOST} dport=3389 action=allow proto=tcp')
        # normal linux
        for _ in range(rng.randint(40, 70)):
            when = business_second(day)
            linux.add(when, f'{ts(when)} dvc={FILE_SERVER} sshd[{rng.randint(1000,9999)}]: '
                            f'Accepted publickey for backupsvc from 10.20.5.11 port {rng.randint(30000,60000)} ssh2')
        # normal web
        for _ in range(rng.randint(150, 220)):
            when = business_second(day)
            web.add(when, f'{rng.choice(INTERNAL)} - - [{when.strftime("%d/%b/%Y:%H:%M:%S +0000")}] '
                          f'"GET /portal/home HTTP/1.1" 200 {rng.randint(500,9000)}')
        # normal mail
        for _ in range(rng.randint(80, 120)):
            when = business_second(day)
            mail.add(when, f'{ts(when)} from={rng.choice(STAFF)}@partner.example.com '
                           f'to={rng.choice(STAFF)}@{FQDN} subject="RE: project update" '
                           f'action=delivered spam_score={rng.randint(0,3)}')

    # ========================================================================
    # THE INCIDENT. All times on INCIDENT_DAY unless noted.
    # ========================================================================
    day = INCIDENT_DAY

    # -- Step 1: the phish, three days earlier, at the MSP contractor ---------
    phish_day = INCIDENT_DAY - timedelta(days=3)
    when = phish_day + timedelta(hours=14, minutes=22)
    mail.add(when, f'{ts(when)} from=it-support@microsoft-verify.com '
                   f'to={VENDOR_USER}@northwind-msp.com '
                   f'subject="Action required: reauthenticate your VPN certificate" '
                   f'url=https://microsoft-verify.com/sso/vpn action=delivered spam_score=6 '
                   f'note="external lookalike domain"')

    # -- Step 2: vendor VPN logs in at 02:14 from a NEW ASN ------------------
    t_login = day + timedelta(hours=2, minutes=14)
    vpn.add(t_login, f'{ts(t_login)} action=connect user={VENDOR_USER} src_ip={VENDOR_IP_ATTACK} '
                     f'asn=AS200651 country=RO assigned_ip=10.20.99.20 result=success '
                     f'note="first connection from this ASN"')
    # they RDP to the jump host
    wevt(JUMP_HOST, 4624, t_login + timedelta(seconds=40), LogonType=10,
         TargetUserName=VENDOR_USER, IpAddress="10.20.99.20", AuthenticationPackage="Negotiate")
    fw.add(t_login + timedelta(seconds=30), f'{ts(t_login)} src=10.20.99.20 dst={JUMP_HOST} '
           f'dport=3389 action=allow proto=tcp')

    # -- Step 3: AD enumeration from the jump host ---------------------------
    base = t_login + timedelta(minutes=6)
    for i, (img, cmd) in enumerate([
        (r"C:\Windows\System32\net.exe", "net group \"Domain Admins\" /domain"),
        (r"C:\Windows\System32\net.exe", "net user /domain"),
        (r"C:\Windows\System32\nltest.exe", "nltest /domain_trusts"),
        (r"C:\Windows\System32\whoami.exe", "whoami /groups"),
        (r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe",
         "Get-ADUser -Filter * -Properties servicePrincipalName"),
    ]):
        w = base + timedelta(minutes=i * 2, seconds=rng.randint(0, 40))
        wevt(JUMP_HOST, 4688, w, NewProcessName=img, SubjectUserName=VENDOR_USER,
             CommandLine=f'"{cmd}"')
        sysmon.add(w, f'{ts(w)} Computer={JUMP_HOST} EventID=1 Image={img} '
                      f'User={DOMAIN}\\{VENDOR_USER} CommandLine="{cmd}"')

    # -- Step 4: Kerberoasting -- RC4 (0x17) service ticket for svc-sqlbackup -
    t_kerb = base + timedelta(minutes=14)
    wevt(DC, 4769, t_kerb, ServiceName=SVC_ACCOUNT, TicketEncryptionType="0x17",
         TargetUserName=VENDOR_USER, IpAddress="10.20.99.20",
         note="RC4_requested_for_SPN")
    sysmon.add(t_kerb + timedelta(seconds=90), f'{ts(t_kerb)} Computer={JUMP_HOST} EventID=1 '
               f'Image=C:\\Users\\{VENDOR_USER}\\rubeus.exe User={DOMAIN}\\{VENDOR_USER} '
               f'CommandLine="rubeus.exe kerberoast /outfile:hashes.txt"')

    # -- Step 5: lateral movement to the file server as the service account --
    t_lat = t_kerb + timedelta(minutes=22)
    wevt(FILE_SERVER, 4624, t_lat, LogonType=3, TargetUserName=SVC_ACCOUNT,
         IpAddress="10.20.99.20", AuthenticationPackage="Kerberos", note="SMB_from_jump")
    fw.add(t_lat, f'{ts(t_lat)} src=10.20.99.20 dst={FILE_SERVER} dport=445 action=allow proto=tcp')
    # NFS no_root_squash abuse on the file server (ties to Week 3)
    t_nfs = t_lat + timedelta(minutes=4)
    linux.add(t_nfs, f'{ts(t_nfs)} dvc={FILE_SERVER} rpc.mountd[2211]: '
                     f'authenticated mount request from 10.20.99.20:783 for /export/finance (/export/finance)')
    linux.add(t_nfs + timedelta(seconds=20), f'{ts(t_nfs)} dvc={FILE_SERVER} kernel: '
              f'nfsd: client 10.20.99.20 mounted /export/finance rw,no_root_squash')
    linux.add(t_nfs + timedelta(minutes=1), f'{ts(t_nfs)} dvc={FILE_SERVER} audit: '
              f'uid=0 euid=0 path=/export/finance/payroll_2026.xlsx op=read note=root_access_via_no_root_squash')

    # -- Step 6: persistence -- scheduled task + privileged group add --------
    t_persist = t_lat + timedelta(minutes=15)
    wevt(FILE_SERVER, 4688, t_persist, NewProcessName=r"C:\Windows\System32\schtasks.exe",
         SubjectUserName=SVC_ACCOUNT,
         CommandLine='"schtasks /create /tn UpdateSync /tr C:\\Windows\\Temp\\us.exe /sc onstart /ru SYSTEM"')
    # new member added to a privileged group (4732)
    wevt(DC, 4732, t_persist + timedelta(minutes=2), TargetUserName="Administrators",
         MemberName=SVC_ACCOUNT, SubjectUserName=VENDOR_USER, note="privileged_group_add")
    # new account created too (4720)
    wevt(DC, 4720, t_persist + timedelta(minutes=3), TargetUserName="svc-helpdesk2",
         SubjectUserName=VENDOR_USER)

    # -- Step 7: collection -- large archive staged at 04:40 -----------------
    t_stage = day + timedelta(hours=4, minutes=40)
    wevt(FILE_SERVER, 4688, t_stage, NewProcessName=r"C:\Windows\System32\cmd.exe",
         SubjectUserName=SVC_ACCOUNT,
         CommandLine='"7z a -tzip C:\\Windows\\Temp\\archive.zip \\\\FS01\\finance\\*"')
    sysmon.add(t_stage + timedelta(seconds=30), f'{ts(t_stage)} Computer={FILE_SERVER} EventID=11 '
               f'Image=7z.exe TargetFilename=C:\\Windows\\Temp\\archive.zip note=file_created size=1980321044')

    # -- Step 8: exfiltration -- chunked HTTPS to an unsanctioned SaaS -------
    t_exfil = t_stage + timedelta(minutes=18)
    dns.add(t_exfil - timedelta(seconds=5),
            f'{ts(t_exfil)} client={FILE_SERVER} query={EXFIL_DOMAIN} type=A rcode=NOERROR answer={EXFIL_IP}')
    for i in range(14):  # chunked to stay under thresholds
        w = t_exfil + timedelta(minutes=i * 3, seconds=rng.randint(0, 40))
        proxy.add(w, f'{ts(w)} user={SVC_ACCOUNT} src={FILE_SERVER} method=POST dest={EXFIL_DOMAIN} '
                     f'bytes_out={rng.randint(140_000_000, 150_000_000)} bytes_in={rng.randint(200,800)} '
                     f'status=200 note=large_upload')
        fw.add(w, f'{ts(w)} src={FILE_SERVER} dst={EXFIL_IP} dport=443 action=allow proto=tcp '
                  f'bytes={rng.randint(140_000_000,150_000_000)}')

    # -- Step 9: anti-forensics -- security log cleared on the file server ---
    t_clear = t_exfil + timedelta(minutes=52)
    wevt(FILE_SERVER, 1102, t_clear, SubjectUserName=SVC_ACCOUNT,
         note="audit_log_cleared")

    # ========================================================================
    # RED HERRINGS: suspicious-looking but innocent.
    # ========================================================================
    # (a) scheduled Qualys vuln scan sweeps the network -- looks like enumeration
    t_q = day + timedelta(hours=1, minutes=0)
    for h in INTERNAL:
        w = t_q + timedelta(seconds=rng.randint(0, 600))
        fw.add(w, f'{ts(w)} src=10.20.250.10 dst={h} dport={rng.choice([22,80,443,445,3389])} '
                  f'action=allow proto=tcp note=qualys_scanner')
        wevt(rng.choice(HOSTS[:6]), 4625, w, TargetUserName="qualys_scan",
             IpAddress="10.20.250.10", Status="0xC000006A")

    # (b) a developer legitimately pushes a big build artifact to cloud storage
    t_dev = day + timedelta(hours=15, minutes=12)
    dns.add(t_dev, f'{ts(t_dev)} client=10.20.6.7 query=storage.googleapis.com type=A rcode=NOERROR')
    proxy.add(t_dev, f'{ts(t_dev)} user=c.diaz src=10.20.6.7 method=PUT dest=storage.googleapis.com '
                     f'bytes_out=890000000 bytes_in=400 status=200 note=ci_build_artifact')

    # (c) internet SSH brute force that never succeeds
    for _ in range(rng.randint(60, 90)):
        w = day + timedelta(hours=rng.randint(0, 23), minutes=rng.randint(0, 59), seconds=rng.randint(0, 59))
        linux.add(w, f'{ts(w)} dvc={VPN_HOST} sshd[{rng.randint(1000,9999)}]: '
                     f'Failed password for {rng.choice(["root","admin","test","oracle"])} '
                     f'from {rng.choice(["61.177.172.13","218.92.0.34","112.85.42.8"])} '
                     f'port {rng.randint(30000,60000)} ssh2')

    for s in [win, sysmon, vpn, dns, proxy, fw, linux, web, mail]:
        s.flush()

    total = sum(len(s.rows) for s in [win, sysmon, vpn, dns, proxy, fw, linux, web, mail])
    print(f"wrote {total} events across 9 sources to {out}")
    print(f"incident day: {INCIDENT_DAY:%Y-%m-%d}")
    print("--- answer key ---")
    print(f"  patient zero (phished MSP contractor): {VENDOR_USER}@northwind-msp.com")
    print(f"  compromised vendor account: {VENDOR_USER}")
    print(f"  initial access time: {t_login:%Y-%m-%d %H:%M} from {VENDOR_IP_ATTACK} (AS200651, RO)")
    print(f"  escalation: Kerberoast of {SVC_ACCOUNT} (RC4/0x17 ticket, EventCode 4769)")
    print(f"  persistence: schtasks UpdateSync + {SVC_ACCOUNT} added to Administrators (4732)")
    print(f"  exfil channel: HTTPS POST to {EXFIL_DOMAIN} ({EXFIL_IP}), ~2GB chunked")
    print(f"  anti-forensics: security log cleared on {FILE_SERVER} (EventCode 1102)")
    print(f"  dwell time: phish {phish_day:%m-%d} -> exfil {t_exfil:%m-%d %H:%M}")


if __name__ == "__main__":
    main()
