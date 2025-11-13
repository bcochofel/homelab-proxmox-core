from ..utils import run_cmd
from pathlib import Path

def check_lynis():
    bin_exists = bool(Path('/usr/sbin/lynis').exists() or Path('/usr/local/sbin/lynis').exists())
    if not bin_exists:
        return {'installed': False, 'score': None, 'warnings': [], 'output': ''}
    out = run_cmd('lynis audit system --quick 2>&1 || true')
    score = None
    warnings = []
    for line in out.splitlines():
        if 'Hardening index' in line:
            parts = line.split(':',1)
            if len(parts) > 1:
                try:
                    score = int(''.join(ch for ch in parts[1] if ch.isdigit()))
                except Exception:
                    pass
        if 'WARNING' in line or 'Warning' in line:
            warnings.append(line.strip())
    return {'installed': True, 'score': score, 'warnings': warnings, 'output': out}
