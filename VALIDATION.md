# Validation record — 2026-09-24

## Actually executed in the authoring environment

- Windows host; portable GNU Bash from the Git for Windows SDK.
- `bash -n gre.sh`: passed.
- ShellCheck 0.11.0, warning/error severity: passed with no findings.
- `tests/unit.sh`: 43 checks passed. Covers IPv4 parsing, private /30 boundaries, numeric and executable-looking input rejection, port lists, management exclusions, peer/interface GRE filtering, constrained DNAT/SNAT, conntrack direction, MSS generation, selected/all modes and FOREIGN local-service rules.
- `tests/self_install.sh`: passed. The self-serialized installed copy parses, reports its version independently, and executes through Bash process substitution. No second download or sibling repository file is needed.
- `tests/rollback.sh`: three mock scenarios passed: reverse cleanup, failure at the final firewall hook, and cleanup failure followed by retry. Existing sentinel chain remains; owned chains are not flushed while a hook remains attached.
- Python compilation of `tests/integration.py`: passed.

Mock tests inspect generated rules and exercise state/error handling. They do **not** prove Linux kernel acceptance of every rule, real GRE connectivity, systemd boot behavior or production firewall compatibility.

## Included but not executed here

`tests/integration.py` needs Linux, root, GRE/conntrack support and network namespaces. This Windows environment has no installed WSL distribution. The GitHub workflow runs it with both iptables-nft and iptables-legacy on Ubuntu.

The integration harness isolates its interfaces/firewall/sysctls in four network namespaces and uses separate state/config paths. It tests actual TCP/UDP relay, management-port preservation, ICMP/MTU, selected/all modes, repeat-start idempotence, respect for an existing DROP, restart, last-hook failure rollback and owned-resource cleanup. Tests use real packet flow; they are not claimed to have passed until CI is run.

## Required deployment verification

1. Run the included CI and Linux namespace integration tests.
2. On two disposable hosts, use `Setup + auto boot`, verify listeners and diagnostics, then reboot both hosts and verify the tunnel starts without another command or configuration prompt.
3. Check actual UFW/Fail2Ban/Docker/cloud firewall ordering and avoid Docker-published port conflicts. The source preserves their rules but cannot guarantee their policy permits GRE/relay traffic.
4. Verify every management port is excluded, check the effective path MTU in both directions, and compare latency/loss from actual clients.

The implementation deliberately does not promise zero overhead, encrypted/authenticated GRE, uninterrupted restart, guaranteed ping reduction, or compatibility with arbitrary independent nftables and policy-routing configurations.
