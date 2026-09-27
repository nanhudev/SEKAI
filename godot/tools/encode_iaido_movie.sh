#!/usr/bin/env bash
# Encodes an Iaido frame sequence into an MP4, with the placeholder audio cues
# mixed in at exactly the times IaidoAudioTimeline fires them.
#
# The picture is rendered by godot/tools/iaido_movie_renderer.gd. The frame
# sequence starts PRE_ROLL frames before t=0, so every audio cue is shifted by
# that same amount to stay in sync with the picture.
#
# Usage: encode_iaido_movie.sh <frames_dir> <out.mp4> [ffmpeg]
set -euo pipefail

FRAMES="${1:?frames dir}"
OUT="${2:?output mp4}"
FFMPEG="${3:-ffmpeg}"
SFX="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/audio/sfx"

FPS=30
PRE_ROLL=12                     # must match PRE_ROLL in the renderer
OFFSET_MS=$(( PRE_ROLL * 1000 / FPS ))

# Pad the mix to exactly the picture length. Padding to a hardcoded guess
# leaves the container as long as the audio, so the file plays on a frozen
# last frame for the difference.
FRAME_COUNT=$(find "$FRAMES" -name 'frame_*.png' | wc -l)
CLIP_SECONDS=$(awk "BEGIN{printf \"%.3f\", $FRAME_COUNT / $FPS}")
echo "frames: $FRAME_COUNT  ->  ${CLIP_SECONDS}s"

# cue file : time in ceremony seconds : gain in dB : extra filter
CUES=(
  "iaido_air_suck.wav:0.20:-6:"
  "iaido_sheath_move.wav:0.80:-11:"
  "iaido_reverse_wave.wav:1.20:-7:"
  "iaido_pressure.wav:2.20:-5:"
  "iaido_lock_click.wav:2.85:-4:"
  "iaido_draw.wav:2.97:-3:"
  "iaido_world_cut.wav:3.10:-3:"
  "iaido_void_open.wav:3.40:-5:"
  "iaido_glass_stress.wav:4.25:-8:"
  "iaido_glass_break.wav:4.58:-6:"
  "iaido_spin.wav:4.60:-9:"
  "iaido_slow_sheathe.wav:5.50:-10:"
  "iaido_final_click.wav:6.20:-2:"
  "iaido_glass_break.wav:6.25:-2.5:atempo=0.78"
  "iaido_reality_restore.wav:6.80:-7:"
)

args=(-y -hide_banner -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%04d.png")
filters=""
labels=""
index=1
for cue in "${CUES[@]}"; do
  IFS=':' read -r file at gain extra <<< "$cue"
  args+=(-i "$SFX/$file")
  delay=$(( OFFSET_MS + $(awk "BEGIN{printf \"%d\", $at*1000}") ))
  filters+="[${index}:a]${extra:+$extra,}adelay=${delay}:all=1,volume=${gain}dB[a${index}];"
  labels+="[a${index}]"
  index=$(( index + 1 ))
done
filters+="${labels}amix=inputs=${#CUES[@]}:normalize=0:dropout_transition=0,apad=whole_dur=${CLIP_SECONDS}[aout]"

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
