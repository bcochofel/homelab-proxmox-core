from ..utils import run_cmd
from pathlib import Path
import re

CLOUDINIT_RKHUNTER_PATTERNS = [
    r'/etc/hosts',
    r'/etc/hostname',
    r'/etc/resolv.conf',
    r'/etc/machine-id',
    r'/etc/cloud/.*',
    r'/etc/ssh/ssh_host_.*',         # cloud-init regenerates host keys
    r'/etc/passwd',                   # adds default cloud user
    r'/etc/group',
    r'/etc/sudoers.d/.*',
]

def check_rkhunter():
    bin_exists = bool(Path('/usr/bin/rkhunter').exists() or Path('/usr/local/bin/rkhunter').exists())
    if not bin_exists:
        return {
            'installed': False,
            'warnings': [],
            'ignored_warnings': [],
            'status': 'not-installed',
            'output': ''
        }

    out = run_cmd('rkhunter --check --sk --report-warnings-only 2>&1 || true')

    raw_warnings = []
    for line in out.splitlines():
        if 'Warning' in line or 'ROOTKIT' in line or 'Suspect' in line:
            raw_warnings.append(line.strip())

    ignored = []
    real = []

    for w in raw_warnings:
        if any(re.search(p, w) for p in CLOUDINIT_RKHUNTER_PATTERNS):
            ignored.append(w)
        else:
            real.append(w)

    status = "ok" if len(real) == 0 else "warnings"

    return {
        'installed': True,
        'warnings': real,
        'ignored_warnings': ignored,
        'status': status,
        'output': out
    }
