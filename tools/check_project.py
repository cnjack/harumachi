#!/usr/bin/env python3
"""Source-only project checks; works without downloading LFS payloads in CI."""
import ast
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []
counts = Counter()

def check(condition, message):
    counts['checks'] += 1
    if not condition:
        errors.append(message)

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key: ' + key)
        result[key] = value
    return result

for folder in ['game/data', 'game/ui_kit', 'art/manifests']:
    for file in sorted((ROOT / folder).rglob('*.json')):
        try:
            json.loads(file.read_text(), object_pairs_hook=unique_object)
            counts['json_files'] += 1
        except (ValueError, OSError) as error:
            errors.append(str(file.relative_to(ROOT)) + ': ' + str(error))

lock = json.loads((ROOT / 'tools/godot-version.json').read_text())
project = (ROOT / 'game/project.godot').read_text()
check('"' + lock['feature_version'] + '"' in project.split('config/features=')[1].splitlines()[0], 'Godot feature version differs from version lock')
check('config/custom_user_dir_name="晴町日常"' in project, 'Player save-directory compatibility changed')
check((ROOT / 'game/scenes/title.tscn').exists(), 'Game title scene missing')
check((ROOT / 'site/index.html').exists(), 'Website entry missing')

for folder in ['tools', 'art/tools']:
    for file in sorted((ROOT / folder).rglob('*.py')):
        if '__pycache__' in file.parts:
            continue
        try:
            ast.parse(file.read_text(), filename=str(file))
            counts['python_files'] += 1
        except (SyntaxError, UnicodeError) as error:
            errors.append(str(file.relative_to(ROOT)) + ': ' + str(error))

resource_pattern = re.compile(r'preload\(\s*"(res://[^"\n]+)"\s*\)')
for file in sorted((ROOT / 'game/scripts').rglob('*.gd')):
    for resource in resource_pattern.findall(file.read_text()):
        if any(token in resource for token in ['%', '*', '{']):
            continue
        check((ROOT / 'game' / resource[6:]).exists(), str(file.relative_to(ROOT)) + ': missing preload resource ' + resource)

try:
    listed = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT)
    paths = [item.decode() for item in listed.split(b'\0') if item]
except subprocess.CalledProcessError:
    paths = []
for name in paths:
    parts = Path(name).parts
    forbidden = name.startswith(('builds/', 'evidence/', 'output/', 'site/play/', 'art/poc/')) or '.godot' in parts
    forbidden |= Path(name).name.startswith('.env') and Path(name).name != '.env.example'
    forbidden |= name.endswith(('.db', '.sqlite', '.pem', '.key', '.tokens.json'))
    check(not forbidden, 'Generated/private file is tracked: ' + name)
    file = ROOT / name
    if file.is_file() and file.stat().st_size > 100 * 1024 * 1024:
        indexed_size = int(subprocess.check_output(['git', 'cat-file', '-s', ':' + name], cwd=ROOT))
        check(indexed_size <= 100 * 1024 * 1024, 'Git blob above GitHub limit: ' + name)

print(json.dumps({'passed': not errors, 'counts': dict(counts), 'errors': errors}, ensure_ascii=False, indent=2))
raise SystemExit(1 if errors else 0)
