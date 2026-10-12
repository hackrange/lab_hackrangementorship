#!/usr/bin/env bash
# Meet every lab the way a student does, in a disposable container.
#
# A lab that builds is not a lab that works.  The hosted course learned this
# repeatedly: a desktop whose session never started, a launcher split on an
# unquoted space, a lesson's first command running with an empty variable
# because a desktop terminal is not a login shell.  None of those show up in a
# build log, and all of them are the first thing a student meets.
#
# So each lab is started here with the SAME capabilities, ports and
# environment the launcher gives it, and then asked the questions its lessons
# depend on: does the door open, does the tool the lesson names exist, does the
# command the lesson prints actually return something.
#
# Usage:  tests/rehearse.sh [lab ...]     (default: every lab in the catalog)
#         BUILD=1 tests/rehearse.sh       build each image from source first
#
# Author: Tim Rice - tim.j.rice@hackrange.com
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$HERE/config/labs.conf"
# The capabilities and budgets a lab runs with, shared with the launcher so the
# two cannot drift apart.
. "$HERE/bin/lab-runopts.sh"
PASS=0; FAIL=0; SKIP=0
FAILED_LABS=()

C_G=$'\e[32m'; C_R=$'\e[31m'; C_Y=$'\e[33m'; C_B=$'\e[1m'; C_O=$'\e[0m'
ok()   { printf '    %s[pass]%s %s\n' "$C_G" "$C_O" "$1"; PASS=$((PASS+1)); }
bad()  { printf '    %s[FAIL]%s %s\n' "$C_R" "$C_O" "$1"; [ -n "${2:-}" ] && printf '           %s\n' "$2"; FAIL=$((FAIL+1)); }
skip() { printf '    %s[skip]%s %s\n' "$C_Y" "$C_O" "$1"; SKIP=$((SKIP+1)); }
head2(){ printf '\n%s== %s%s\n' "$C_B" "$1" "$C_O"; }

row()   { grep -vE '^\s*#|^\s*$' "$CATALOG" | awk -F'|' -v k="$1" '$1==k {print; exit}'; }
field() { echo "$1" | cut -d'|' -f"$2"; }
keys()  { grep -vE '^\s*#|^\s*$' "$CATALOG" | cut -d'|' -f1; }

NAME=""; COMP=""; PNET=""; ANET=""
cleanup() { [ -n "$NAME" ] && docker rm -f "$NAME" >/dev/null 2>&1
            [ -n "$COMP" ] && docker rm -f "$COMP" >/dev/null 2>&1
            [ -n "$PNET" ] && docker network rm "$PNET" >/dev/null 2>&1
            [ -n "$ANET" ] && docker network rm "$ANET" >/dev/null 2>&1; return 0; }
trap cleanup EXIT

# Run a command the way a LESSON does: a login shell, with none of this
# script's environment leaking in.  Testing with a bare `docker exec` is how
# the hosted course missed that the session's values were absent from a
# student's shell: exec inherits the container's env, a login shell does not.
inlab() { docker exec -u student "$NAME" env -i HOME=/home/student USER=student TERM=xterm \
              bash -lc "$1" 2>&1; }

# Does running <cmd> in the lab produce output matching <regex>?
#
# Always capture, never pipe into `grep -q`.  Under `set -o pipefail` grep
# exits at the first match, the writer takes SIGPIPE, and the pipeline reports
# failure even though the match succeeded.  It depends on buffering, so it
# fails intermittently, which cost real time to track down once already.
# A herestring, not a pipe: there is no pipeline here at all, so pipefail has
# nothing to report and the result is purely "did it match".
produces() { local out; out="$(inlab  "$1")"; grep -qE "$2" <<< "$out"; }
shows()    { local out; out="$(asroot "$1")"; grep -qE "$2" <<< "$out"; }
asroot() { docker exec "$NAME" sh -c "$1" 2>&1; }

# Wait for the door the lesson uses.
wait_door() {
    local want="$1" i
    for i in $(seq 1 90); do
        docker exec "$NAME" pgrep -x "$want" >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

start_lab() {
    local key="$1" r image proto caps companion
    r="$(row "$key")"
    image="$(field "$r" 2)"; proto="$(field "$r" 3)"
    caps="$(field "$r" 4)"; companion="$(field "$r" 5)"

    docker image inspect "$image" >/dev/null 2>&1 || { skip "$key: $image is not built"; return 1; }

    NAME="rehearse-$key-$$"; COMP=""; PNET=""
    # A stand-in for the access network the web desktop reaches labs on, so the
    # arrangement here is the launcher's: the lab sits on the access network and
    # is then CONNECTED to the pair network under the alias 'target'.  Starting
    # it on the pair network instead and connecting again is rejected by Docker
    # ("already exists in network"), the alias is silently never created, and
    # the scan the lesson asks for has nothing to aim at.
    ANET="rehearse-access-$$"
    docker network inspect "$ANET" >/dev/null 2>&1 || docker network create "$ANET" >/dev/null
    # Exactly what the launcher will give it.
    local runopts; read -r -a runopts <<< "$(lab_run_opts "$proto" "$caps")"

    local netargs=()
    if [ "$companion" != "-" ]; then
        docker image inspect "$companion" >/dev/null 2>&1 || { skip "$key: $companion is not built"; return 1; }
        PNET="rehearse-pair-$$"; COMP="rehearse-dast-$$"
        docker network create --internal "$PNET" >/dev/null 2>&1
        local compopts; read -r -a compopts <<< "$(lab_companion_opts)"
        docker run -d --name "$COMP" --network "$PNET" --network-alias dast \
            "${compopts[@]}" "$companion" >/dev/null 2>&1 ||
            { bad "$key: the scanner sidecar would not start"; return 1; }
    fi
    netargs=(--network "$ANET")

    local platform; read -r -a platform <<< "$(lab_platform_opts "$image")"

    docker run -d --name "$NAME" --hostname "$key-lab" "${netargs[@]}" \
        ${platform[@]+"${platform[@]}"} "${runopts[@]}" \
        -e LAB_PASSWORD=rehearse-probe \
        -e DAST_URL=http://dast:8888 -e DAST_USER=admin -e DAST_PASSWORD=student \
        -e PORTAL_URL=http://portal.lab:5000 \
        "$image" >/dev/null 2>&1 ||
        { bad "$key: the container would not start"; return 1; }

    [ "$companion" != "-" ] && docker network connect --alias target "$PNET" "$NAME" >/dev/null 2>&1

    local want=xrdp; [ "$proto" = ssh ] && want=sshd
    if wait_door "$want"; then
        ok "$key: the $([ "$proto" = ssh ] && echo terminal || echo desktop) door is open ($want)"
    else
        bad "$key: $want never started" "$(docker logs "$NAME" 2>&1 | tail -3)"
        return 1
    fi
    return 0
}

# A lab has to survive the machine it runs on being rebooted.  Docker restarts
# the SAME container then, writable layer and all, so anything a service wrote
# into /run before the machine went down is still there when it starts again.
# That is not hypothetical: a stale xrdp-sesman pid file put two of the desktop
# labs into a restart loop that no reboot ever recovered from, and the web
# desktop showed a login page with nothing behind it.  A restart is the cheapest
# honest reproduction of a reboot, so every lab now gets one.
restart_check() {
    local key="$1" proto="$2"
    docker restart "$NAME" >/dev/null 2>&1 || { bad "$key: would not restart"; return; }
    local want=xrdp; [ "$proto" = ssh ] && want=sshd
    if wait_door "$want"; then
        ok "$key: comes back after a restart, as it must after a reboot"
    else
        bad "$key: does not come back after a restart" \
            "a reboot would leave this lab permanently down: $(docker logs "$NAME" 2>&1 | tail -2)"
    fi
}

# A lab whose catalog row publishes a web port has to listen on every address
# inside the container.  A service bound to 127.0.0.1 there cannot be published
# at all, so the address the student is handed would simply refuse them.
web_checks() {
    local key="$1" r w spec port code
    r="$(row "$key")"; w="$(field "$r" 8)"
    [ -n "$w" ] && [ "$w" != "-" ] || return 0
    while IFS= read -r spec; do
        [ -n "$spec" ] || continue
        port="${spec%%/*}"
        case "$port" in ''|*[!0-9]*) continue ;; esac
        if inlab "ss -lnt 'sport = :$port'" 2>/dev/null | grep -qE '0\.0\.0\.0:'"$port"'|\*:'"$port"; then
            ok "$key: port $port listens on every address, so it can be published"
        else
            bad "$key: port $port is not listening on every address" \
                "the address a student is given for it would refuse them"
        fi
        code="$(inlab "curl -s -o /dev/null -w '%{http_code}' --max-time 60 http://127.0.0.1:$port/" 2>/dev/null)"
        case "$code" in
            2??|3??) ok "$key: port $port answers ($code)" ;;
            *) bad "$key: port $port answered '$code'" "the student's browser would get nothing" ;;
        esac
    done <<< "$(printf '%s\n' "$w" | tr ',' '\n')"
}

# Every lab: the things true of all of them.
common_checks() {
    local key="$1"
    local u; u="$(inlab 'id -un')"
    [ "$u" = student ] && ok "$key: a lesson's shell runs as student" || bad "$key: a shell runs as '$u'"
    # sudo, because lessons use it and a dropped capability can break it.
    inlab 'sudo -n true' >/dev/null 2>&1 && ok "$key: sudo works" || bad "$key: sudo does not work" "lessons that install or inspect will fail"
    # A writable home, which every lab needs and a root-owned .config breaks.
    inlab 'touch ~/.rehearse-probe && rm ~/.rehearse-probe' >/dev/null 2>&1 &&
        ok "$key: home is writable" || bad "$key: home is not writable by student"
}

lab_kali() {
    # Week 1 reads a machine's own addressing.  The lesson commands are ip,
    # ping and ss, and nothing more: nmap appears nowhere in this course, which
    # is why this does not ask for it.  (caps=offsec rides along from the
    # hosted profile; nothing in Week 1 needs the raw socket.)
    for t in ip ping ss; do
        inlab "command -v $t" >/dev/null && ok "kali: $t present" || bad "kali: $t missing" "Week 1 lessons run it"
    done
    # The lessons read real output, so the commands must PRODUCE it, not merely exist.
    produces 'ip -4 addr show' 'inet ' && ok "kali: ip addr shows an address" || bad "kali: ip addr printed nothing usable"
    produces 'ip -6 addr show' 'inet6'   && ok "kali: ip -6 shows an IPv6 address" || bad "kali: no IPv6 address" "the IPv6 lesson reads this"
    produces 'ss -ltn' ':22|LISTEN'      && ok "kali: ss lists listening ports" || bad "kali: ss printed no listeners"
}

lab_netlab() {
    # Weeks 2-4 reconfigure DNS, routing, the firewall and NFS, which is why
    # this lab gets NET_ADMIN.  If these fail, three weeks fail.
    local out
    out="$(asroot 'nft list ruleset 2>&1 | head -3')"
    printf '%s' "$out" | grep -qiE "permission denied|not permitted" \
        && bad "netlab: nft is refused" "caps=netlab (NET_ADMIN) is not reaching the container" \
        || ok "netlab: nft list ruleset works"
    out="$(asroot 'iptables -L -n 2>&1 | head -3')"
    printf '%s' "$out" | grep -qiE "permission denied|not permitted" \
        && bad "netlab: iptables is refused" "the firewall lesson depends on it" \
        || ok "netlab: iptables works"
    out="$(asroot 'ip link add dummy-probe type dummy 2>&1; ip link del dummy-probe 2>&1')"
    printf '%s' "$out" | grep -qiE "permission denied|not permitted" \
        && bad "netlab: cannot change its own interfaces" "the routing lessons need this" \
        || ok "netlab: can add and remove an interface"
    # The commands the lessons actually print, including this lab's own two.
    for t in dig getent ss nano awk find uname dpkg showmount tcpdump; do
        inlab "command -v $t" >/dev/null && ok "netlab: $t present" || bad "netlab: $t missing" "a Week 2-4 lesson runs it"
    done
    for t in lab-dns lab-nfs; do
        inlab "command -v $t" >/dev/null && ok "netlab: $t present" || bad "netlab: $t missing" "this lab's own helper, named in the lessons"
    done
    # The DNS server must START and LISTEN.  It must NOT already serve a zone:
    # declaring one is the student's work, and an earlier version of this test
    # asserted a resolvable answer and failed the lab for behaving correctly.
    # Captured, not piped: a failure has to be able to SAY what it saw, or
    # diagnosing it is guesswork.
    local dns
    dns="$(inlab 'lab-dns start 2>&1; lab-dns status 2>&1')"
    printf '%s' "$dns" | grep -qi 'RUNNING' \
        && ok "netlab: the lab DNS server starts and reports running" \
        || bad "netlab: the lab DNS server would not start" "$(printf '%s' "$dns" | tr '\n' ' ' | cut -c1-160)"
    printf '%s' "$dns" | grep -qE ':53' \
        && ok "netlab: it is listening on port 53" \
        || bad "netlab: nothing is listening on 53" "$(printf '%s' "$dns" | tr '\n' ' ' | cut -c1-160)"
    # sudo must be CLEAN.  The audit warning is what a too-strict capability
    # set looks like from the student's chair, and it appears on every command.
    local se
    se="$(inlab 'sudo -n true 2>&1')"
    [ -z "$se" ] && ok "netlab: sudo prints no warnings" \
        || bad "netlab: sudo prints a warning on every use" "$se"
}

lab_analyst() {
    # Weeks 5-7: six deliberately inconsistent exports, and the instructor key.
    inlab 'test -d ~/audit' && ok "analyst: the audit exports are in ~/audit" \
        || bad "analyst: ~/audit is missing" "the whole challenge reads these files"
    # The exact files the lessons name, not a count.  A missing one breaks the
    # specific step that reads it, and a count would hide that.
    local f
    for f in cmdb.csv computer_sid_objects.csv crowdstrike_output.csv ecm_hosts.csv identity.csv qualys_data_output_v2.csv; do
        inlab "test -s ~/audit/$f" && ok "analyst: $f present" || bad "analyst: $f missing" "a lesson reads this file by name"
    done
    inlab 'test -s ~/audit/proxy_log.csv || test -s ~/proxy_log.csv' \
        && ok "analyst: proxy_log.csv present (the shadow IT hunt)" \
        || bad "analyst: proxy_log.csv missing" "Week 7 reads it"
    for t in comm awk cut sort uniq wc python3; do
        inlab "command -v $t" >/dev/null && ok "analyst: $t present" || bad "analyst: $t missing"
    done
    inlab 'command -v lab-audit-answers' >/dev/null \
        && ok "analyst: the answer key is installed" \
        || bad "analyst: lab-audit-answers missing" "hackrange-lab check analyst would fail"
    # The key must RUN and produce numbers, because the checker executes it.
    produces 'lab-audit-answers 2>&1 | head -20' '[0-9]{2,}' \
        && ok "analyst: the answer key runs and produces numbers" \
        || bad "analyst: the answer key produced no numbers" "check analyst would show a student nothing"
    inlab 'command -v lab-shadow-answers' >/dev/null \
        && ok "analyst: the shadow IT key is installed" || bad "analyst: lab-shadow-answers missing"
}

lab_splunk() {
    # Weeks 8-10 live entirely inside Splunk.
    local i up=0
    for i in $(seq 1 90); do
        asroot 'curl -fsS -o /dev/null http://127.0.0.1:8000/ 2>/dev/null' >/dev/null 2>&1 && { up=1; break; }
        sleep 5
    done
    [ "$up" = 1 ] && ok "splunk: the web interface answers on 8000" \
        || bad "splunk: the web interface never came up" "weeks 8-10 cannot run"

    # 8089 is the REST API, and it speaks HTTPS with a self signed certificate.
    # An earlier version of this asked port 8000, which answers every REST path
    # with a 303 redirect to a login page.  Every check below then "passed" by
    # finding letters in that redirect's HTML, so eight sourcetype tests were
    # green while nothing had been searched at all.  Hence the control below.
    local api="https://127.0.0.1:8089"
    local code
    code="$(asroot "curl -sk -o /dev/null -w '%{http_code}' -u admin:Changeme123 $api/services/server/info")"
    case "$code" in
        200) ok "splunk: admin / Changeme123 signs in to the API" ;;
        401) bad "splunk: admin / Changeme123 is refused" "the credential the lab hands the student is wrong" ;;
        *)   bad "splunk: the API answered '$code'" "expected 200 on $api" ;;
    esac

    # search <sourcetype> -> the CSV of up to two events
    splunk_search() {
        asroot "curl -sk -u admin:Changeme123 --data-urlencode 'search=search index=* sourcetype=$1 | head 2' -d output_mode=csv -d exec_mode=oneshot $api/services/search/jobs 2>/dev/null"
    }

    # The control FIRST.  If a sourcetype that cannot exist returns data, then
    # this test cannot tell presence from absence and every result below is
    # meaningless.  Checking it first means a broken test fails loudly instead
    # of quietly reporting that everything is fine.
    local control; control="$(splunk_search definitely_not_a_real_sourcetype_probe)"
    if grep -qE '^"?_(bkt|raw)' <<< "$control"; then
        bad "splunk: the search test cannot tell a missing sourcetype from a present one" \
            "a sourcetype that does not exist returned rows, so the checks below prove nothing"
        return
    fi
    ok "splunk: a sourcetype that does not exist returns nothing (the test discriminates)"

    # Now the real ones.  A result must carry Splunk's own event fields, not
    # merely some characters.
    local st out
    for st in winsec sysmon vpn dns proxy firewall linux_auth mailgw; do
        out="$(splunk_search "$st")"
        if grep -qE '^"?_(bkt|raw)' <<< "$out" && [ "$(grep -c . <<< "$out")" -ge 2 ]; then
            ok "splunk: sourcetype=$st returns real events"
        else
            bad "splunk: sourcetype=$st returned no events" "the lessons search this by name"
        fi
    done

    inlab 'test -s ~/READ-ME-Splunk-login.txt || test -s ~/Desktop/READ-ME-Splunk-login.txt' \
        && ok "splunk: the login note is on the desktop" \
        || bad "splunk: the login note is missing" "the student is told to read it for the password"
}

lab_webapp() {
    # Week 11 source review: the app, its source, curl, and the AI.
    inlab 'test -f ~/app/app.py' && ok "webapp: ~/app/app.py is present" \
        || bad "webapp: ~/app/app.py is missing" "the lessons read this file by name"
    for t in curl cat python3; do
        inlab "command -v $t" >/dev/null && ok "webapp: $t present" || bad "webapp: $t missing"
    done
    inlab 'command -v claude' >/dev/null && ok "webapp: Claude Code is installed" \
        || bad "webapp: Claude Code missing" "the lesson runs 'claude' to review the source"
    # The lessons curl the running app, so it has to be running.
    local i up=0
    for i in $(seq 1 40); do
        inlab 'curl -fsS -o /dev/null http://127.0.0.1:5000/ 2>/dev/null' >/dev/null 2>&1 && { up=1; break; }
        sleep 2
    done
    [ "$up" = 1 ] && ok "webapp: the portal answers on 5000" || bad "webapp: the portal is not running" "the lessons curl it"
}

lab_webapp_gui() {
    # The challenge desktop: the target, the proxy, the AI, and the scanner.
    local i up=0
    for i in $(seq 1 60); do
        asroot 'curl -fsS -o /dev/null http://127.0.0.1:5000/ 2>/dev/null' >/dev/null 2>&1 && { up=1; break; }
        sleep 2
    done
    [ "$up" = 1 ] && ok "webapp-gui: the portal answers on 5000" || bad "webapp-gui: the portal never started" "$(asroot 'tail -3 /home/student/app/server.log 2>/dev/null')"
    # portal.lab, not localhost: the lesson's whole Burp story depends on the name.
    asroot 'getent hosts portal.lab' >/dev/null 2>&1 &&
        ok "webapp-gui: portal.lab resolves" || bad "webapp-gui: portal.lab does not resolve" "Firefox will not proxy localhost, so Burp would see nothing"
    for t in burpsuite firefox-esr claude xdg-open xclip; do
        inlab "command -v $t" >/dev/null && ok "webapp-gui: $t present" || bad "webapp-gui: $t missing"
    done
    # Every desktop launcher must point at a real program AND survive the
    # desktop spec's splitting of Exec on spaces.
    local f name cmd bin stripped
    for f in $(asroot 'ls /home/student/Desktop/*.desktop 2>/dev/null'); do
        name="$(basename "$f")"
        cmd="$(asroot "sed -n 's/^Exec=//p' '$f' | head -1")"
        bin="$(printf '%s' "$cmd" | awk '{print $1}')"
        stripped="$(printf '%s' "$cmd" | sed 's/"[^"]*"//g')"
        if ! asroot "command -v '$bin'" >/dev/null 2>&1; then
            bad "webapp-gui: $name points at a missing program" "$bin"
        elif printf '%s' "$stripped" | grep -qE '=[A-Za-z]+ [A-Za-z]'; then
            bad "webapp-gui: $name has an unquoted multi word argument" "$cmd"
        else
            ok "webapp-gui: $name runs $bin"
        fi
    done
    # The scanner beside it, and the login the student is handed.
    if [ -n "$COMP" ]; then
        local i2 dup=0
        for i2 in $(seq 1 60); do
            asroot 'curl -fsS -o /dev/null http://dast:8888/ 2>/dev/null' >/dev/null 2>&1 && { dup=1; break; }
            sleep 3
        done
        [ "$dup" = 1 ] && ok "webapp-gui: the scanner answers at http://dast:8888" ||
            bad "webapp-gui: the scanner never answered" "$(docker logs "$COMP" 2>&1 | tail -3)"
        # It must see the portal as 'target', which is what the lesson says to scan.
        docker exec "$COMP" sh -c 'curl -fsS -o /dev/null http://target:5000/ 2>/dev/null' >/dev/null 2>&1 &&
            ok "webapp-gui: the scanner can reach http://target:5000" ||
            bad "webapp-gui: the scanner cannot reach the portal" "the lesson tells the student to scan exactly this"
        # And the seeded admin login must work without the student setting it up.
        local body
        body="$(docker exec "$COMP" sh -c "curl -s -i -X POST -d 'username=admin&password=student' http://127.0.0.1:8888/login 2>/dev/null | head -20")"
        if printf '%s' "$body" | grep -qiE "Set-Cookie|302|303"; then
            ok "webapp-gui: admin / student signs in to the scanner"
        else
            bad "webapp-gui: admin / student is refused by the scanner" "the credential the lab hands the student does not work"
        fi
    fi
}

lab_cloud() {
    # Week 12: the account export, and the markers the checker counts.
    inlab 'test -d ~/account-export' && ok "cloud: the account export is present" ||
        bad "cloud: ~/account-export is missing" "the whole challenge reads it"
    for t in jq grep less aws; do
        inlab "command -v $t" >/dev/null && ok "cloud: $t present" || bad "cloud: $t missing" "a Week 12 lesson runs it"
    done
    inlab 'command -v claude' >/dev/null && ok "cloud: Claude Code is installed" \
        || bad "cloud: Claude Code missing" "the lesson audits the export with an AI"
    # Every marker the answer key claims must really be in the lab, or the
    # checker would mark a student wrong for something that is not there.
    local conf="$HERE/config/answers/cloud.conf" m missing=0
    while IFS= read -r m; do
        asroot "grep -rqF '$m' /home/student /opt 2>/dev/null" ||
            { bad "cloud: the key expects $m but the lab does not contain it"; missing=$((missing+1)); }
    done <<< "$(grep -oE '^FLAG[^|]+' "$conf")"
    [ "$missing" = 0 ] && ok "cloud: all $(grep -cE '^FLAG' "$conf") markers in the answer key really exist in the lab"
}

run_lab() {
    local key="$1"
    head2 "the $key lab"
    NAME=""; COMP=""; PNET=""
    if start_lab "$key"; then
        common_checks "$key"
        web_checks "$key"
        case "$key" in
            kali)       lab_kali ;;
            netlab)     lab_netlab ;;
            analyst)    lab_analyst ;;
            splunk)     lab_splunk ;;
            webapp)     lab_webapp ;;
            webapp-gui) lab_webapp_gui ;;
            cloud)      lab_cloud ;;
        esac
        # Last, because it interrupts the container every other check just used.
        restart_check "$key" "$(field "$(row "$key")" 3)"
    else
        FAILED_LABS+=("$key")
    fi
    cleanup; NAME=""; COMP=""; PNET=""
}

want=("$@")
[ ${#want[@]} -eq 0 ] && mapfile -t want < <(keys)

printf '%sRehearsing %s lab(s) the way a student meets them%s\n' "$C_B" "${#want[@]}" "$C_O"
for k in "${want[@]}"; do run_lab "$k"; done

printf '\n%s%s passed, %s failed, %s skipped%s\n' "$C_B" "$PASS" "$FAIL" "$SKIP" "$C_O"
[ "$FAIL" -eq 0 ] || exit 1
