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
run as x86 under emulation. Everything else is unaffected.

Measured on the same lab on both kinds of machine:

| | ARM, emulated | x86, native |
|---|---|---|
| Splunk ready to answer, from starting the lab | 163 s | a few seconds |
| Splunk serving a page | 13 ms | 1 ms |
| a search counting events by sourcetype | 3.9 s | 0.3 s |

This lab does work on an ARM machine. What it needs is patience at the start:
give it about three minutes after starting it before Splunk will answer at all,
where natively it is ready in seconds. The panel's card for it says so, and so
does `hackrange-lab start`.

After that it is responsive enough to work in. Splunk itself is roughly twelve
times slower and still perfectly workable: a search that answers in a third of
a second on an x86 machine answers in about four.

You can also open Splunk from the browser you are already using, at port 8000
on the machine running the lab, which keeps all the drawing on your own
machine:

    http://<the address of the Ubuntu machine>:8000

`hackrange-lab env` prints that address next to the Splunk login, and
`show_information.sh` lists it whenever the Splunk lab is running. On an ARM
machine the panel's button for this card opens that address for you rather than
opening the lab's desktop, because this is the way to use this lab here.

Use your own browser for this lab on an ARM machine. The lab's desktop is not
worth your time here: every frame of it is drawn under emulation, which is slow
enough to be practically unusable, and the lessons for these weeks all work
inside Splunk's own pages in any case. The other six labs are unaffected and
open normally.

## Using it

There are two ways to use the lab, and they do the same things.  Use whichever
you prefer; nothing is only available in one of them.

### The control panel, in a web browser

```
https://<the address of the Ubuntu machine>:8456/control/
```

That is also what the plain address answers, so `https://<the machine>:8456`
is enough.  Sign in as `student` with the lab password, which
`show_information.sh` prints on the Ubuntu machine.

The panel has a card for each of the seven labs.  A card starts its lab, opens
it in the browser, marks your work in it, and ends it.  Above the cards are the
machine's processor, memory, disk and network, and your login with the password
hidden until you ask for it.

One lab runs at a time, because there is one web desktop for it to answer on.
Starting a lab therefore ends the one before it and deletes everything in it,
and the panel says so before it does it.

A lab takes a minute or two to be ready, and a desktop lab longer than a
terminal one.  Its card says **Preparing** until the lab will really let you
in, and only then offers the button to open it, so the button is never a
promise the lab cannot keep.  Starting a lab does not change your password and
does not sign you out, of the panel or of the web desktop.

**Open the lab** does not ask for your password again.  You gave it to the
panel, so the panel spends it on your behalf and the lab opens signed in.

### The terminal

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
same username (`student`) and the same password. The password is made when you
install the lab and lasts until you ask for a new one with `hackrange-lab
reset`, which is what to run if you think somebody saw it:

- **a web browser**, at `https://<this machine>:8456`, with nothing to install
- **SSH**, on port 2223
- **Remote Desktop**, on port 13489

The browser opens whatever the running lab actually is: a desktop for the
analyst, Splunk and Week 11 challenge labs, and a terminal for the rest. The
one exception is the Splunk lab on an ARM machine, where the panel opens Splunk
itself instead of the lab's desktop, for the reason given above.

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

`tests/doors.sh` checks the other half, which is everything between you and a
lab: the published ports, the control panel, signing in, and whether **Open the
lab** really opens it.  It runs against this install rather than a throwaway
container, because that gap is where the faults a student meets first have
lived.

```
sudo tests/doors.sh               the lab that is running
sudo tests/doors.sh splunk        start that lab first, then check
```

## Reporting a problem

Security issues: see [SECURITY.md](SECURITY.md). Anything else: open an issue,
and attach the file `hackrange-lab diag` writes, which is redacted.

Author: Tim Rice - tim.j.rice@hackrange.com
