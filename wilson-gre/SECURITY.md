# Security boundaries

Wilson GRE requires root and changes Linux network state. GRE is unencrypted and unauthenticated. An outer peer IP allowlist is not cryptographic authentication.

Supported scope: one IPv4 GRE interface; IRAN public-port relay to services listening on FOREIGN's tunnel address. No arbitrary routing, NAT traversal, IPv6, multiple instances or container destination routing.

The host's existing firewall remains authoritative. Explicit earlier drops are respected; no global flush or full-table restore is performed. The two early deny-only guards affect the configured local GRE endpoint and the project's tunnel transit. Do not use this endpoint IP for additional GRE tunnels.

Root-owned configuration is parsed as data. Input validation is not a defense against a malicious root administrator. A host firewall reload, a concurrent privileged network manager, or raw nftables policies may require manual reconciliation. Checks cannot eliminate IP spoofing or guarantee reachability.

Before reporting a problem, remove endpoint addresses, traffic data, credentials and identifiers from logs. Report suspected vulnerabilities privately to the repository owner through an enabled private reporting channel. No address or security reporting URL is configured by this template.

Use reviewed commit-pinned raw URLs. The installer serializes the already-loaded Bash program into a standalone local script, including when launched from process substitution; it does not fetch another copy. Syntax checking and the script marker are not signature verification. Boot uses only this installed copy. Review GitHub Actions results and test on disposable Linux hosts before production use.
