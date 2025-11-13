import argparse
from .checks import ipv6, ssh, docker, proxy, aide, auditd, packages, lynis, rkhunter
from .scoring import Scorer
from .reports import write_all_reports
from .utils import run_cmd
from rich import print

def build_report(cis_mode=1):
    report = {}
    report['hostname'] = run_cmd('hostname --fqdn 2>/dev/null || hostname')
    report['kernel'] = run_cmd('uname -r 2>/dev/null || echo unknown')
    report['ipv6'] = ipv6.check_ipv6()
    report['ssh'] = ssh.check_ssh_hardening()
    report['docker'] = docker.check_docker()
    report['proxy'] = proxy.check_proxy()
    report['aide'] = aide.check_aide()
    report['auditd'] = auditd.check_auditd()
    report['packages'] = packages.check_packages()
    report['lynis'] = lynis.check_lynis()
    report['rkhunter'] = rkhunter.check_rkhunter()

    scorer = Scorer(cis_mode=cis_mode)
    scorer.add('ipv6_sysctl', report['ipv6']['sysctl']=='disabled', severity='low', cis_level=2, message='IPv6 sysctl should be disabled')
    scorer.add('ssh_permit_root', report['ssh']['permit_root_login'].lower()=='no', severity='high', cis_level=1, message='PermitRootLogin should be no')
    scorer.add('ssh_password_auth', report['ssh']['password_authentication'].lower()=='no', severity='high', cis_level=1, message='PasswordAuthentication should be no')
    scorer.add('ssh_protocol', report['ssh']['protocol']=='2', severity='high', cis_level=1, message='SSH Protocol should be 2')
    docker_installed = 'not installed' not in report['docker']['version'].lower()
    if not docker_installed:
        scorer.add('docker_not_installed', True, severity='medium', cis_level=1, message='Docker not installed')
    else:
        scorer.add('docker_service', report['docker']['service']=='active', severity='medium', cis_level=1, message='Docker service should be active')
    root_locked = False
    ps = run_cmd('passwd -S root 2>/dev/null || true')
    if ps:
        parts = ps.split()
        if len(parts) >= 2 and parts[1].startswith('L'):
            root_locked = True
    scorer.add('root_locked', root_locked, severity='high', cis_level=1, message='root account should be locked')
    scorer.add('timesyncd', run_cmd('systemctl is-active systemd-timesyncd.service 2>/dev/null || echo inactive')=='active', severity='medium', cis_level=1, message='timesyncd should be active')
    scorer.add('cloud_init', run_cmd('systemctl is-active cloud-init 2>/dev/null || echo inactive')=='active', severity='medium', cis_level=1, message='cloud-init should be active')
    scorer.add('auditd_installed', report['auditd']['installed'] is True, severity='high', cis_level=1, message='auditd should be installed')
    scorer.add('auditd_service', report['auditd']['service']=='active', severity='high', cis_level=1, message='auditd should be running')
    scorer.add('audispd_plugins', report['auditd'].get('audispd_plugins') in (True,'yes','True'), severity='low', cis_level=2, message='audispd-plugins should be installed')
    if report['aide']['installed']:
        scorer.add('aide_check', report['aide']['result']=='ok', severity='high', cis_level=2, message='AIDE check should pass')
    else:
        scorer.add('aide_installed', False, severity='high', cis_level=2, message='AIDE not installed')
    if report['lynis']['installed']:
        ly_score = report['lynis']['score'] or 0
        scorer.add('lynis_score', ly_score >= 60, severity='high', cis_level=2, message=f'Lynis hardening index >= 60 (found {ly_score})')
    else:
        scorer.add('lynis_installed', False, severity='low', cis_level=2, message='Lynis not installed')
    if report['rkhunter']['installed']:
        scorer.add('rkhunter', len(report['rkhunter']['warnings'])==0, severity='high', cis_level=2, message='rkhunter should report no warnings')
    else:
        scorer.add('rkhunter_installed', False, severity='low', cis_level=2, message='rkhunter not installed')
    scorer.add('packages_required', len(report['packages']['missing'])==0, severity='high', cis_level=1, message='required packages missing: '+(','.join(report['packages']['missing']) if report['packages']['missing'] else 'none'))

    scoring = scorer.compute()
    report['compliance_score'] = scoring['score']
    return report, scoring['failed']

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--cis-mode', type=int, default=1, choices=[1,2])
    parser.add_argument('--cis-threshold', type=int, default=85)
    parser.add_argument('--fail-on-threshold', action='store_true')
    parser.add_argument('--out-dir', default='.')
    args = parser.parse_args()

    report, failed = build_report(cis_mode=args.cis_mode)
    write_all_reports(args.out_dir, report, failed)

    print(f"[cyan]Host:[/cyan] {report.get('hostname')}")
    print(f"[cyan]Compliance Score:[/cyan] [bold]{report.get('compliance_score')}%[/bold]")
    if failed:
        print('[red]Failed checks:[/red]')
        for f in failed:
            print(f" - [red]{f['name']}[/red]: {f['message']}")
    else:
        print('[green]All checks passed[/green]')

    if args.fail_on_threshold and report.get('compliance_score',0) < args.cis_threshold:
        print(f"[red]Compliance {report.get('compliance_score')} < threshold {args.cis_threshold}; failing as requested[/red]")
        raise SystemExit(2)

if __name__ == '__main__':
    main()
