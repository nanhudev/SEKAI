# SWORD VISUAL PROFILE - specification and current status

> **GENERATED** by `tools/gen_profile_doc.py` from `source/sword_visual_profile.json` and `exports/p11_report.json`.
> Do not hand-edit: change the spec and regenerate, or the two will disagree and the disagreement will not be visible.

Batch: **SWORD PRESENTATION V3 + MAGIC SWORD VFX V1**. Folder: `/Game/SEKAI/VFX/Sword/`.

## 1. The rule this document exists to enforce

> Magic must call the SAME Sword Move as Normal. There is no MagicSwordAttackA1/A2. The only difference between the two swords is which profile is applied.

A profile is **only** a set of slot bindings: which core system realises the slot, which material instance it wears, and the `User.*` values that drive it. It owns no animation, no timing and no geometry of its own.

Timing never lives here. It arrives as events from the Sword line - see `docs/sword_vfx_event_contract.json`, which is generated from the Godot source of truth. A profile that appears to know about time is a bug.

## 2. The parameter namespace (what a profile may change)

Read back from the nine built systems, not copied from a plan - so a parameter listed here is one the graph really exposes.

| # | Parameter | Type | Purpose |
|---|-----------|------|---------|
| 1 | `User.PrimaryColor` | `LinearColor` | stroke body colour |
| 2 | `User.CoreColor` | `LinearColor` | hot core colour |
| 3 | `User.MistColor` | `LinearColor` | void / mist colour |
| 4 | `User.DarkColor` | `LinearColor` | void core colour |
| 5 | `User.Intensity` | `NiagaraFloat` | global multiplier, drives Color.Scale Alpha |
| 6 | `User.Width` | `NiagaraFloat` | stroke width, metres |
| 7 | `User.Length` | `NiagaraFloat` | stroke length, authored value, metres |
| 8 | `User.Radius` | `NiagaraFloat` | arc / burst / sprite radius, metres |
| 9 | `User.ArcAngle` | `NiagaraFloat` | major arc sweep, degrees |
| 10 | `User.Lifetime` | `NiagaraFloat` | particle lifetime, seconds |
| 11 | `User.Speed` | `NiagaraFloat` | travel speed, authored value, m/s |
| 12 | `User.Distortion` | `NiagaraFloat` | refraction offset strength |
| 13 | `User.MistAmount` | `NiagaraFloat` | 0 = normal sword, 1 = magic sword |
| 14 | `User.SpawnRate` | `NiagaraFloat` | particles per second, primary emitters |
| 15 | `User.StartPosition` | `NiagaraPosition` | world start |
| 16 | `User.EndPosition` | `NiagaraPosition` | world end |
| 17 | `User.BladeBase` | `NiagaraPosition` | blade base, world |
| 18 | `User.BladeTip` | `NiagaraPosition` | blade tip, world |
| 19 | `User.ArcStart` | `NiagaraFloat` | arc begin angle, degrees |
| 20 | `User.ArcEnd` | `NiagaraFloat` | arc end angle, degrees |
| 21 | `User.ScaleVector` | `Vector3f` | ScaleMeshSize takes Vector3f, so Length/Radius have this vector twin |
| 22 | `User.Velocity` | `Vector3f` | SolveForcesAndVelocity takes Vector3f, so Speed has this vector twin |
| 23 | `User.MistCount` | `NiagaraInt32` | burst count for mist emitters; 0 in the Normal profile keeps them free |
| 24 | `User.MistRate` | `NiagaraFloat` | spawn rate for mist emitters; 0 in the Normal profile keeps them free |

`User.DarkColor`, `User.ArcStart`, `User.ArcEnd`, `User.ScaleVector`, `User.Velocity`, `User.MistCount` and `User.MistRate` are documented extensions beyond the brief's section 24 list. `ArcStart`/`ArcEnd` exist so a 300-degree arc cannot silently close into a 360-degree ring; `ScaleVector` and `Velocity` exist because `ScaleMeshSize.Scale Factor` and `SolveForcesAndVelocity.Velocity` are `Vector3f`, not `float`, and linking a float into them makes the compiler repair the graph.

## 3. Slot map (shared by both swords)

Changing this map changes **both** swords. That is why it is not inside either profile.

| Slot | Realised by | What it is for |
|------|-------------|----------------|
| `IdleVFX` | `NS_SW_Core_PurpleMotes`, `NS_SW_Core_MistWake` | section 14 / 6. Normal is deliberately near-zero here: a cold blade does not smoke. Magic is a few motes and a thin wisp, never a continuous smoke machine. |
| `EquipGlint` | `NS_SW_Core_Glint` | section 7. Blade is only 12-20 cm out; ONE narrow highlight scans the exposed steel, 80-160 ms. Normal: silver-white. Magic: purple, and still reads as LIGHT running along the steel - never the whole sword becoming a purple tube. |
| `InspectGlint` | `NS_SW_Core_Glint` | section 8. The SAME glint core as EquipGlint, retuned: slower, and travelling base -> tip instead of a partial scan. This is why the glint is a parameterised component rather than two effects. |
| `BladeTrail` | `NS_SW_Core_EdgeTrail` | section 9. Thickness is the whole identity: extremely thin. A thick trail would read as a separate effect rather than as the edge of this blade. |
| `A1Slice` | `NS_SW_Core_AirSlice`, `NS_SW_Core_EdgeTrail` | section 9 / 17. Peak only. Normal is a pressure cut in AIR, ~1.5-2.5 m, NOT a projectile. Magic keeps the identical geometry and adds a thread of black vapour along the original path. |
| `A2Wave` | `NS_SW_Core_Wave` | section 10 / 18. A thin curved PRESSURE SHEET, 6-10 m, NOT a thick blue crescent. Bright edge, faint interior, distortion in the tail only. |
| `A3Scar` | `NS_SW_Core_SpatialScar` | section 11 / 19. WORLD-space, three separate cuts, never screen space, never HUD. Magic is the hero of this batch and the one place that can FAIL: three scars must still read as three. |
| `A4Arc` | `NS_SW_Core_MajorArc`, `NS_SW_Core_EdgeTrail` | section 12 / 21. 240-300 degrees, NOT a 360 ring. The arc forms live with the blade so START, SWEEP and END are all visible. |
| `IaidoDraw` | `NS_SW_Core_Glint` | section 22. The new Iaido motion. Normal: cold draw glint. Magic: purple draw glint. |
| `IaidoScar` | `NS_SW_Core_SpatialScar` | section 22 / 19. The cut of the new Iaido line, i.e. the void scar rather than the A3 triple. |
| `SheatheVFX` | `NS_SW_Core_MistWake`, `NS_SW_Core_Glint` | section 22. As the blade approaches the saya the mist steadily reduces; once the blade is truly IN, the mist is pulled back in. On the final click one point appears at the saya mouth for 20-50 ms, then ALL vfx return to zero. This beat must be very clean and is the last thing the player sees. |
| `HitBody` | `NS_SW_Core_Hit` | contact family. Colour is the blade's own, so a Normal hit never flashes purple. |
| `HitStone` | `NS_SW_Core_Hit` | contact family. Substrate test: a sword that cuts space should still sound and look different on stone. |
| `HitMetal` | `NS_SW_Core_Hit` | contact family. Metal is the one that must not be handed to a bright additive - brief section 32 is about overdraw and metal hits are the usual offender. |
| `HitWood` | `NS_SW_Core_Hit` | contact family. The softest read of the four; the only one where a small amount of material breakup is allowed. |

## 4. `VP_Sword_Normal`

**Identity:** white, silver, pale cyan

**Keywords:** thin, sharp, fast, clean, air pressure, space cut

> few particles, more Ribbon / Mesh / Material / world-space geometry / distortion. Section 6 forbids solving this with particle count.

| Slot | System | Material instance | Profile values |
|------|--------|-------------------|----------------|
| `IdleVFX` | `NS_SW_Core_PurpleMotes` | `MI_SW_Mote_Normal` | `SpawnRate`=0.0, `MistAmount`=0.0, `Intensity`=0.0 |
| `EquipGlint` | `NS_SW_Core_Glint` | `MI_SW_Glint_Normal` | `Intensity`=1.0, `Lifetime`=0.14, `Speed`=1.4, `Length`=0.16 |
| `InspectGlint` | `NS_SW_Core_Glint` | `MI_SW_Glint_Normal` | `Intensity`=0.85, `Lifetime`=0.4, `Speed`=0.55, `Length`=1.0 |
| `BladeTrail` | `NS_SW_Core_EdgeTrail` | `MI_SW_Trail_Normal` | `Width`=0.045, `Lifetime`=0.18, `Intensity`=1.0 |
| `A1Slice` | `NS_SW_Core_AirSlice` | `MI_SW_SpatialScar_Normal` | `Length`=2.0, `Lifetime`=0.09, `Width`=0.03, `MistAmount`=0.0 |
| `A2Wave` | `NS_SW_Core_Wave` | `MI_SW_Wave_Normal` | `Length`=8.0, `Speed`=34.0, `Lifetime`=0.3, `Width`=0.6, `Distortion`=0.35 |
| `A3Scar` | `NS_SW_Core_SpatialScar` | `MI_SW_SpatialScar_Normal` | `Lifetime`=0.42, `Width`=0.055, `MistAmount`=0.05, `Distortion`=0.0 |
| `A4Arc` | `NS_SW_Core_MajorArc` | `MI_SW_Trail_Normal` | `ArcAngle`=300.0, `ArcStart`=-150.0, `ArcEnd`=150.0, `Lifetime`=0.3, `Width`=0.34 |
| `IaidoDraw` | `NS_SW_Core_Glint` | `MI_SW_Glint_Normal` | `Intensity`=1.1, `Lifetime`=0.1, `Speed`=2.2 |
| `IaidoScar` | `NS_SW_Core_SpatialScar` | `MI_SW_SpatialScar_Normal` | `Lifetime`=0.6, `Width`=0.06, `MistAmount`=0.0 |
| `SheatheVFX` | `NS_SW_Core_MistWake` | `MI_SW_Mist_Normal` | `MistAmount`=0.0, `SpawnRate`=0.0, `Intensity`=0.0 |
| `HitBody` | `NS_SW_Core_Hit` | `MI_SW_Glint_Normal` | `Intensity`=0.85, `Lifetime`=0.14 |
| `HitStone` | `NS_SW_Core_Hit` | `MI_SW_Trail_Normal` | `Intensity`=0.7, `Lifetime`=0.16 |
| `HitMetal` | `NS_SW_Core_Hit` | `MI_SW_Glint_Normal` | `Intensity`=0.95, `Lifetime`=0.12 |
| `HitWood` | `NS_SW_Core_Hit` | `MI_SW_Trail_Normal` | `Intensity`=0.6, `Lifetime`=0.18 |

Per-slot reasoning:

- **`IdleVFX`** - deliberately silent: a cold blade does not idle. Zero, not small.
- **`EquipGlint`** - 12-20 cm of exposed blade, 140 ms scan, silver-white.
- **`InspectGlint`** - same core, slower, full base->tip travel.
- **`BladeTrail`** - thin is the identity. Width above 0.06 stops reading as an edge.
- **`A1Slice`** - 50-100 ms at the peak only. Air pressure, not a projectile. NOTE: the slice is a 6 cm scar-strip MESH drawn on start->end by the scar mask's U wipe, so it wears the flat scar material rather than the ribbon's trail material - an earlier revision of this spec said MI_SW_Trail_Normal and the slot-binding check below caught it.
- **`A2Wave`** - 8.0 m at 34 m/s = 0.235 s, inside the 0.18-0.35 s band. Distortion is tail-only.
- **`A3Scar`** - space remembers three cuts. Mist is 0.05 - present only so the core system stays identical.
- **`A4Arc`** - 300 degrees, not 360. ArcStart/ArcEnd exist so the ring can never silently close.
- **`IaidoDraw`** - the 100 ms draw (tuning 4.68 -> 4.78) is short and axial.
- **`IaidoScar`** - void_life is 1.0 s in the tuning; the scar is the readable part of it.
- **`SheatheVFX`** - Normal has nothing to suck back in. Kept as a slot so the click cue has one home.


## 5. `VP_Sword_Magic`

**Identity:** deep violet, cold purple, pale purple-white core, black / blue-black mist

**Keywords:** the sword cuts space and darkness leaks through the cut

> section 13: this is NOT a purple reskin of Normal. Every slot must read as the same swordsmanship with something leaking through it. No neon purple, ever.

| Slot | System | Material instance | Profile values |
|------|--------|-------------------|----------------|
| `IdleVFX` | `NS_SW_Core_PurpleMotes` | `MI_SW_Mote_Magic` | `SpawnRate`=6.0, `MistAmount`=0.18, `Intensity`=0.55 |
| `EquipGlint` | `NS_SW_Core_Glint` | `MI_SW_Glint_Magic` | `Intensity`=1.05, `Lifetime`=0.16, `Speed`=1.4, `Length`=0.16 |
| `InspectGlint` | `NS_SW_Core_Glint` | `MI_SW_Glint_Magic` | `Intensity`=0.9, `Lifetime`=0.42, `Speed`=0.55, `Length`=1.0 |
| `BladeTrail` | `NS_SW_Core_EdgeTrail` | `MI_SW_Trail_Magic` | `Width`=0.05, `Lifetime`=0.2, `Intensity`=1.05 |
| `A1Slice` | `NS_SW_Core_AirSlice` | `MI_SW_SpatialScar_Magic` | `Length`=2.0, `Lifetime`=0.24, `Width`=0.032, `MistAmount`=0.3 |
| `A2Wave` | `NS_SW_Core_Wave` | `MI_SW_Wave_Magic` | `Length`=8.0, `Speed`=32.0, `Lifetime`=0.34, `Width`=0.62, `Distortion`=0.4, `MistAmount`=0.35 |
| `A3Scar` | `NS_SW_Core_SpatialScar` | `MI_SW_SpatialScar_Magic` | `Lifetime`=0.55, `Width`=0.062, `MistAmount`=0.55, `Distortion`=0.15 |
| `A4Arc` | `NS_SW_Core_MajorArc` | `MI_SW_Trail_Magic` | `ArcAngle`=300.0, `ArcStart`=-150.0, `ArcEnd`=150.0, `Lifetime`=0.34, `Width`=0.36, `MistAmount`=0.3 |
| `IaidoDraw` | `NS_SW_Core_Glint` | `MI_SW_Glint_Magic` | `Intensity`=1.15, `Lifetime`=0.1, `Speed`=2.2 |
| `IaidoScar` | `NS_SW_Core_SpatialScar` | `MI_SW_SpatialScar_Magic` | `Lifetime`=0.6, `Width`=0.064, `MistAmount`=0.45 |
| `SheatheVFX` | `NS_SW_Core_MistWake` | `MI_SW_Mist_Magic` | `MistAmount`=1.0, `SpawnRate`=12.0, `Intensity`=1.0 |
| `HitBody` | `NS_SW_Core_Hit` | `MI_SW_Glint_Magic` | `Intensity`=0.9, `Lifetime`=0.15, `MistAmount`=0.12 |
| `HitStone` | `NS_SW_Core_Hit` | `MI_SW_Trail_Magic` | `Intensity`=0.75, `Lifetime`=0.17, `MistAmount`=0.1 |
| `HitMetal` | `NS_SW_Core_Hit` | `MI_SW_Glint_Magic` | `Intensity`=1.0, `Lifetime`=0.12, `MistAmount`=0.08 |
| `HitWood` | `NS_SW_Core_Hit` | `MI_SW_Trail_Magic` | `Intensity`=0.65, `Lifetime`=0.19, `MistAmount`=0.14 |

Per-slot reasoning:

- **`IdleVFX`** - a few motes and a thin wisp - section 14 explicitly forbids a continuous smoke machine.
- **`EquipGlint`** - same scan as Normal, purple. Section 15: still light running along the steel.
- **`InspectGlint`** - motion unchanged from Normal; only the values differ.
- **`BladeTrail`** - marginally thicker than Normal so the violet body reads, still an edge.
- **`A1Slice`** - section 17: identical geometry, purple-white core, black vapour along the ORIGINAL path only. 0.15-0.30 s. Wears the scar material for the same reason as Normal.
- **`A2Wave`** - same shape and gameplay. Black mist is a short WAKE, not a fireball and not lightning.
- **`A3Scar`** - HERO BEAT, section 19. Core purple-white, inner deep purple, an extremely narrow black void outside it. Mist leaks gently and expands slowly along the scar normal - never a burst. Section 20: if the hero frame shows one mass of purple-black smoke it is a FAIL, so MistAmount is capped here on purpose.
- **`A4Arc`** - section 21: same geometry, leading edge purple-white, and the black wake behind must NOT close into a ring. ArcStart/ArcEnd enforce the gap.
- **`IaidoDraw`** - purple draw glint on the identical new Iaido motion.
- **`IaidoScar`** - purple void scar cut, same construction as A3.
- **`SheatheVFX`** - section 22. This is the ONLY slot that starts at full mist, because it is the one that has to visibly empty: mist reduces as the blade nears the saya, is suctioned in once the blade is truly inside, then one purple point on the click for 20-50 ms and everything returns to zero. The final beat must be clean.


## 6. Slot-binding check (derived, not declared)

Every slot above names a material instance. This section checks that claim against the material actually sitting on that system's renderers, and sorts the result into three kinds - because lumping them together would drown a real error in a known gap:

- **exact** - the instance the slot names is on the system right now.
- **blocked** - the slot names the *other* profile's instance (same material family, only the `_Normal`/`_Magic` suffix differs). Correct as written, but undeliverable until the section 7 fix lands: the system carries one instance and cannot wear both.
- **mismatch** - a different material family entirely. That is a real disagreement between this spec and the built system, and this check has already found one: the A1 slice was documented as wearing the trail material while the built system wears the scar material, because the slice is a drawn-on strip mesh, not a ribbon.

| Result | Slots |
|--------|-------|
| exact | **13** / 30 |
| blocked by the section 7 gap | **13** / 30 |
| mismatch - spec disagrees with the build | **4** / 30 |

Mismatches, which are the ones worth acting on:

| Profile | Slot | System | Declared | System actually wears |
|---------|------|--------|----------|-----------------------|
| `VP_Sword_Normal` | `HitStone` | `NS_SW_Core_Hit` | `MI_SW_Trail_Normal` | `MI_SW_Glint_Normal` |
| `VP_Sword_Normal` | `HitWood` | `NS_SW_Core_Hit` | `MI_SW_Trail_Normal` | `MI_SW_Glint_Normal` |
| `VP_Sword_Magic` | `HitStone` | `NS_SW_Core_Hit` | `MI_SW_Trail_Magic` | `MI_SW_Glint_Normal` |
| `VP_Sword_Magic` | `HitWood` | `NS_SW_Core_Hit` | `MI_SW_Trail_Magic` | `MI_SW_Glint_Normal` |

The **`HitStone`, `HitWood`** family is a different kind of failure from the rest and is worth separating: `NS_SW_Core_Hit` has a single renderer, so it cannot wear four different instances at once no matter what the profile says. Either the hit core gets one renderer per substrate, or the four slots share one instance and the substrate difference lives in `User.*` alone. That is a design decision, not a typo, and it is left visible rather than quietly resolved in the spec.

Blocked slots are `13` of `30` and are all the same sentence: the profile asks for the other sword's material and the graph has not been parameterised yet. They are listed here as a count rather than a table because the remedy is one change - `User.Material` on the renderers - not 13 edits.


## 7. Shared vs different (the honest accounting)

Shared, and this is not a compromise:

- **Animation.** Every beat is the same beat. Magic does not get a second Iaido, a second A3, or a longer A4.
- **The Sword Move.** Magic calls the same move through the same controller. `MagicSwordAttackA1()` / `MagicSwordAttackA2()` are forbidden - brief section 5.
- **The nine core systems.** One graph each, composited through `User.*`. Section 23 forbids a second set for Magic.
- **Geometry.** A2's sheet, A3's three scar traces and A4's arc are the same shapes. Section 17-21 require this explicitly.

Different, and this is the entire observable difference between the two swords:

- **The material instance** worn by each renderer.
- **The `User.*` values**, chiefly the four colours (`PrimaryColor` / `CoreColor` / `MistColor` / `DarkColor`) and `MistAmount`.

### Known gap: the renderer material is currently hard-wired

Derived from the build report, not asserted. A core system whose renderers name one material instance cannot serve both swords, so while this holds, Magic needs a second copy of the graph and section 5 is not satisfiable.

| System | Material on its renderers | Serves both? |
|--------|---------------------------|--------------|
| `NS_SW_Core_AirSlice` | `MI_SW_SpatialScar_Normal` | **no - one instance only** |
| `NS_SW_Core_EdgeTrail` | `MI_SW_Trail_Normal` | **no - one instance only** |
| `NS_SW_Core_Glint` | `MI_SW_Glint_Normal` | **no - one instance only** |
| `NS_SW_Core_Hit` | `MI_SW_Glint_Normal` | **no - one instance only** |
| `NS_SW_Core_MajorArc` | `MI_SW_Mist_Normal`, `MI_SW_Trail_Normal` | **no - one instance only** |
| `NS_SW_Core_MistWake` | `MI_SW_Mist_Normal` | **no - one instance only** |
| `NS_SW_Core_PurpleMotes` | `MI_SW_Mote_Normal` | **no - one instance only** |
| `NS_SW_Core_SpatialScar` | `MI_SW_Mist_Normal`, `MI_SW_SpatialScar_Normal` | **no - one instance only** |
| `NS_SW_Core_Wave` | `MI_SW_Mist_Normal`, `MI_SW_Wave_Normal` | **no - one instance only** |

**9 of 9** systems are single-instance.

**Fix (design, `SPEC READY`):** drive the renderer material from a `User.Material` parameter of type `MaterialInterface`, and let the profile assign `MI_SW_*_Normal` or `MI_SW_*_Magic`. Then the profile swap is literally one parameter write, no duplicate graph exists, and the table above becomes yes / yes / yes.

Until that lands, the two material instances per core are both built and present, so the visual comparison this batch is for can still be done by swapping the material on the renderer by hand - marked below as a `MANUAL EDITOR STEP`. Both statements are true at once and neither is hidden.

## 8. Status

| Item | State | Evidence |
|------|-------|----------|
| Profile spec (15 brief slots, 2 profiles) | `SPEC READY` | `source/sword_visual_profile.json` |
| 24 user parameters on the built systems | `ASSET READY` | `exports/p11_report.json` |
| 9 core systems | `IMPLEMENTED` | 9/9 built, 49 pins linked, saved 9/9 |
| 12 material instances (Normal + Magic) | `ASSET READY` | `exports/p10_assets.txt` |
| Renderer material parameterised (`User.Material`) | `SPEC READY` | gap in section 7 |
| Profile as a UE Data Asset | *not built* | needs a `UDataAsset` subclass; see section 9 |
| Visual profile verified in engine | *not verified* | requires looking at a render |

Per brief section 35, nothing on this page is `VISUALLY VERIFIED` yet. `IMPLEMENTED` means the graph exists and runs, not that it looks right.

## 9. Why there is no `DA_SwordVisualProfile` asset yet

A UE Data Asset needs a `UDataAsset` subclass with `UPROPERTY` fields. This project is Blueprint-only - there is no `Source/` module - and neither a `USTRUCT` nor a `UCLASS` can be declared from Python. Checked against the engine:

- `unreal.DataAssetFactory` is present, but it takes a `DataAssetClass` (`TSubclassOf<UDataAsset>`) and no engine subclass has these fields.
- `unreal.UserDefinedStructFactory` and `unreal.PrimaryDataAssetFactory` are **not exposed to Python** in 5.8.3 - probed, not assumed.

So the profile ships as a versioned, machine-readable spec plus this generated document, which is what the VFX and gameplay code can actually read today. Turning it into a real Data Asset is either a one-file C++ module or a short editor session, and is marked accordingly rather than faked with an empty asset. An empty `DA_SwordVisualProfile` would be worse than none: it would look like the dependency was resolved.

