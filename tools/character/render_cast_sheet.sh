#!/usr/bin/env bash
# SEKAI / C-PH -- render the WHOLE placeholder roster into one grid PNG.
#
# One Godot launch, N characters. A launch costs ~85 s of startup + asset load +
# first-shader compile, so doing this per character would be ~30 min for 21; the
# whole roster now takes about a minute.
#
#   bash tools/character/render_cast_sheet.sh [out.png] [cast_file] [cols]
#
# Defaults: assets_source/characters/placeholders/_review/CAST_all.png
#           tools/character/cast_all.txt        7 columns
#
# Cell size == --resolution. Total sheet = (cols*W) x (ceil(N/cols)*H).
# 21 chars at 360x480 x 7 cols  ->  2520x1440.
#
# Regenerate the cast list after adding characters:
#   tools/character/placeholders.tsv  ->  tools/character/cast_all.txt
#
# !! NEVER add --headless. The capture waits on SubViewport/viewport
#    frame_post_draw, and headless has no rendering device -> permanent hang.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
G="${GODOT:-/g/Godot/Godot_v4.4.1-stable_win64_console.exe}"
SCENE="res://scenes/characters/CharacterAssetTest.tscn"

OUT="${1:-$ROOT/assets_source/characters/placeholders/_review/CAST_all.png}"
CAST="${2:-$ROOT/tools/character/cast_all.txt}"
COLS="${3:-7}"

CELL_W="${CELL_W:-360}"
CELL_H="${CELL_H:-480}"
ANIM="${ANIM:-Idle}"
PHASE="${PHASE:-0.45}"
PIVOT_Y="${PIVOT_Y:-0.95}"
DIST="${DIST:-3.2}"
TIMEOUT="${TIMEOUT:-300}"

[ -f "$CAST" ] || { echo "no cast list at $CAST" >&2; exit 1; }
N=$(grep -cvE '^\s*(#|$)' "$CAST")
[ "$N" -gt 0 ] || { echo "cast list $CAST has no entries" >&2; exit 1; }

# ABSOLUTISE.  Godot's FileAccess resolves relative paths against the PROJECT
# ROOT (godot/), not the shell's CWD, so a relative --cast-file silently finds
# nothing: the list reads as empty, the scene quits(1), and the only message
# goes to stderr where the grep below used to eat it.  Cost one debugging round.
abspath() { case "$1" in /*|[A-Za-z]:[\\/]*) printf '%s' "$1" ;; *) printf '%s/%s' "$ROOT" "$1" ;; esac; }
OUT="$(abspath "$OUT")"
CAST="$(abspath "$CAST")"
mkdir -p "$(dirname "$OUT")"

echo "cast: $N characters  cell=${CELL_W}x${CELL_H}  cols=$COLS  clip=$ANIM"

# `timeout` is not optional: a script error inside the scene means quit() is never
# reached, and Godot then blocks forever instead of failing.
LOG="$(mktemp)"
timeout "$TIMEOUT" "$G" --path "$ROOT/godot" \
  --resolution "${CELL_W}x${CELL_H}" "$SCENE" -- \
  --cast-file "$CAST" --cast-out "$OUT" --cast-cols "$COLS" \
  --cast-anim "$ANIM" --cast-phase "$PHASE" \
  --pivot-y "$PIVOT_Y" --dist "$DIST" >"$LOG" 2>&1
rc=$?

grep -E '^\[CHARTEST-CAST' "$LOG" | sed 's/^/  /'

if [ -f "$OUT" ]; then
  echo "OK  $OUT"
else
  # Never discard the reason: the old pipeline grep'd stderr away and reported
  # only "no sheet written", which is the least useful half of the story.
  echo "FAILED (godot rc=$rc, no sheet written)" >&2
  echo "--- godot output (last 20 lines) ---" >&2
  tail -20 "$LOG" >&2
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"
[ "$rc" = "0" ] || { echo "FAILED (godot rc=$rc)" >&2; exit "$rc"; }
