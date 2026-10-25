#!/bin/zsh
set -eu
cd "$(dirname "$0")"
exec python3 tools/material_light_poc.py review --out evidence/material_light_refine_20261025/interactive --timeout 3600
