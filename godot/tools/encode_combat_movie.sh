#!/usr/bin/env bash
# Encodes the combat tour frame sequence into an MP4.
#
# The frame rate is NOT a constant: combat_movie_renderer.gd runs in real time
# (the combat windows are wall-clock based, so pinning the clock would desync
# them from the animation), and how many frames this machine manages per second
# of game time depends on the scene. The renderer writes the measured rate to
# fps.txt; encoding at that rate is what makes the clip play back at true speed
# instead of looking sped up or in slow motion.
#
# Usage: encode_combat_movie.sh <frames_dir> <out.mp4> [ffmpeg]
set -euo pipefail

FRAMES="${1:?frames dir}"
OUT="${2:?output mp4}"
FFMPEG="${3:-ffmpeg}"

RISK_MARGIN=0.02   # accept a 2% drift; anything larger means the take was uneven

if [[ -f "$FRAMES/fps.txt" ]]; then
  FPS=$(tr -d '[:space:]' < "$FRAMES/fps.txt")
else
  echo "fps.txt missing in $FRAMES — cannot guarantee true-speed playback" >&2
  exit 1
fi

FRAME_COUNT=$(find "$FRAMES" -name 'frame_*.png' | wc -l)
if [[ "$FRAME_COUNT" -eq 0 ]]; then
  echo "no frames found in $FRAMES" >&2
  exit 1
fi

CLIP_SECONDS=$(awk "BEGIN{printf \"%.3f\", $FRAME_COUNT / $FPS}")
echo "frames: $FRAME_COUNT  fps: $FPS  ->  ${CLIP_SECONDS}s"

# Video only, on purpose: every combat cue in COMBAT_SFX_BRIEF.md is still
# TODO (Priority A / A2 / D / E / F), so an audio track here would be a
# placeholder pretending to be a verdict.
for encoder in h264_amf h264_mf h264_nvenc libx264; do
  if "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -q " $encoder "; then
    echo "encoding with $encoder"
    "$FFMPEG" -y -hide_banner -loglevel error \
      -framerate "$FPS" -i "$FRAMES/frame_%04d.png" \
      -c:v "$encoder" -b:v 16M -pix_fmt yuv420p \
      -movflags +faststart \
      "$OUT" && { echo "wrote $OUT"; exit 0; }
    echo "$encoder failed, trying next"
  fi
done

echo "no working H.264 encoder found" >&2
exit 1
