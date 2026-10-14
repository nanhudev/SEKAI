#!/usr/bin/env bash
# §V4·B — renders the floating-motion pass and files the six key frames §20 names.
#
# Four steps that have to happen together, which is why this is a script and not
# four commands pasted into a transcript:
#
#   1. RENDER the `motion` tour TWICE, at two resolutions, in a VISIBLE window.
#
#      WHY TWICE. The renderer captures in REAL TIME and writes down the frame rate
#      it actually managed, and on this machine that rate is a function of
#      resolution: 1280x720 measures ~17.5 fps, 960x540 measures ~28. That is not a
#      quality knob, it is the SAMPLING RATE of a film about MOTION — §9's dodge
#      kick lasts 183 ms, which is 3 frames at 17.5 fps and 5 at 28. The A1 slice
#      settled this convention already (see PRODUCTION_BUDGET notes): the CLIP is
#      shot at 960x540 so the fast beats have frames to exist in, and the STILLS are
#      shot at 1280x720 because a still is looked at rather than played.
#
#      ⛔ --headless IS NOT AN OPTION FOR EITHER. The renderer awaits
#      `RenderingServer.frame_post_draw` for every frame it captures, and with no
#      rendering device that signal never fires, so the run HANGS FOREVER instead
#      of failing loudly. §18 asks for a visible training ground; this is what
#      satisfies it.
#
#   2. ENCODE at the frame rate MEASURED (`fps.txt`), not a guessed one — encoding
#      at a nominal 60 would resample the whole film.
#
#   3. FILE the six stills under the exact names §20 asks for. The renderer writes
#      `still_<tag>.png`, so the delivered name is a copy — and a still the renderer
#      never captured FAILS this script rather than quietly shipping five of six.
#      A named beat with no picture is the exact failure `_report_missing_stills`
#      exists to shout about.
#
# Usage: render_chain_motion_pass.sh [godot] [ffmpeg]
set -euo pipefail

GODOT="${1:-G:/Godot/Godot_v4.4.1-stable_win64_console.exe}"
# ffmpeg IS NOT ON THIS MACHINE'S PATH, and `encode_combat_movie.sh` defaults to the
# bare name — so this script resolves it rather than assuming. Ordered by capability:
# the first is a full build (the only one here shipping libx264 as well as the
# hardware encoders), and the encoder tries its candidates in quality order, so the
# last one has to exist for the case where the GPU ones refuse.
FFMPEG="${2:-}"
if [[ -z "$FFMPEG" ]]; then
	for candidate in \
		"/c/Program Files (x86)/fastpdf/ffmpeg.exe" \
		"/g/娱乐/JianyingPro/4.9.0.10872/ffmpeg.exe" \
		"/f/ACLOS/Cross/recorder-release/ffmpeg.exe"; do
		if [[ -x "$candidate" ]]; then
			FFMPEG="$candidate"
			break
		fi
	done
fi
if [[ -z "$FFMPEG" ]] || ! "$FFMPEG" -hide_banner -version >/dev/null 2>&1; then
	echo "no usable ffmpeg — pass one as the second argument" >&2
	exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MOVIE_DIR="$ROOT/.render/motion"
STILL_DIR="$ROOT/.render/motion_stills"
OUT="$ROOT/.render/chain_v4_floating_motion_pass.mp4"

# §20's six, in the order the brief lists them.
STILLS=(01_idle 02_sprint_lag 03_dodge_lag 04_a1_release 05_wall_bite 06_repacked_idle)

echo "ffmpeg: $FFMPEG"
echo "== 1/4 stills render (1280x720) -> $STILL_DIR"
"$GODOT" --path "$ROOT/godot" --resolution 1280x720 --audio-driver Dummy \
	--script res://tools/combat_movie_renderer.gd -- \
	"$STILL_DIR" 999 0 motion fp clean

echo "== 2/4 clip render (960x540) -> $MOVIE_DIR"
"$GODOT" --path "$ROOT/godot" --resolution 960x540 --audio-driver Dummy \
	--script res://tools/combat_movie_renderer.gd -- \
	"$MOVIE_DIR" 999 0 motion fp clean

echo "== 3/4 encode -> $OUT"
"$ROOT/godot/tools/encode_combat_movie.sh" "$MOVIE_DIR" "$OUT" "$FFMPEG"

echo "== 4/4 file the six key frames"
missing=0
for tag in "${STILLS[@]}"; do
	src="$STILL_DIR/still_$tag.png"
	if [[ ! -f "$src" ]]; then
		echo "  !! $tag was never captured by the renderer" >&2
		missing=$((missing + 1))
		continue
	fi
	cp -f "$src" "$ROOT/.render/$tag.png"
	echo "  $tag.png"
done

if [[ "$missing" -ne 0 ]]; then
	echo "DELIVERY INCOMPLETE: $missing of ${#STILLS[@]} key frames missing" >&2
	exit 1
fi

echo "done: $OUT"
