#!/usr/bin/env python3
"""Build dist/web_of_night_city-<version>.zip laid out from the Cyberpunk 2077 game folder root.

Runs preflight, codegen and the simulator first; refuses to package if any of them fail.
"""
import hashlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod" / "web_of_night_city"
DEST = "bin/x64/plugins/cyber_engine_tweaks/mods/web_of_night_city"


def run(*args):
    r = subprocess.run([sys.executable, *args], cwd=ROOT)
    if r.returncode != 0:
        sys.exit(f"package: {' '.join(args)} failed")


def main():
    run("tools/preflight.py")
    run("tools/gen.py")
    run("tests/run_sim.py", "--no-write")
    version = re.search(r'version = "([^"]+)"', (MOD / "init.lua").read_text()).group(1)
    out = ROOT / "dist" / f"web_of_night_city-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    files = sorted(p for p in MOD.rglob("*") if p.is_file() and p.suffix == ".lua")
    files.append(ROOT / "README.md")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in files:
            rel = f.relative_to(MOD) if f.is_relative_to(MOD) else Path(f.name)
            info = zipfile.ZipInfo(f"{DEST}/{rel.as_posix()}", date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, f.read_bytes())
    data = out.read_bytes()
    print(f"package: {out.relative_to(ROOT)} {len(data)} bytes sha256={hashlib.sha256(data).hexdigest()}")
    with zipfile.ZipFile(out) as z:
        for n in z.namelist():
            print("   ", n)


if __name__ == "__main__":
    main()
