from ..utils import run_cmd, read_file
import json
from pathlib import Path

def read_apt_proxy():
    out = run_cmd("grep -E 'Acquire::http::Proxy|Acquire::https::Proxy' /etc/apt/apt.conf /etc/apt/apt.conf.d/* 2>/dev/null || true")
    http = ""; https = ""
    for line in out.splitlines():
        if 'Acquire::http::Proxy' in line:
            parts = line.split('"')
            if len(parts) >= 2:
                http = parts[1]
        if 'Acquire::https::Proxy' in line:
            parts = line.split('"')
            if len(parts) >= 2:
                https = parts[1]
    return {"http": http, "https": https}

def read_env_proxy():
    env = {}
    for k in ["http_proxy","HTTP_PROXY","https_proxy","HTTPS_PROXY","no_proxy","NO_PROXY"]:
        v = run_cmd(f"printenv {k} || true")
        if v:
            env[k.lower()] = v
    envfile = read_file('/etc/environment')
    for line in envfile.splitlines():
        if '=' in line:
            k, v = line.split('=', 1)
            k = k.strip(); v = v.strip().strip('"')
            if k.lower() in ['http_proxy','https_proxy','no_proxy'] and k.lower() not in env:
                env[k.lower()] = v
    return env

def read_docker_daemon_proxy():
    p = Path('/etc/docker/daemon.json')
    http = https = no = ""
    if p.exists():
        try:
            j = json.loads(p.read_text())
            proxies = j.get('proxies', {})
            default = proxies.get('default', {})
            http = default.get('httpProxy','')
            https = default.get('httpsProxy','')
            no = default.get('noProxy','')
        except Exception:
            pass
    out = run_cmd("grep -R \"HTTP_PROXY\" /etc/systemd/system/docker.service.d 2>/dev/null || true")
    if out:
        import re
        m = re.search(r'HTTP_PROXY=(\"?)([^\"\n ]+)\1', out)
        if m:
            http = m.group(2)
    return {"http": http, "https": https, "no_proxy": no}

def read_docker_client_proxy():
    p = Path.home() / '.docker' / 'config.json'
    if p.exists():
        try:
            j = json.loads(p.read_text())
            default = j.get('proxies', {}).get('default', {})
            return {'http': default.get('httpProxy',''), 'https': default.get('httpsProxy',''), 'no_proxy': default.get('noProxy','')}
        except Exception:
            return {'http':'','https':'','no_proxy':''}
    return {'http':'','https':'','no_proxy':''}

def check_proxy():
    return {'env': read_env_proxy(), 'apt': read_apt_proxy(), 'docker_daemon': read_docker_daemon_proxy(), 'docker_client': read_docker_client_proxy()}
