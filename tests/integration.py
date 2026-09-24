#!/usr/bin/env python3
"""Root-only Linux namespace test. Run on a disposable VM/CI runner.

Creates four isolated network namespaces; never modifies host firewall/sysctls.
This test uses real iproute2, iptables, conntrack, GRE, TCP and UDP.
"""
import os
import pathlib
import shutil
import subprocess as sp
import tempfile
import time

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "gre.sh"
PREFIX = f"wgtest-{os.getpid()}"
NAMES = {r: f"{PREFIX}-{r}" for r in ("iran", "foreign", "client", "lan")}
PROCS = []
CREATED = []


def run(*args, check=True):
    result = sp.run(args, text=True, stdout=sp.PIPE, stderr=sp.PIPE)
    if check and result.returncode:
        raise RuntimeError(f"{args}\n{result.stdout}\n{result.stderr}")
    return result


def ns(role, *args, **kw):
    return run("ip", "netns", "exec", NAMES[role], *args, **kw)


def manager(role, action, inject=False, check=True):
    shell = 'source "$1"; BASE="$2/etc"; RUN="$2/run"; LOG="$2/log"; UNIT="$2/unit"; BIN="$2/bin"; '
    if inject:
        shell += '''ipt() {
          if [[ "$*" == *"-A PREROUTING"* ]]; then return 42; fi
          command iptables -w 10 "$@"
        }; '''
    shell += 'main "$3"'
    return ns(role, "bash", "-c", shell, "--", str(SCRIPT), str(ROOT / role), action, check=check)


def config(role, mode="ports", tcp="8443", udp="8443"):
    index = 1 if role == "iran" else 2
    folder = ROOT / role / "etc"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "config").write_text(
        f"ROLE={role.upper()}\nLOCAL_IP=192.0.2.{index}\nPEER_IP=192.0.2.{3-index}\n"
        f"WAN=eth0\nGRE_NET=10.200.200.0/30\nMTU=1476\nMODE={mode}\n"
        f"TCP_PORTS={tcp}\nUDP_PORTS={udp}\nMANAGEMENT=22,2222\n"
    )


SERVER = r'''
import socket,sys,threading
port=int(sys.argv[1]); label=sys.argv[2].encode()
def tcp():
 s=socket.socket();s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
 s.bind(('0.0.0.0',port));s.listen()
 while True:
  c,_=s.accept()
  with c: c.recv(100);c.sendall(label)
def udp():
 s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM);s.bind(('0.0.0.0',port))
 while True:
  _,a=s.recvfrom(100);s.sendto(label,a)
threading.Thread(target=tcp,daemon=True).start();udp()
'''
CLIENT = r'''
import socket,sys
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM if sys.argv[1]=='tcp' else socket.SOCK_DGRAM)
s.settimeout(2);s.connect(('192.0.2.1',int(sys.argv[2])));s.send(b'hello')
assert s.recv(100).decode()==sys.argv[3]
'''


def service(role, port, label):
    PROCS.append(sp.Popen(["ip", "netns", "exec", NAMES[role], "python3", "-u", "-c", SERVER, str(port), label]))


def request(proto, port, label, allowed=True):
    result = ns("client", "python3", "-c", CLIENT, proto, str(port), label, check=False)
    assert (result.returncode == 0) == allowed, (proto, port, result.stderr)


def pristine(role):
    assert "WG_" not in ns(role, "iptables-save").stdout
    assert ns(role, "ip", "link", "show", "wilson-gre", check=False).returncode != 0
    assert not (ROOT / role / "run" / "journal").exists()
    assert "KEEP_SENTINEL" in ns(role, "iptables-save").stdout


def suite():
    for name in NAMES.values():
        run("ip", "netns", "add", name)
        CREATED.append(name)
    ns("lan", "ip", "link", "add", "br0", "type", "bridge")
    ns("lan", "ip", "link", "set", "br0", "up")
    for i, role in enumerate(("iran", "foreign", "client"), 1):
        run("ip", "link", "add", "eth0", "netns", NAMES[role], "type", "veth", "peer", "name", f"p{i}", "netns", NAMES["lan"])
        ns("lan", "ip", "link", "set", f"p{i}", "master", "br0")
        ns("lan", "ip", "link", "set", f"p{i}", "up")
        ns(role, "ip", "link", "set", "lo", "up")
        ns(role, "ip", "addr", "add", f"192.0.2.{i}/24", "dev", "eth0")
        ns(role, "ip", "link", "set", "eth0", "up")
    for role in ("iran", "foreign"):
        config(role)
        ns(role, "iptables", "-N", "KEEP_SENTINEL")
        ns(role, "iptables", "-A", "INPUT", "-p", "icmp", "-j", "ACCEPT")
        ns(role, "iptables", "-A", "INPUT", "-p", "tcp", "--dport", "2222", "-j", "ACCEPT")
        ns(role, "iptables", "-A", "INPUT", "-p", "udp", "--dport", "2222", "-j", "ACCEPT")
        ns(role, "iptables", "-P", "INPUT", "DROP")
        ns(role, "iptables", "-P", "FORWARD", "DROP")
    ns("iran", "sysctl", "-qw", "net.ipv4.ip_forward=1")
    service("foreign", 8443, "FOREIGN")
    service("foreign", 9443, "ALL")
    service("iran", 2222, "MANAGEMENT")
    time.sleep(0.5)
    manager("foreign", "start")
    manager("iran", "start")
    ns("iran", "ping", "-c", "1", "-W", "2", "10.200.200.1")
    ns("iran", "ping", "-c", "1", "-W", "2", "-M", "do", "-s", "1448", "10.200.200.1")
    ns("client", "ping", "-c", "1", "-W", "2", "192.0.2.1")
    for proto in ("tcp", "udp"):
        request(proto, 8443, "FOREIGN")
        request(proto, 2222, "MANAGEMENT")
        request(proto, 9443, "ALL", allowed=False)
    before = ns("iran", "iptables-save").stdout
    manager("iran", "start")
    assert before == ns("iran", "iptables-save").stdout, "Duplicate rules after start"
    # Existing host denial must still win over appended Wilson ACCEPT rules.
    ns("iran", "iptables", "-I", "FORWARD", "1", "-p", "tcp", "--dport", "8443", "-j", "DROP")
    request("tcp", 8443, "FOREIGN", allowed=False)
    ns("iran", "iptables", "-D", "FORWARD", "-p", "tcp", "--dport", "8443", "-j", "DROP")
    manager("iran", "restart")
    request("tcp", 8443, "FOREIGN")
    manager("iran", "stop")
    manager("iran", "stop")
    pristine("iran")
    # Fail at last hook: both already-attached hooks and all owned chains roll back.
    assert manager("iran", "start", inject=True, check=False).returncode != 0
    pristine("iran")
    manager("foreign", "stop")
    for role in ("foreign", "iran"):
        config(role, mode="all")
        manager(role, "start")
    for proto in ("tcp", "udp"):
        request(proto, 9443, "ALL")
        request(proto, 2222, "MANAGEMENT")
    # Configuration change must not revive cached NAT for a removed port.
    for role in ("iran", "foreign"):
        manager(role, "stop")
        config(role)
    manager("foreign", "start")
    manager("iran", "start")
    request("udp", 9443, "ALL", allowed=False)
    for role in ("iran", "foreign"):
        manager(role, "stop")
        pristine(role)
    print("PASS: real GRE, TCP/UDP relay, management exclusions, ICMP/MTU, idempotence, host denial, restart, rollback, all mode, cleanup")


if __name__ == "__main__":
    if os.geteuid() != 0:
        raise SystemExit("Run as root on a disposable Linux VM/CI runner")
    for tool in ("ip", "iptables", "iptables-save", "conntrack", "ping", "bash"):
        if not shutil.which(tool):
            raise SystemExit(f"Missing dependency: {tool}")
    with tempfile.TemporaryDirectory(prefix="wilson-gre-tests-") as folder:
        ROOT = pathlib.Path(folder)
        try:
            suite()
        finally:
            for process in PROCS:
                process.terminate()
            for process in PROCS:
                try:
                    process.wait(timeout=3)
                except sp.TimeoutExpired:
                    process.kill()
                    process.wait()
            for name in reversed(CREATED):
                run("ip", "netns", "del", name, check=False)
