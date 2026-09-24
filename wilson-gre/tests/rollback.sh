#!/usr/bin/env bash
# Mock firewall failure/recovery; no privileges or Linux network required.
set -Eeuo pipefail
source "${1:-./gre.sh}"
RUN=${2:?Pass an existing temporary directory}
declare -A CHAINS=([filter/KEEP_SENTINEL]=1) HOOKS=()
FAIL_LAST=0
FAIL_DELETE=0
DELETES=0
log() { printf '%s\n' "$*"; }
# No real interface exists in this mock. Real-link cleanup is in integration.py.
ip() { return 1; }
rm() { REMOVED=1; }
ipt() {
    local table=$2 op=$3 name=${4:-} key
    key=$table/$name
    case $op in
        -N) [[ -z ${CHAINS[$key]:-} ]] || return 1; CHAINS[$key]=1 ;;
        -S) [[ -z $name || -n ${CHAINS[$key]:-} ]] ;;
        -A|-I)
            if [[ $name == PREROUTING && $FAIL_LAST == 1 ]]; then return 42; fi
            if [[ $name != WG_* ]]; then HOOKS["$*"]=1; fi ;;
        -C)
            shift 4
            [[ -n ${HOOKS[-t $table -A $name $*]:-${HOOKS[-t $table -I $name $*]:-}} ]] ;;
        -D)
            [[ $FAIL_DELETE != 1 ]] || return 4
            shift 4
            unset 'HOOKS[-t $table -A $name $*]' 'HOOKS[-t $table -I $name $*]'
            DELETES=$((DELETES+1)) ;;
        -F) [[ $name == WG_* && ${#HOOKS[@]} == 0 ]] || die 'Flush before hooks detached or non-owned flush' ;;
        -X) unset 'CHAINS[$key]' ;;
        *) die "Unexpected iptables command $*" ;;
    esac
}
verify() {
    [[ ${#CHAINS[@]} == 1 && ${CHAINS[filter/KEEP_SENTINEL]} == 1 && ${#HOOKS[@]} == 0 && ${REMOVED:-0} == 1 ]] || die 'Rollback state mismatch'
}
C=([ROLE]=IRAN [LOCAL_IP]=192.0.2.1 [PEER_IP]=192.0.2.2 [WAN]=eth0 [GRE_NET]=10.200.200.0/30 [MTU]=1476 [MODE]=ports [TCP_PORTS]=443 [UDP_PORTS]=443 [MANAGEMENT]=22)
validate
: > "$RUN/journal"
build_firewall
cleanup
verify
[[ $DELETES == 8 ]] || die 'Wrong number of detached hooks'
printf '%s\n' 'PASS: reverse cleanup removes all eight hooks before owned chains; sentinel preserved'
: > "$RUN/journal"
FAIL_LAST=1
set +e
(
    set -Ee
    TX=1
    trap 'rc=$?; cleanup; verify; printf "%s\n" "PASS: final-hook failure rolled back all prior changes"; exit "$rc"' EXIT
    build_firewall
)
rc=$?
set -e
[[ $rc == 42 ]] || die "Failure exit code not preserved: $rc"
: > "$RUN/journal"
FAIL_LAST=0
build_firewall
REMOVED=0
FAIL_DELETE=1
if cleanup; then die 'Cleanup should fail when hooks cannot be detached'; fi
[[ $REMOVED == 0 && ${#CHAINS[@]} == 8 ]] || die 'Journal/chains discarded despite failed hook removal'
FAIL_DELETE=0
cleanup
verify
printf '%s\n' 'PASS: failed cleanup retains state and succeeds on retry'
