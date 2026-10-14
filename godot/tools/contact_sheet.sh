#!/usr/bin/env bash
# Tiles an explicit list of frames from a PNG sequence into one labelled contact sheet.
#
# WHY A SHEET AND NOT THE STILLS. §19 asks for a MOTION review, and a still cannot
# show motion — the memory note on this line is that "静帧骗人" (stills lie). What
# actually answers "did the chain lag the run" is a ROW of consecutive frames read
# together, which is one image to look at instead of twelve. The named stills §20
# asks for are a separate artefact with a separate job.
#
# The frame numbers are ABSOLUTE in the tour's sequence (`frame_%04d.png`), which is
# why they are passed in rather than derived: the renderer's own log prints the frame
# index of every segment boundary and every still, so the sheet is built from numbers
# the run actually reported instead of from a guessed frame rate.
#
# LABELLED MODE (§39-B). A delivery sheet has a different job from a motion sheet:
# its cells are NAMED beats, and a reader has to be able to point at a cell and say
# "that is A3 cut 2". So when `SHEET_LABELS` is set — one `|`-separated label per
# frame number, in the same order — the label is burned into the cell.
#
# The label is burned AFTER the downscale, not before. Scaling a 1280px frame that
# already carries 20px text down to 440px leaves 7px text, which is exactly the
# "unreadable because it was drawn at the wrong resolution" failure this mode
# exists to avoid.
#
# Usage: contact_sheet.sh <frames_dir> <out.png> <ncols> [frame numbers...]
#        SHEET_LABELS="A1|A2|..." contact_sheet.sh ...   (optional, same count)
set -euo pipefail

FFMPEG="${FFMPEG:-/c/Program Files (x86)/fastpdf/ffmpeg.exe}"
FRAMES="${1:?frames dir}"
OUT="${2:?output png}"
COLS="${3:?columns}"
shift 3

if [[ "$#" -eq 0 ]]; then
	echo "no frame numbers given" >&2
	exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FONT="${FONT:-C:/Windows/Fonts/arial.ttf}"
SCALE="${SCALE:-440}"

LABELS=()
if [[ -n "${SHEET_LABELS:-}" ]]; then
	IFS='|' read -r -a LABELS <<<"$SHEET_LABELS"
	if [[ "${#LABELS[@]}" -ne "$#" ]]; then
		echo "SHEET_LABELS has ${#LABELS[@]} labels for $# frames" >&2
		exit 1
	fi
fi

i=0
for n in "$@"; do
	src="$(printf '%s/frame_%04d.png' "$FRAMES" "$n")"
	if [[ ! -f "$src" ]]; then
		echo "missing $src" >&2
		exit 1
	fi
	# renumbered densely so ffmpeg's image2 demuxer reads them as one sequence;
	# a gap in the numbering would silently truncate the sheet
	i=$((i + 1))
	dst="$(printf '%s/f%04d.png' "$TMP" "$i")"
	if [[ "${#LABELS[@]}" -gt 0 ]]; then
		# `\:` escapes the drive colon so ffmpeg does not read it as a filter
		# separator; `\:` inside the text is avoided by keeping labels colon-free.
		"$FFMPEG" -y -hide_banner -loglevel error -i "$src" \
			-vf "scale=${SCALE}:-1,drawtext=fontfile=${FONT//:/\\:}:text='${LABELS[$((i - 1))]}':x=10:y=10:fontsize=22:fontcolor=white:box=1:boxcolor=black@0.62:boxborderw=7" \
			-frames:v 1 "$dst"
	fi
	# unlabelled mode still needs the scaled frame copied through, and labelled
	# mode has already written it, so the copy is the fallback, not the rule.
	[[ -f "$dst" ]] || cp -f "$src" "$dst"
done

rows=$(( (i + COLS - 1) / COLS ))
# Tile width is a variable because the two uses want different things: a 6-wide sheet
# answers "is this the same over three seconds" at a glance, while a 3-wide one is for
# reading where the chain actually sits relative to the crosshair, and at 440 the whole
# sheet is downscaled past the point where a 4 cm lag is visible at all.
"$FFMPEG" -y -hide_banner -loglevel error \
	-framerate 1 -i "$TMP/f%04d.png" \
	-vf "scale=${SCALE}:-1,tile=${COLS}x${rows}:margin=4:padding=3:color=0x101418" \
	-frames:v 1 "$OUT"
echo "$OUT  ($i frames, ${COLS}x${rows}, tile ${SCALE}px)"
