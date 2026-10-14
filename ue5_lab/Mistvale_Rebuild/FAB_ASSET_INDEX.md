# Fab assets actually used in Mistvale

## Slavic Medieval Town Kit Lite

- Listing: https://www.fab.com/listings/b99a0776-f733-4cc0-b771-aa326b616a88
- Source: user's existing Fab library and local downloaded FBX package, `Slavic_Medieval_Town_Kit_-_Lite__Free_Starter_Pack_-b99a0776`.
- Local package: 213 FBX files. Twenty selected FBX families were imported to `/Game/Fab/SlavicLite` as separate LOD0/LOD1/LOD2 meshes; only LOD0 is currently placed. The UE import produced 77 package assets including material instances.
- Current placement: 95 first-pass replacements of houses, corner buildings, inn, church nave, blacksmith, warehouse, gate towers and market roofs. The new map also uses the rock gate arch as its north entrance, the village tower as church bell tower, and 17 cobble-fence segments at the guild yard.
- Main building families: Administrative, Cubby, PentHouse, Shed 01a, Shed 03b, WoodRoof and Village Tover. Additional imported modular parts include walls, porches, fences, platform and door.
- Material issue: the downloaded FBX references an atlas image at a vendor-local `H:` path; the image is not in this package. Imported houses initially rendered white in UE. Four locally authored wall/roof palette materials now make their shapes readable, but texture fidelity and detailed art direction are unfinished.
- Audit files: `Source/slavic_mesh_dimensions.json`, `Source/art_level_placements.json`, `Source/art_level_verify.json`, `Source/art_dress_result.json`, `Source/colorize_result.json`.

No additional Fab product was downloaded or imported for this pass.
