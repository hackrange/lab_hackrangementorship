The Auditor's Request
=====================

Internal Audit wants proof that every computer in the environment is:

  * joined to Active Directory, with a real user assigned
  * reporting vulnerabilities to Qualys
  * running CrowdStrike antivirus
  * communicating with SCCM/ECM so patches can be deployed
  * protected by BitLocker disk encryption

Six teams sent you six files.  None of them agreed on a format, because in real
life nobody ever does.

  cmdb.csv                   desktop team: which computer belongs to whom
  computer_sid_objects.csv   AD team: every computer object in the domain
  identity.csv               identity team: the user accounts
  ecm_hosts.csv              SCCM: patch status and the BitLocker flag
  qualys_data_output_v2.csv  vulnerability team: what has been scanned
  crowdstrike_output.csv     security team: where antivirus is installed

Look before you leap
--------------------
Run this first, on every file:

  head -3 cmdb.csv
  head -2 computer_sid_objects.csv | cat -A | cut -c1-120

You will find, and none of this is in the file names:

  * Three files have NO HEADER ROW at all.  You cannot look up a column by
    name because there are no names.  Count the fields instead.
  * computer_sid_objects.csv is TILDE separated (~), not comma.
  * Three files use Windows line endings, so every last field ends with an
    invisible carriage return that breaks comparisons.
  * Some CrowdStrike hostnames carry a numeric prefix: 9137P-2LPLLG4 is the
    same machine everyone else calls P-2LPLLG4.
  * Qualys and AD write the full name with a domain, others write the short one.

The two traps that decide your answer
-------------------------------------
1. NORMALIZE before comparing.  Lowercase, drop the domain, strip the leading
   digits, remove the carriage return.  Miss one and the numbers come out wrong
   while still looking completely reasonable.

2. The list of computers is NOT the CMDB.  It is the union of every source.
   A machine nobody wrote down is not missing from the network, only from the
   paperwork, and those are exactly what an auditor is asking about.

Two ways to do it
-----------------
Spreadsheet:  LibreOffice Calc is on the desktop.
Shell:        the Terminal is on the desktop.

Both walkthrough videos are in the lesson.  Try it yourself first.
