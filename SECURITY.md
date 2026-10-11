# Security

This repository is a **cyber security training lab**.  It contains deliberately
vulnerable code, images and configurations, and fake secrets, all for students
to find and fix.  Install it only in a disposable virtual machine on a private
network.

## Planted secrets are not vulnerabilities

The labs of this course contain made-up credentials on purpose, because finding
them is the exercise:

- the cloud account export carries fake AWS access keys (`AKIA5NIMBUSPAY0ADMIN`
  and friends, for a company that does not exist), a secret written into a
  machine's start up script, and a plaintext key file
- the vulnerable web portal has its own sample database credentials
- the Splunk lab signs in as `admin` / `Changeme123`, and the DAST scanner as
  `admin` / `student`

The last two are weak on purpose. They belong to disposable teaching instances
that exist only inside a lab container on one person's machine, are never
reachable from the internet, and are deleted when the lab stops. They are the
credentials the lessons tell students to type.

None of these are findings. Please do not report them.

## Reporting a real problem

If you find a real vulnerability in the installer, the lab services or the
control panel, please report it privately: use **Security > Report a
vulnerability** on this repository's GitHub page.  Please do not open a public
issue for a security problem.

The Local Lab is meant to run on a private virtual machine for one student.
Its services only answer on private network addresses, and it should never be
exposed to the internet.

Author: Tim Rice
