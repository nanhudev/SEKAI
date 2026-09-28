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

## REQ-2 · Swap the placeholder sword for the real one — **OPEN**

**Asks:** in `Player.tscn`, under
`CameraRig/LookPivot/MotionPivot/ShakePivot/WeaponRoot`:

- instance `res://scenes/weapons/Sword_FP.tscn`
- keep `TempSwordVisual` in the file but `visible = false`, as the one-step
  fallback the brief asks for

**Already done by ART:** `Sword_FP.tscn` exists and wraps
`res://models/weapons/fp_sword.glb`. Measured by the importer
(`tools/audit_art_import.gd`): **832 tris, 4 materials**
(`MAT_Sword_Steel`, `MAT_Sword_Fittings`, `MAT_Sword_Grip`, `MAT_Sword_Inlay`),
AABB **0.131 × 0.044 × 1.047 m**.

> **CORRECTION worth recording.** The earlier note in `CHAT2BLENDER_LOG.md` said
> the blade runs along **+Y**. The importer disagrees: the sword's long axis is
> **Z** (1.047 m), its thickness is **Y** (0.044 m). That is what the Blender
> Z-up to glTF Y-up conversion does to a Blender +Y blade. `Sword_FP.tscn` is
> built on the measured axis, and its `BladeForward` marker points along −Z.
> Anything that previously hard-coded +Y needs the same fix.

**Do not** set `layers` on the sword's meshes — `ForegroundWeaponLayer` owns that
layer and moves everything under `WeaponRoot` to the unlit foreground itself.

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

## REQ-4 · The scabbard is still fake — **OPEN, waiting on C2B-FP-SCABBARD**

**Current state:** `Player.tscn` has `WeaponRoot/SheathAnchor/CeremonyScabbard`
(a `MeshInstance3D` placeholder) driven by `iaido_scabbard_rig.gd`.

**Ask (after the real scabbard exists):** make the scabbard an **independent
node**, not a child of the sword, fixed to a **left-waist anchor**, and support
the five states the brief names: `Idle hidden / waist` · `Iaido ready` · `Draw` ·
`Return` · `Final insertion`.

**Ask, explicitly:** if the new scabbard needs anchor adjustment, adjust the
anchor. **Do not** reshape the Iaido state machine to fit the model.

**ART side not started:** the C2B brief and request package are written
(`docs/asset_briefs/prompts/`) but not yet sent, because the ChatGPT session is
busy with KIT-02a. The key requirement is that the blade must genuinely enter the
scabbard — no fake overlap.

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

**Verification:** the current menu still is not "ART reviewed" — it is a
greybox with atmosphere. See `ui_web/previews/ui_pass02_headline.png` for what it
looks like in situ. Mark this REQ closed when the file above is a real-material
render and the vantage is authored in the region scene.

---

## Cross-references

- `docs/ASSET_MANIFEST.md` — measured status of every asset
- `docs/UE5_VFX_LAB.md` — the UE5 prototyping → Godot rebuild pipeline
- `docs/asset_briefs/KIT-02a-STAIR-TERRACE.md` — stair kit rev. 2
- `assets_source/review/art_import_audit.txt` — the audit run that produced the
  numbers quoted in REQ-2
