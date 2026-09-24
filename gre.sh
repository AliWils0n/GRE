#!/usr/bin/env bash
# Minimal GRE relay, adapted from the user's vatanhost example.
# Manual start only: this file does not install a boot service.
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C
TUN=vatan-m2
OWNER=gre-simple-v1
TX=0
ipt() { iptables -w 10 "$@"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ipv4() {
    local v=$1 n
    local -a parts
    [[ $v =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r -a parts <<< "$v"
    for n in "${parts[@]}"; do
        [[ ${#n} -le 3 && ( $n == 0 || $n != 0* ) ]] && ((10#$n<=255)) || return 1
    done
    ((parts[0]>0 && parts[0]<224 && parts[0]!=127))
}
rollback() {
    local rc=$?
    trap - EXIT
    if ((TX)); then
        set +e
        ipt -t nat -D PREROUTING -m comment --comment "$OWNER" -j VGS_DNAT 2>/dev/null
        ipt -t nat -D POSTROUTING -m comment --comment "$OWNER" -j VGS_SNAT 2>/dev/null
        ipt -t mangle -D FORWARD -m comment --comment "$OWNER" -j VGS_MSS 2>/dev/null
        ipt -t mangle -D OUTPUT -m comment --comment "$OWNER" -j VGS_MSS 2>/dev/null
        ipt -t nat -F VGS_DNAT; ipt -t nat -X VGS_DNAT
        ipt -t nat -F VGS_SNAT; ipt -t nat -X VGS_SNAT
        ipt -t mangle -F VGS_MSS; ipt -t mangle -X VGS_MSS
        if [[ -e /sys/class/net/$TUN/ifalias ]] && [[ $(cat "/sys/class/net/$TUN/ifalias") == "$OWNER" ]]; then
            ip link del dev "$TUN"
        fi
        printf 'Setup failed; attempted cleanup of this script resources. Review errors above.\n' >&2
    fi
    exit "$rc"
}
((EUID==0)) || die 'Run as root.'
for cmd in ip iptables sysctl flock awk cut grep; do command -v "$cmd" >/dev/null || die "Missing: $cmd"; done
exec 9>/run/gre-simple.lock
flock -n 9 || die 'Another setup is running.'
[[ ! -e /sys/class/net/wilson-gre ]] || die 'Stop/uninstall Wilson GRE first. Do not run both versions together.'
[[ ! -e /etc/systemd/system/wilson-gre.service ]] || die 'Uninstall the Wilson GRE service first so it cannot return at boot.'
[[ ! -e /sys/class/net/$TUN ]] || die 'vatan-m2 already exists; refusing to overwrite it.'
for pair in 'nat VGS_DNAT' 'nat VGS_SNAT' 'mangle VGS_MSS'; do
    read -r table chain <<< "$pair"
    ipt -t "$table" -S >/dev/null
    if ipt -t "$table" -S "$chain" >/dev/null 2>&1; then die "Existing chain $chain; refusing duplicate setup"; fi
done
printf '\n=== Simple GRE | all TCP/UDP | MTU 1250 ===\n'
read -r -p '1 = IRAN, 2 = FOREIGN: ' LOCATION </dev/tty
[[ $LOCATION == 1 || $LOCATION == 2 ]] || die 'Choose 1 or 2.'
read -r -p 'IRAN tunnel IP (94.249.244.60): ' IP_IRAN </dev/tty
read -r -p 'FOREIGN tunnel IP (91.107.161.207): ' IP_FOREIGN </dev/tty
IP_IRAN=${IP_IRAN:-94.249.244.60}
IP_FOREIGN=${IP_FOREIGN:-91.107.161.207}
ipv4 "$IP_IRAN" && ipv4 "$IP_FOREIGN" && [[ $IP_IRAN != "$IP_FOREIGN" ]] || die 'Invalid endpoint IPs.'
if [[ $LOCATION == 1 ]]; then
    LOCAL=$IP_IRAN; PEER=$IP_FOREIGN; INNER=10.200.200.2; OTHER=10.200.200.1
    read -r -p 'IP users connect to (94.249.244.12): ' CLIENT </dev/tty
    CLIENT=${CLIENT:-94.249.244.12}
    ipv4 "$CLIENT" || die 'Invalid client-facing IP.'
    [[ $(sysctl -n net.ipv4.ip_forward) == 1 ]] || die 'Enable IPv4 forwarding in your host configuration first.'
    read -r -p 'Protected SSH/admin ports, comma-separated [22]: ' MANAGEMENT </dev/tty
    MANAGEMENT=${MANAGEMENT:-22}
    [[ $MANAGEMENT =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ ]] || die 'Invalid port list.'
    IFS=, read -r -a ADMIN <<< "$MANAGEMENT"
    for p in "${ADMIN[@]}"; do [[ ${#p} -le 5 ]] && ((p<=65535)) || die 'Invalid port'; done
    [[ ,$MANAGEMENT, == *,22,* ]] || die 'Include port 22 and every custom SSH/admin port.'
    if [[ -n ${SSH_CONNECTION:-} ]]; then
        [[ ,$MANAGEMENT, == *,${SSH_CONNECTION##* },* ]] || die 'Current SSH port is missing.'
    fi
else
    LOCAL=$IP_FOREIGN; PEER=$IP_IRAN; INNER=10.200.200.1; OTHER=10.200.200.2
fi
ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$LOCAL" || die 'Tunnel IP is not assigned locally.'
if [[ $LOCATION == 1 ]]; then
    ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$CLIENT" || die 'Client IP is not assigned locally.'
fi
[[ -z $(ip -4 route show exact 10.200.200.0/30) ]] || die 'Tunnel subnet is already routed.'
trap rollback EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
TX=1
ipt -t nat -N VGS_DNAT
ipt -t nat -N VGS_SNAT
ipt -t mangle -N VGS_MSS
ip link add name "$TUN" type gre local "$LOCAL" remote "$PEER" ttl 255
ip link set dev "$TUN" alias "$OWNER"
ip addr add "$INNER/30" dev "$TUN"
ip link set dev "$TUN" mtu 1250
for direction in -i -o; do
    ipt -t mangle -A VGS_MSS "$direction" "$TUN" -p tcp --tcp-flags SYN,RST SYN -m tcpmss --mss 1211:65535 -j TCPMSS --set-mss 1210
done
ipt -t mangle -A FORWARD -m comment --comment "$OWNER" -j VGS_MSS
ipt -t mangle -A OUTPUT -m comment --comment "$OWNER" -j VGS_MSS
if [[ $LOCATION == 1 ]]; then
    for proto in tcp udp; do
        for p in "${ADMIN[@]}"; do
            ipt -t nat -A VGS_DNAT -p "$proto" --dport "$p" -j RETURN
        done
        ipt -t nat -A VGS_DNAT -d "$CLIENT" -p "$proto" -j DNAT --to-destination "$OTHER"
    done
    ipt -t nat -A VGS_SNAT -o "$TUN" -d "$OTHER" -m conntrack --ctstate DNAT --ctorigdst "$CLIENT" -j SNAT --to-source "$INNER"
    ipt -t nat -A PREROUTING -m comment --comment "$OWNER" -j VGS_DNAT
    ipt -t nat -A POSTROUTING -m comment --comment "$OWNER" -j VGS_SNAT
fi
ip link set dev "$TUN" up
TX=0
printf '\nConfigured %s -> %s, MTU 1250. Test: ping -c 3 %s\n' "$INNER" "$OTHER" "$OTHER"
printf 'Manual setup only: no automatic boot. Existing firewall policies are unchanged.\n'
