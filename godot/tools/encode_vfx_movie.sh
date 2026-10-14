#!/usr/bin/env bash
# Encodes one VFX prototype's frame sequence into an MP4.
#
# The clips in this round are silent on purpose. The brief for it is entirely
# about whether a rule being broken is LEGIBLE FROM A STILL, and mixing sound
# into that question would add a second variable to a comparison that has to be
# about the picture. A silent AAC track is still written, because a video with no
# audio stream at all behaves differently in a few players and that is a
# distraction nobody needs while reviewing eleven clips.
#
# The frame layout comes from `manifest.txt`, which the renderer writes. A number
# typed in here would be a second home for a fact about the picture — and this
# project has already paid once for an encoder that carried a hand-typed copy of
# a timeline that then drifted.
#
# Usage: encode_vfx_movie.sh <frames_dir> <out.mp4> [ffmpeg]
set -euo pipefail

FRAMES="${1:?frames dir}"
OUT="${2:?output mp4}"
FFMPEG="${3:-ffmpeg}"

MANIFEST="$FRAMES/manifest.txt"
if [ ! -f "$MANIFEST" ]; then
  echo "no manifest.txt in $FRAMES — the renderer writes it; a still-only render" >&2
  echo "has no take to encode." >&2
  exit 1
fi
FPS=$(sed -n 's/^FPS=//p' "$MANIFEST")
EFFECT=$(sed -n 's/^EFFECT=//p' "$MANIFEST")
LEAD_FRAMES=$(sed -n 's/^LEAD_FRAMES=//p' "$MANIFEST")
TAKE_FRAMES=$(sed -n 's/^TAKE_FRAMES=//p' "$MANIFEST")
TAIL_FRAMES=$(sed -n 's/^TAIL_FRAMES=//p' "$MANIFEST")
T_END=$(sed -n 's/^T_END=//p' "$MANIFEST")
echo "manifest: effect=$EFFECT fps=$FPS lead=$LEAD_FRAMES take=$TAKE_FRAMES tail=$TAIL_FRAMES t_end=$T_END"

FRAME_COUNT=$(find "$FRAMES" -name 'frame_*.png' | wc -l)
CLIP_SECONDS=$(awk "BEGIN{printf \"%.3f\", $FRAME_COUNT / $FPS}")
echo "frames: $FRAME_COUNT  ->  ${CLIP_SECONDS}s"

# ---------------------------------------------------------------------------
# DOES THE WORLD COME BACK?
#
# Every one of these eleven concepts has a Restore beat, and the cheap way to get
# one wrong is for the effect to end on a frame that is still broken — which from
# the outside looks like a deliberate ending and is actually a missing restore.
#
# This REPORTS AND DOES NOT FAIL, unlike the chain ultimate's encoder. The
# difference is deliberate: 08 白界 legitimately ends with a region of the world
# still erased, because the point of that skill is a mark that stays. A hard gate
# would have been the wrong instrument and would have been worked around rather
# than fixed.
# ---------------------------------------------------------------------------
mean_luma() {
  "$FFMPEG" -v error -i "$1" -vf "scale=1:1:flags=area,format=gray" \
    -frames:v 1 -f rawvideo - 2>/dev/null | od -An -tu1 | tr -d ' \n'
}
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
  RESIDUE=$(differs_per_mille "$FIRST_FRAME" "$LAST_FRAME")
  echo "restore check: luma first=$FIRST_LUMA last=$LAST_LUMA (of 255)"
  echo "restore check: ${RESIDUE}/255 of the last frame differs from the first by >24/255"
  if [ "${LAST_LUMA:-0}" -lt "$(( FIRST_LUMA * 60 / 100 ))" ]; then
    echo "  WARNING: the clip ends much darker than it began — the restore may not" >&2
    echo "  have happened. Look at the last frame before delivering." >&2
  fi
fi

# Hardware H.264 first (this machine is AMD), then MediaFoundation, then software.
args=(-y -hide_banner -loglevel error -framerate "$FPS" -i "$FRAMES/frame_%04d.png")
args+=(-f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=48000")

# EVEN DIMENSIONS OR NOTHING.
#
# The renderer captures the WINDOW it was given, and this desktop clamps a
# 1920x1080 request down to 1920x1061 — so every frame comes back with an odd
# height. libx264 refuses to open a yuv420p stream at an odd height
# ("height not divisible by 2 (1920x1061)"), and it is the only encoder this
# machine actually has, so ALL ELEVEN takes failed and the deliverable was
# eleven zero-byte mp4s that looked like eleven successful runs in the log.
# One dropped row of pixels is invisible; a missing movie is not.
args+=(-vf "scale=trunc(iw/2)*2:trunc(ih/2)*2")

for encoder in h264_amf h264_mf h264_nvenc libx264; do
  if "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -q " $encoder "; then
    echo "encoding with $encoder"
    if "$FFMPEG" "${args[@]}" -map 0:v -map 1:a -shortest \
        -c:v "$encoder" -b:v 16M -pix_fmt yuv420p \
        -c:a aac -b:a 128k -movflags +faststart \
        "$OUT"; then
      echo "wrote $OUT"
      exit 0
    fi
    echo "$encoder failed, trying next"
  fi
done

echo "no working H.264 encoder found" >&2
exit 1
