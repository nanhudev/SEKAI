#!/usr/bin/env bash
# PART R: same camera, three generations.  Reproduce with:
#   bash tools/blender/compare_sheets.sh
set -e
cd /f/SEKAI
PY=/c/Users/Administrator/.workbuddy/binaries/python/envs/default/Scripts/python.exe
R=.render/asset_review

$PY /f/tmp/vcmp.py $R/CMP_side_V1_V2_FINAL.png 560 \
  "V1 first build (placeholder rig):$R/sword_v4_sheet/01_side_p.png" \
  "V2 guard gen3, rig fixed:$R/sword_v7_sheet/01_side_p.png" \
  "FINAL bite guard, iron:$R/sword_v10_sheet/01_side_p.png"

$PY /f/tmp/vcmp.py $R/CMP_guard_V1_V2_FINAL.png 440 \
  "V1 modelled circle:$R/sword_v5_sheet/05_guard_p.png" \
  "V2 forged + raised rim:$R/sword_v7_sheet/05_guard_p.png" \
  "V3 spline = flower:$R/sword_v8_sheet/05_guard_p.png" \
  "FINAL bite + iron:$R/sword_v10_sheet/05_guard_p.png"

$PY /f/tmp/vcmp.py $R/CMP_fp_FINAL.png 420 \
  "FINAL first-person:$R/sword_v10_sheet/FP_camera_p.png" \
  "FINAL grip close:$R/sword_v10_sheet/D3_grip_p.png" \
  "FINAL guard close:$R/sword_v10_sheet/D2_habaki_p.png"
echo "compare_sheets: done"
