#!/bin/zsh
# usage: codex_gen_ref.sh <relative-out-path-under-anime> <prompt-file> <ref image> [<ref image> ...]
ROOT="/Users/jack/workpath/research/3D model/anime"
OUT="$1"; PF="$2"; shift 2
mkdir -p "$ROOT/$(dirname $OUT)"
[[ "$PF" = /* ]] || PF="$ROOT/$PF"
BRIEF="$(cat "$PF")"
[ -n "$BRIEF" ] || { echo "empty brief $PF"; exit 1; }
IMGS=()
for f in "$@"; do IMGS+=(-i "$ROOT/$f"); done
codex exec --skip-git-repo-check -s workspace-write -C "$ROOT" "${IMGS[@]}" -- "Use your built-in image generation tool (image_gen) to create exactly ONE new image for the brief below. The attached images are references only: character portraits (keep those characters' faces, hair and colours) and/or a finished anime frame (match its drawing style, line weight and colouring). Draw a brand-new scene. Do not edit or post-process the result. Copy the generated PNG file to $OUT (relative to the working directory) and reply with the final path only.

Image brief: $BRIEF" > "$ROOT/$OUT.log" 2>&1
ls -la "$ROOT/$OUT"
