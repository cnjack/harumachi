#!/bin/zsh
# usage: codex_gen.sh <relative-out-path-under-anime> <prompt-file>
ROOT="/Users/jack/workpath/research/3D model/anime"
OUT="$1"; PF="$2"
mkdir -p "$ROOT/$(dirname $OUT)"
BRIEF="$(cat $PF)"
codex exec --skip-git-repo-check -s workspace-write -C "$ROOT" "Use your built-in image generation tool (image_gen) to create exactly ONE image for the brief below. Do not edit or post-process it. Copy the generated PNG file to $OUT (relative to the working directory) and reply with the final path only.

Image brief: $BRIEF" > "$ROOT/$OUT.log" 2>&1
ls -la "$ROOT/$OUT"
