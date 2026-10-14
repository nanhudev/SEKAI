#!/usr/bin/env bash
# SEKAI / CHARACTER LINE — placeholder character baker
#
# Runs retarget_humanoid.py over tools/character/placeholders.tsv and lands a
# self-contained GLB (+ retarget metadata) per character.
#
#   bash tools/character/bake_placeholders.sh                 # all 21
#   bash tools/character/bake_placeholders.sh lpg_witch_w ... # named only
#
# Output: assets_source/characters/placeholders/<name>.glb
#         assets_source/characters/placeholders/<name>_retarget.json
# Mirror to Godot afterwards (see render_review_sheet.sh / docs spec).

set -u

ROOT="${SEKAI_ROOT:-F:/SEKAI}"
BLENDER="${BLENDER_BIN:-/g/blender.exe}"
MANIFEST="$ROOT/tools/character/placeholders.tsv"
TOOL="$ROOT/tools/character/retarget_humanoid.py"
LIB="$ROOT/third_party/quaternius/universal_animation_library/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb"
CLIPFILE="$ROOT/tools/character/clips_standard.txt"
OUTDIR="$ROOT/assets_source/characters/placeholders"

[ -f "$MANIFEST" ] || { echo "no manifest at $MANIFEST" >&2; exit 1; }
[ -f "$LIB" ] || { echo "no animation library at $LIB" >&2; exit 1; }
[ -f "$CLIPFILE" ] || { echo "no clip list at $CLIPFILE" >&2; exit 1; }
mkdir -p "$OUTDIR"

# Curated clip set -> comma list. Deliberately NOT `--clips all`: see the header
# of clips_standard.txt for why the pistol and root-motion clips stay out.
CLIPS="$(grep -v '^[[:space:]]*#' "$CLIPFILE" | grep -v '^[[:space:]]*$' | tr -d '\r' | paste -sd, -)"
[ -n "$CLIPS" ] || { echo "clip list is empty" >&2; exit 1; }
CLIPN="$(printf '%s' "$CLIPS" | tr ',' '\n' | grep -c .)"
echo "clip set: $CLIPN clips from $(basename "$CLIPFILE")"

wanted=("$@")
want() {
  [ "${#wanted[@]}" -eq 0 ] && return 0
  local n
  for n in "${wanted[@]}"; do [ "$n" = "$1" ] && return 0; done
  return 1
}

baked=0
failed=0
while IFS=$'\t' read -r name rel height; do
  case "$name" in ''|'#'*) continue ;; esac
  want "$name" || continue

  src="$ROOT/$rel"
  if [ ! -f "$src" ]; then
    echo "SKIP $name: missing $src" >&2
    failed=$((failed + 1))
    continue
  fi

  out="$OUTDIR/$name.glb"
  # Keep a copy of the old bake so a regression is diffable rather than silent.
  [ -f "$out" ] && cp -f "$out" "$out.prev"

  echo "=== bake $name (h=$height) <- $(basename "$rel")"
  "$BLENDER" -b --factory-startup --python "$TOOL" -- \
      --target "$src" --lib "$LIB" --name "$name" \
      --out-glb "$OUTDIR" --out-json "$OUTDIR/${name}_retarget.json" \
      --target-height "$height" --fps 30 --clips "$CLIPS" --skip A_TPose \
      2>&1 | grep -E '^\[RETGT\]|Error|Traceback' | sed 's/^/    /'

  if [ -f "$out" ]; then
    baked=$((baked + 1))
  else
    echo "  FAILED: no GLB produced for $name" >&2
    failed=$((failed + 1))
  fi
done < "$MANIFEST"

echo "--- baked=$baked failed=$failed ---"
[ "$failed" -eq 0 ]
