#!/bin/bash
# Solve the Shadow SaaS / Shadow AI challenge from the shell, showing the working.
#
# Instructor answer key and the worked example behind the walkthrough. Same
# reconciliation shape as the auditor challenge: a big messy log, an allowlist,
# and the finding is the gap. The extra move here is the upload signal, summing
# outbound bytes on POST/PUT to see who is not just visiting a tool but pouring
# data into it.
#
# Usage:  lab-shadow-answers            summary
#         lab-shadow-answers --show     also print the commands
# Author: Tim Rice - tim.j.rice@hackrange.com
set -u

# secure_path lacks /usr/local/bin under sudo; the file is world-readable so no
# elevation is needed, but keep the pattern consistent with the other helpers.
DIR="${AUDIT_DIR:-/home/student/audit}"
SHOW=0
[ "${1:-}" = "--show" ] && SHOW=1

cd "$DIR" 2>/dev/null || { echo "No $DIR" >&2; exit 1; }
for f in proxy_log.csv sanctioned_domains.csv; do
    [ -f "$f" ] || { echo "Missing $DIR/$f" >&2; exit 1; }
done

# Known internet noise: real but not "shadow IT tools". A student separates
# these by judgement; the key just hard-codes them so the counts are exact.
NOISE="cdn.jsdelivr.net fonts.googleapis.com www.bing.com en.wikipedia.org \
stackoverflow.com npmjs.org pypi.org aws.amazon.com azure.microsoft.com \
docs.python.org news.ycombinator.com reddit.com linkedin.com"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# host column (url is field 5): strip scheme and path, lowercase.
seen_hosts() {
    tail -n +2 proxy_log.csv | cut -d, -f5 \
      | sed -E 's#https?://([^/]+).*#\1#' | tr 'A-Z' 'a-z' | sort -u
}
seen_hosts > "$TMP/seen"
tail -n +2 sanctioned_domains.csv | cut -d, -f1 | tr 'A-Z' 'a-z' | sort -u > "$TMP/approved"
printf '%s\n' $NOISE | sort -u > "$TMP/noise"

# unsanctioned = seen - approved - noise
comm -23 "$TMP/seen" "$TMP/approved" | comm -23 - "$TMP/noise" > "$TMP/shadow"

# AI services among the shadow set (by name pattern).
grep -Ei 'openai|chatgpt|claude|gemini|copilot|huggingface|perplexity|characterai|anthropic|\.ai$' \
    "$TMP/shadow" | sort -u > "$TMP/ai"
comm -23 "$TMP/shadow" "$TMP/ai" > "$TMP/saas"

echo "=============================================================="
echo " SHADOW IT DISCOVERY, ANSWER KEY"
echo "=============================================================="
printf ' %-42s %4d\n' "Unsanctioned tools (excluding noise)"  "$(wc -l < "$TMP/shadow")"
printf ' %-42s %4d\n' "  of which shadow SaaS"                "$(wc -l < "$TMP/saas")"
printf ' %-42s %4d\n' "  of which shadow AI"                  "$(wc -l < "$TMP/ai")"
echo "--------------------------------------------------------------"
echo " Shadow AI services in use:"
sed 's/^/   /' "$TMP/ai"
echo "--------------------------------------------------------------"
echo " Top uploaders to unsanctioned destinations (MB out):"
# For each POST/PUT row whose host is in the shadow set, add bytes_sent (field 7)
# to that user (field 3).
awk -F, 'NR==FNR{shadow[$1]=1; next}
         FNR==1{next}
         ($4=="POST"||$4=="PUT"){
            h=$5; sub(/^https?:\/\//,"",h); sub(/\/.*$/,"",h); h=tolower(h)
            if (h in shadow) up[$3]+=$7
         }
         END{ for (u in up) printf "%s %d\n", u, up[u] }' \
    "$TMP/shadow" proxy_log.csv \
  | sort -k2 -nr | head -3 \
  | awk '{ printf "   %-14s %6.1f MB\n", $1, $2/1048576 }'
echo "=============================================================="
echo
echo "Method: pull hosts from the log, subtract the sanctioned list and the"
echo "obvious noise, then split AI from SaaS by name.  The upload ranking uses"
echo "bytes_sent on POST/PUT only, because visiting a tool is not the same as"
echo "pouring data into it.  The heaviest uploader is the first conversation."

if [ "$SHOW" -eq 1 ]; then
    cat <<'EOS'

--------------------------------------------------------------
The same thing, one step at a time
--------------------------------------------------------------
# every host that appears
tail -n +2 proxy_log.csv | cut -d, -f5 \
  | sed -E 's#https?://([^/]+).*#\1#' | sort -u > seen

# the sanctioned allowlist
tail -n +2 sanctioned_domains.csv | cut -d, -f1 | sort -u > approved

# what is unsanctioned (then eyeball out the news/font/package noise)
comm -23 seen approved

# who uploads the most to a given shadow host
awk -F, '$4=="POST" || $4=="PUT" {print $3, $7}' proxy_log.csv \
  | awk '{u[$1]+=$2} END{for(k in u) print u[k], k}' | sort -nr | head
EOS
fi
