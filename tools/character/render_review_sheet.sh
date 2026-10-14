#!/usr/bin/env bash
# SEKAI / CHARACTER LINE — Godot review-sheet renderer
#
# Renders N review views per placeholder character through
# CharacterAssetTest.tscn, then composites one labelled contact sheet per
# character with Blender (pure pixel copy, no external deps).
#
#   bash tools/character/render_review_sheet.sh <out_dir> <char1> [char2 ...]
#
# Character name is the basename of
#   godot/assets/characters/placeholders/<char>.glb
#
# Emits per character:  <char>_report.json  (bones/clips/AABB as Godot imported)
#                       <char>__<view>.png  (6 renders)
#                       <char>_CONTACT.png  (labelled 3x2 sheet)
#
# NOTE: every Godot invocation here exits on its own. If you add a new mode to
# character_asset_test.gd, keep that property or this loop will deadlock.

set -u

OUT="${1:?usage: render_review_sheet.sh <out_dir> <char...>}"
shift
[ "$#" -ge 1 ] || { echo "render_review_sheet.sh: no characters given" >&2; exit 1; }

ROOT="${SEKAI_ROOT:-F:/SEKAI}"
G="${GODOT_BIN:-/g/Godot/Godot_v4.4.1-stable_win64_console.exe}"
BLENDER="${BLENDER_BIN:-/g/blender.exe}"
PROJ="$ROOT/godot"
SCENE="res://scenes/characters/CharacterAssetTest.tscn"
TOOL="$ROOT/tools/character/make_contact_sheet.py"

mkdir -p "$OUT"
[ -x "$G" ] || { echo "no godot at $G" >&2; exit 1; }

# view = name:yaw:pitch:dist:clip:phase   (yaw/pitch radians; phase = seconds the
# clip must PLAY before the shot, reached by real stepping, not seeking)
VIEWS=(
  "idle_front:0.0:0.06:3.2:Idle:0.6"
  "walk_q34:0.75:0.08:3.2:Walk:0.5"
  "jog_side:1.5708:0.06:3.2:Jog_Fwd:0.35"
  "sit_q34:0.9:0.10:2.6:Sitting_Idle:0.6"
  "sword_front:0.25:0.06:3.2:Sword_Idle:0.5"
  "interact_q34:1.1:0.10:3.0:Interact:0.8"
)
PLAN="$(printf '%s;' "${VIEWS[@]}")"
PLAN="${PLAN%;}"

fail=0
for c in "$@"; do
  GLB="res://assets/characters/placeholders/$c.glb"
  if [ ! -f "$PROJ/assets/characters/placeholders/$c.glb" ]; then
    echo "SKIP $c: $PROJ/assets/characters/placeholders/$c.glb missing" >&2
    fail=1
    continue
  fi

  # Report run also warms the import cache, so the plan run that follows is fast.
  timeout 300 "$G" --path "$PROJ" --resolution 900x1000 "$SCENE" -- \
       --glb "$GLB" --report "$OUT/${c}_report.json" >/dev/null 2>&1

  # All six views in ONE process -- a launch costs ~85 s, the frames cost ~0.7 s.
  # `timeout` is not decoration: if the scene script fails to PARSE, Godot loads
  # the scene with no script at all, nothing ever calls quit(), and the process
  # sits there forever. Without a cap the whole batch wedges silently.
  timeout 300 "$G" --path "$PROJ" --resolution 900x1000 "$SCENE" -- \
       --glb "$GLB" --plan "$PLAN" --out-prefix "$OUT/${c}__" 2>&1 \
       | grep -E '^\[CHARTEST-PLAN|SCRIPT ERROR|Parse Error' | sed 's/^/  /'

  SHOTS=()
  missing=0
  for v in "${VIEWS[@]}"; do
    n="${v%%:*}"
    png="$OUT/${c}__${n}.png"
    [ -f "$png" ] || { echo "  MISSING render: $png" >&2; missing=1; fail=1; }
    SHOTS+=("$png")
  done
  [ "$missing" -eq 0 ] || continue

  "$BLENDER" -b --factory-startup --python "$TOOL" -- \
      --out "$OUT/${c}_CONTACT.png" --cell 500x620 --cols 3 --bg 0.10 -- "${SHOTS[@]}" 2>&1 \
      | grep -E '^\[SHEET\]|^SHEET_DONE|no input images'
  echo "done $c"
done

echo "--- PNG count: $(ls "$OUT"/*.png 2>/dev/null | wc -l) ---"
exit $fail
