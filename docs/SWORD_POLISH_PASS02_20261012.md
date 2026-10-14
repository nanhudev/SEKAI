# Sword polish pass 02 — 2026-10-12

## Current state audit

Godot's live sword uses Sword_FP.tscn, registry-derived blade/saya dimensions and procedural SwordPoseSampler poses. Existing October 12 input/damage fixes and dirty working-tree changes are preserved. No node path or combat timing replacement is needed.

Three presentation defects were found in source: the ribbon reconstructs every historical blade base using the newest blade direction and a hard-coded 0.95 m length; its lifetime depends on frame count; A4's height/radius envelope restarts at every sector boundary. Non-beat moves also begin recovery using an unscaled follow duration, despite phase_of scaling it.

## Implementation plan — preserve, refactor, extend

Preserve the model silhouette, measured anchors, curved saya extraction and gameplay events. Refactor ribbon samples to store the rendered blade endpoints and simulation age; use one whole-sweep envelope for A4. Correct scaled recovery sampling. Extend the authored blade material into restrained cutting-face and spine finishes, baked into a new model revision with unchanged dimensions.

Validation: capture the same first-person scripted runtime before/after; check ribbon endpoint/expiry and sector continuity numerically; run existing core combat and Iaido checks. Captures prove rendered behavior, not human play feel.

## Delivered changes and evidence

- Model v9: cutting-face/spine finishes are baked in Blender and imported as `godot/models/weapons/fp_sword.glb`. Editable source: `assets_source/weapons/prototypes/fp_sword_v9.blend`; export: `assets/models/weapons/fp_sword_v9.glb`. 11 parts, 10,378 triangles. The union of blade surface bounds matches the previous model exactly, including tip Y=0.765 m. Previous imported model preserved at `E:/SEKAI-SwordPolish-20261012/fp_sword_before.glb`.
- Ribbon records each rendered tip/base pair, excludes the hilt, rejects tiny movement and expires by simulation age (0.10 s). Root-space placement now removes the actual rendered transform, including contact/locomotion offsets.
- A4 height, radius and width share whole-sweep progress; stationary adjacent sector edges measure 0.0 m gap. Existing per-sector camera frames remain intact for turning players.
- Non-beat recovery poses use the same scaled follow duration as their phase clock. Beat-authored A1–A4 timing is preserved.
- HUD singleton lookup uses `/root/InputContract`, fixing an existing standalone-tool compile failure while preserving the live singleton's signal connections.
- `sword_polish_regression.gd`: PASS, including historical wrist-turn endpoints, scaled recovery and ribbon expiry at 30 fps (0.100 s) / 144 fps (0.104167 s).
- `sword_core_regression.gd`: assertions PASS, A3 three damage receipts totaling 46 damage / 26 posture and A2 one receipt in either body/wave contact order. Existing sandbox zero-vector messages and cleanup resource warnings remain in its log.
- `iaido_integration.gd`: assertions PASS; headless world-capture warnings and a cleanup warning remain. This does not prove rendered Iaido acceptance.
- Real Compatibility renderer: 11 before/after stills and a 441-frame, 60 fps scripted combo capture. A1 historical ribbon placement and A4 sector continuity were visually reviewed. Native capture FPS is not a gameplay performance measurement.

- All 11 mesh bounds compared before/after: identical (`model_bounds_receipt.json`).
- `input_shift_tab_smoke.gd`: PASS for dodge/sprint, Tab tap/hold/release, Iaido input and HUD presence; existing resource cleanup warnings remain. The new presentation regression also reports one resource still in use on teardown; its assertions and exit code pass, so this is not a warning-free gate.
- Review deliverables: `sword_polish_after.mp4` (7.35 s, native engine audio) and `before_after.jpg` (left before / right after). `git diff --check` passed for changed tracked scripts.

Artifacts and logs: `E:/SEKAI-SwordPolish-20261012/`. Remaining presentation work: visible first-person hands, refinement in the actual training environment and human interactive comfort review.
