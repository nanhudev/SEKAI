# Mistvale UE5 Rebuild

Independent art direction candidate. This project does not load or modify the Godot playable scene.

Current target is a 504 x 706 m river valley with a 250 x 350 m dense town. The heightmap and town massing are authored anew. `Source/` holds the reproducible generation scripts; `Content/Maps/` contains the editor map after the builder runs.

`Source/generate_heightmap.py` writes the original 505 x 505 16-bit Landscape heightmap. `Source/grade_town_ground.py` writes the **art map's** revised `Mistvale_Valley_Art_505.r16` and higher-resolution proxy with 91 graded building/public pads. In a future native Landscape import, use XY scale 100 x 140 cm and Z scale 25 cm, with actor origin (-25200, -35300, 0) cm. The saved art map currently uses the matching static-mesh proxy and complex collision.

The playable art target is `/Game/Maps/L_Mistvale_Rebuild`, now the project startup map. It is a separate copy of the preserved `/Game/Maps/Mistvale_Rebuild_Blockout`. It contains 95 first-pass building replacements using the user's downloaded Fab town kit, an open north gate arch, a bell tower, guild-yard fence and a preliminary landscape/road/river palette. The guild hall and main three-arch bridge are original Blender models imported as UE static meshes. See `PASS01_CHECKPOINT.md` for the earlier composition baseline, `FAB_ASSET_INDEX.md` for the art asset audit and `ASSET_SOURCE_LOG.md` for provenance.

This is an active level-art work-in-progress. The terrain remains a collidable static-mesh proxy pending native Landscape conversion; the river is an opaque surface proxy, and the segmented roads and service bridge need final geometry, collision and traversal review. See `PASS02_GROUND_CHECKPOINT.md` for the ground-contact and road-clearance audit.
