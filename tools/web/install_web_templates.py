#!/usr/bin/env python3
"""Compatibility entry point for the version-pinned template installer."""
from datetime import date
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
arguments = sys.argv[1:]
if "--evidence" not in arguments:
    arguments += ["--evidence", str(root / "evidence" / ("godot_templates_" + date.today().strftime("%Y%m%d")))]
subprocess.run([sys.executable, str(root / "tools/install_godot_templates.py"), "--platform", "web", *arguments], check=True)
