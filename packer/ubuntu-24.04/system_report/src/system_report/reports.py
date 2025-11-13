import json
from pathlib import Path

from .utils import write_text


def to_json_safe(obj):
    """
    Recursively convert dataclasses and complex objects into
    JSON-safe dictionaries/lists.
    """
    from dataclasses import asdict, is_dataclass

    if is_dataclass(obj):
        return {k: to_json_safe(v) for k, v in asdict(obj).items()}

    if isinstance(obj, dict):
        return {k: to_json_safe(v) for k, v in obj.items()}

    if isinstance(obj, list):
        return [to_json_safe(i) for i in obj]

    # Basic types pass through
    if isinstance(obj, (str, int, float, bool)) or obj is None:
        return obj

    # Fallback string conversion
    return str(obj)


def build_report(report, failed_checks):
    """
    Normalizes the entire report structure so it becomes JSON-serializable.
    """
    return to_json_safe({
        "report": report,
        "failed_checks": failed_checks,
    })


def write_json_report(path, data):
    """
    Writes system_report.json
    """
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def write_metrics(path, data):
    """
    Writes metrics.txt in GitLab-compatible key:value format
    """
    lines = []
    lines.append(f"kernel_version:{data.get('kernel','')}")
    lines.append(f"compliance_score:{data.get('compliance_score','0')}")
    lines.append(f"cis_mode:{data.get('cis_mode','1')}")

    # IPv6
    ipv6 = data.get("ipv6", {})
    lines.append(f"ipv6_sysctl:{ipv6.get('sysctl','')}")
    lines.append(f"ipv6_status:{ipv6.get('status','')}")

    # SSH
    ssh = data.get("ssh", {})
    hard = ssh.get("hardening", {})
    lines.append(f"ssh_hardening_score:{hard.get('score',0)}")
    lines.append(f"ssh_weak_algorithms:{len(hard.get('weak_algorithms',[]))}")
    lines.append(f"ssh_weak_moduli:{len(hard.get('weak_moduli',[]))}")

    # Docker
    docker = data.get("docker", {})
    lines.append(f"docker_status:{docker.get('service','')}")
    lines.append(f"docker_installed:{'yes' if 'not installed' not in docker.get('version','').lower() else 'no'}")

    # AIDE
    aide = data.get("aide", {})
    lines.append(f"aide_result:{aide.get('result','')}")

    # Lynis
    lyn = data.get("lynis", {})
    lines.append(f"lynis_installed:{'yes' if lyn.get('installed') else 'no'}")
    lines.append(f"lynis_score:{lyn.get('score',0)}")
    lines.append(f"lynis_warning_count:{len(lyn.get('warnings',[]))}")

    # rkhunter
    rkh = data.get("rkhunter", {})
    lines.append(f"rkhunter_installed:{'yes' if rkh.get('installed') else 'no'}")
    lines.append(f"rkhunter_status:{rkh.get('status','unknown')}")
    lines.append(f"rkhunter_warning_count:{len(rkh.get('warnings',[]))}")
    lines.append(f"rkhunter_ignored_warning_count:{len(rkh.get('ignored_warnings',[]))}")

    write_text(path, "\n".join(lines))


def write_codequality(path, failed_checks):
    """
    Writes GitLab CodeQuality JSON file.
    """
    entries = []

    for c in failed_checks:
        entries.append({
            "description": c.get("message", ""),
            "check_name": c.get("name", "system-check"),
            "severity": "major" if c.get("severity","high") == "high" else "minor",
            "fingerprint": c.get("name"),
            "location": {
                "path": "system",
                "lines": {"begin": 1}
            }
        })

    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(entries, f, indent=2)


def write_all_reports(out_dir, report, failed_checks):
    """
    Writes:
    - system_report.json
    - metrics.txt
    - codequality.json
    """
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)

    # JSON
    write_json_report(out / "system_report.json", build_report(report, failed_checks))

    # metrics
    write_metrics(out / "metrics.txt", report)

    # CodeQuality
    write_codequality(out / "codequality.json", failed_checks)
