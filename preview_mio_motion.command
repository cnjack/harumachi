#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./native/mio-companion/tools/build_app.sh
exec ./native/mio-companion/dist/Mio.app/Contents/MacOS/MioCompanion --preview-motion
