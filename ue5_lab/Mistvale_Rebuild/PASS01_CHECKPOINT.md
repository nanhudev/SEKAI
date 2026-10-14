# Mistvale UE5 rebuild — Pass 01 checkpoint

## Built and verified

- New independent UE 5.8 project and saved blockout level `/Game/Maps/Mistvale_Rebuild_Blockout`.
- New 505 x 505 R16 heightmap for a 504 x 706 m river valley. The playable editor level currently uses its lower-resolution mesh proxy because the source has not yet been imported as a UE Landscape.
- A town plan tied to the river: 81 ordinary residential/commercial building masses, a broad guild hall, church with bell tower, inn, blacksmith, dock warehouse, north gate, market stalls, two bridge sites, primary/secondary routes, a south forest entry and nine fixed review cameras.
- Terrain proxy uses complex-as-simple collision. UE editor commandlet reopened the saved map and verified 652 actors, required landmarks and collision setting. Roads are segmented at 4 m intervals to follow ground height; the temporary river is level and has collision disabled. The main road no longer descends into the river under the bridge. A separate road audit measured 0.126 m maximum centre height error and 11.96° maximum segment grade, on the dock approach.
- One original guild hall hero mesh has replaced its whitebox mass. Blender source, FBX, UE static mesh and isolated preview are saved. UE verified 34.2 x 26.3 x 20.2 m bounds, seven material slots and collision.
- One original three-arch main bridge mesh has replaced its deck and parapet proxies. The UE reload audit verified a 38.9 m long mesh and complex-as-simple collision. The smaller service bridge remains blockout geometry.
- Fab candidate board and source log. No paid/free Fab content has been acquired or imported. The guild is an original mesh; the other building masses remain temporary engine geometry.

## Current visual and functional limits

- This is Pass 01 composition blockout with two original hero meshes, not a high-quality art pass or a final playable town. No Fab buildings, vegetation, river water, landscape layers, street dressing or character controller are installed.
- The river ribbon, road strips and bridges are spatial proxies. Bridge decks now have ramp masses, but approaches still need walk collision and grade review in a continuous player traversal. Current segmented road proxies also need batching or replacement before performance review.
- The current map has a PlayerStart but no configured walking pawn or golden-route video. First in-engine screenshot automation triggered a prolonged UE shader compile and was stopped after the compiler ran without producing a frame. The top-down composition audit is at `Review/blockout_plan.png`; it is not an in-engine beauty screenshot.
- The target 1080p 45–60 FPS on RX 6650 XT is not measured yet.
- The Blender MCP session is disconnected, so the guild was authored with local headless Blender. Fab plugin import requires an interactive Epic account session that is not currently available on this machine; the free sample has not been claimed.

## Immediate production sequence

1. Inspect C01 south reveal and C07 rooftop density renders; revise parcel spacing and route bends before asset purchase.
2. Import the R16 as native Landscape and replace the temporary terrain mesh. Sculpt terraces and bridge banks by hand in editor.
3. Acquire one main Fab town family after license and visual review, then replace the Golden Route masses first. Continue with water, foliage, props and unified materials.
4. Configure a walking character; capture a continuous south-to-north route, ten fixed screenshots and a separate aerial only after the route reads coherently.

Do not describe this checkpoint as the requested commercial-quality town or as a completed first-phase gate.
