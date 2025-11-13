from ..utils import run_cmd

def check_ipv6():
    sysctl = run_cmd("sysctl net.ipv6.conf.all.disable_ipv6 || true")
    sysctl_disabled = " = 1" in sysctl
    cmdline = run_cmd("cat /proc/cmdline || true")
    grub_disabled = "ipv6.disable=1" in cmdline
    grub_cfg = run_cmd("grep -R \"ipv6.disable=1\" /etc/default/grub /etc/default/grub.d 2>/dev/null || true")
    if grub_cfg:
        grub_disabled = True
    status = "disabled" if (sysctl_disabled or grub_disabled) else "enabled"
    return {
        "sysctl": "disabled" if sysctl_disabled else "enabled",
        "grub_or_cmdline": "disabled" if grub_disabled else "enabled",
        "status": status,
    }
