from ..utils import run_cmd, read_file
import re
from dataclasses import dataclass

@dataclass
class SSHCheckResult:
    name: str
    passed: bool
    severity: str
    cis_level: int
    message: str

def get_effective_sshd():
    """
    Returns fully-evaluated SSHD configuration using `sshd -T`.
    """
    out = run_cmd("sshd -T 2>/dev/null || true")
    effective = {}

    if out:
        for line in out.splitlines():
            parts = line.split(None, 1)
            if len(parts) == 2:
                key, val = parts
                effective[key.lower()] = val.strip()
    return effective


def get_moduli():
    """
    Returns list of bit sizes of moduli in /etc/ssh/moduli.
    """
    text = read_file("/etc/ssh/moduli")
    sizes = []
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        if len(parts) >= 5:
            try:
                sizes.append(int(parts[4]))
            except ValueError:
                continue
    return sizes


def check_weak_patterns(effective):
    """
    Inspect weak algorithms in:
    - Ciphers
    - MACs
    - KEXAlgorithms
    - HostKeyAlgorithms
    """
    weak = {
        "ciphers": [
            r"cbc", r"arcfour", r"blowfish", r"3des", r"aes128-cbc"
        ],
        "macs": [
            r"md5", r"hmac-md5", r"hmac-md5-96", r"hmac-sha1-96"
        ],
        "kex": [
            r"group1", r"group-exchange-sha1", r"sha1$"
        ],
        "hostkeys": [
            r"ssh-dss", r"ecdsa-sha2-nistp256", r"rsa1"
        ],
    }

    findings = []

    def match_any(value, patterns):
        for p in patterns:
            if re.search(p, value):
                return True
        return False

    # Evaluate each category
    for field, patterns in weak.items():
        value = effective.get(field, "")
        if value and match_any(value, patterns):
            findings.append(f"Weak {field}: {value}")

    return findings


def ssh_hardening_score(effective):
    """
    Compute weighted SSH hardening score.
    """
    results = []
    add = lambda name, passed, sev, cis, msg: results.append(
        SSHCheckResult(name, passed, sev, cis, msg)
    )

    # L1 CIS: PermitRootLogin no
    add("ssh_permit_root",
        effective.get("permitrootlogin") == "no",
        "high", 1,
        "PermitRootLogin must be no")

    # L1 CIS: PasswordAuthentication no
    add("ssh_password_auth",
        effective.get("passwordauthentication") == "no",
        "high", 1,
        "PasswordAuthentication must be no")

    # L1 CIS: X11Forwarding no
    add("ssh_x11",
        effective.get("x11forwarding") == "no",
        "medium", 1,
        "X11Forwarding must be no")

    # L1 CIS: AllowAgentForwarding no
    add("ssh_agentforward",
        effective.get("allowagentforwarding") == "no",
        "medium", 1,
        "AllowAgentForwarding must be no")

    # L2 CIS: AllowTcpForwarding no
    add("ssh_tcp_forwarding",
        effective.get("allowtcpforwarding") == "no",
        "low", 2,
        "AllowTcpForwarding should be no")

    # KEX/ciphers/mac modern patterns
    weak = check_weak_patterns(effective)
    add("ssh_algorithms_strong",
        len(weak) == 0,
        "high", 2,
        "Weak cryptographic algorithms present" if weak else "OK")

    # Moduli (L2)
    moduli = get_moduli()

    # Deduplicate weak moduli sizes
    weak_moduli_raw = [m for m in moduli if m < 2048]
    weak_moduli = sorted(list(set(weak_moduli_raw)))
    weak_moduli_count = len(weak_moduli_raw)
    add(
        "ssh_moduli",
        len(weak_moduli) == 0,
        "high",
        2,
        f"Weak moduli detected ({weak_moduli_count} entries): {weak_moduli}"
    )

    # Compute score
    weights = {"high": 3, "medium": 2, "low": 1}
    total, passed = 0, 0
    failures = []

    for r in results:
        if r.cis_level == 1 or r.cis_level == 2:
            w = weights[r.severity]
            total += w
            if r.passed:
                passed += w
            else:
                failures.append(r)

    score = round((passed / total * 100) if total else 100, 2)

    return {
        "score": score,
        "results": results,
        "failed": failures,
        "weak_algorithms": weak,
        "weak_moduli": weak_moduli,

        "weak_moduli_count": weak_moduli_count,
    "weak_moduli_count": weak_moduli_count,
    }


def check_ssh():
    """
    Called by main program.
    """
    effective = get_effective_sshd()
    service = run_cmd(
        "systemctl is-active ssh 2>/dev/null || "
        "systemctl is-active sshd 2>/dev/null || echo inactive"
    )

    hard = ssh_hardening_score(effective)

    return {
        "service": service,
        "effective": effective,
        "hardening": hard,
    }
