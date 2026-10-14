#!/usr/bin/env bash
# Encodes the chain ultimate's frame sequence into an MP4, with the placeholder
# audio cues mixed in at exactly the times ChainUltimateAudioTimeline fires them.
#
# Two things are ASKED FOR rather than typed in:
#
#   · the cue table, from ChainUltimateAudioTimeline via dump_chain_ultimate_cues.gd
#   · the frame layout (lead-in, first pass, tail, where the slow section starts),
#     from `manifest.txt`, which the renderer writes.
#
# Both exist because the iaido line already paid for the alternative: its encoder
# carried a hand-typed copy of the cue list, that copy drifted a third of a
# second, and nothing failed — because nothing compared the two. A mirror that is
# only checked by eye is a mirror that is wrong.
#
# The audio is mixed TWICE: once at normal speed under the first pass, and once
# time-stretched under the slow section. `atempo=0.5` is the exact reciprocal of
# the renderer's SLOW_FACTOR, so the second mix lands on the second pass instead
# of eight seconds early.
#
# Usage: encode_chain_ultimate_movie.sh <frames_dir> <out.mp4> [ffmpeg] [godot]
set -euo pipefail

FRAMES="${1:?frames dir}"
OUT="${2:?output mp4}"
FFMPEG="${3:-ffmpeg}"
GODOT="${4:-${GODOT:-godot}}"
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO="$PROJECT/audio"

MANIFEST="$FRAMES/manifest.txt"
if [ ! -f "$MANIFEST" ]; then
  echo "no manifest.txt in $FRAMES — the renderer writes it; a shot-list render" >&2
  echo "has no timeline to score, so there is nothing to encode." >&2
  exit 1
fi
# shellcheck disable=SC1090
FPS=$(sed -n 's/^FPS=//p' "$MANIFEST")
LEAD_FRAMES=$(sed -n 's/^LEAD_FRAMES=//p' "$MANIFEST")
TAIL_FRAMES=$(sed -n 's/^TAIL_FRAMES=//p' "$MANIFEST")
SLOW_START_FRAME=$(sed -n 's/^SLOW_START_FRAME=//p' "$MANIFEST")
SLOW_FACTOR=$(sed -n 's/^SLOW_FACTOR=//p' "$MANIFEST")
T_END=$(sed -n 's/^T_END=//p' "$MANIFEST")
echo "manifest: fps=$FPS lead=$LEAD_FRAMES tail=$TAIL_FRAMES slow_from=$SLOW_START_FRAME slow=$SLOW_FACTOR t_end=$T_END"

OFFSET_MS=$(awk "BEGIN{printf \"%d\", $LEAD_FRAMES * 1000 / $FPS}")
SLOW_AT_MS=0
HAS_SLOW=0
if [ "$SLOW_START_FRAME" -ge 0 ]; then
  SLOW_AT_MS=$(awk "BEGIN{printf \"%d\", $SLOW_START_FRAME * 1000 / $FPS}")
  HAS_SLOW=1
fi

FRAME_COUNT=$(find "$FRAMES" -name 'frame_*.png' | wc -l)
CLIP_SECONDS=$(awk "BEGIN{printf \"%.3f\", $FRAME_COUNT / $FPS}")
echo "frames: $FRAME_COUNT  ->  ${CLIP_SECONDS}s"

# ---------------------------------------------------------------------------
# THE CUE TABLE IS ASKED FOR, NOT COPIED.
# ---------------------------------------------------------------------------
CUE_TABLE="$(cd "$PROJECT" && "$GODOT" --headless --path "$PROJECT" \
  --audio-driver Dummy --script res://tools/dump_chain_ultimate_cues.gd 2>/dev/null \
  | grep '^CUE ' || true)"
if [ -z "$CUE_TABLE" ]; then
  echo "could not read the cue table from ChainUltimateAudioTimeline via $GODOT." >&2
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
  # The path can contain no colon; the time:gain:extra triple is the tail.
  file="${cue%%:*}"
  rest="${cue#*:}"
  IFS=':' read -r at gain extra <<< "$rest"
  if [ ! -f "$AUDIO/$file" ]; then
    echo "cue file missing: $AUDIO/$file" >&2
    exit 1
  fi
  args+=(-i "$AUDIO/$file")
  # The time is in ceremony seconds; the picture starts LEAD_FRAMES earlier, and
  # ffmpeg's adelay is in milliseconds.
  delay=$(( OFFSET_MS + $(awk "BEGIN{printf \"%d\", $at*1000}") ))
  filters+="[${index}:a]${extra:+$extra,}adelay=${delay}:all=1,volume=${gain}dB[a${index}];"
  labels+="[a${index}]"
  if [ "$HAS_SLOW" = "1" ]; then
    # The same cue, under the slow pass. `atempo` first (so a pitched cue is
    # already the length the game plays it), then the slow factor's reciprocal.
    slow_delay=$(( SLOW_AT_MS + $(awk "BEGIN{printf \"%d\", $at*1000*$SLOW_FACTOR}") ))
    filters+="[${index}:a]${extra:+$extra,}atempo=$(awk "BEGIN{printf \"%.4f\", 1/$SLOW_FACTOR}")"
    filters+=",adelay=${slow_delay}:all=1,volume=${gain}dB[b${index}];"
    labels+="[b${index}]"
  fi
  index=$(( index + 1 ))
  cue_count=$(( cue_count + 1 ))
done <<< "$CUE_TABLE"
echo "cues: $cue_count (read from ChainUltimateAudioTimeline)"

if [ "$HAS_SLOW" = "1" ]; then
  mix_inputs=$(( cue_count * 2 ))
else
  mix_inputs=$cue_count
fi
filters+="${labels}amix=inputs=${mix_inputs}:normalize=0:dropout_transition=0,apad=whole_dur=${CLIP_SECONDS},atrim=0:${CLIP_SECONDS}[aout]"

# ---------------------------------------------------------------------------
# THE CEREMONY MUST END ON THE WORLD IT BEGAN WITH.
#
# A final frame that is dark is not a subtle failure: it means the void was never
# closed and the whole restore ended on an empty frame. Compared as a RATIO rather
# than an absolute, so it survives a lighting or exposure change on the ART line.
#
# AND THE RATIO ALONE IS NOT ENOUGH, WHICH THIS LINE FOUND OUT. The first pass of
# this ceremony ended on a frame that was the whole room at 97% of the opening
# frame's luma and STILL had the film's pieces hanging over it: the dissolve's own
# mask floored at 0.30, so the last third of the film's pixels kept 70% of their
# alpha no matter how long the dissolve ran. 断片消失 did not happen and the mean
# luma barely noticed, because a ghost over 15% of the frame does not move a mean.
#
# So the last frame is also compared to the FIRST one, pixel by pixel, and the
# verdict is the fraction of the picture that still differs by more than 24/255.
# The two frames are the same room through the same lens at the same fov with the
# ceremony over, so what is left is the chain settling into its idle pose — a few
# percent around the weapon — and anything else is residue.
# ---------------------------------------------------------------------------
mean_luma() {
  "$FFMPEG" -v error -i "$1" -vf "scale=1:1:flags=area,format=gray" \
    -frames:v 1 -f rawvideo - 2>/dev/null | od -An -tu1 | tr -d ' \n'
}
# The share of the picture that differs from the reference by more than 24/255,
# as an integer per mille. One number, from ffmpeg, with no thresholding in here.
differs_per_mille() {
  "$FFMPEG" -v error -i "$1" -i "$2" \
    -filter_complex "[0:v][1:v]blend=all_mode=difference,format=gray,lut=y='if(gt(val,24),255,0)',scale=1:1:flags=area" \
    -frames:v 1 -f rawvideo - 2>/dev/null | od -An -tu1 | tr -d ' \n'
}
FIRST_FRAME="$FRAMES/frame_0000.png"
LAST_FRAME="$FRAMES/$(printf 'frame_%04d.png' $(( FRAME_COUNT - 1 )) )"
if [ -f "$FIRST_FRAME" ] && [ -f "$LAST_FRAME" ]; then
  FIRST_LUMA=$(mean_luma "$FIRST_FRAME")
  LAST_LUMA=$(mean_luma "$LAST_FRAME")
  echo "luma: first=$FIRST_LUMA last=$LAST_LUMA (of 255)"
  if [ "${LAST_LUMA:-0}" -lt "$(( FIRST_LUMA * 60 / 100 ))" ]; then
    echo "the ceremony does not end on a restored world: last frame is luma" >&2
    echo "$LAST_LUMA against $FIRST_LUMA at the start — the void never closed." >&2
    exit 1
  fi
  RESIDUE=$(differs_per_mille "$FIRST_FRAME" "$LAST_FRAME")
  echo "residue: ${RESIDUE}/255 of the picture still differs from the opening frame"
  if [ "${RESIDUE:-255}" -gt 24 ]; then
    echo "the ceremony ends with something still on screen that was not there at the" >&2
    echo "start: ${RESIDUE}/255 of the last frame differs from the first by more than" >&2
    echo "24/255. The room comes back; an effect does not. Look at the dissolve's mask." >&2
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
