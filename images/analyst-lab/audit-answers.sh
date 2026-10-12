#!/bin/bash
# Solve the auditor challenge from the shell, showing the working.
#
# Instructor answer key, and the worked example behind the bash walkthrough.  It
# prints the reasoning for each number rather than just the number, because the
# method is the point.
#
# The real exports are deliberately inconsistent, which is the whole lesson:
#
#   cmdb.csv                  comma, NO HEADER   host,firstname,lastname
#   computer_sid_objects.csv  TILDE, NO HEADER   class~host~fqdn~DN~...
#   crowdstrike_output.csv    comma, NO HEADER   host,rfc1918,publicip,os,mac,...
#   ecm_hosts.csv             comma, header, CRLF   utc,hn,status,os,bitlocker
#   identity.csv              comma, header, CRLF   fname,lname,email,userid
#   qualys_data_output_v2.csv comma, header, CRLF   publicip,time,rfc1918,fqdn,hostname,status,os
#
# Three traps are baked into the data:
#   1. Three files have no header at all, so "find the column by name" does not
#      work and you have to count fields.
#   2. Some CrowdStrike hostnames carry a numeric prefix (9137P-2LPLLG4), so they
#      never match the same machine elsewhere (P-2LPLLG4) until you strip it.
#   3. Qualys and AD carry a domain suffix, and three files use CRLF line
#      endings, so a stray \r silently breaks comparisons.
#
# Usage:  lab-audit-answers            summary
#         lab-audit-answers --show     also print the commands
# Author: Tim Rice - tim.j.rice@hackrange.com
set -u

DIR="${AUDIT_DIR:-/home/student/audit}"
SHOW=0
[ "${1:-}" = "--show" ] && SHOW=1

cd "$DIR" 2>/dev/null || { echo "No $DIR" >&2; exit 1; }
for f in cmdb.csv computer_sid_objects.csv ecm_hosts.csv \
         qualys_data_output_v2.csv crowdstrike_output.csv identity.csv; do
    [ -f "$f" ] || { echo "Missing $DIR/$f" >&2; exit 1; }
done

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Normalize one field to a comparable key: strip quotes and CR, drop the domain,
# strip any leading digits (CrowdStrike), lowercase.
# $1 file  $2 delimiter  $3 field number  $4 lines to skip (1 if it has a header)
key() {
    awk -F"$2" -v f="$3" -v skip="$4" '
        NR<=skip { next }
        $f != "" {
            v=$f
            gsub(/\r/, "", v); gsub(/^"|"$/, "", v)
            sub(/\..*$/, "", v)      # drop domain
            sub(/^[0-9]+/, "", v)    # drop CrowdStrike numeric prefix
            if (v != "") print tolower(v)
        }' "$1" | sort -u
}

key cmdb.csv                  ,    1 0 > "$TMP/cmdb"    # no header
key computer_sid_objects.csv  '~'  2 0 > "$TMP/ad"      # tilde, no header
key crowdstrike_output.csv    ,    1 0 > "$TMP/cs"      # no header
key ecm_hosts.csv             ,    2 1 > "$TMP/ecm"     # header
key qualys_data_output_v2.csv ,    5 1 > "$TMP/qualys"  # header

# The population is the UNION of every source.  The CMDB is only the desktop
# team's paperwork; machines nobody wrote down are exactly what the auditor wants.
cat "$TMP"/cmdb "$TMP"/ad "$TMP"/ecm "$TMP"/qualys "$TMP"/cs | sort -u > "$TMP/all"
missing() { comm -23 "$TMP/all" "$TMP/$1" | wc -l; }

# BitLocker: 1 means compliant.  Anything else, including blank, means we cannot
# prove the disk is encrypted.
awk -F, 'NR>1 && $2!="" { v=$5; gsub(/\r|"/,"",v); if (v!="1") { h=$2; gsub(/\r|"/,"",h); sub(/\..*$/,"",h); print tolower(h) } }' \
    ecm_hosts.csv | sort -u > "$TMP/bl_off"
comm -23 "$TMP/all" "$TMP/ecm" > "$TMP/no_ecm"
cat "$TMP/bl_off" "$TMP/no_ecm" | sort -u > "$TMP/bl_unproven"

echo "=============================================================="
echo " AUDITOR CHALLENGE, ANSWER KEY"
echo "=============================================================="
printf ' %-46s %6d\n' "Unique computers in the environment"   "$(wc -l < "$TMP/all")"
printf ' %-46s %6d\n' "Missing CrowdStrike (no antivirus)"    "$(missing cs)"
printf ' %-46s %6d\n' "No user assigned (absent from CMDB)"   "$(missing cmdb)"
printf ' %-46s %6d\n' "Not seen by Qualys (never scanned)"    "$(missing qualys)"
printf ' %-46s %6d\n' "Not joined to AD"                      "$(missing ad)"
printf ' %-46s %6d\n' "BitLocker cannot be validated"         "$(wc -l < "$TMP/bl_unproven")"
printf ' %-46s %6d\n' "Missing from ECM/SCCM"                 "$(missing ecm)"
echo "=============================================================="
echo
echo "How each number was reached:"
echo "  population = union of ALL five sources, never the CMDB alone"
echo "  missing X  = in the population but absent from X"
echo "  no user    = no CMDB row exists, so nobody owns the machine"
echo "  bitlocker  = flag is not 1, PLUS machines absent from SCCM entirely"
echo
echo "Normalization is what makes it work: drop the domain, strip the leading"
echo "digits some CrowdStrike names carry, remove CR from the CRLF files, and"
echo "lowercase everything.  Skip any one of those and the counts come out"
echo "wrong in a way that still looks completely believable."

if [ "$SHOW" -eq 1 ]; then
    cat <<'EOS'

--------------------------------------------------------------
The same thing, one line at a time
--------------------------------------------------------------
# normalize: field $2 of file $1, drop domain + leading digits, lowercase
k() { awk -F"$2" -v f="$3" -v s="$4" 'NR>s && $f!=""{v=$f; gsub(/\r|"/,"",v); sub(/\..*$/,"",v); sub(/^[0-9]+/,"",v); if(v!="")print tolower(v)}' "$1" | sort -u; }

k cmdb.csv                  ,   1 0 > cmdb      # no header
k computer_sid_objects.csv  '~' 2 0 > ad        # TILDE separated
k crowdstrike_output.csv    ,   1 0 > cs        # no header
k ecm_hosts.csv             ,   2 1 > ecm       # has header
k qualys_data_output_v2.csv ,   5 1 > qualys    # has header

cat cmdb ad ecm qualys cs | sort -u > all   # the true population
wc -l < all                                 # unique computers

comm -23 all cs     | wc -l                 # no antivirus
comm -23 all cmdb   | wc -l                 # no user assigned
comm -23 all qualys | wc -l                 # never scanned
comm -23 all ad     | wc -l                 # not in AD
comm -23 all ecm    | wc -l                 # missing from SCCM

--------------------------------------------------------------
In LibreOffice Calc or Excel
--------------------------------------------------------------
1. Import each file, choosing the RIGHT delimiter:
     computer_sid_objects.csv is tilde (~), the rest are comma.
     cmdb / AD / CrowdStrike have NO header row, so untick
     "column heading in first line" or you lose a machine.
   Set the hostname column type to Text, or names like 1E9 turn
   into numbers.
2. Add a key column to every sheet so the names match:
     =LOWER(TRIM(SUBSTITUTE(A2,".hackrange.net","")))
   For CrowdStrike, also strip the leading digits.
3. Stack every key column on a Master sheet, then remove duplicates.
4. Ask each system whether it knows the machine:
     =IF(ISNA(VLOOKUP($A2,cs.$K$2:$K$2000,1,0)),"MISSING","ok")
5. Total each column with COUNTIF(range,"MISSING").
6. BitLocker is two-part: flag not 1, plus machines with no SCCM row.
EOS
fi
