# Hackrange Mentorship: the Local Lab

Every hands-on lab from the **Hackrange Mentorship** course, installed on a
machine of your own with one command.

The hosted labs run in your browser and need nothing but a login. This is the
same set of labs on your own virtual machine, for working offline, keeping a
lab running for days, or simply seeing how the whole thing is put together.

## Installing it

On an Ubuntu 22.04 or newer machine:

```
curl -fsSL https://raw.githubusercontent.com/hackrange/lab_hackrangementorship/main/install.sh | sudo bash
```

That is all of it. The installer checks the machine, installs Docker if it is
missing, builds the lab images, and sets up the web desktop. Run the same
command again at any time to update the lab or to finish an install that
stopped partway: each step checks what is already there.

Everything lands in `/opt/hackrange-mentorship`, with settings in
`/etc/hackrange-mentorship` and a log at
`/var/log/hackrange-mentorship-install.log`.

### What the machine needs

|          | minimum | recommended |
| -------- | ------- | ----------- |
| processors | 2 | 4 |
| memory   | 8 GB | 16 GB |
| free disk | 60 GB | 100 GB |

One lab runs at a time, and the largest asks for 3GB of memory. The disk goes
mostly on the lab images, which come to about 15GB once built, with room for
the downloads the build pulls in.

### On an Apple Silicon or other ARM machine

Six of the seven labs run natively. The Splunk labs (weeks 8 to 10) cannot:
Splunk publishes no ARM build for Linux at all, so that one image is built and
run as x86 under emulation. It works, and it is slower. Everything else is
unaffected.

## Using it

```
hackrange-lab list              the labs, and the course weeks each one is for
hackrange-lab start netlab      start the lab your lesson names
hackrange-lab info              how to get in: web address, username, password
hackrange-lab env               the lab's own usernames and passwords
hackrange-lab check             mark your own findings against the answer key
hackrange-lab stop              end the lab
hackrange-lab status            is everything running?
hackrange-lab update            get the latest version
hackrange-lab diag              save a diagnostics file to send for help
```

### The labs

| lab | weeks | what it is for |
| --- | ----- | -------------- |
| `kali` | 1 | Networking foundations: addresses, subnets, IPv6, reading a machine |
| `netlab` | 2-4 | DNS, routing, the firewall, server hardening and the CIS Controls |
| `analyst` | 5-7 | Audit evidence, and hunting shadow SaaS and shadow AI |
| `splunk` | 8-10 | Splunk: first searches, Operation Quiet Vendor, detection engineering |
| `webapp` | 11 | Source-driven web app review with AI |
| `webapp-gui` | 11 | The AI-assisted security review: desktop, Burp, and a DAST scanner |
| `cloud` | 12 | Auditing a misconfigured cloud account |

Each lab is a separate machine, and one runs at a time. Starting another swaps
it over. A lab is disposable: stopping it deletes it and everything inside, so
anything you want to keep belongs on your own machine.

### Getting in

`hackrange-lab info` prints the ways in. There are three, and they all use the
same username (`student`) and the same password, which changes every time you
start a lab:

- **a web browser**, at `https://<this machine>:8456` — nothing to install
- **SSH**, on port 2223
- **Remote Desktop**, on port 13489

The browser opens whatever the running lab actually is: a desktop for the
analyst, Splunk and Week 11 challenge labs, and a terminal for the rest.

All three answer only on private networks, never from the internet, whatever
the password. If you forward one of these ports on your router, the connection
arrives from a public address and is refused.

### The certificate warning

The web desktop is served with a certificate from this machine's own
certificate authority, so a browser will warn you the first time. To make the
warning go away, download `https://<this machine>:8456/lab-ca.crt` and tell
your own computer to trust it. That authority is constrained: it can vouch only
for lab names and private addresses, never for a real website, so trusting it
cannot be used against you elsewhere.

### Checking your work

Two of the challenges hide a marker behind each real finding, reachable only by
exploiting or locating it properly. Write what you find in `~/findings.txt`
inside the lab, then:

```
hackrange-lab check
```

It tells you how many of them you have, and describes what is still missing in
plain words rather than printing the answer. When you want the key in full,
`hackrange-lab check <lab> --reveal`.

The other challenges are a piece of reasoning rather than a string to find, and
those labs carry the instructor's own answer key: `check` runs it so you can
compare your working to it.

## Deliberately fake credentials

This is a training lab, so some of what is inside looks alarming and is not.
The cloud account export contains invented AWS access keys for a company that
does not exist, the vulnerable portal has sample database credentials, and two
labs hand you a weak login on purpose: Splunk as `admin` / `Changeme123`, and
the DAST scanner as `admin` / `student`.

Those two are the logins the lessons tell you to use. They belong to throwaway
instances that live inside a lab container on this machine, answer only inside
it, and are deleted when you stop the lab. Nothing there is a real secret, and
none of it reaches the internet.

## Removing it

```
sudo /opt/hackrange-mentorship/uninstall.sh
```

## Testing a change

`tests/rehearse.sh` starts every lab the way a student meets it and asks the
questions its lessons depend on: does the door open, is the tool the lesson
names installed, does the command the lesson prints return something real.

```
sudo tests/rehearse.sh            every lab
sudo tests/rehearse.sh netlab     one of them
```

## Reporting a problem

Security issues: see [SECURITY.md](SECURITY.md). Anything else: open an issue,
and attach the file `hackrange-lab diag` writes, which is redacted.

Author: Tim Rice - tim.j.rice@hackrange.com
