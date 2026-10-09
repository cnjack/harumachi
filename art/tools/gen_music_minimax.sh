#!/bin/zsh
# Generate the game's main music with the local MiniMax Music 3 (MLX) server from
# /Users/jack/workpath/research/music (start it there with ./run-server.sh).
#   art/tools/gen_music_minimax.sh [name ...]      names: title day market ending
set -euo pipefail
ROOT="${0:A:h:h:h}"
REQ="$ROOT/art/manifests/music_minimax"
RAW="$ROOT/art/audio/music_raw"
PORT="${MINIMAX_PORT:-11438}"
mkdir -p "$RAW"
names=(${@:-title day market ending})
for n in $names; do
  echo "== $n"
  t0=$(date +%s)
  curl --fail-with-body --silent --show-error \
    "http://127.0.0.1:$PORT/v1/audio/music-generations" \
    -H 'Content-Type: application/json' \
    --data-binary "@$REQ/$n.json" \
    --output "$RAW/$n.wav"
  echo "   $(( $(date +%s) - t0 )) s"
  ffprobe -v error -show_entries format=duration -of default=nw=1 "$RAW/$n.wav"
done
