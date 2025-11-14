from ..utils import run_cmd
from pathlib import Path

def check_aide():
    if not Path('/usr/bin/aide').exists() and not Path('/usr/sbin/aide').exists():
        return {'installed': False, 'db': 'missing', 'result': 'not-installed', 'output': ''}
    db_exists = any(Path('/var/lib/aide').glob('aide.db*'))
    if not db_exists:
        return {'installed': True, 'db': 'missing', 'result': 'db-missing', 'output': ''}
    out = run_cmd('aide --check 2>&1 || true')
    ok = 'found differences between the database and the filesystem' not in out.lower()
    return {'installed': True, 'db': 'present', 'result': 'ok' if ok else 'failed', 'output': out}
