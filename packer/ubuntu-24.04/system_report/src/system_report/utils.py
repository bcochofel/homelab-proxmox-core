import json
import subprocess
from pathlib import Path

def run_cmd(cmd, capture_output=True, shell=True):
    try:
        if capture_output:
            out = subprocess.check_output(cmd, shell=shell, stderr=subprocess.STDOUT, text=True)
            return out.strip()
        else:
            subprocess.check_call(cmd, shell=shell)
            return ""
    except subprocess.CalledProcessError as e:
        return e.output.strip() if getattr(e, 'output', None) else ""

def read_file(path: str) -> str:
    p = Path(path)
    if not p.exists(): return ""
    try:
        return p.read_text()
    except Exception:
        return ""

def write_json(path: str, data, indent=2):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=indent)

def write_text(path: str, text: str):
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        f.write(text)

def safe_int(s, default=0):
    try:
        return int(s)
    except Exception:
        return default
