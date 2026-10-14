# Mistvale Foundation V2 — R04 terrain and bridge checkpoint

## Kept in the playable scene

- The near south riverbank at the bridge reach now has a continuous 0.85 m erosion shoulder in `MistvaleHeights.height_at()`. The shape fades along the river and before the road. The visual terrain, 2 m collision mesh, and grounded placements sample the same height field.
- The 1 m Golden Path visual tile exposes broken mineral earth on this bank using its vertex alpha mask. Its remaining decorative relief stays at or below 0.30 m above gameplay collision; the tile border remains level with the surrounding terrain.
- The existing bridge has two solid cutwater piers under its arch divisions. The wooden parapet geometry is batched into one mesh without changing the collision deck.
- R04_G is a fixed bank inspection view, alongside the existing R04 bridge views.

## Rejected after image review

- Three Blender bank-stratum slabs, including a slope-following wedge, remained visibly separate from the terrain and read as placed stone plates. They were removed from the scene and workspace. The continuous height-field sculpt replaced them.
- A separate 50 m visual bank band made a dark stripe across the river approach and was removed.

## Verification

- Beauty frames: `.render/levelart/bank_shelf_shared/R04_G_bank_profile.png`, `R04_F_arch_profile.png`, and `R04_A_forward.png`.
- `audit_terrain_continuity.gd`: PASS; 22,701 visual-tile vertices, maximum visual/collision delta 0.300 m, tile seam 0.000 m, maximum 2 m mesh interpolation error 0.315 m.
- `audit_routes.gd`: main route and both mountain routes PASS with no sampled section above 45 degrees. Existing C05 Guild Terrace pad remains uneven and requires a separate layout/terrain pass.
- `smoke_region_entry.gd`: PASS; player moved, bridge deck collision continuous at 11 stations, pause/resume and return to title succeeded. The engine still prints existing material migration and resource cleanup warnings.
- Spawn performance with a 120-frame Compatibility sample: approximately 29.6 FPS at 1280×720 with 726 draw calls. Parapet batching cut draw calls from 877, but did not establish an FPS gain. The 45–60 FPS target remains open.

## Next terrain node

Resolve the C05 Guild Terrace entrance as a composed stair/ramp transition, then inspect the R03 riverbank dark slope and R05 road wedge from player height. Preserve the shared height-field and collision rule.
