#!/usr/bin/env bash
# Encodes an Iaido frame sequence into an MP4, with the placeholder audio cues
# mixed in at exactly the times IaidoAudioTimeline fires them.
#
# The picture is rendered by godot/tools/iaido_movie_renderer.gd. The frame
# sequence starts PRE_ROLL frames before t=0, so every audio cue is shifted by
# that same amount to stay in sync with the picture.
#
# Usage: encode_iaido_movie.sh <frames_dir> <out.mp4> [ffmpeg] [godot]
set -euo pipefail

FRAMES="${1:?frames dir}"
OUT="${2:?output mp4}"
FFMPEG="${3:-ffmpeg}"
GODOT="${4:-${GODOT:-godot}}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SFX="$PROJECT/audio/sfx/iaido"

FPS=30
PRE_ROLL=12                     # must match PRE_ROLL in the renderer
OFFSET_MS=$(( PRE_ROLL * 1000 / FPS ))

# Pad the mix to exactly the picture length. Padding to a hardcoded guess
# leaves the container as long as the audio, so the file plays on a frozen
# last frame for the difference.
FRAME_COUNT=$(find "$FRAMES" -name 'frame_*.png' | wc -l)
CLIP_SECONDS=$(awk "BEGIN{printf \"%.3f\", $FRAME_COUNT / $FPS}")
echo "frames: $FRAME_COUNT  ->  ${CLIP_SECONDS}s"

# ---------------------------------------------------------------------------
# THE CUE TABLE IS ASKED FOR, NOT COPIED.
#
# This used to be a hand-typed array mirroring IaidoAudioTimeline._build(), and
# it drifted: `pressure` was still at the old `suck_start` (2.50 against 2.14)
# and `spin` was at 6.25 against 6.45, so the movie's audio sat up to 0.36s away
# from what the game plays. Nothing failed, because nothing compared the two.
#
# Reading the table out of the timeline at encode time makes that impossible:
# IaidoAudioTimeline is the only place a cue time is written down.
# ---------------------------------------------------------------------------
CUE_TABLE="$(cd "$PROJECT" && "$GODOT" --headless --path "$PROJECT" \
  --audio-driver Dummy --script res://tools/dump_iaido_cues.gd 2>/dev/null | grep '^CUE ' || true)"
if [ -z "$CUE_TABLE" ]; then
  echo "could not read the cue table from IaidoAudioTimeline via $GODOT." >&2
  echo "Pass the Godot binary as the 4th argument." >&2
  exit 1
fi

args=(-y -hide_banner -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%04d.png")
filters=""
labels=""
index=1
cue_count=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  cue="${line#CUE }"
  IFS=':' read -r file at gain extra <<< "$cue"
  if [ ! -f "$SFX/$file" ]; then
    echo "cue file missing: $SFX/$file" >&2
    exit 1
  fi
  args+=(-i "$SFX/$file")
  # The time is in ceremony seconds; the picture starts PRE_ROLL earlier, and
  # ffmpeg's adelay is in milliseconds.
  delay=$(( OFFSET_MS + $(awk "BEGIN{printf \"%d\", $at*1000}") ))
  filters+="[${index}:a]${extra:+$extra,}adelay=${delay}:all=1,volume=${gain}dB[a${index}];"
  labels+="[a${index}]"
  index=$(( index + 1 ))
  cue_count=$(( cue_count + 1 ))
done <<< "$CUE_TABLE"
echo "cues: $cue_count (read from IaidoAudioTimeline)"

filters+="${labels}amix=inputs=${cue_count}:normalize=0:dropout_transition=0,apad=whole_dur=${CLIP_SECONDS}[aout]"

# ---------------------------------------------------------------------------
# THE CEREMONY MUST END ON THE WORLD IT BEGAN WITH.
#
# A final frame that is dark is not a subtle failure: it means the void was
# never closed and the whole eight-second restore ended on an empty frame with
# the sword floating in it. That is exactly what a `stream` wedge which
# saturates and never releases produced — the last frame measured 0.10 mean
# luminance against 0.67 for the opening frame — and nothing in the pipeline
# noticed, because the only artefacts anyone looked at were the interesting
# frames in the middle.
#
# A one-pixel area average is enough to catch it and costs one ffmpeg pass per
# frame. Compared as a RATIO, not an absolute, so it survives a lighting or
# exposure change on the ART line.
# ---------------------------------------------------------------------------
mean_luma() {
  "$FFMPEG" -v error -i "$1" -vf "scale=1:1:flags=area,format=gray" \
    -frames:v 1 -f rawvideo - 2>/dev/null | od -An -tu1 | tr -d ' \n'
}
FIRST_FRAME="$FRAMES/frame_0000.png"
LAST_FRAME="$FRAMES/$(printf 'frame_%04d.png' $(( FRAME_COUNT - 1 )) )"
if [ -f "$FIRST_FRAME" ] && [ -f "$LAST_FRAME" ]; then
  FIRST_LUMA=$(mean_luma "$FIRST_FRAME")
  LAST_LUMA=$(mean_luma "$LAST_FRAME")
  echo "luma: first=$FIRST_LUMA last=$LAST_LUMA (of 255)"
  # 75% of the opening frame. The broken ending measured 15%.
  if [ "$(( LAST_LUMA * 100 ))" -lt "$(( FIRST_LUMA * 75 ))" ]; then
    echo "the ceremony does not end on a restored world: last frame is" >&2
    echo "luma $LAST_LUMA against $FIRST_LUMA at the start — the void never closed." >&2
    exit 1
  fi
else
  echo "warning: could not find first/last frame for the ending check" >&2
fi

# Hardware H.264 first (this machine is AMD), software last.
for encoder in h264_amf h264_mf h264_nvenc libx264; do
  if "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -q " $encoder "; then
    echo "encoding with $encoder"
    "$FFMPEG" "${args[@]}" -filter_complex "$filters" \
      -map 0:v -map "[aout]" \
      -c:v "$encoder" -b:v 14M -pix_fmt yuv420p \
      -c:a aac -b:a 192k -movflags +faststart \
      "$OUT" && { echo "wrote $OUT"; exit 0; }
    echo "$encoder failed, trying next"
  fi
done

echo "no working H.264 encoder found" >&2
exit 1
