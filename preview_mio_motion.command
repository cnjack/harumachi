#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
# Keep existing shortcuts working; all user launchers open Desktop Mail.
exec ./open_mio_companion.command
