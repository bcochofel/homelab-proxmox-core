from ..utils import run_cmd
from pathlib import Path

def check_auditd():
    installed = Path('/sbin/auditd').exists() or Path('/usr/sbin/auditd').exists()
    service = run_cmd('systemctl is-active auditd 2>/dev/null || echo inactive')
    enabled = run_cmd('systemctl is-enabled auditd 2>/dev/null || echo no')
    audispd = False
    try:
        out = run_cmd('dpkg -s audispd-plugins 2>/dev/null || true')
        audispd = bool(out and 'install' in out.lower())
    except Exception:
        audispd = False
    return {'installed': installed, 'service': service, 'enabled': enabled, 'audispd_plugins': audispd}
