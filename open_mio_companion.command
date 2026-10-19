#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./native/mio-companion/tools/build_app.sh
open "$PWD/native/mio-companion/dist/Mio.app"
