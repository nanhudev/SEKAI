# Mistvale Environment Foundation V2 — Round 01 checkpoint

Status: **production foundation in progress; Golden Path art gate fails**. The gameplay heightfield, road network, river, bridge deck collision, guild terrace, north gate, mountain routes and ruins location remain authoritative.

## Built and integrated

- **Separate visual terrain tile:** the bridge reach `x=-80..80, z=80..220` is rendered at 1 m sampling. The complete 2 m gameplay surface remains the collision mesh. Four authored bank shoulders add at most 0.30 m of visual relief and fade exactly to the tile border. The tile uses the existing terrain palette for now.
- **First Blender rock family:** small, medium and large river rocks, two clusters, and two cliff shelf assets. The source generator is `assets/chat2blender/mistvale_foundation_v2/build_rocks.py`; seven GLBs are under `godot/models/environment/mistvale/foundation_v2/`. One material per mesh avoids the original four to five draw calls per rock.
- **Bridge reach composition:** sparse new rock clusters replace legacy scattered rocks near the crossing. Legacy hero rocks, boulders and shelves are excluded within 52 m in X and 38 m of the river centre, so they no longer obscure the arch with dark angular masses. The raised riverbank ribbon tried during review was removed because it read as a grey dome.
- **Shared material seed:** `mistvale_ground_master_v2.gdshader` provides one reusable color, roughness and three scale surface language. It currently shades the new rocks. It is **not** yet the requested eight material terrain library.
- **Bridge form:** the visual stone wall now carries three continuous open vaults and an exterior rim, while the walkable deck and its collision are unchanged. This improves the side silhouette, though the bridge still needs a complete parapet, abutment and masonry art pass.
- **Distance grouping:** flora tile grouping increased from 110 to 160 m. At the measured spawn frame, MultiMesh nodes fell from 1,031 to 656 and draw calls from 950 to 877; FPS stayed around 28. The broader tile had no obvious R02/R04 still frame loss, but moving LOD transitions need review.

## Fixed camera evidence

| Frame | Before | Current | Read |
|---|---|---|---|
| Bridge side | `.render/levelart/world_round03_beauty/R04_F_arch_profile.png` | `.render/levelart/foundation_tile160/R04_F_arch_profile.png` | Three vault rhythm reads and the black foreground rock is gone. Still a simple block bridge. |
| Forest reveal | `.render/levelart/world_round03_beauty/R02_A_forward.png` | `.render/levelart/foundation_tile160/R02_A_forward.png` | No meaningful art leap. The broad road, repetitive thin trees and distant pale town remain the main faults. |
| Market | `.render/levelart/world_round03_beauty/R05_A_forward.png` | `.render/levelart/foundation_round01_beauty/R05_A_forward.png` | Plaza solves the crossing seam but looks like a broad brown fill. |

Full structural and beauty sets are in `.render/levelart/foundation_round01_structure/` and `.render/levelart/foundation_round01_beauty/` for R02, R04, R05, R07, R08 and R10. The tile grouping check is in `.render/levelart/foundation_tile160/`.

## Verified

- `audit_terrain_continuity.gd`: 22,701 visual tile vertices; maximum visual/gameplay height difference **0.300 m**, seam difference **0.000 m**; pass.
- `smoke_region_entry.gd`: spawn, forward movement, bridge deck at 11 stations, pause/resume and return to title; pass.
- RX 6650 XT, Compatibility, 1280×720 spawn frame: **28 FPS, 877 draw calls**, 25,980 instances, 656 MultiMeshes. The 45–60 FPS target is unmet. The FPS reading is a single location, not a full route profile.
- Blender 5.1.2 exports and Godot 4.4.1 imports completed. Godot logs the existing `SpatialMaterial ... specular` remap warnings on imported environment assets.

## Next production gate

1. **Terrain and ground materials:** replace the now separate bridge tile's old surface shader with a real shared terrain master and five to eight controlled ground variants. Compose 2–20 m shelves and cut banks around the route with proper normals and seamless joins. Review from R02 and R04 at player height.
2. **Riverbank and road:** build a 50 m riverbank with a truly irregular soil → gravel → shallow water transition, then a 50–100 m road section with compression, embedded stones and believable edges. The rejected raised ribbon must stay out until the terrain surface itself can blend the band.
3. **Vegetation:** author Broadleaf/River/Mountain first batch in Blender with 3D canopy clusters and designed LOD0/1/2. R02's flat, repeated tree silhouettes are the Golden Path's largest asset failure.
4. **Bridge V2:** develop vault stones, pier foundations, bridgeheads, parapet and road transitions as one kit. Audit underside and river clearance at R04.
5. **Performance:** profile the whole Golden Path before adding density; group repeated meshes and materials rather than reducing hero asset quality. The current 28 FPS cannot support more buildings, NPCs and VFX.

Architecture V2 remains after the visual foundation gate. R07, R08 and R10 screenshots are retained as references but are not signed off as finished art.
