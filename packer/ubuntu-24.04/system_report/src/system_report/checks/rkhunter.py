from ..utils import run_cmd
from pathlib import Path

def check_rkhunter():
    bin_exists = bool(Path('/usr/bin/rkhunter').exists() or Path('/usr/local/bin/rkhunter').exists())
    if not bin_exists:
        return {'installed': False, 'warnings': [], 'status': 'not-installed', 'output': ''}
    out = run_cmd('rkhunter --check --sk --report-warnings-only 2>&1 || true')
    warnings = []
    status = 'ok'
    for line in out.splitlines():
        if 'Warning' in line or 'ROOTKIT' in line or 'Suspect' in line:
            warnings.append(line.strip())
    if warnings:
        status = 'warnings'
    return {'installed': True, 'warnings': warnings, 'status': status, 'output': out}
