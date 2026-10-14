#!/usr/bin/env bash
# Encodes the SWORD AUDIO take into an MP4 with the sound that was actually
# played, and refuses to hand back a clip whose picture and sound disagree.
#
# WHY THIS IS NOT encode_combat_movie.sh. That script renders VIDEO ONLY on
# purpose - the combat cues it was written for were still TODO, so an audio track
# would have been a placeholder pretending to be a verdict. This take records the
# real SFX bus while it shoots (see godot/scripts/audio/audio_bus_capture.gd), so
# an audio track is the whole point, and with a track comes the one failure this
# script exists to catch: a clip that looks right and is 80 ms out.
#
# The frame rate is NOT a constant. The take runs in real time - the combat
# windows and the combo grace are wall-clock based, so pinning the clock would
# desync them from the animation - and how many frames this machine manages per
# second of game time depends on the scene. The renderer writes the measured rate
# to fps.txt; encoding at that rate is what makes the clip play at true speed, and
# the check below is what makes "at true speed" a measurement instead of a hope.
#
# Usage: encode_sword_audio_movie.sh <take_dir> <out.mp4> [ffmpeg]
set -euo pipefail

TAKE="${1:?take dir}"
OUT="${2:?output mp4}"
FFMPEG="${3:-ffmpeg}"
AUDIO="${TAKE}/sword_performance_pass01.wav"

if [[ ! -f "$TAKE/fps.txt" ]]; then
  echo "fps.txt missing in $TAKE - cannot guarantee true-speed playback" >&2
  exit 1
fi
if [[ ! -f "$AUDIO" ]]; then
  echo "$AUDIO missing - this take has no recorded bus, so there is nothing to sync" >&2
  exit 1
fi

FPS=$(tr -d '[:space:]' < "$TAKE/fps.txt")
FRAME_COUNT=$(find "$TAKE" -name 'frame_*.png' | wc -l)
[[ "$FRAME_COUNT" -eq 0 ]] && { echo "no frames in $TAKE" >&2; exit 1; }

CLIP=$(awk "BEGIN{printf \"%.3f\", $FRAME_COUNT / $FPS}")
echo "frames: $FRAME_COUNT   fps: $FPS   picture: ${CLIP}s"

# Duration comes out of ffmpeg's own banner rather than from ffprobe, because
# ffprobe is a separate binary that is not always next to the ffmpeg a caller
# hands us - and a sync check that fails to run is worse than no check, since it
# exits 0 and looks like agreement.
duration_of() {
  local stamp
  stamp=$("$FFMPEG" -hide_banner -i "$1" 2>&1 \
    | sed -n 's/.*Duration: \([0-9][0-9]*:[0-9][0-9]*:[0-9.]*\).*/\1/p' | head -1)
  [[ -z "$stamp" ]] && { echo ""; return; }
  awk -F: "BEGIN{split(\"$stamp\", a, \":\"); printf \"%.3f\", a[1]*3600 + a[2]*60 + a[3]}"
}

# The audio was captured off the same wall clock as the frames, so the two
# lengths should agree to within a frame or two. A larger gap means the take was
# uneven (a stall mid-render) and the clip would drift against its own sound.
AUDIO_LEN=$(duration_of "$AUDIO")
if [[ -z "$AUDIO_LEN" ]]; then
  echo "could not read the duration of $AUDIO - refusing to ship an unverified sync" >&2
  exit 1
fi
DRIFT=$(awk "BEGIN{d=$CLIP-$AUDIO_LEN; if (d<0) d=-d; printf \"%.3f\", d}")
echo "audio:  ${AUDIO_LEN}s   drift: ${DRIFT}s"
if awk "BEGIN{exit !($DRIFT > 0.20)}"; then
  echo "picture and sound disagree by ${DRIFT}s - re-shoot rather than ship a clip that drifts" >&2
  exit 1
fi

for encoder in h264_amf h264_mf h264_nvenc libx264; do
  if "$FFMPEG" -hide_banner -encoders 2>/dev/null | grep -q " $encoder "; then
    echo "encoding with $encoder"
    if "$FFMPEG" -y -hide_banner -loglevel error \
      -framerate "$FPS" -start_number 0 -i "$TAKE/frame_%04d.png" \
      -i "$AUDIO" \
      -c:v "$encoder" -b:v 16M -pix_fmt yuv420p \
      -c:a aac -b:a 192k -ar 48000 \
      -t "$CLIP" -movflags +faststart \
      "$OUT"; then
      echo "wrote $OUT"
      exit 0
    fi
    echo "$encoder failed, trying next"
  fi
done

echo "no working H.264 encoder found" >&2
exit 1
