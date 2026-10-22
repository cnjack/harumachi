#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
if ! python3 native/mio-companion/tools/voice_services.py start; then
  echo "本机语音服务未启动，桌面来信仍可使用文字对话。"
fi
./native/mio-companion/tools/build_app.sh
open "$PWD/native/mio-companion/dist/Mio.app"
