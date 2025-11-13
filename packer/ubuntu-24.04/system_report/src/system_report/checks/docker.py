from ..utils import run_cmd

def check_docker():
    version = run_cmd("docker --version 2>/dev/null || true")
    compose = run_cmd("docker compose version 2>/dev/null || docker-compose --version 2>/dev/null || true")
    service = run_cmd("systemctl is-active docker 2>/dev/null || echo inactive")
    return {"version": version or "not installed", "compose": compose or "not installed", "service": service}
