from ..utils import run_cmd

def parse_sshd_effective():
    out = run_cmd("sshd -T 2>/dev/null || true")
    if out:
        m = {}
        for line in out.splitlines():
            parts = line.split(None, 1)
            if parts:
                key = parts[0]
                val = parts[1].strip() if len(parts) > 1 else ""
                m[key] = val
        return {"effective": m, "source": "sshd -T"}
    conf = run_cmd("cat /etc/ssh/sshd_config 2>/dev/null || true")
    m = {}
    for line in conf.splitlines():
        line = line.strip()
        if not line or line.startswith("#"): continue
        parts = line.split()
        m[parts[0].lower()] = parts[1] if len(parts) > 1 else ""
    return {"effective": m, "source": "sshd_config"}

def check_ssh_hardening():
    d = parse_sshd_effective()
    e = d["effective"]
    permit_root = e.get("permitrootlogin", "unknown")
    pass_auth = e.get("passwordauthentication", "unknown")
    protocol = e.get("protocol", "unknown")
    return {
        "service": run_cmd("systemctl is-active ssh 2>/dev/null || systemctl is-active sshd 2>/dev/null || echo inactive"),
        "permit_root_login": permit_root,
        "password_authentication": pass_auth,
        "protocol": protocol,
        "kex": e.get("kexalgorithms", ""),
        "ciphers": e.get("ciphers", ""),
        "macs": e.get("macs", ""),
        "raw_source": d.get("source", ""),
    }
