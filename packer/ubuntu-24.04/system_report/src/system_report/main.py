import argparse
from pathlib import Path

from .checks import (
    ipv6,
    ssh,
    docker,
    proxy,
    aide,
    auditd,
    packages,
    lynis,
    rkhunter
)

from .scoring import Scorer
from .reports import write_all_reports
from .utils import run_cmd
from rich import print


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cis-mode", type=int, default=1, choices=[1, 2])
    parser.add_argument("--cis-threshold", type=int, default=85)
    parser.add_argument("--fail-on-threshold", action="store_true")
    parser.add_argument("--out-dir", default=".")
    args = parser.parse_args()

    # -------------------------------------------------------
    # SYSTEM BASELINE
    # -------------------------------------------------------
    report = {}
    report["cis_mode"] = args.cis_mode
    report["hostname"] = run_cmd("hostname --fqdn 2>/dev/null || hostname")
    report["kernel"] = run_cmd("uname -r 2>/dev/null || echo unknown")

    # Checks
    report["ipv6"] = ipv6.check_ipv6()
    report["ssh"] = ssh.check_ssh()
    report["docker"] = docker.check_docker()
    report["proxy"] = proxy.check_proxy()
    report["aide"] = aide.check_aide()
    report["auditd"] = auditd.check_auditd()
    report["packages"] = packages.check_packages()
    report["lynis"] = lynis.check_lynis()
    report["rkhunter"] = rkhunter.check_rkhunter()

    # -------------------------------------------------------
    # MAIN COMPLIANCE SCORING (global score)
    # -------------------------------------------------------
    scorer = Scorer(cis_mode=args.cis_mode)

    # IPv6
    scorer.add(
        "ipv6_sysctl",
        report["ipv6"]["sysctl"] == "disabled",
        severity="low",
        cis_level=2,
        message="IPv6 sysctl should be disabled",
    )

    # SSH — use only CIS-level checks for global scoring
    ssh_hard = report["ssh"]["hardening"]
    for r in ssh_hard["results"]:
        if r.cis_level <= args.cis_mode:
            scorer.add(
                r.name,
                r.passed,
                severity=r.severity,
                cis_level=r.cis_level,
                message=r.message,
            )

    # Docker
    docker_installed = "not installed" not in report["docker"]["version"].lower()
    if not docker_installed:
        scorer.add(
            "docker_not_installed",
            True,
            severity="medium",
            cis_level=1,
            message="Docker not installed",
        )
    else:
        scorer.add(
            "docker_service",
            report["docker"]["service"] == "active",
            severity="medium",
            cis_level=1,
            message="Docker service should be active",
        )

    # Root account
    ps = run_cmd("passwd -S root 2>/dev/null || true")
    root_locked = False
    if ps:
        parts = ps.split()
        if len(parts) >= 2 and parts[1].startswith("L"):
            root_locked = True

    scorer.add(
        "root_locked",
        root_locked,
        severity="high",
        cis_level=1,
        message="root account should be locked",
    )

    # timesyncd
    scorer.add(
        "timesyncd",
        run_cmd("systemctl is-active systemd-timesyncd 2>/dev/null || echo inactive")
        == "active",
        severity="medium",
        cis_level=1,
        message="timesyncd should be active",
    )

    # auditd
    scorer.add(
        "auditd_installed",
        report["auditd"]["installed"] is True,
        severity="high",
        cis_level=1,
        message="auditd should be installed",
    )
    scorer.add(
        "auditd_service",
        report["auditd"]["service"] == "active",
        severity="high",
        cis_level=1,
        message="auditd must be running",
    )

    # audispd plugins (L2)
    scorer.add(
        "audispd_plugins",
        report["auditd"].get("audispd_plugins") in ("yes", True, "True"),
        severity="low",
        cis_level=2,
        message="audispd-plugins should be installed",
    )

    # AIDE
    if report["aide"]["installed"]:
        scorer.add(
            "aide_check",
            report["aide"]["result"] == "ok",
            severity="high",
            cis_level=2,
            message="AIDE check should pass",
        )
    else:
        scorer.add(
            "aide_installed",
            False,
            severity="high",
            cis_level=2,
            message="AIDE not installed",
        )

    # Lynis
    if report["lynis"]["installed"]:
        ly_score = report["lynis"].get("score") or 0
        scorer.add(
            "lynis_score",
            ly_score >= 60,
            severity="high",
            cis_level=2,
            message=f"Lynis hardening index >= 60 (found {ly_score})",
        )
    else:
        scorer.add(
            "lynis_installed",
            False,
            severity="low",
            cis_level=2,
            message="Lynis not installed",
        )

    # rkhunter
    if report["rkhunter"]["installed"]:
        scorer.add(
            "rkhunter",
            len(report["rkhunter"]["warnings"]) == 0,
            severity="high",
            cis_level=2,
            message="rkhunter must show no real warnings",
        )
    else:
        scorer.add(
            "rkhunter_installed",
            False,
            severity="low",
            cis_level=2,
            message="rkhunter not installed",
        )

    # Required packages
    scorer.add(
        "packages_required",
        len(report["packages"]["missing"]) == 0,
        severity="high",
        cis_level=1,
        message="required packages missing: "
        + (",".join(report["packages"]["missing"]) or "none"),
    )

    # Compute score
    scoring = scorer.compute()
    report["compliance_score"] = scoring["score"]

    # -------------------------------------------------------
    # ADD SSH CHECK FAILURES TO CODEQUALITY
    # -------------------------------------------------------
    failed_checks = scoring["failed"]

    # Add algorithm/moduli weaknesses from SSH module
    ssh_weak = report["ssh"]["hardening"]

    for w in ssh_weak["weak_algorithms"]:
        failed_checks.append(
            {
                "name": f"ssh_weak_algorithm:{w}",
                "severity": "high",
                "message": f"Weak SSH algorithm detected: {w}",
            }
        )

    if ssh_weak["weak_moduli"]:
        failed_checks.append({
            "name": "ssh_weak_moduli",
            "severity": "high",
            "message": f"Weak SSH moduli detected ({ssh_weak['weak_moduli_count']} entries): {ssh_weak['weak_moduli']}"
        })

    # -------------------------------------------------------
    # WRITE ALL OUTPUTS (json, metrics, codequality)
    # -------------------------------------------------------
    write_all_reports(args.out_dir, report, failed_checks)

    # -------------------------------------------------------
    # TERMINAL SUMMARY
    # -------------------------------------------------------
    print(f"[cyan]Hostname:[/cyan] {report.get('hostname')}")
    print(f"[cyan]Compliance Score:[/cyan] {report.get('compliance_score')}%")
    print(
        f"[cyan]SSH Hardening Score:[/cyan] {report['ssh']['hardening']['score']}%"
    )

    if failed_checks:
        print("[red]Failed checks:[/red]")
        for f in failed_checks:
            print(f" - [red]{f['name']}[/red]: {f['message']}")
    else:
        print("[green]All checks passed[/green]")

    # Gate pipeline if requested
    if (
        args.fail_on_threshold
        and report["compliance_score"] < args.cis_threshold
    ):
        print(
            f"[red]Compliance {report['compliance_score']} < threshold {args.cis_threshold}; failing pipeline.[/red]"
        )
        raise SystemExit(2)

if __name__ == "__main__":
    main()
