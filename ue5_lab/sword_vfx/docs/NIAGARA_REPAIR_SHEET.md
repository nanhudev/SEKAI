# NIAGARA REPAIR SHEET — the nine core systems

**Status: the nine `NS_SW_Core_*` systems are empty shells. They must be filled
in the editor.**

This sheet is the actionable half of `VERIFICATION_STATUS.md` §3. Read that
section for the evidence; this is what to do about it.

Companion: `EXACT_BUILD.md` is the source of truth for every **input value**
(49 pins of names, types and linked `User.*` parameters). This sheet gives the
**module index** — which module goes in which stack — and deliberately does not
re-transcribe the input values, so the two cannot drift apart.

---

## 1. Why the editor, and not a script

Measured, `p51`: calling `AddModule` on one of these emitters kills the editor.

```
Assertion failed: StackNodeGroups.Num() >= 2
[Engine/Plugins/FX/Niagara/Source/NiagaraEditor/Private/ViewModels/...]
Callstack: ToolsetRegistry.dll → CoreUObject.dll → PythonScriptPlugin.dll
           → python311.dll → Slate.dll → UnrealEditor-Cmd.exe
```

The assert fires because these stacks have **no module group at all** — there is
nothing for the stack view model to attach a second group to. So the failure is a
consequence of the emptiness, and it means there is no scripted way in: any bulk
tool hits the same wall on an empty stack.

---

## 2. What is actually on disk

Read with `GetEmitterTopology` in `p49` (and proven against stock engine systems
in `p50`, which returns 27 and 28 modules through the identical call):

| System | Emitters present | Emitters the plan called for | Modules in all stacks |
|---|---|---|---|
| `NS_SW_Core_EdgeTrail` | `E_Trail` | `E_Trail` | **0** |
| `NS_SW_Core_Glint` | `E_Glint` | `E_Glint` | **0** |
| `NS_SW_Core_AirSlice` | `E_Slice` | `E_Slice` | **0** |
| `NS_SW_Core_Wave` | `E_Wave`, `E_MistWake` | same | **0** |
| `NS_SW_Core_SpatialScar` | `E_Scar`, `E_ScarMist` | same | **0** |
| `NS_SW_Core_MajorArc` | `E_Arc` | `E_Arc`, **`E_ArcMist`** | **0** |
| `NS_SW_Core_MistWake` | `E_Wisp` | `E_Wisp` | **0** |
| `NS_SW_Core_PurpleMotes` | `E_Motes` | `E_Motes` | **0** |
| `NS_SW_Core_Hit` | `E_Hit` | `E_Hit` | **0** |

Two things to notice:

- **`E_ArcMist` does not exist.** `NS_SW_Core_MajorArc` needs a second emitter
  created, not filled. It is the incomplete black-mist wake behind the A4 arc
  (§21) — the Magic counterpart's whole distinguishing feature.
- Everything else about the shells is correct: emitter names, renderer classes,
  sim target, and the full §24 user-parameter set including `User.ArcAngle = 300`.

---

## 3. Module index — what goes in which stack

Module assets, all confirmed present on disk (`p51`):

| Short name | Asset |
|---|---|
| `InitializeParticle` | `/Niagara/Modules/Spawn/Initialization/V2/InitializeParticle` |
| `SpawnRate` | `/Niagara/Modules/Emitter/SpawnRate` |
| `SpawnBurst_Instantaneous` | `/Niagara/Modules/Emitter/SpawnBurst_Instantaneous` |
| `Color` | `/Niagara/Modules/Update/Color/Color` |
| `ScaleSpriteSize` | `/Niagara/Modules/Update/Size/ScaleSpriteSize` |
| `ScaleMeshSize` | `/Niagara/Modules/Update/Size/ScaleMeshSize` |
| `RibbonWidth` | `/Niagara/Modules/Ribbons/RibbonWidth` |
| `SolveForcesAndVelocity` | `/Niagara/Modules/Solvers/SolveForcesAndVelocity` |

Stack order is Emitter Spawn → Emitter Update → Particle Spawn → Particle Update,
and within each stack the order below is the order they must appear
(`InitializeParticle` before anything that reads a particle; `ParticleState`
style state modules come first in Particle Update where they are used).

### `NS_SW_Core_EdgeTrail` — ribbon edge trail (A1 / A4)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnRate` |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `Color`, `RibbonWidth` |

Renderer `E_Trail`: Ribbon, `MI_SW_Trail_Normal`.

### `NS_SW_Core_Glint` — equip / inspect cold glint (§7, §8)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count 1) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleSpriteSize`, `Color` |

Renderers `E_Glint`: Sprite (`MI_SW_Glint_Normal`) + Light.
`ScaleSpriteSize`'s "Uniform Scale Factor" is not editable through the toolset —
set it on the module by hand (this is `EXACT_BUILD.md`'s manual step for this
system, and it is the reason the parameter is set there rather than scripted).

### `NS_SW_Core_AirSlice` — A1 thin air slice (§9)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count 1) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleMeshSize`, `Color` |

Renderer `E_Slice`: Mesh, `MI_SW_SpatialScar_Normal` / `SM_SW_ScarStrip`.

### `NS_SW_Core_Wave` — A2 pressure sheet (§10, §18)
**`E_Wave`**
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count 1) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleMeshSize`, `SolveForcesAndVelocity`, `Color` |

Renderer `E_Wave`: Mesh, `MI_SW_Wave_Normal` / `SM_SW_WaveSheet`.

**`E_MistWake`**
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count `User.MistCount`) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `Color` |

Renderer `E_MistWake`: Mesh, `MI_SW_Mist_Normal` / `SM_SW_GlintQuad`.
Zero cost in the Normal profile — `User.MistCount` is 0 there.

### `NS_SW_Core_SpatialScar` — A3 world-space scars (§11, §19, §20)
**`E_Scar`**
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count 1) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleMeshSize`, `Color` |

Renderer `E_Scar`: Mesh, `MI_SW_SpatialScar_Normal` / `SM_SW_ScarStrip`.

**`E_ScarMist`**
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count `User.MistCount`) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `Color` |

Renderer `E_ScarMist`: Mesh, `MI_SW_Mist_Normal` / `SM_SW_GlintQuad`.

### `NS_SW_Core_MajorArc` — A4 major arc (§12, §21)
**`E_Arc`**
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count 1) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleMeshSize`, `Color` |

Renderer `E_Arc`: Mesh, `MI_SW_Trail_Normal` / `SM_SW_ArcSheet`.

**`E_ArcMist` — MUST BE CREATED** (it is not in the asset)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count `User.MistCount`) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `Color` |

Renderer: Mesh, `MI_SW_Mist_Normal` / `SM_SW_GlintQuad`. Duplicate `E_Wave`'s
`E_MistWake` as the starting point — it is the same shape.

### `NS_SW_Core_MistWake` — void leakage (§14, §15, §33)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnRate` |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleMeshSize`, `Color` |

Renderer `E_Wisp`: Mesh, `MI_SW_Mist_Normal` / `SM_SW_GlintQuad`.
Zero cost in the Normal profile — `User.MistRate` is 0 there.

### `NS_SW_Core_PurpleMotes` — magic idle motes (§14)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnRate` |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleSpriteSize`, `Color` |

Renderer `E_Motes`: Sprite, `MI_SW_Mote_Normal`. Sprite size is the same
hand-set "Uniform Scale Factor" as the glint.

### `NS_SW_Core_Hit` — contact burst (§24, §36)
| Stack | Modules |
|---|---|
| Emitter Update | `SpawnBurst_Instantaneous` (count 14) |
| Particle Spawn | `InitializeParticle` |
| Particle Update | `ScaleSpriteSize`, `Color` |

Renderer `E_Hit`: Sprite, `MI_SW_Glint_Normal`.
Hit timing belongs to the animation event, never to the system.

---

## 4. Procedure, per system

1. Open the system in the **Niagara editor**.
2. **Add the first module of each stack by hand**, from the stack's own `+` menu
   or by dragging it in. This is the step that cannot be scripted — `AddModule`
   asserts when a stack has no module group (§1). Once one group exists the stack
   is normal and behaves.
3. Add the remaining modules for that stack in the order listed in §3.
4. Set the input values and the `User.*` links from `EXACT_BUILD.md`. Where the
   sheet marks a `MANUAL EDITOR STEP`, that input is one the toolset could not
   reach — set it on the module.
5. **Verify the renderer's material and mesh.** p11 binds materials on the
   **renderer**, not on the mesh asset, and `p34` measured that all four VFX
   meshes still have `static_materials[0] = /Engine/EngineMaterials/
   WorldGridMaterial`. That is expected and not a bug — but it means a renderer
   whose material slot was never filled will draw a checkerboard, so check it
   rather than assume it.
6. Create `E_ArcMist` on `NS_SW_Core_MajorArc` (§3).
7. **Save the package.** Compiling without saving leaves the asset exactly as it
   was; this is the step p11 and p43 both could not perform from a script.

---

## 5. Pass criteria

Re-run the two readers. Do not accept a verdict from the tool that made the
change.

```
cd sword_vfx/scripts
# 1. the graph: does the topology now show modules?
./run_ue.sh p50_topology_control.py --editor
# 2. the component: does it activate?
./run_ue.sh p44_verify_after_manual_pass.py --render
```

**Graph gate** — `exports/p50_topology.txt`. The bottom of that report prints a
line per subject against a live control:

```
  stock/Fountain    total modules across all stacks: 0
  stock/RadialBurst total modules across all stacks: 27
  stock/Explosion   total modules across all stacks: 28
  ours/EdgeTrail    total modules across all stacks: 0     ← must stop being 0
```

Repair is progressing when `ours/EdgeTrail` rises off 0 while the stock arms stay
at 27/28. (Change the `ours` subject to whichever system you just finished.)

**Component gate** — `exports/p44_...`. `comp.is_active()` must read True after
`activate(True)` and stay True. That is the exact measurement that separated the
stock system from ours in `p48`.

**Pixel gate — read `VERIFICATION_STATUS.md` §3.4 first.** A scripted session
does not render Niagara into a `SceneCapture2D` even when the component is
active: `p48`'s three arms were byte-identical down to the last digit, including
the arm with an active stock system. So an unchanged frame from `p44` is **not**
evidence that the graph is still wrong. Judge pixels in the editor viewport, or
through Movie Render Queue.

---

## 6. Do not

- **Do not bulk-add modules with the toolset.** `AddModule` asserts
  `StackNodeGroups.Num() >= 2` and takes the editor down (§1).
- **Do not trust `EXACT_BUILD.md`'s "Links verified" column.** It is generated
  from `exports/p11_report.json`, and p11 reported `37 modules, 49 pins, 0
  unverified` for assets that contain neither. That column records what the build
  script believed it did.
- **Do not save without re-reading the topology.** The whole failure being
  repaired is a gap between what a tool said it did and what the asset contains.
- **Do not conclude from one frame.** p33 lost a run to a single early frame
  read as "produced nothing" when it meant "produced nothing yet"; p47 lost a
  verdict to a 6.1 s run against a 6.7 s compile.

---

## 7. Order of work

Following §38 of the brief's own priorities, which put the physical A3 partial
sheathe and the Iaido recovery ahead of the cosmetic systems:

1. `NS_SW_Core_SpatialScar` — A3 is the hero (§12, §19, §20)
2. `NS_SW_Core_EdgeTrail` — A1/A4, and the ribbon is the whole Normal identity
3. `NS_SW_Core_MajorArc` — A4, and the only system that also needs a new emitter
4. `NS_SW_Core_Wave` — A2
5. `NS_SW_Core_Glint`, `NS_SW_Core_PurpleMotes` — equip / inspect / idle
6. `NS_SW_Core_Hit` — contact families
7. `NS_SW_Core_MistWake` — the Magic differentiator, and the one with the
   overdraw risk, so it wants the eyes of someone who has already seen the four
   attacks read correctly
