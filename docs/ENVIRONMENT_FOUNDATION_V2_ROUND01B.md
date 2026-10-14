# Mistvale Foundation V2 — Golden Path material trial

## Accepted in this pass

- Painted packed dirt source: `assets_source/environment/mistvale/materials_v2/mv_packed_dirt_source_v1.png`.
- Tile processing source: `assets/chat2blender/mistvale_foundation_v2/process_packed_dirt.py`. It exports albedo, normal, and roughness images. Only albedo is used in game at this checkpoint.
- The main road blends the painted dirt into its first Golden Path segment between route metres 58 and 164, with fades at both ends. Side roads and the market apron retain their previous material behavior.
- The existing rut, verge, stone and wetness logic remains active above the painted dirt.
- R04 bridge shadow was traced to the stone arch wall and river bush casters. These no longer cast onto the road ribbon; the bridge deck and rails were already set to avoid self shadowing.

## Rejected after fixed-camera review

- Procedural gravel and soil set: visible noise and repeating round pebbles.
- Two bamboo mesh variations: one made spike clusters, the other became too sparse. Both were removed from the live scene.

## Evidence and gate

- Beauty comparison: `.render/levelart/foundation_tile160/R02_A_forward.png` and `.render/levelart/foundation_round01b_final_shadowfix/R02_A_forward.png`. Bridge before/after: `.render/levelart/foundation_round01b_final/R04_A_forward.png` and `.render/levelart/foundation_round01b_final_shadowfix/R04_A_forward.png`.
- Road paint improves near-surface readability at R02. It does not solve the bamboo silhouettes, distant whitebox buildings, bridge material, or 50 m riverbank composition.
- Compatibility renderer on RX 6650 XT at 1280×720: 29 FPS, 877 draw calls, 656 MultiMesh nodes at spawn. The prior 28 FPS observation is within run variance; there is no proven performance gain from this pass. The 45–60 FPS target remains unmet.
- `smoke_region_entry.gd` passes, including bridge deck collision and player movement. The scene still emits existing material migration and cleanup warnings on exit.

## Next production gate

Keep the Golden Path as the review scope. Build a deliberately composed bamboo/forest kit and paint the bridge/riverbank in context, then capture R02 and R04 in both structure and beauty modes. Do not promote this checkpoint to a finished commercial quality foundation.
