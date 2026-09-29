# ART → MAIN / COMBAT · Integration Requests

**Owner:** ART line
**Rule:** ART does not edit `combat_controller.gd`, the weapon state machine, the
input system, `iaido_director.gd` or `Player.tscn`. Those are MAIN / COMBAT files.
When ART needs something from them, it is written here instead of applied.

Status vocabulary used below (UE5 pipeline update):
`UE PROTOTYPE` → `UE VISUALLY VERIFIED` → `EXPORTED` → `GODOT REBUILT` →
`INTEGRATED` → `IN-GAME VERIFIED`

---

## REQ-1 · Training Ground needs a way in — **OPEN**

**Asks:** add `res://scenes/training/TrainingGround.tscn` as a reachable scene.

The scene is built and self-contained. It needs one of:

- a line in `main_flow.gd` that can open it (a debug key or a menu entry), or
- `application/run/main_scene` pointed at it while the review hub is the thing
  being worked on, or
- at minimum, confirmation that running it directly
  (`--path godot --main-pack` / editor "Current Scene") is the intended path.

**Why it is not ART's to do:** `main_flow.gd` is MAIN's flow control.

**Blocking note:** `Sword_FP.tscn` and `TrainingGround.tscn` cannot be fully
exercised until the parse errors listed in REQ-5 are resolved, because the
Training Ground carries over the same director stack as `CombatSandbox`.

---

## REQ-2 · Swap the placeholder sword for the real one — **CLOSED by ART, differently**

**Status:** done, and **`Player.tscn` was not edited.** Correcting this request is
the point of this entry, because the plan it originally asked for would have
broken both ceremonies.

**What the original ask was.** Instance `Sword_FP.tscn` under `WeaponRoot` and set
`TempSwordVisual.visible = false`, keeping the placeholder as the fallback.

**Why that plan is wrong.** `iaido_director.gd:46` and
`moment_of_no_moon_director.gd:55` both hard-`get_node()` `TempSwordVisual` and
then **write its transform for the whole skill**. Hiding the node does not stop
that — it hides the only thing being animated, so the ceremony would play out on
an invisible placeholder while the real sword stood still at its idle pose. The
skill would look broken while every line of its code ran correctly. And
`temp_sword_visual.gd` is not a passive carrier either: the trail, the glint
band, the void rim, the contact springs and the five locomotion channels are all
children of that node.

**What was actually done.**

```
WeaponRoot/TempSwordVisual/Sword_FP      <- the real rig, at identity
```

The real rig is a **child of the existing carrier**, so every pose, judgement and
animation path keeps driving exactly the node it always drove and only what is
drawn changes. The three placeholder boxes are hidden rather than removed, and
`temp_sword_visual.gd`'s `use_real_model` export puts them back in one step.

**Measured after the swap** (`godot/tools/shot_weapon_rack.gd`, live world AABB):

- exhibit AABB **1.0570 × 0.0777 × 0.0697 m**, **10,378 tris**, four materials
  (`MAT_Sword_Steel`, `MAT_Sword_Fittings`, `MAT_Sword_Grip`, `MAT_Sword_Inlay`)
- `WeaponRoot/SwordHitbox` **unchanged** at `(0, −0.2, −1.4)`, size `1.4 × 1.2 ×
  1.6` — the swing volume is COMBAT's and the model swap does not move it
- `ForegroundWeaponLayer` copies **32** nodes under `WeaponRoot`; the real rig is
  among them, which is only true because the rig is created during
  `TempSwordVisual._ready()` and the layer is later in the scene tree
- `TempSwordVisual.blade_length` **0.95 → 0.7650**, read from the registry. 0.95
  drew 185 mm of trail past a tip that stops at 0.765

**Superseded note above:** the `CORRECTION` in the original text said the blade
runs along −Z. That was true of the old GLB and is no longer true of anything.
The asset was re-authored to **+Y** so the file matches the contract that
`Sword_FP.tscn`, `iaido_tuning.gd`, `iaido_director.gd:_bore_pose()` and
`iaido_scabbard_rig.gd` all already spoke. The importer confirms the new GLBs
carry **no root rotation or scale**.

**Still true and worth repeating:** **do not set `layers` on the sword's meshes.**
`ForegroundWeaponLayer` owns `WEAPON_LAYER` and moves everything under
`WeaponRoot` there itself. The only way to opt a subtree out is
`ForegroundWeaponLayer.WORLD_DRAWN`, and the sword must not use it — a
first-person weapon drawn in the world clips into geometry the player stands
next to.

**One comment COMBAT should correct (`weapon_manager.gd:61-62`).** It currently
reads:

> `TempSwordVisual is the placeholder; Sword_FP is the real rig ART is building to`
> `replace it (see scenes/weapons/Sword_FP.tscn), which is why this is a list.`

The first clause is stale and the "which is why this is a list" is now backwards:
`Sword_FP` is a **child of** `TempSwordVisual`, not its successor, so the right
answer is that `SWORD_RIGS` lists **exactly one** node and should stay that way.
Left as-is it invites the next session to "finish the replacement" — put
`Sword_FP` in `SWORD_RIGS`, or reparent it to `WeaponRoot` — and that breaks the
ceremonies in the exact way described above. The list being one entry long is
**correct**, not unfinished.

The line itself needs no behaviour change: `rig.visible = sword_in_hand` sets
visibility on `TempSwordVisual`, and a child inherits it, so switching to the
chain still hides the real sword. Verified on the shipped scene.

---

## REQ-3 · Weapon switching from a physical rack — **PARTIALLY CLOSED**

**Good news:** `WeaponSlot` is now mounted on `Player.tscn` (ART found
`WeaponSlot (Node)` in the tree), so no new interface is needed. ART's weapon
racks call the existing contract and nothing else:

```
WeaponSlot.kind             -> StringName, &"sword" | &"chain"
WeaponSlot.equip(wanted)    -> bool, false when refused or already held
WeaponSlot.holds(wanted)    -> bool
WeaponSlot.display_name()   -> String
signal changed(previous, current)
```

**Ask:** confirm that the slot is the single owner of the decision (per its own
header comment) and that nothing else writes `kind` behind it. If a second
writer appears, the rack's `equip()` will start silently losing races, and a
rack that sometimes does nothing is worse than no rack.

**ART side implemented:** `scripts/training/training_weapon_rack.gd` binds `E`
via `InputMap.add_action(&"interact")` at runtime, exactly the way
`player_movement.gd` binds WASD, so ART never has to add an `[input]` section to
`project.godot`. It looks the slot up as `Player/WeaponSlot`, and if it is absent
it prints one specific warning naming the missing node rather than failing
silently.

---

## REQ-4 · The scabbard is still fake — **PARTLY CLOSED**

**The real scabbard now exists.** `godot/models/weapons/fp_saya.glb`,
**3,130 tris**, 4 materials (`MAT_Saya_Lacquer`, `MAT_Saya_Bore`,
`MAT_Sword_Fittings`, `MAT_Sword_Grip`), built by `tools/blender/saya_build.py`.
Measured dimensions:

| | |
|---|---|
| mouth bore | **43.5 × 13.7 mm** |
| mouth outside | **49.9 × 20.1 mm** |
| body length | **0.803 m** |
| bore depth | **0.790 m** |

Those are derived from the sword, not chosen: `HABAKI` + 1.75 mm of clearance per
side gives the bore, `SAYA_WALL` 3.2 mm gives the outside, and the tip is left
22 mm of room past the blade so a sheathed tip cannot wear a hole in its own
kojiri. `scripts/weapons/sword_classes.gd` recomputes all of them from the sword's
row, so a new sword cannot silently get a scabbard that does not fit it.

**ART installed it in two places and touched nothing of COMBAT's.**

1. **The Iaido ceremony scabbard.** `iaido_scabbard_rig.gd`'s own header says
   *"replacing it with the GLB is a geometry-only swap with no runtime change"*,
   and its published frame (origin at the koiguchi mouth plane, +Y down the bore,
   −X the edge side, +Z the kurikata side) is **the same frame `saya_build.py`
   authors in**. So `SwordFPRig.install_real_scabbard()` adds the real saya as a
   child of `CeremonyScabbard` at **identity**, and retires the stand-in by
   clearing its `mesh` — which is exactly the hook `iaido_scabbard_rig.gd:49`
   (`if mesh == null: build()`) publishes. The director keeps toggling the same
   node's `visible`, and the real saya inherits it. **No COMBAT file was edited.**
   Verified: `CeremonyScabbard.mesh == null`, one child named `Saya`.
2. **藏锋's sheathed idle** (`temp_sword_visual.gd:sheath_prop`). Left the same
   node as the carrier and replaced its box mesh with the real saya.

**One thing here is a decision CONTACT should look at.** With the stand-in, the
blade was hidden by a `visible = false` at 55 % sheathed, so nothing ever had to
actually be inside anything. With a real closed tube that stops working: the
blade travels to `sheath_pose` along a straight lerp, and a straight lerp to a
pose inside the bore is not the same path as sliding down the bore. ART therefore
**derives** the scabbard's pose instead of using the authored one:

```
saya = Transform3D(Basis.from_euler(move.sheath_pose_rot), move.sheath_pose)
       * sword_classes.saya_in_sword_frame(id)
```

which makes "fully sheathed" true by construction at any pose a moveset author
picks. `move.sheath_scabbard_pose/rot` are superseded while the real saya is in
use and remain the fallback. If COMBAT would rather keep authoring the scabbard
pose by hand, say so — but then the two poses have to be checked against each
other, because nothing currently makes them agree.

**Still open, and it is the real remaining ask:** the **left-waist anchor and the
five states** (`Idle hidden / waist` · `Iaido ready` · `Draw` · `Return` · `Final
insertion`). The scabbard is currently positioned by `IaidoTuning.sheath_position`
+ `scabbard_basis()` and by the moveset, not by a body-mounted anchor.

**Ask, explicitly (unchanged):** if the new scabbard needs anchor adjustment,
adjust the anchor. **Do not** reshape the Iaido state machine to fit the model.

**ART side next (W02 ART PASS 2):** the saya is still blockout in its *fittings* —
plain bands, a blob kurikata, no lacquer sheen break-up and no functional polish
at the mouth lip (§K). The mouth is the part that matters most (§7): it is what
every reverse-wave converges on and it is 43.5 mm across.

---

## REQ-8 · `ForegroundWeaponLayer`'s lighting was dead code — **FIXED by ART, please review**

**This is the highest-impact thing ART found this session, and it is in a MAIN
file, so it is written down rather than left as a quiet edit.**

`_mirror_world_lighting()` guarded on `viewport.world_3d`. With
`own_world_3d = true`, Godot **never** puts anything in that property — the
private world lives in a separate slot that only `find_world_3d()` reaches. So
the guard was always null, the assignment below it errored on a null instance,
and the `DirectionalLight3D` copy underneath it **was never added**.

Measured on the Training Ground before the fix:

```
find_world_3d()             -> valid
find_world_3d().environment -> NULL
directional lights in it    -> NONE      (with 32 meshes copied into it)
```

The private world had **no Environment and no light of any kind**, so every lit
mesh on the weapon layer was rendered by nothing. Same pose, same camera, same
material (`albedo 0.46, metallic 0.48, roughness 0.20`):

| | |
|---|---|
| `assets_source/review/fg_lighting/02_lighting_OFF_before_the_fix.png` | blade, tsuba and grip all a **flat pure black silhouette** (darkest pixel on the blade **0.000** on every scanline) |
| `assets_source/review/fg_lighting/01_lighting_ON_the_fix.png` | polished flat, edge line, kissaki facet, legible tsuba, wound grip relief (darkest pixel **0.069–0.404**) |

Nothing about the material changed between those two frames.

**Why nobody noticed:** everything on this layer used to be `UNSHADED`.
`temp_sword_visual.gd` builds its placeholder sword out of
`SHADING_MODE_UNSHADED` materials, which render at full albedo under no light at
all. The only lit mesh there was the chain's held bundle — which is exactly why
V4 recorded the bundle as CHARCOAL against a PALE rope drawn with one
`LINK_TINT`. That was never a chain bug; its light had been deleted.

**What ART changed** (`scripts/player/foreground_weapon_layer.gd`): `world_3d` →
`find_world_3d()`, restoring the Environment and the sun copy, plus the sun
staying in sync in `_process` so the Training Ground's DAY/NEUTRAL toggle still
moves it. **`WORLD_DRAWN` is untouched and still works** — and with the lighting
restored, a subtree no longer *has* to opt out to be lit, so the chain's rope and
handle could be un-split again. That is COMBAT's call, not ART's.

**Ask:** review the change and, if the chain's look was tuned against the
unlit private world, re-check it. Note also that `tools/shot_fp_sword.gd` had to
be given a 240-frame settle: quitting the engine too soon after loading this
scene segfaults in Godot's own teardown, which reproduces with this fix disabled
and with the attack removed.

---

## REQ-5 · Current parse errors blocking any full-scene run — **FYI, not an ART fix**

Found by `tools/diag_training_tree.gd` while load-testing the training ground.
These are **COMBAT's in-flight files**, mid-refactor, and ART has not touched them:

```
combat_hud.gd:157-158    Identifier "weapon" / "chain" not declared in the current scope
chain_director.gd:884    variable type inferred from a Variant (warning treated as error)
developer_panel.gd:118   Identifier "ChainLab" not declared in the current scope
developer_panel.gd:210   Identifier "_go_to_chain_lab" not declared
developer_panel.gd:489+  Cannot find type "ChainLab"
iaido_director.gd        Failed to compile depended scripts
combat_controller.gd     Failed to compile depended scripts
player_movement.gd       Compilation failed -> Player.tscn cannot load
```

This is reported, not requested. It is normal mid-refactor state; it is listed
because until it clears, **every scene that instances `Player.tscn` fails**, and
that includes the Training Ground. `developer_panel.gd` referencing a `ChainLab`
type also suggests COMBAT is building a chain lab of its own — see the note below.

---

## NOTE · Possible overlap: two chain labs

ART has built **zone D, the Chain Lab**, inside the Training Ground: a 24 × 20 m
bay with light/medium/heavy masses, a pillar, a wall, crates and an anchor post.

`developer_panel.gd` references a `ChainLab` **type** and a `_go_to_chain_lab()`
function, which implies COMBAT is building its own chain lab space.

**These should not both exist.** ART's is a *visual* bay — its job is to make
chain VFX and proportions reviewable. COMBAT's is presumably a *behavioural* rig.
Proposal: ART owns the room and the props, COMBAT owns what the chain does in it,
and the `ChainLab` type should point at ART's zone coordinates rather than
declaring a second room. **Please confirm which way you want this split before
either side does more work.**

---

## REQ-6 · The title screen is currently showing a greybox — **OPEN** (from UI line, not ART)

**Asks:** when the real Mistvale scene lands, re-render the main menu background
from it. Nothing else in the UI needs to change.

**What exists now.** UI PASS 02 (§1: *the world is the UI background*) made the
main menu show an actual in-engine render of the region instead of a generated
illustration. The shipping file is:

```
assets_source/ui/world/mistvale_menu_v1.png      2560x1440
```

It is produced by a first-party renderer, not by ART:

```
godot/tools/menu_vista_renderer.gd     loads scenes/world/MistvaleRegion.tscn
                                       (shot 53 — V1's forest shelf, fov 30, sun 19°/34°)
```

**Read this as a contract, not a mockup.** The whole point of §4 is that the
title screen is a *view of the real scene*, so ART progress upgrades it
automatically. It is therefore **not** a placeholder to be replaced by a painting,
and **not** a one-off image UI should re-shoot by eye. The right end state is:
the view is authored in the region scene (a named menu vantage), and the UI's
background is regenerated from the scene every time the region gets a real art
pass.

**What UI needs from ART, in priority order:**

1. **One authored menu vantage in `MistvaleRegion.tscn`.** It currently does not
   exist as an authored thing — UI picked shot 53 by rendering five batches and
   measuring. That choice should live in the region scene where ART can see and
   maintain it, not in a shot list inside a UI tool.
2. **A re-render once the region has real materials.** Run
   `godot --path F:/SEKAI/godot -s tools/menu_vista_renderer.gd --only=53 --name=mistvale_menu_v1`
   and drop the result over `assets_source/ui/world/mistvale_menu_v1.png`. The UI
   picks it up with no code change.
3. **Keep the left third quiet.** The menu sits on the left third of the frame
   with the logo above it. If a future vista puts a bright mass or a landmark
   there, the menu becomes unreadable and the composition breaks. This is a real
   constraint on the shot, not a preference — UI currently compensates with a
   left-only scrim plus a text-lift shadow, and both are band-aids over a bad
   composition.

**Also relevant to ART:** the renderer writes only to `assets_source/ui/world/`
and reads the region scene read-only; it disables the greybox review markers at
the source (`show_vistas = false` etc.) rather than hiding them afterwards. If
ART renames those flags, this tool breaks silently and only the stills will show
it.

**PASS 03 addition — re-check the enter-transition fog against the real scene.**
The menu→world transition passes a bank of fog across the frame to hide the
camera swap (`ui_web/v2/world/world_bg.css` `.world__wipe`). Its contrast was
tuned against the *greybox*, which is almost the same value as the fog, so on
today's background the wipe reads faint (measured opacity 0.12→0.68 crossing the
frame — the mechanism works, the *read* is weak). When the real scene lands,
check `menu_to_game_final.mp4` once more: if the wipe disappears against the new
background, lower its brightness (`rgba(226,231,229,…)` → closer to the scene's
sky value) rather than raising its opacity past ~0.85 — an over-opaque wipe reads
as a white flash, not weather.

**Verification:** the current menu still is not "ART reviewed" — it is a
greybox with atmosphere. See `ui_web/previews/ui_pass02_headline.png` for what it
looks like in situ. Mark this REQ closed when the file above is a real-material
render and the vantage is authored in the region scene.

---

## REQ-7 · Every production enemy needs an IAIDO CUT SUPPORT plan — **OPEN**

**Owner:** ART · **Raised by:** MAIN (Iaido execution pass) ·
**Blocks:** the signature kill reading as authored rather than as a generic death

聚合斩 now kills, and a kill by this刀 has to leave a body that is *evidence the
刀 happened*: the world is cut open, and so is the thing standing in front of it,
and the two are cut by the **same plane**. That is a technical contract, not a
polish pass, and it cannot be bolted on after an enemy is finished — hence this
request going out now, before the models exist, exactly as §U asks.

### What MAIN has already built (do not rebuild it)

- `IaidoExecutionProfile` (`godot/scripts/combat/iaido_execution_profile.gd`) —
  a `.tres` per enemy. Templates exist in `godot/resources/execution/`:
  `construct_sentinel`, `biological_placeholder`, `heavy_construct`,
  `ruin_warden` (Boss, see below), `unanchored_placeholder` (fallback).
- `IaidoExecutionLibrary` — the **material table**. One rule, one face per
  material class: construct / biological / ice / plant / generic, each with its
  own interior colour, rim, band width, core emission and debris colour. **None
  of them is blood red.** A profile does not restate this table; it points at it.
- `iaido_cleave.gdshader` — draws the fine cut line, the dark interior and a
  small emissive edge on the **live** body, and can discard half of it.
- `IaidoExecution` (`godot/scripts/combat/iaido_execution.gd`) — the runtime:
  hold → 1–3 cm creep → release on the sheath click → mass-dependent,
  deliberately **asymmetric** fall → dissolve from the wound outward.

### What ART owes, per production enemy

Add an `IAIDO CUT SUPPORT` block to the enemy's asset brief:

1. **Cut plane constraints.** Where a cut may pass. A body with a rigid shell
   over a soft core is not the same body as a slab of stone; if some region must
   never be separated (a shoulder that carries a silhouette read, a helmet that
   is the character), say so — the profile has `cuttable_region`
   (full / upper / core).
2. **Split geometry.** `Enemy_Cut_A` / `Enemy_Cut_B` — the two halves, modelled
   as real geometry, **not** a runtime boolean. Runtime arbitrary mesh slicing is
   forbidden; the budget does not allow it and the visual does not need it.
   - The halves must be authored so that, in their rest pose, they reassemble
     into the intact model to the vertex. The handover is a **mesh swap at the
     release instant**: before it the body is the normal mesh, after it the two
     halves are already falling. If the seam is visible in the intact pose, the
     swap will be visible too.
   - Position/origin convention: same as the normal model, no offsets. The
     runtime places them from the intact transform.
3. **Interior material.** The cross-section is *not* a flat colour. It needs its
   own material with a real interior — for a construct: stone fracture, broken
   metal, a hint of core emission; for a biological: a stylized dark interior
   with a restrained pale rim, **explicitly not realistic gore**; ice: crystal
   section and frost dust; plant: fibre and sap-like stylization.
4. **Fallback.** If the enemy ships without split geometry the generic path runs
   (cut-plane shader on one body + brief freeze + dissolve along the wound). It
   is legible and it is obviously provisional — so **the absence of split
   geometry must be a decision, not an oversight.** `resolve_mode()` deliberately
   does *not* treat a missing mesh as a reason to fall back, precisely so that
   the fallback cannot become the only path anyone ever sees.

### Two special cases, already decided

- **Bosses (Ruins Warden and successors).** A Boss killed by an Iaido Final Blow
  uses an authored **special response**, not a cleave: armour splits, the core is
  cut, the mask breaks, a large diagonal scar opens and the body collapses along
  the cut. `execution_type = "special"`, `cuttable_region = "core"`. It must
  **not** fall back to an ordinary death — that is the whole point of the beat.
- **Non-humanoids** (Lesser Ruin Sentinel). Not "top half and bottom half". A
  construct is separated along the slash plane into two **structural groups** —
  core shell / body ring / arm module — and the cross-section is stone, aged
  metal and magic core. See `cut_material` on the profile.

### Verification

`godot/tests/iaido_execution_integration.gd` already asserts the contract:
non-lethal never splits, a lethal cut holds the body, the sheath click releases
it, a held body cannot act, every exit path resolves, multi-kill shares one cut
plane, and the fallback runs when there is no split geometry. When split meshes
arrive, `_verify_authored_split_meshes()` is the test that has to start
exercising them **instead of** the fallback.

**Status: OPEN.** Not a blocker for shipping the ceremony — the fallback covers
every enemy — but a production enemy is not DONE until this block exists.

---

## REQ-9 · The chain can stop being drawn in code — **OPEN, ART side delivered**

**From:** ART (weapon line) · **To:** COMBAT · **Blocking:** nothing yet — this is
the interface request that has to exist *before* the held arcs can be authored.

The user's ruling of 2026-09-29: the chain's visual is split into named pieces,
`而不是再生成那坨程序圆盘`, and the four-layer idle stow becomes an **authored mesh /
curve asset, 由 Combat 只控制显隐和释放比例**. Three of those pieces are now built
and asserted. The fourth cannot be built until COMBAT answers one question.

### What ART has delivered

`assets/models/weapons/`:

| File | Envelope | Tris | Materials |
|---|---|---|---|
| `wpn_chain_handle.glb` | 0.2805 m, butt ring outer 0.0415 m | 1624 | `chain_grip`, `chain_head`, leather |
| `wpn_chain_link.glb` | 0.0911 × 0.0601 × 0.0137 m | 320 | `chain_link` |
| `wpn_chain_trident.glb` | 0.7800 m long, 0.26 m fork span | 1096 | `chain_head`, iron |

Masters (Git LFS, editable source): `assets_source/weapons/masters/chn/wpn_chain_*.blend`.
Spec: `assets_source/weapons/specs/chn_variants.json`. Builder:
`tools/blender/wpn_chn_build.py`. Full asset rationale:
`docs/weapons/CHAIN_ASSET_DECOMPOSITION.md`.

### The three swap points, and what each has to keep

**1 · `_link_geometry()` → `wpn_chain_link.glb`.**

The link's three dimensions are **not free**: two of them set the interlock and
the third is the material `stow_ring_readings()` subtracts. Its outer envelope
is *where the procedural link's was*, so swapping the mesh must not move it.
Authored values, all derived in one place from the live constants
(`link_spacing` 0.052, `LINK_FILL` 1.752, `LINK_WIDTH_SCALE` 0.66,
`LINK_TUBE_RATIO` 0.7):

```
length along the rope  0.09110 m
across the rope        0.06013 m
along the hole axis    0.01367 m      <- the same r the ring test subtracts
```

⚠️ **The previous numbers in `CHAIN_ASSET_DECOMPOSITION.md` §4 were stale**
(0.0473 / 0.0312 are `LINK_FILL` 1.82 values) and have been corrected there.
If COMBAT changes `link_spacing` or `LINK_FILL`, **the GLB must be rebuilt** —
the build asserts the extents and will fail rather than drift.

⚠️ **One deliberate difference.** The authored link bakes the 0.66 oval into the
mesh instead of applying it through `_link_basis`. The outer envelope is
unchanged, but the **tube is round** rather than squashed to 0.66 across the
rope. Net effect: more metal across the rope, a slightly smaller hole. That is
the direction `LINK_TUBE_RATIO`'s own comment asks for, and it removes the
non-uniform basis scale — but it does mean `_link_basis` becomes a pure rotation
and its `LINK_WIDTH_SCALE` row should become **1.0**, not stay 0.66, or the
authored oval gets squashed twice.

**2 · `_build_head()` → `wpn_chain_trident.glb`.**

Sized to the head it replaces, **by measurement, not by taste**: the procedural
head is built in multiples of `head_size` (0.34 m) with the tip at −1.84h and
the collar back at +0.50h, i.e. **0.796 m**. The authored head is **0.7800 m**.
That matters because `_contact_point - _contact_normal * head_size *
BITE_DRIVE_SHARE` places the bite from `head_size` and **not from the mesh** — an
authored head that came out shorter would visibly bite from inside a wall.

The head's origin is its **connecting ring, which sits behind the hub** at
y = −0.036 m, and the rope passes through it along +Y. Local forward is +Y (the
procedural one used −Z).

**3 · The three materials, which COMBAT currently sets in code.**

`LINK_TINT` / `HEAD_TINT` / `HANDLE_TINT` and `LINK_METALLIC` have been moved
into the shared palette as `chain_link` / `chain_head` / `chain_grip`, at the
exact linear conversions of those sRGB values. Nothing about the look changes.
What changes is that **`metallic > 0.75` is now a build-time assertion** in
`weapon_common.METALLIC_CEILING` — the metal trap that already cost this weapon
two review passes is finally guarded, and it could not be while the values lived
in code.

### What COMBAT has to answer before the held arcs can exist

The four arcs (`WPN_CHAIN_HELD_ARC_A..D`) are the part that is **not** a model
swap. They replace a per-frame parameter solve with an authored performance, so
ART needs one interface, and only one:

> **Publish `visible: bool` and `release: float 0..1` per layer, at a single
> node, and let ART own everything inside it.**

Specifically:

1. **`visible`** must keep the semantics `_place_coils` already has:
   *第 D 层最先放出去，第 A 层最后*, i.e. the existing
   **「INNERMOST FIRST, OUTERMOST LAST」** rule. The comment above `_place_coils`
   is the contract — hiding from the top is what makes a shed layer behave like
   rope leaving a stow.
2. **`release` (0..1)** interpolates the whole group from the stowed pose to
   "all let go". **Per-layer stagger stays COMBAT's decision**, not the asset's —
   if each arc carried its own offset, the layout mathematics would have moved
   back into the art asset, which is the thing this split exists to avoid.
3. **The four arcs must share one origin convention** (the arc's entry, nearest
   the fist, tangent along the arc). Different origins per layer would make (1)
   and (2) impossible to express.
4. **The acceptance criteria stay where they are and must keep running.**
   `stow_frame_reach() < 1.0` (framing is a *second, independent* failure —
   `stow_breach()` only looks at the centre, so an over-wide fan walks off the
   edge while breach stays 0.0000), `stow_interpenetration() == 0`, and
   `stow_ring_readings()` for anything that is still links.

### The tradeoff, stated plainly, because it is not a free upgrade

> An authored arc **can** draw the small·flat·on-the-hip four-layer fan that this
> chain physically cannot bend into — `CHAIN_STOW_TUNING.md` has already proved
> the flattened-ellipse constraint is 5–8× tighter than the minimum bend radius,
> and no amount of link fidelity changes that. That is the whole reason to do it.
>
> But it also means **the release has to be authored too** — it can no longer be
> derived from the rope's real pitch. **画面可以说谎，姿态必须自洽。**

### What ART is not asking for

- Not a rewrite of `chain_visual.gd`. The free rope, the hit choreography, the
  sag, the trail, `BUNDLE_SHED_SHARE`, the bite drive and the whole `_stow_path`
  solve stay COMBAT's. Only the three geometry/material sources above change.
- Not a change to `chain_length`, `max_radius` or `head_size`.
- Not a new system. `LINK_FILL` and friends stay the single source of truth for
  the link size; the builder reads them and asserts against them.

**Status: OPEN.** The geometry side is done and asserted; the swap is COMBAT's to
schedule, and the held arcs are blocked on items 1–3 above.

---

## Cross-references

- `docs/ASSET_MANIFEST.md` — measured status of every asset
- `docs/UE5_VFX_LAB.md` — the UE5 prototyping → Godot rebuild pipeline
- `docs/asset_briefs/KIT-02a-STAIR-TERRACE.md` — stair kit rev. 2
- `assets_source/review/art_import_audit.txt` — the audit run that produced the
  numbers quoted in REQ-2
