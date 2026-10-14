# Mistvale Pass 02: ground and town access

## Correction and continuation, 2026-09-30

The earlier source-height clearance results below did not verify the imported terrain. Full saved-level FBX export exposed a Y-handedness error: the terrain was mirrored north/south. This is now corrected in `SM_Mistvale_Terrain_Corrected`; OBJ preprocessing reflects Y and reverses winding. Actual exported triangle samples confirm the correct orientation. Local differences from the analytic source remain, up to roughly 0.53 m in the six sampled points; these are not proof of complete walking collision clearance.

Replaced 480 road actors and 50 river pieces with eight continuous road meshes, three public forecourts and one river surface. Saved level actor count is now 238 (previously 756). Road/plaza vertices are conformed to the actual exported terrain with `conform_surfaces_to_saved_mesh.py`, after generation and before installation. Re-running the generator alone loses that correction. Terrain and surface Nanite flags are disabled. This actor reduction has not been benchmarked for FPS.

Current review images are `Review/saved_scene_overview.png` and `Review/saved_scene_riverside.png`: real saved UE geometry exported to Blender, with simplified materials and preview lighting. They are not UE beauty captures. Water remains a flat visual surface; fluid simulation, final textures, full player traversal, bridge approach continuity and final building art remain unfinished.

## Earlier source-based report (superseded where noted above)

The new `/Game/Maps/L_Mistvale_Rebuild` remains separate from the preserved Pass 01 blockout. This pass addresses floating houses and foundations crossing streets.

- Rebuilt the art-only terrain mesh from a 505 x 505 R16 source, grading 91 building/public footprints and feathering their edges into the valley.
- Resettled the nine Riverside houses from a north-south row, whose middle plots entered the river, into a continuous south-bank street wall.
- Repositioned 20 other road-conflicting buildings; the church bell tower follows its nave. The final plan-view clearance check reports **zero** foundation/road conflicts and **zero** foundation/foundation overlaps across 87 foundations and 480 road segments.
- Grounded 87 building footprints with weathered-stone foundations, each 0.9 m deep, and re-seated all 480 road segments on the graded terrain. The saved map has 756 actors. A saved-map audit measured 0.035–0.514 m vertical clearance from the sampled terrain at building centres; the stone foundations fill those gaps.
- New terrain asset: `/Game/MistvaleArt/Terrain/SM_Mistvale_Terrain_Art`; source: `Source/Mistvale_Valley_Art_505.r16` and `Source/Mistvale_Terrain_Art_Proxy.obj`.

The saved UE commandlets completed with zero errors. Numerical audits are in `Source/ground_grade_report.json`, `Source/apply_ground_result.json`, `Source/ground_final_audit.json` and `Source/ground_clearance_audit.json`.

Still pending: visual review of the final graded map, native UE Landscape and water, replacement of segmented road geometry, continuous walking collision check, performance/LOD and final environment art. An interactive UE editor restart encountered the RX 6650 XT driver warning and a long shader rebuild, so this checkpoint does not claim a final in-engine beauty frame.
