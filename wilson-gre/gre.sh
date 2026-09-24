#!/usr/bin/env bash
# Wilson GRE - IPv4 GRE port relay. SPDX-License-Identifier: MIT
# The wrapper lets a process-substitution launch install its own loaded code.
wilson_program() {
set -Eeuo pipefail
umask 077
export LC_ALL=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
VERSION=1.1.0
BASE=/etc/wilson-gre
RUN=/run/wilson-gre
LOG=/var/log/wilson-gre.log
BIN=/usr/local/sbin/wilson-gre
UNIT=/etc/systemd/system/wilson-gre.service
TUN=wilson-gre
OWNER=wilson-gre-v1
TX=0
INSTALL_TX=0
TEMP=''
declare -gA C=()
KEYS=(ROLE LOCAL_IP CLIENT_IP PEER_IP WAN GRE_NET MTU MODE TCP_PORTS UDP_PORTS MANAGEMENT)

say() { printf '%s\n' "$*"; }
log() { printf '%(%FT%T%z)T %s\n' -1 "$*" | tee -a "$LOG"; }
die() { say "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "Missing dependency: $1"; }
ipt() { command iptables -w 10 "$@"; }
ipv4() {
    local s=$1 a b c d x
    [[ $s =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
    IFS=. read -r a b c d <<< "$s"
    for x in "$a" "$b" "$c" "$d"; do
        [[ ${#x} -le 3 && ( $x == 0 || $x != 0* ) ]] || return 1
        ((10#$x <= 255)) || return 1
    done
    IPNUM=$(( (10#$a<<24) | (10#$b<<16) | (10#$c<<8) | 10#$d ))
}
ipstr() { printf '%d.%d.%d.%d' "$((($1>>24)&255))" "$((($1>>16)&255))" "$((($1>>8)&255))" "$(($1&255))"; }
ports() {
    local s=$1 p last=0
    [[ $s == - ]] && return 0
    [[ $s =~ ^[1-9][0-9]*(,[1-9][0-9]*)*$ && ${#s} -le 2048 ]] || return 1
    local -a ps
    IFS=, read -r -a ps <<< "$s"
    ((${#ps[@]} <= 128)) || return 1
    for p in "${ps[@]}"; do
        [[ ${#p} -le 5 ]] && ((p <= 65535 && p > last)) || return 1
        last=$p
    done
}
validate() {
    local k n a b
    C[CLIENT_IP]=${C[CLIENT_IP]:-${C[LOCAL_IP]:-}}
    for k in "${KEYS[@]}"; do [[ -n ${C[$k]:-} ]] || die "Missing $k"; done
    [[ ${C[ROLE]} == IRAN || ${C[ROLE]} == FOREIGN ]] || die 'ROLE must be IRAN or FOREIGN'
    ipv4 "${C[LOCAL_IP]}" || die 'Invalid LOCAL_IP'; a=$IPNUM
    ipv4 "${C[PEER_IP]}" || die 'Invalid PEER_IP'; b=$IPNUM
    ((a != b && (a>>24)>0 && (a>>24)<224 && (a>>24)!=127 && (b>>24)>0 && (b>>24)<224 && (b>>24)!=127)) || die 'Invalid endpoints'
    ipv4 "${C[CLIENT_IP]}" || die 'Invalid CLIENT_IP'
    (( (IPNUM>>24)>0 && (IPNUM>>24)<224 && (IPNUM>>24)!=127 )) || die 'Invalid client-facing address'
    [[ ${C[WAN]} =~ ^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,14}$ && ${C[WAN]} != "$TUN" ]] || die 'Invalid WAN interface'
    [[ ${C[GRE_NET]} == */30 ]] || die 'GRE_NET must be a private /30 network'
    ipv4 "${C[GRE_NET]%/30}" || die 'Invalid GRE_NET'; n=$IPNUM
    (( (n&3)==0 && ( (n>>24)==10 || (n>>20)==2753 || (n>>16)==49320 ) )) || die 'Use an aligned RFC1918 /30 network'
    ((a < n || a > n+3)) && ((b < n || b > n+3)) || die 'Outer endpoints overlap GRE network'
    ipv4 "${C[CLIENT_IP]}"
    ((IPNUM < n || IPNUM > n+3)) || die 'CLIENT_IP overlaps GRE network'
    [[ ${C[MTU]} =~ ^[1-9][0-9]{2,3}$ ]] && ((C[MTU]>=576 && C[MTU]<=1476)) || die 'MTU must be 576..1476'
    [[ ${C[MODE]} == ports || ${C[MODE]} == all ]] || die 'MODE must be ports or all'
    for k in TCP_PORTS UDP_PORTS MANAGEMENT; do ports "${C[$k]}" || die "$k: use ascending unique ports, comma-separated, or -"; done
    [[ ,${C[MANAGEMENT]}, == *,22,* ]] || die 'MANAGEMENT must contain 22 and all custom management ports'
    if [[ ${C[MODE]} == ports ]]; then
        [[ ${C[TCP_PORTS]} != - || ${C[UDP_PORTS]} != - ]] || die 'Choose at least one port'
    fi
    if [[ ${C[ROLE]} == IRAN ]]; then
        INNER=$(ipstr "$((n+2))"); OTHER=$(ipstr "$((n+1))")
    else
        INNER=$(ipstr "$((n+1))"); OTHER=$(ipstr "$((n+2))")
    fi
}
load_config() {
    local file=${1:-$BASE/config} k v
    [[ -f $file && ! -L $file ]] || die "Configure first: $file"
    C=()
    while IFS='=' read -r k v || [[ -n $k ]]; do
        [[ -z $k || $k == \#* ]] && continue
        [[ " ${KEYS[*]} " == *" $k "* && -z ${C[$k]+yes} ]] || die "Unknown/duplicate key: $k"
        [[ $v != *$'\r'* && $v != *$'\t'* ]] || die 'Invalid configuration characters'
        C[$k]=$v
    done < "$file"
    validate
}
write_config() { local k; for k in "${KEYS[@]}"; do printf '%s=%s\n' "$k" "${C[$k]}"; done; }
ask() { local v; read -r -p "$2 [$3]: " v </dev/tty; C[$1]=${v:-$3}; }
configure() {
    [[ ! -f $RUN/journal ]] || die 'Stop before configuring; resolve any pending cleanup first'
    [[ ! -f $BASE/config ]] || load_config
    say 'Wilson GRE | same ports on FOREIGN tunnel IP; IPv4 only'
    say 'Lists: ascending comma-separated ports; - means none. Include every SSH/admin port.'
    ask ROLE 'Role: IRAN / FOREIGN' "${C[ROLE]:-IRAN}"
    ask LOCAL_IP 'Local outer IPv4 (must be assigned on this server)' "${C[LOCAL_IP]:-}"
    if [[ ${C[ROLE]} == IRAN ]]; then
        ask CLIENT_IP 'Public IPv4 that clients connect to (may differ from GRE endpoint)' "${C[CLIENT_IP]:-${C[LOCAL_IP]}}"
    else C[CLIENT_IP]=${C[LOCAL_IP]}; fi
    ask PEER_IP 'Peer outer IPv4' "${C[PEER_IP]:-}"
    ask WAN 'Interface used to reach peer and receive clients' "${C[WAN]:-eth0}"
    ask GRE_NET 'Private /30 network (same on both servers)' "${C[GRE_NET]:-10.200.200.0/30}"
    ask MTU 'Inner MTU (outer path MTU minus 24; lower for upstream VPN)' "${C[MTU]:-1476}"
    ask MODE 'Forward ports / all (same on both servers)' "${C[MODE]:-ports}"
    ask TCP_PORTS 'TCP ports' "${C[TCP_PORTS]:-443}"
    ask UDP_PORTS 'UDP ports' "${C[UDP_PORTS]:-443}"
    ask MANAGEMENT 'Excluded management ports (TCP AND UDP)' "${C[MANAGEMENT]:-22}"
    validate
    if [[ ${C[MODE]} == all ]]; then
        local answer
        read -r -p 'Expose all non-management TCP/UDP services on FOREIGN? Type ALL: ' answer </dev/tty
        [[ $answer == ALL ]] || die 'Cancelled'
    fi
    write_config > "$BASE/config.new"
    mv -f "$BASE/config.new" "$BASE/config"
    log 'Configuration saved; start FOREIGN, then IRAN.'
}

# Journal is root-only data, never shell code. Record inverse BEFORE each mutation.
record() { local x; printf '%s' "$1" >> "$RUN/journal"; shift; for x; do printf '\t%s' "$x" >> "$RUN/journal"; done; printf '\n' >> "$RUN/journal"; }
chain() { record chain "$1" "$2"; ipt -t "$1" -N "$2"; }
rule() { local table=$1 name=$2; shift 2; ipt -t "$table" -A "$name" "$@"; }
hook() {
    local table=$1 parent=$2 target=$3 where=${4:--A}
    record rule "$table" "$parent" -m comment --comment "$OWNER" -j "$target"
    ipt -t "$table" "$where" "$parent" -m comment --comment "$OWNER" -j "$target"
}
cleanup() {
    [[ -f $RUN/journal ]] || return 0
    local i failed=0 kind table name
    local -a lines fields
    # Distinguish a missing rule from an unavailable firewall backend before cleanup.
    for table in filter nat mangle; do ipt -t "$table" -S >/dev/null || return 1; done
    if ip link show dev "$TUN" >/dev/null 2>&1; then
        [[ $(cat "/sys/class/net/$TUN/ifalias") == "$OWNER" ]] || return 1
        ip link set dev "$TUN" down || return 1
    fi
    mapfile -t lines < "$RUN/journal"
    for ((i=${#lines[@]}-1;i>=0;i--)); do
        IFS=$'\t' read -r -a fields <<< "${lines[i]}"
        kind=${fields[0]}; table=${fields[1]:-}; name=${fields[2]:-}
        case $kind in
            rule)
                if ipt -t "$table" -C "$name" "${fields[@]:3}" 2>/dev/null; then
                    ipt -t "$table" -D "$name" "${fields[@]:3}" || failed=1
                fi ;;
            chain)
                if ipt -t "$table" -S "$name" >/dev/null 2>&1; then
                    # Stop if a hook could not be detached. Never clear an attached guard.
                    ((failed == 0)) || break
                    ipt -t "$table" -F "$name" && ipt -t "$table" -X "$name" || failed=1
                fi ;;
            link)
                ((failed == 0)) || break
                if ip link show dev "$TUN" >/dev/null 2>&1; then
                    [[ $(cat "/sys/class/net/$TUN/ifalias") == "$OWNER" ]] || { failed=1; break; }
                    ip link del dev "$TUN" || failed=1
                fi ;;
            conntrack)
                ((failed == 0)) || break
                local proto rc remaining
                for proto in tcp udp; do
                    rc=0
                    conntrack -D -p "$proto" --orig-dst "${fields[1]}" --reply-src "${fields[2]}" --reply-dst "${fields[3]}" || rc=$?
                    # Exit 1 can mean no matches OR an error. Verify by listing.
                    ((rc <= 1)) || failed=1
                    if remaining=$(conntrack -L -p "$proto" --orig-dst "${fields[1]}" --reply-src "${fields[2]}" --reply-dst "${fields[3]}"); then
                        [[ -z $remaining ]] || failed=1
                    else failed=1; fi
                done ;;
            *) failed=1 ;;
        esac
    done
    if ((failed)); then say 'Cleanup incomplete; journal retained. Fix the reported error and run stop again.' >&2; return 1; fi
    rm -f "$RUN/journal" "$RUN/active" "$RUN/config" "$RUN/rules"
}
on_exit() {
    local rc=$?
    trap - EXIT INT TERM HUP
    if ((TX)); then
        set +e
        log "Start interrupted/failed (exit $rc): rolling back owned resources"
        cleanup
    fi
    if ((INSTALL_TX)); then
        set +e
        systemctl disable wilson-gre.service
        rm -f "$UNIT" "$BIN"
        systemctl daemon-reload
        log 'Incomplete service installation rolled back'
    fi
    [[ -z $TEMP ]] || rm -f "$TEMP"
    exit "$rc"
}

preflight() {
    local route dev mtu addr net prefix base mask a sshport
    for a in ip iptables sysctl; do need "$a"; done
    [[ ! -e /sys/class/net/$TUN ]] || die "Interface $TUN already exists without a usable active state"
    ip -4 -o addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "${C[LOCAL_IP]}" || die 'LOCAL_IP is not assigned locally; automatic NAT traversal is unsupported'
    if [[ ${C[ROLE]} == IRAN ]]; then
        ip -4 -o addr show dev "${C[WAN]}" | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "${C[CLIENT_IP]}" || die 'CLIENT_IP must be assigned on WAN'
    fi
    route=$(ip -4 route get "${C[PEER_IP]}" from "${C[LOCAL_IP]}")
    dev=$(awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1)}' <<< "$route")
    [[ $dev == "${C[WAN]}" ]] || die "Peer route uses $dev, configured WAN is ${C[WAN]}"
    mtu=$(cat "/sys/class/net/${C[WAN]}/mtu")
    ((C[MTU]+24 <= mtu)) || die "MTU exceeds WAN MTU minus 24 ($((mtu-24)))"
    if [[ ${C[ROLE]} == IRAN ]]; then
        need conntrack
        [[ $(sysctl -n net.ipv4.ip_forward) == 1 ]] || die 'IPv4 forwarding is disabled. Enable it in your host policy, then retry (see README).'
    fi
    ipv4 "${C[GRE_NET]%/30}"; base=$IPNUM
    while read -r net; do
        [[ $net == */* && $net != default ]] || continue
        addr=${net%/*}; prefix=${net#*/}
        [[ $prefix =~ ^[0-9]+$ ]] && ((prefix>0 && prefix<=32)) || continue
        ipv4 "$addr" || continue
        mask=$(( (0xffffffff << (32-prefix)) & 0xffffffff ))
        (( (base & mask) != (IPNUM & mask) && (IPNUM & 0xfffffffc) != base )) || die "GRE network overlaps route $net"
    done < <(ip -4 route show table all | awk '{if($1=="local"||$1=="broadcast"||$1=="unreachable"||$1=="blackhole")print $2;else print $1}')
    if [[ -n ${SSH_CONNECTION:-} ]]; then
        sshport=${SSH_CONNECTION##* }
        [[ ,${C[MANAGEMENT]}, == *,$sshport,* ]] || die "Current SSH port $sshport is missing from MANAGEMENT"
    fi
    if command -v sshd >/dev/null; then
        local sshcfg
        sshcfg=$(sshd -T) || die 'Cannot inspect sshd configuration; resolve sshd -T errors first'
        while read -r sshport; do
            [[ ,${C[MANAGEMENT]}, == *,$sshport,* ]] || die "sshd port $sshport is missing from MANAGEMENT"
        done < <(awk '$1=="port"{print $2}' <<< "$sshcfg")
    fi
    for a in 'filter WG_GUARD' 'filter WG_TRANSIT' 'filter WG_INPUT' 'filter WG_FORWARD' 'nat WG_DNAT' 'nat WG_SNAT' 'mangle WG_MSS'; do
        read -r table name <<< "$a"
        ! ipt -t "$table" -S "$name" >/dev/null 2>&1 || die "Reserved chain $name already exists; will not take ownership"
    done
}
port_rules() {
    local table=$1 name=$2 proto=$3 key=$4; shift 4
    local p
    local -a ps
    if [[ ${C[MODE]} == all ]]; then rule "$table" "$name" -p "$proto" "$@"; return; fi
    [[ ${C[$key]} != - ]] || return 0
    IFS=, read -r -a ps <<< "${C[$key]}"
    for p in "${ps[@]}"; do rule "$table" "$name" -p "$proto" --dport "$p" "$@"; done
}
exclusions() {
    local table=$1 name=$2 p proto
    local -a ps
    IFS=, read -r -a ps <<< "${C[MANAGEMENT]}"
    for proto in tcp udp; do for p in "${ps[@]}"; do rule "$table" "$name" -p "$proto" --dport "$p" -j RETURN; done; done
}
build_firewall() {
    local t n proto key
    for t in 'filter WG_GUARD' 'filter WG_TRANSIT' 'filter WG_INPUT' 'filter WG_FORWARD' 'nat WG_DNAT' 'nat WG_SNAT' 'mangle WG_MSS'; do
        read -r t n <<< "$t"; chain "$t" "$n"
    done
    # Early guard only denies unsolicited GRE/invalid inner addresses. No early ACCEPT.
    rule filter WG_GUARD -d "${C[LOCAL_IP]}" -p gre ! -s "${C[PEER_IP]}" -j DROP
    rule filter WG_GUARD -d "${C[LOCAL_IP]}" -p gre ! -i "${C[WAN]}" -j DROP
    rule filter WG_GUARD -i "$TUN" ! -s "$OTHER" -j DROP
    rule filter WG_GUARD -i "$TUN" ! -d "$INNER" -j DROP
    # Restrict transit before broad ACCEPT rules installed by other software.
    if [[ ${C[ROLE]} == IRAN ]]; then
        rule filter WG_TRANSIT -i "$TUN" -s "$OTHER" -m conntrack --ctstate ESTABLISHED,RELATED --ctorigdst "${C[CLIENT_IP]}" --ctdir REPLY -j RETURN
        rule filter WG_TRANSIT -o "$TUN" -d "$OTHER" -m conntrack --ctstate DNAT --ctorigdst "${C[CLIENT_IP]}" --ctdir ORIGINAL -j RETURN
    fi
    rule filter WG_TRANSIT -i "$TUN" -j DROP
    rule filter WG_TRANSIT -o "$TUN" -j DROP
    rule filter WG_INPUT -i "${C[WAN]}" -s "${C[PEER_IP]}" -d "${C[LOCAL_IP]}" -p gre -j ACCEPT
    rule filter WG_INPUT -i "$TUN" -s "$OTHER" -d "$INNER" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    rule filter WG_INPUT -i "$TUN" -s "$OTHER" -d "$INNER" -p icmp -j ACCEPT
    exclusions filter WG_INPUT
    if [[ ${C[ROLE]} == FOREIGN ]]; then
        for proto in tcp udp; do
            key=${proto^^}_PORTS
            port_rules filter WG_INPUT "$proto" "$key" -i "$TUN" -s "$OTHER" -d "$INNER" -m conntrack --ctstate NEW -j ACCEPT
        done
    else
        # The different current and original addresses prove DNAT in stateful rules.
        # DNAT is a virtual --ctstate, NOT a --ctstatus.
        rule filter WG_FORWARD -i "$TUN" -o "${C[WAN]}" -s "$OTHER" -m conntrack --ctstate ESTABLISHED,RELATED --ctorigdst "${C[CLIENT_IP]}" --ctdir REPLY -j ACCEPT
        exclusions filter WG_FORWARD
        for proto in tcp udp; do
            key=${proto^^}_PORTS
            port_rules filter WG_FORWARD "$proto" "$key" -i "${C[WAN]}" -o "$TUN" -d "$OTHER" -m conntrack --ctstate NEW,ESTABLISHED --ctorigdst "${C[CLIENT_IP]}" --ctdir ORIGINAL -j ACCEPT
        done
        exclusions nat WG_DNAT
        for proto in tcp udp; do
            key=${proto^^}_PORTS
            port_rules nat WG_DNAT "$proto" "$key" -i "${C[WAN]}" -d "${C[CLIENT_IP]}" -j DNAT --to-destination "$OTHER"
        done
        rule nat WG_SNAT -o "$TUN" -d "$OTHER" -m conntrack --ctstate DNAT --ctorigdst "${C[CLIENT_IP]}" -j SNAT --to-source "$INNER"
    fi
    # Fixed upper MSS also handles SYN-ACKs whose return route has a larger MTU.
    for n in -i -o; do
        rule mangle WG_MSS "$n" "$TUN" -p tcp --tcp-flags SYN,RST SYN -m tcpmss --mss "$((C[MTU]-39)):65535" -j TCPMSS --set-mss "$((C[MTU]-40))"
        rule mangle WG_MSS "$n" "$TUN" -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
    done
    hook filter INPUT WG_GUARD -I
    hook filter FORWARD WG_TRANSIT -I
    hook filter INPUT WG_INPUT
    hook filter FORWARD WG_FORWARD
    hook mangle FORWARD WG_MSS
    # Locally terminated FOREIGN services traverse OUTPUT rather than FORWARD.
    hook mangle OUTPUT WG_MSS
    hook nat POSTROUTING WG_SNAT
    hook nat PREROUTING WG_DNAT
}
start() {
    load_config
    if [[ -f $RUN/active ]]; then
        cmp -s "$BASE/config" "$RUN/config" || die 'Config changed while running; stop first'
        health || die 'Active state has drifted; run restart to reconcile'
        log 'Already running; no rules added.'; return
    fi
    [[ ! -f $RUN/journal ]] || die 'Interrupted transaction found; run stop to recover'
    preflight
    TX=1
    : > "$RUN/journal"
    cp "$BASE/config" "$RUN/config"
    record link "$TUN"
    ip link add name "$TUN" alias "$OWNER" type gre local "${C[LOCAL_IP]}" remote "${C[PEER_IP]}" dev "${C[WAN]}" ttl 64 pmtudisc
    ip link set dev "$TUN" alias "$OWNER"
    if [[ ${C[ROLE]} == IRAN ]]; then record conntrack "${C[CLIENT_IP]}" "$OTHER" "$INNER"; fi
    ip addr add "$INNER/30" dev "$TUN"
    # Interface-specific only; never overwrite host-wide routing/firewall tuning.
    sysctl -q -w "net.ipv4.conf.$TUN.rp_filter=2"
    ip link set dev "$TUN" mtu "${C[MTU]}"
    build_firewall
    owned_rules > "$RUN/rules"
    ip link set dev "$TUN" up
    : > "$RUN/active"
    TX=0
    log "Started ${C[ROLE]}: $INNER <-> $OTHER; MTU ${C[MTU]}"
}
stop() { cleanup; log 'Stopped; owned hooks, chains and tunnel removed. Host settings retained.'; }
health() {
    local kind table name
    local -a f
    [[ -f $RUN/journal && -e /sys/class/net/$TUN ]] || return 1
    [[ $(cat "/sys/class/net/$TUN/ifalias") == "$OWNER" ]] || return 1
    while IFS=$'\t' read -r -a f; do
        kind=${f[0]}; table=${f[1]:-}; name=${f[2]:-}
        case $kind in
            rule) ipt -t "$table" -C "$name" "${f[@]:3}" 2>/dev/null || return 1 ;;
            chain) ipt -t "$table" -S "$name" >/dev/null 2>&1 || return 1 ;;
        esac
    done < "$RUN/journal"
    [[ -f $RUN/rules ]] && cmp -s "$RUN/rules" <(owned_rules) || return 1
    ip -o link show dev "$TUN" | grep -q '<[^>]*UP[,>]' || return 1
}
owned_rules() {
    local t n
    for t in 'filter WG_GUARD' 'filter WG_TRANSIT' 'filter WG_INPUT' 'filter WG_FORWARD' 'nat WG_DNAT' 'nat WG_SNAT' 'mangle WG_MSS'; do
        read -r t n <<< "$t"; ipt -t "$t" -S "$n" || return 1
    done
}
status() {
    if [[ -f $RUN/active ]]; then
        if health; then say 'RUNNING (resources present; use diagnostics for end-to-end checks)'; else say 'DEGRADED: resource drift; restart required'; fi
        ip -s -d link show dev "$TUN" || true
    elif [[ -f $RUN/journal ]]; then say 'INCOMPLETE: run stop to recover'; else say 'STOPPED'; fi
}
diagnostics() {
    load_config; status
    say '--- Outer route'; ip -4 route get "${C[PEER_IP]}" from "${C[LOCAL_IP]}" || true
    say '--- Forwarding'; sysctl net.ipv4.ip_forward
    say '--- Firewall counters (earlier host DROP/REJECT still wins)'
    local t n
    for t in 'filter WG_GUARD' 'filter WG_TRANSIT' 'filter WG_INPUT' 'filter WG_FORWARD' 'nat WG_DNAT' 'nat WG_SNAT' 'mangle WG_MSS'; do
        read -r t n <<< "$t"; ipt -t "$t" -nvL "$n" || true
    done
    if command -v ping >/dev/null && [[ -f $RUN/active ]]; then
        say '--- Inner peer ping'; ping -n -I "$INNER" -c 3 -W 2 "$OTHER" || true
        say '--- Inner configured MTU probe (failure can also mean ICMP filtering)'
        ping -n -I "$INNER" -M 'do' -s "$((C[MTU]-28))" -c 2 -W 2 "$OTHER" || true
    fi
    say 'Check upstream protocol 47, UFW/Fail2Ban rules, matching peer config and service listeners.'
    say 'GRE has no encryption/authentication. Peer IP filtering does not prevent spoofing.'
}
install_service() {
    need systemctl; load_config
    [[ -d /run/systemd/system ]] || die 'systemd is not running'
    [[ ! -e $UNIT && ! -L $UNIT && ! -e $BIN && ! -L $BIN ]] || die 'Service/install path exists; uninstall-service first'
    local tmp
    tmp=$(mktemp "$BASE/download.XXXXXX")
    TEMP=$tmp
    render_self > "$tmp"
    bash -n "$tmp" && grep -Fq '# Wilson GRE - IPv4 GRE port relay.' "$tmp" || { rm -f "$tmp"; die 'Invalid script'; }
    INSTALL_TX=1
    install -m 0755 "$tmp" "$BIN"; rm -f "$tmp"; TEMP=''
    cat > "$UNIT" <<'SERVICE'
# Wilson GRE managed unit
[Unit]
Description=Wilson GRE IPv4 port relay
Wants=network-online.target
After=network-online.target ufw.service firewalld.service docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/wilson-gre _service-start
ExecStop=/usr/local/sbin/wilson-gre _service-stop
TimeoutStartSec=180
TimeoutStopSec=180
UMask=0077
[Install]
WantedBy=multi-user.target
SERVICE
    if ! systemctl daemon-reload || ! systemctl enable wilson-gre.service; then
        systemctl disable wilson-gre.service || true
        rm -f "$UNIT" "$BIN"
        systemctl daemon-reload || true
        die 'Service installation failed; new installed files rolled back'
    fi
    INSTALL_TX=0
    log 'Service installed and enabled for next boot. Run systemctl start wilson-gre now if desired.'
}
render_self() {
    printf '%s\n' '#!/usr/bin/env bash' '# Wilson GRE - IPv4 GRE port relay. SPDX-License-Identifier: MIT'
    declare -f wilson_program
    printf '\nwilson_program "$@"\n'
}
service_action() {
    local action=$1 rc=0
    need systemctl
    flock -u 9
    systemctl "$action" wilson-gre.service 9>&- || rc=$?
    flock -n 9 || die 'Another process acquired the lock; retry'
    ((rc==0)) || die "Service $action failed; run diagnostics and journalctl -u wilson-gre"
    [[ $action != stop ]] || stop
}
setup() {
    need systemctl
    [[ -d /run/systemd/system ]] || die 'Automatic boot requires systemd; use configure/start for manual mode'
    configure
    if [[ ! -e $UNIT ]]; then install_service
    else grep -Fxq '# Wilson GRE managed unit' "$UNIT" || die 'Service name is already in use'; fi
    service_action start
    log 'Setup complete: saved configuration + automatic start at every boot.'
}
uninstall_service() {
    need systemctl
    [[ ! -f $UNIT ]] || grep -Fxq '# Wilson GRE managed unit' "$UNIT" || die 'Unit is not owned by Wilson GRE'
    [[ ! -f $BIN ]] || grep -Fq '# Wilson GRE - IPv4 GRE port relay.' "$BIN" || die 'Binary is not owned by Wilson GRE'
    if [[ -f $UNIT ]]; then
        # ExecStop acquires the same lock; release while systemd calls it.
        flock -u 9
        local rc=0
        systemctl disable --now wilson-gre.service 9>&- || rc=$?
        flock -n 9 || die 'Another process acquired the lock; retry uninstall-service'
        ((rc==0)) || die 'systemd could not stop/disable the unit; files retained'
    fi
    cleanup
    rm -f "$UNIT" "$BIN"
    systemctl daemon-reload
    log 'Service and installed script removed; configuration and log retained.'
}
dispatch() {
    if [[ $1 == start || $1 == stop || $1 == restart ]]; then
        if [[ -f $UNIT ]] && grep -Fxq '# Wilson GRE managed unit' "$UNIT"; then service_action "$1"; return; fi
    fi
    case $1 in
        setup) setup ;; _service-start) start ;; _service-stop) stop ;;
        configure) configure ;; start) start ;; stop) stop ;; restart) load_config; stop; start ;;
        status) status ;; diagnostics) diagnostics ;; install-service) install_service ;; uninstall-service) uninstall_service ;;
        *) die 'Usage: gre.sh [setup|configure|start|stop|restart|status|diagnostics|install-service|uninstall-service|--version]' ;;
    esac
}
main() {
    [[ ${1:-} != --version ]] || { say "Wilson GRE $VERSION"; return; }
    [[ $(uname -s) == Linux ]] || die 'Linux required'
    ((EUID == 0)) || die 'Run as root (sudo -i, then run the command)'
    for cmd in flock tee awk cut grep cmp install mktemp ip iptables sysctl; do need "$cmd"; done
    [[ ! -L $BASE && ! -L $RUN && ! -L $LOG ]] || die 'Unsafe symlink in runtime paths'
    install -d -o root -g root -m 0700 "$BASE" "$RUN"
    touch "$LOG"; chmod 0600 "$LOG"
    exec 2> >(tee -a "$LOG" >&2)
    exec 9>"$RUN/lock"
    flock -n 9 || die 'Another Wilson GRE process is running'
    trap on_exit EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    if (($#)); then dispatch "$1"; return; fi
    [[ -r /dev/tty ]] || die 'Interactive terminal required, or pass an action'
    local choice action
    local -a actions=(setup start stop restart status diagnostics install-service uninstall-service configure)
    while :; do
        if [[ -t 1 ]]; then printf '\033[1;36m'; fi
        printf '\n  ╔══════════════════════════════╗\n  ║       WILSON GRE  1.1        ║\n  ╚══════════════════════════════╝\n'
        if [[ -t 1 ]]; then printf '\033[0m'; fi
        say '  1 Setup + auto boot    2 Start      3 Stop'
        say '  4 Restart       5 Status     6 Diagnostics'
        say '  7 Install service   8 Uninstall service   0 Exit'
        say '  9 Configure only (manual mode)'
        read -r -p '  Select: ' choice </dev/tty
        [[ $choice != 0 ]] || break
        if [[ $choice =~ ^[1-9]$ ]]; then
            action=${actions[choice-1]}
            # Keep errexit enabled inside the worker; parent menu survives failure.
            set +e
            (set -Ee; trap on_exit EXIT; dispatch "$action")
            local rc=$?
            set -e
            ((rc==0)) || say "Action failed ($rc); see $LOG"
        else say 'Choose 0..9'; fi
    done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
}
wilson_program "$@"
