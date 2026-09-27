# Asset manifest

| Asset | Source / prompt | Blender source | GLB | Polycount | Materials | Game usage | Status |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| Mistvale modular building kit | GPT-5.6 Sol; modular timber fantasy town, metre scale, GLB friendly, 12 parts | `assets/chat2blender/mistvale_kit_blockout.py`, `mistvale_kit_details.py`, `mistvale_kit_export.py` | `assets/models/mistvale/*.glb` | 1,946 total tris at generation | See source | East village house | Integrated; further town reuse needed |
| C2B-01 First Person Sword | Not generated — brief only | `assets_source/weapons/fp_sword.blend` (pending) | `assets/models/weapons/fp_sword.glb` (pending) | Budget < 12k tris | Max 4 | Replaces TempSwordVisual primitive | SPEC READY |
| C2B-02 FP Hand / Forearm | Not generated — brief only | `assets_source/character/fp_hand.blend` (pending) | `assets/models/character/fp_hand.glb` (pending) | Budget < 9k tris | Max 3 | Sword / Block / Cast / Iaido poses | SPEC READY |
| C2B-03 Lesser Ruin Sentinel | Not generated — brief only | `assets_source/enemies/lesser_ruin_sentinel.blend` (pending) | `assets/models/enemies/lesser_ruin_sentinel.glb` (pending) | Budget < 18k tris | Max 4 | Replaces technical_dummy | SPEC READY |
| C2B-04 Magic Catalyst | Not generated — brief only | `assets_source/weapons/magic_catalyst.blend` (pending) | `assets/models/weapons/magic_catalyst.glb` (pending) | Budget < 7k tris | Max 3 | First-person casting focus | SPEC READY |

Future Chat2Blender assets must record the exact generation prompt, `.blend` or reproducible script, exported GLB, measured triangle and material counts, usage, and visible QA result before marking complete.
