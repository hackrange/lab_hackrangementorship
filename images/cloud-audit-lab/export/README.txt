NimbusPay - Cloud Account Configuration Export
==============================================
You are auditing the AWS account of NimbusPay, a small payments startup. Their
lead engineer left, and nobody is sure the account is safe. Below is an export
of the account's configuration. Find what is wrong, prove it from these files,
and write it up.

Layout:
  iam/          identity policies (who can do what)
  s3/           storage bucket policies
  ec2/          virtual machines, their startup scripts, and firewall rules
  cloudtrail/   the account audit-logging configuration
  secrets/      files that were found lying around in the account

Useful tools on this box:  grep -r   jq   less   aws   claude
Tip: read the POLICY, not just the name. A confirmation marker of the form
FLAG-... sits inside the evidence for each real misconfiguration.
