#!/usr/bin/env bash
# No root privileges or network changes. Pass path to gre.sh as first argument.
set -Eeuo pipefail
source "${1:-./gre.sh}"
PASS=0
ok() { PASS=$((PASS+1)); printf 'ok %d - %s\n' "$PASS" "$1"; }
assert() { "$@" || { printf 'FAIL: %s\n' "$*" >&2; exit 1; }; }
reject_ip() { if ipv4 "$1"; then die "Accepted invalid IPv4: $1"; fi; ok "reject IPv4 $1"; }
for value in 0.0.0.0 192.0.2.1 255.255.255.255; do assert ipv4 "$value"; ok "valid IPv4 $value"; done
for value in 256.1.1.1 01.2.3.4 1.2.3 '1.2.3.4;id' 1.2.3.-1 1.2.3.99999999999999999999; do reject_ip "$value"; done
for value in - 22 22,443,65535; do assert ports "$value"; ok "ports $value"; done
for value in 0 65536 022 22,22 443,22 1:20 '22;id' 999999999999999999999; do
    if ports "$value"; then die "Accepted invalid ports: $value"; fi; ok "reject ports $value"
done
defaults() {
    C=([ROLE]=IRAN [LOCAL_IP]=192.0.2.1 [PEER_IP]=192.0.2.2 [WAN]=eth0 [GRE_NET]=10.200.200.0/30 [MTU]=1476 [MODE]=ports [TCP_PORTS]=443,8443 [UDP_PORTS]=443 [MANAGEMENT]=22,2222)
}
defaults; validate
assert test "$INNER" = 10.200.200.2
assert test "$OTHER" = 10.200.200.1
ok 'IRAN address allocation'
C[ROLE]=FOREIGN; validate
assert test "$INNER" = 10.200.200.1
ok 'FOREIGN address allocation'
for value in 10.0.0.0/30 172.16.0.0/30 172.31.255.252/30 192.168.255.252/30; do
    C[GRE_NET]=$value; validate; ok "private $value"
done
for value in 132.168.30.0/30 172.32.0.0/30 172.15.0.0/30 192.169.0.0/30 10.0.0.1/30 10.0.0.0/24; do
    defaults; C[GRE_NET]=$value
    if (validate) 2>/dev/null; then die "Accepted network $value"; fi; ok "reject network $value"
done
defaults; C[MTU]='$(touch BAD)'
if (validate) 2>/dev/null; then die 'Accepted executable MTU'; fi; ok 'config code rejected'
defaults; C[MANAGEMENT]=2222
if (validate) 2>/dev/null; then die 'Accepted missing SSH exclusion'; fi; ok 'SSH exclusion required'

declare -a TRACE=()
ipt() { TRACE+=("$*"); }
record() { :; }
has() { local s; for s in "${TRACE[@]}"; do [[ $s == "$1" ]] && return 0; done; return 1; }
contains() { local s; for s in "${TRACE[@]}"; do [[ $s == *"$1"* ]] && return 0; done; return 1; }
index_of() { local i; for i in "${!TRACE[@]}"; do if [[ ${TRACE[i]} == *"$1"* ]]; then INDEX=$i; return; fi; done; return 1; }
defaults; validate; build_firewall
assert has '-t filter -I INPUT -m comment --comment wilson-gre-v1 -j WG_GUARD'
assert has '-t filter -A INPUT -m comment --comment wilson-gre-v1 -j WG_INPUT'
ok 'early deny-only guard; appended allow hook'
assert contains '-d 192.0.2.1 -p gre ! -s 192.0.2.2 -j DROP'
assert contains '-d 192.0.2.1 -p gre ! -i eth0 -j DROP'
ok 'outer peer and interface restrictions'
assert contains '-p tcp --dport 8443 -i eth0 -d 192.0.2.1 -j DNAT --to-destination 10.200.200.1'
assert contains '-o wilson-gre -d 10.200.200.1 -m conntrack --ctstate DNAT --ctorigdst 192.0.2.1 -j SNAT --to-source 10.200.200.2'
ok 'DNAT and SNAT constrained to relay'
index_of 'WG_DNAT -p udp --dport 2222 -j RETURN'; excluded=$INDEX
index_of '-j DNAT'; assert test "$excluded" -lt "$INDEX"
ok 'management exclusions precede forwarding'
assert contains '--ctdir ORIGINAL -j ACCEPT'
assert contains '--ctdir REPLY -j ACCEPT'
ok 'conntrack directions constrained'
assert contains '--mss 1437:65535 -j TCPMSS --set-mss 1436'
assert contains '-j TCPMSS --clamp-mss-to-pmtu'
assert contains '-A OUTPUT -m comment --comment wilson-gre-v1 -j WG_MSS'
ok 'MSS limit, PMTU clamp and local service output'
for line in "${TRACE[@]}"; do
    [[ $line != *' -F '* && $line != *' -P '* && $line != *MASQUERADE* && $line != *'icmp -j DROP'* && $line != *'--ctstatus DNAT'* ]] || die "Unsafe/invalid rule $line"
done
ok 'no flush, policy change, global MASQUERADE or ICMP drop'
TRACE=(); C[MODE]=all; build_firewall
assert contains 'WG_DNAT -p tcp -i eth0 -d 192.0.2.1 -j DNAT'
assert contains 'WG_DNAT -p udp -i eth0 -d 192.0.2.1 -j DNAT'
assert contains 'WG_DNAT -p tcp --dport 2222 -j RETURN'
ok 'all TCP/UDP preserves management exceptions'
TRACE=(); C[ROLE]=FOREIGN; validate; build_firewall
if contains '-j DNAT' || contains '-j SNAT'; then die 'FOREIGN should not NAT'; fi
assert contains 'WG_INPUT -p tcp -i wilson-gre -s 10.200.200.2 -d 10.200.200.1 -m conntrack --ctstate NEW -j ACCEPT'
ok 'FOREIGN local service acceptance without NAT'
printf '\nPASS: %d tests\n' "$PASS"
