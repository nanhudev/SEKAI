## What this file is

One row per sound atom that is actually loadable in the game, with where it came from.
**The rows are generated** by `audio_source/tools/emit_manifest_doc.py`; the header and the
license section are written by hand. The machine-readable authorities are:

| field | authority |
| --- | --- |
| `id`, `category`, `family`, `usage` | `godot/scripts/audio/{chain_atom_table,sound_atom_registry}.gd` |
| `raw`, `processed`, `seed`, `provider`, `prompt`, `status` | `audio_source/library/sfx_manifest.json` |
| `duration`, `peak` | measured from the shipped wav, not trusted from a table |
| `license` | **not in any table** - see below |

## License and provenance

Every atom in this library is generated locally, not licensed from a sound pack:

- **Provider / model:** `stabilityai/stable-audio-3-small-sfx` (`stable-audio-3-small-sfx`),
  run on **CPU**, `steps=8`, `cfg_scale=1.0`, `sample_rate=44100`.
- **License:** **Stability AI Community License.** Outputs are owned by the user and may be
  distributed and commercialised freely; the carve-out is scale - an organisation above
  **USD 1M annual revenue** must move to the Stability AI Enterprise licence, which is also
  the tier that carries legal indemnification.
- **Training data posture:** the model family is trained on licensed audio (AudioSparx
  catalogue plus Freesound under CC-0 / CC-BY / CC-Sampling+), which is the basis of the
  commercial-use claim rather than a post-hoc legal argument.
- **Not Suno.** Suno is used in this project for **BGM only**; no SFX in this manifest comes
  from Suno. The legacy Suno SFX that predate this rule are marked LEGACY and must not be
  deleted (they are still referenced as fallbacks).

### Open item - the license is recorded once, not per row

`audio_source/library/sfx_manifest.json` has **no `license` key at all** (verified over all
404 entries of the sword library and all 228 of the main one). The license above is uniform
across the generated library, so recording it once is accurate *today* - and it stops being
accurate the moment a second provider is added, because there will be nothing in the data
to distinguish the rows. The fix is one field in the generator plus a re-emit, and it is
deliberately not done here: the manifest is written by a tool this line does not own.


## Atoms (35 families, 99 atoms)

`variants` is how many seeds this family can alternate between - the number
that decides whether a fast combo machine-guns one file (§17).

| id | category | family | variants | duration | peak | seed | usage | status |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| `air_cut_heavy_01_A` | air | `air_cut_heavy` | 3 | 0.82s | -6.0 | 1000 | heavy release; broad displaced air with weight behind it | processed |
| `air_cut_heavy_01_B` | air | `air_cut_heavy` | 3 | 0.82s | -6.0 | 1137 | heavy release; broad displaced air with weight behind it | processed |
| `air_cut_heavy_01_C` | air | `air_cut_heavy` | 3 | 0.82s | -6.0 | 1274 | heavy release; broad displaced air with weight behind it | processed |
| `air_cut_light_01_A` | air | `air_cut_light` | 3 | 0.42s | -6.0 | 1000 | A1/A2 identity layer; a fast clean blade cut, no metal | processed |
| `air_cut_light_01_B` | air | `air_cut_light` | 3 | 0.42s | -6.0 | 1137 | A1/A2 identity layer; a fast clean blade cut, no metal | processed |
| `air_cut_light_01_C` | air | `air_cut_light` | 3 | 0.42s | -6.0 | 1274 | A1/A2 identity layer; a fast clean blade cut, no metal | processed |
| `air_cut_medium_01_A` | air | `air_cut_medium` | 3 | 0.94s | -6.0 | 1000 | A3 combo finisher; wider than light, still no low boom | processed |
| `air_cut_medium_01_B` | air | `air_cut_medium` | 3 | 1.05s | -6.0 | 1137 | A3 combo finisher; wider than light, still no low boom | processed |
| `air_cut_medium_01_C` | air | `air_cut_medium` | 3 | 1.03s | -6.0 | 1274 | A3 combo finisher; wider than light, still no low boom | processed |
| `air_heavy_01_A` | air | `air_heavy` | 2 | 0.84s | -6.0 | 1000 | A1 左甩 low air whoosh; heavy swing layer for any large object | processed |
| `air_heavy_01_B` | air | `air_heavy` | 2 | 0.98s | -6.0 | 1137 | A1 左甩 low air whoosh; heavy swing layer for any large object | processed |
| `air_stab_01_A` | air | `air_stab` | 3 | 0.37s | -6.0 | 1000 | thrust and riposte; narrow focused forward air | processed |
| `air_stab_01_B` | air | `air_stab` | 3 | 0.37s | -6.0 | 1137 | thrust and riposte; narrow focused forward air | processed |
| `air_stab_01_C` | air | `air_stab` | 3 | 0.37s | -6.0 | 1274 | thrust and riposte; narrow focused forward air | processed |
| `body_impact_soft_01_A` | body | `body_impact` | 2 | 0.37s | -6.0 | 1000 | CHAIN_CONTACT on an enemy — stylized, no gore; shared by sword and magic | processed |
| `body_impact_soft_01_B` | body | `body_impact` | 2 | 0.37s | -6.0 | 1137 | CHAIN_CONTACT on an enemy — stylized, no gore; shared by sword and magic | processed |
| `low_impact_short_01_A` | body | `low_impact_short` | 3 | 0.52s | -6.0 | 1000 | short low transient; the finisher's weight, never a cinematic boom | processed |
| `low_impact_short_01_B` | body | `low_impact_short` | 3 | 0.54s | -6.0 | 1137 | short low transient; the finisher's weight, never a cinematic boom | processed |
| `low_impact_short_01_C` | body | `low_impact_short` | 3 | 0.74s | -6.0 | 1274 | short low transient; the finisher's weight, never a cinematic boom | processed |
| `sword_contact_body_01_A` | body | `sword_contact_body` | 3 | 0.56s | -6.0 | 1000 | SWORD_CONTACT_BODY: stylized, dull hit plus a small blade slice | processed |
| `sword_contact_body_01_B` | body | `sword_contact_body` | 3 | 0.52s | -6.0 | 1137 | SWORD_CONTACT_BODY: stylized, dull hit plus a small blade slice | processed |
| `sword_contact_body_01_C` | body | `sword_contact_body` | 3 | 0.54s | -6.0 | 1274 | SWORD_CONTACT_BODY: stylized, dull hit plus a small blade slice | processed |
| `weapon_body_heavy_01_A` | body | `weapon_body_heavy` | 3 | 0.69s | -6.0 | 1000 | the weapon's own mass on a heavy move; the mass that swings it | processed |
| `weapon_body_heavy_01_B` | body | `weapon_body_heavy` | 3 | 0.69s | -6.0 | 1137 | the weapon's own mass on a heavy move; the mass that swings it | processed |
| `weapon_body_heavy_01_C` | body | `weapon_body_heavy` | 3 | 0.69s | -6.0 | 1274 | the weapon's own mass on a heavy move; the mass that swings it | processed |
| `weapon_body_light_01_A` | body | `weapon_body_light` | 3 | 0.36s | -6.0 | 1000 | the weapon's own mass on a light move; hilt and guard, not the target | processed |
| `weapon_body_light_01_B` | body | `weapon_body_light` | 3 | 0.35s | -6.0 | 1137 | the weapon's own mass on a light move; hilt and guard, not the target | processed |
| `weapon_body_light_01_C` | body | `weapon_body_light` | 3 | 0.36s | -6.0 | 1274 | the weapon's own mass on a light move; hilt and guard, not the target | processed |
| `cloth_heavy_01_A` | cloth | `cloth_heavy` | 3 | 1.40s | -6.0 | 1000 | heavy wind-up: coat and fabric shifting under a big motion | processed |
| `cloth_heavy_01_B` | cloth | `cloth_heavy` | 3 | 1.25s | -6.0 | 1137 | heavy wind-up: coat and fabric shifting under a big motion | processed |
| `cloth_heavy_01_C` | cloth | `cloth_heavy` | 3 | 1.29s | -6.0 | 1274 | heavy wind-up: coat and fabric shifting under a big motion | processed |
| `cloth_light_01_A` | cloth | `cloth_light` | 3 | 0.81s | -6.0 | 1000 | a PERSON is swinging: sleeve and fabric on a quick cut | processed |
| `cloth_light_01_B` | cloth | `cloth_light` | 3 | 0.81s | -6.0 | 1137 | a PERSON is swinging: sleeve and fabric on a quick cut | processed |
| `cloth_light_01_C` | cloth | `cloth_light` | 3 | 0.78s | -6.0 | 1274 | a PERSON is swinging: sleeve and fabric on a quick cut | processed |
| `grip_shift_01_A` | cloth | `grip_shift` | 3 | 0.60s | -6.0 | 1000 | the hand re-taking the grip; a beat of intent before a heavy release | processed |
| `grip_shift_01_B` | cloth | `grip_shift` | 3 | 1.27s | -6.0 | 1137 | the hand re-taking the grip; a beat of intent before a heavy release | processed |
| `grip_shift_01_C` | cloth | `grip_shift` | 3 | 1.31s | -6.0 | 1274 | the hand re-taking the grip; a beat of intent before a heavy release | processed |
| `weapon_sway_01_A` | cloth | `weapon_sway` | 3 | 0.74s | -6.0 | 1000 | PART H: dodge and sprint sway, very quiet, event based | processed |
| `weapon_sway_01_B` | cloth | `weapon_sway` | 3 | 0.72s | -6.0 | 1137 | PART H: dodge and sprint sway, very quiet, event based | processed |
| `weapon_sway_01_C` | cloth | `weapon_sway` | 3 | 0.67s | -6.0 | 1274 | PART H: dodge and sprint sway, very quiet, event based | processed |
| `crystal_break_01_A` | ice | `crystal_break` | 3 | 1.02s | -6.0 | 1000 | SHATTER: a frozen object coming apart, not a window breaking | processed |
| `crystal_break_01_B` | ice | `crystal_break` | 3 | 1.02s | -6.0 | 1137 | SHATTER: a frozen object coming apart, not a window breaking | processed |
| `crystal_break_01_C` | ice | `crystal_break` | 3 | 1.05s | -6.0 | 1274 | SHATTER: a frozen object coming apart, not a window breaking | processed |
| `ice_crack_01_A` | ice | `ice_crack` | 3 | 1.18s | -6.0 | 1000 | frozen flesh under stress; the beat before the shatter | processed |
| `ice_crack_01_B` | ice | `ice_crack` | 3 | 1.26s | -6.0 | 1137 | frozen flesh under stress; the beat before the shatter | processed |
| `ice_crack_01_C` | ice | `ice_crack` | 3 | 1.12s | -6.0 | 1274 | frozen flesh under stress; the beat before the shatter | processed |
| `ice_impact_01_A` | ice | `ice_impact` | 3 | 0.42s | -6.0 | 1000 | SWORD_CONTACT_ICE: the blade arriving on frozen matter | processed |
| `ice_impact_01_B` | ice | `ice_impact` | 3 | 0.42s | -6.0 | 1137 | SWORD_CONTACT_ICE: the blade arriving on frozen matter | processed |
| `ice_impact_01_C` | ice | `ice_impact` | 3 | 0.42s | -6.0 | 1274 | SWORD_CONTACT_ICE: the blade arriving on frozen matter | processed |
| `ice_shard_settle_01_A` | ice | `ice_shard_settle` | 3 | 0.83s | -6.0 | 1000 | the aftermath of a shatter; shards settling, dry and short | processed |
| `ice_shard_settle_01_B` | ice | `ice_shard_settle` | 3 | 0.80s | -6.0 | 1137 | the aftermath of a shatter; shards settling, dry and short | processed |
| `ice_shard_settle_01_C` | ice | `ice_shard_settle` | 3 | 1.01s | -6.0 | 1274 | the aftermath of a shatter; shards settling, dry and short | processed |
| `blade_move_heavy_01_A` | metal | `blade_move_heavy` | 3 | 0.80s | -6.0 | 1000 | heavy blade in motion; the steel's own body resonance | processed |
| `blade_move_heavy_01_B` | metal | `blade_move_heavy` | 3 | 0.80s | -6.0 | 1137 | heavy blade in motion; the steel's own body resonance | processed |
| `blade_move_heavy_01_C` | metal | `blade_move_heavy` | 3 | 0.80s | -6.0 | 1274 | heavy blade in motion; the steel's own body resonance | processed |
| `blade_move_light_01_A` | metal | `blade_move_light` | 3 | 0.46s | -6.0 | 1000 | the blade itself in motion; sits under the air, above nothing | processed |
| `blade_move_light_01_B` | metal | `blade_move_light` | 3 | 0.47s | -6.0 | 1137 | the blade itself in motion; sits under the air, above nothing | processed |
| `blade_move_light_01_C` | metal | `blade_move_light` | 3 | 0.56s | -6.0 | 1274 | the blade itself in motion; sits under the air, above nothing | processed |
| `blade_ring_short_01_A` | metal | `blade_ring_short` | 3 | 0.58s | -6.0 | 1000 | short blade ring; the steel answering, never a bell | processed |
| `blade_ring_short_01_B` | metal | `blade_ring_short` | 3 | 0.57s | -6.0 | 1137 | short blade ring; the steel answering, never a bell | processed |
| `blade_ring_short_01_C` | metal | `blade_ring_short` | 3 | 0.58s | -6.0 | 1274 | short blade ring; the steel answering, never a bell | processed |
| `blade_slide_short_01_A` | metal | `blade_slide_short` | 3 | 0.87s | -6.0 | 1000 | edge sliding along edge; the bind, and the beat before a riposte | processed |
| `blade_slide_short_01_B` | metal | `blade_slide_short` | 3 | 0.81s | -6.0 | 1137 | edge sliding along edge; the bind, and the beat before a riposte | processed |
| `blade_slide_short_01_C` | metal | `blade_slide_short` | 3 | 0.85s | -6.0 | 1274 | edge sliding along edge; the bind, and the beat before a riposte | processed |
| `guard_metal_01_A` | metal | `guard_metal` | 3 | 0.58s | -6.0 | 1000 | ordinary block: SOLID METAL CONTACT, dull, edge did not bite | processed |
| `guard_metal_01_B` | metal | `guard_metal` | 3 | 0.58s | -6.0 | 1137 | ordinary block: SOLID METAL CONTACT, dull, edge did not bite | processed |
| `guard_metal_01_C` | metal | `guard_metal` | 3 | 0.58s | -6.0 | 1274 | ordinary block: SOLID METAL CONTACT, dull, edge did not bite | processed |
| `hook_metal_01_A` | metal | `hook_metal` | 2 | 0.37s | -6.0 | 1000 | CHAIN_WALL on metal / weapon rack / iron door | processed |
| `hook_metal_01_B` | metal | `hook_metal` | 2 | 0.41s | -6.0 | 1137 | CHAIN_WALL on metal / weapon rack / iron door | processed |
| `metal_contact_heavy_01_A` | metal | `metal_contact_heavy` | 3 | 0.68s | -6.0 | 1000 | sword meeting metal with commitment; the body of the clash | processed |
| `metal_contact_heavy_01_B` | metal | `metal_contact_heavy` | 3 | 0.69s | -6.0 | 1137 | sword meeting metal with commitment; the body of the clash | processed |
| `metal_contact_heavy_01_C` | metal | `metal_contact_heavy` | 3 | 0.69s | -6.0 | 1274 | sword meeting metal with commitment; the body of the clash | processed |
| `metal_contact_light_01_A` | metal | `metal_contact_light` | 3 | 0.41s | -6.0 | 1000 | sword meeting metal lightly; graze and deflect | processed |
| `metal_contact_light_01_B` | metal | `metal_contact_light` | 3 | 0.42s | -6.0 | 1137 | sword meeting metal lightly; graze and deflect | processed |
| `metal_contact_light_01_C` | metal | `metal_contact_light` | 3 | 0.41s | -6.0 | 1274 | sword meeting metal lightly; graze and deflect | processed |
| `metal_link_heavy_01_A` | metal | `chain_link_heavy` | 2 | 0.83s | -6.0 | 1000 | heavy rattle accent; the loud end of the rattle range | processed |
| `metal_link_heavy_01_B` | metal | `chain_link_heavy` | 2 | 0.35s | -6.0 | 1137 | heavy rattle accent; the loud end of the rattle range | processed |
| `perfect_guard_sharp_01_A` | metal | `perfect_guard_sharp` | 3 | 0.41s | -6.0 | 1000 | PERFECT GUARD: the sharpest, cleanest metal transient in the game | processed |
| `perfect_guard_sharp_01_B` | metal | `perfect_guard_sharp` | 3 | 0.42s | -6.0 | 1137 | PERFECT GUARD: the sharpest, cleanest metal transient in the game | processed |
| `perfect_guard_sharp_01_C` | metal | `perfect_guard_sharp` | 3 | 0.42s | -6.0 | 1274 | PERFECT GUARD: the sharpest, cleanest metal transient in the game | processed |
| `riposte_release_01_A` | metal | `riposte_release` | 3 | 0.47s | -6.0 | 1000 | the answer out of a perfect guard; a focused decisive release | processed |
| `riposte_release_01_B` | metal | `riposte_release` | 3 | 0.47s | -6.0 | 1137 | the answer out of a perfect guard; a focused decisive release | processed |
| `riposte_release_01_C` | metal | `riposte_release` | 3 | 0.47s | -6.0 | 1274 | the answer out of a perfect guard; a focused decisive release | processed |
| `hook_stone_01_A` | stone | `hook_stone` | 2 | 0.38s | -6.0 | 1000 | CHAIN_WALL on stone — the trident BITE; CONTACT layer for any stone surface | processed |
| `hook_stone_01_B` | stone | `hook_stone` | 2 | 0.42s | -6.0 | 1137 | CHAIN_WALL on stone — the trident BITE; CONTACT layer for any stone surface | processed |
| `stone_chip_01_A` | stone | `stone_chip` | 3 | 0.52s | -6.0 | 1000 | small debris answering a blade; a chip, not a hammer blow | processed |
| `stone_chip_01_B` | stone | `stone_chip` | 3 | 0.58s | -6.0 | 1137 | small debris answering a blade; a chip, not a hammer blow | processed |
| `stone_chip_01_C` | stone | `stone_chip` | 3 | 0.58s | -6.0 | 1274 | small debris answering a blade; a chip, not a hammer blow | processed |
| `sword_contact_stone_01_A` | stone | `sword_contact_stone` | 3 | 0.42s | -6.0 | 1000 | SWORD_CONTACT_STONE: stone chip plus metal edge contact, NOT a hammer | processed |
| `sword_contact_stone_01_B` | stone | `sword_contact_stone` | 3 | 0.42s | -6.0 | 1137 | SWORD_CONTACT_STONE: stone chip plus metal edge contact, NOT a hammer | processed |
| `sword_contact_stone_01_C` | stone | `sword_contact_stone` | 3 | 0.42s | -6.0 | 1274 | SWORD_CONTACT_STONE: stone chip plus metal edge contact, NOT a hammer | processed |
| `hook_wood_01_A` | wood | `hook_wood` | 2 | 0.37s | -6.0 | 1000 | CHAIN_WALL on wood — bridge, door, dock, crate | processed |
| `hook_wood_01_B` | wood | `hook_wood` | 2 | 0.37s | -6.0 | 1137 | CHAIN_WALL on wood — bridge, door, dock, crate | processed |
| `sword_contact_wood_01_A` | wood | `sword_contact_wood` | 3 | 0.47s | -6.0 | 1000 | SWORD_CONTACT_WOOD: dry cut plus a wood crack | processed |
| `sword_contact_wood_01_B` | wood | `sword_contact_wood` | 3 | 0.47s | -6.0 | 1137 | SWORD_CONTACT_WOOD: dry cut plus a wood crack | processed |
| `sword_contact_wood_01_C` | wood | `sword_contact_wood` | 3 | 0.47s | -6.0 | 1274 | SWORD_CONTACT_WOOD: dry cut plus a wood crack | processed |
| `wood_crack_01_A` | wood | `wood_crack` | 3 | 0.47s | -6.0 | 1000 | wood giving way; the second half of a wooden contact | processed |
| `wood_crack_01_B` | wood | `wood_crack` | 3 | 0.47s | -6.0 | 1137 | wood giving way; the second half of a wooden contact | processed |
| `wood_crack_01_C` | wood | `wood_crack` | 3 | 0.47s | -6.0 | 1274 | wood giving way; the second half of a wooden contact | processed |

