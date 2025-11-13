from pathlib import Path
import json
from .utils import write_json, write_text

def write_metrics(path: str, data: dict):
    lines = []
    lines.append(f"kernel_version:{data.get('kernel','')}")
    lines.append(f"compliance_score:{data.get('compliance_score','0')}")
    lines.append(f"cis_mode:{data.get('cis_mode','1')}")
    lines.append(f"ipv6_sysctl:{data.get('ipv6',{}).get('sysctl','')}")
    lines.append(f"ssh_service:{data.get('ssh',{}).get('service','')}")
    lines.append(f"docker_status:{data.get('docker',{}).get('service','')}")
    lines.append(f"aide_result:{data.get('aide',{}).get('result','')}")
    write_text(path, '\n'.join(lines))

def make_codequality(path: str, failed_checks):
    entries = []
    sev_map = {'high':'critical','medium':'major','low':'minor'}
    for f in failed_checks:
        entries.append({
            'description': f.get('message', f.get('name')),
            'severity': sev_map.get(f.get('severity','medium'),'minor'),
            'fingerprint': f.get('name'),
            'location': {'path':'system', 'lines': {'begin': 1}}
        })
    write_json(path, entries)

def write_all_reports(out_dir: str, report: dict, failed_checks):
    p = Path(out_dir)
    p.mkdir(parents=True, exist_ok=True)
    write_json(p / 'system_report.json', report)
    write_metrics(p / 'metrics.txt', report)
    make_codequality(p / 'codequality.json', failed_checks)
