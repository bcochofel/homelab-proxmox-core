from ..utils import run_cmd

def check_packages(required=None):
    if required is None:
        required = ['curl','wget','sudo','openssh-server','ca-certificates','apt-transport-https','gnupg']
    missing = []
    for pkg in required:
        out = run_cmd(f"dpkg -s {pkg} 2>/dev/null || true")
        if not out or ('status:' in out.lower() and 'installed' not in out.lower()):
            missing.append(pkg)
    upgradeable = run_cmd('apt list --upgradeable 2>/dev/null || true')
    count = 0
    if upgradeable:
        count = len([l for l in upgradeable.splitlines() if '/' in l]) - 1
    return {'missing': missing, 'upgradeable_count': count}
