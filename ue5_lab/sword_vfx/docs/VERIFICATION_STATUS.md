# Verification Status — Sword Presentation V3 + Magic Sword VFX V1

> Evidence document. Every claim below names the run that measured it, or says
> it is not measured.
> Companion documents: `EXACT_BUILD.md` (the graph build sheets),
> `SWORD_VISUAL_PROFILE.md` (the profile spec), `EVENT_INTEGRATION.md` (the
> event contract), `SWORD_VFX_EVENT_CONTRACT.md` (the contract in full),
> `NIAGARA_REPAIR_SHEET.md` (what a human must do next, per system).

**Rewritten after `p45`–`p51`.** The verdict in §1 changed, `ASSET READY` was
qualified down, and §3's blocker is now a named defect rather than "an
outstanding compile". §5 records two mistakes of mine, one of which is a
correction to a correction.

---

## 1. Status in the strict vocabulary

| Term | Status | Basis |
|---|---|---|
| `SPEC READY` | **YES** | Event contract (§3), visual profile (§4–§22), 24 `MANUAL EDITOR STEP` markers in `EXACT_BUILD.md` |
| `ASSET READY` | **PARTLY — see the correction** | Materials (6 masters + 12 instances), textures (7), meshes (4), the review map, and 9 blueprint wrappers are real files. **The nine Niagara core systems are NOT built: every one of their 11 emitters has zero modules in all four script stacks** (§3.1, measured in `p49`/`p50`). They are shells with correct names, correct emitters and correct renderers, and no graph. |
| `IMPLEMENTED` | **NO** | Nothing here has ever run. `p48` measured the direct comparison: a stock engine system activates and stays active in this session, `NS_SW_Core_EdgeTrail` never activates at all. |
| `VISUALLY VERIFIED` | **NO** | Never rendered. `p48` puts a number on why a healthy system would not have shown up either (§3.4). |
| `GAMEPLAY VERIFIED` | **NO** | Only the user can award this. |

**Do not upgrade `ASSET READY` to `IMPLEMENTED` on the strength of file counts.
A file that exists has never executed — and here, nine of them are not even the
thing their filenames claim.**

---

## 2. What exists

```
Content/SEKAI/VFX/Sword/
  Systems/  NS_SW_Core_{EdgeTrail,Glint,AirSlice,Wave,SpatialScar,
                        MajorArc,MistWake,PurpleMotes,Hit}      9  (§23)  ← EMPTY SHELLS
  Materials/ M_SW_{Trail,Glint,Wave,SpatialScar,Mist,Mote}       6  (§25)
             MI_SW_*_{Normal,Magic}                             12
  Textures/  T_SW_{EdgeMask,ScarMask,WaveMask,DistortionNormal,
                   MistMask,Streak,Mote}                         7  (§26)
  Meshes/    SM_SW_{ArcSheet,GlintQuad,ScarStrip,WaveSheet}      4  (§27)
  BP/        B_SW_Core_*                                         9  (§3/§4 host)
  Lab/       L_SwordVFX_Lab  (review map, §30)
```

The nine systems' shells were read back from the engine in `p49` (names,
emitters, renderers are real and correct):

| System | Emitters | Renderer | Sim |
|---|---|---|---|
| EdgeTrail | `E_Trail` | Ribbon | CPUSim |
| Glint | `E_Glint` | Sprite + Light | CPUSim |
| AirSlice | `E_Slice` | Mesh | CPUSim |
| Wave | `E_Wave`, `E_MistWake` | Mesh, Mesh | CPUSim |
| SpatialScar | `E_Scar`, `E_ScarMist` | Mesh, Mesh | CPUSim |
| MajorArc | `E_Arc` | Mesh | CPUSim |
| MistWake | `E_Wisp` | Mesh | CPUSim |
| PurpleMotes | `E_Motes` | Sprite | CPUSim |
| Hit | `E_Hit` | Sprite | CPUSim |

All nine carry the unified User Parameter set (§24) including `User.ArcAngle`
default **300** — i.e. the A4 arc is specified as a partial arc and not a 360°
ring, which is §12 and §21. That part is correct.

**The names are right. The graphs behind them are absent.**

---

## 3. The blocker, with its evidence

### 3.1 The nine systems have no modules (measured against a control)

`p49` asked `GetEmitterTopology` — a tool whose own description says it does
**not** wait on a compile, unlike `GetStackIssues` / `GetSystemCompileState`
which say "等待任何正在进行的编译完成". It answered for all **11** emitters:

```
EdgeTrail / E_Trail
  Emitter Spawn     0 modules: (none)
  Emitter Update    0 modules: (none)
  Particle Spawn    0 modules: (none)
  Particle Update   0 modules: (none)
```

`p50` then ran the same call, in the same session, on stock engine systems, to
prove the reader can see modules at all:

| Subject | Total modules across all four stacks |
|---|---|
| `stock/RadialBurst` | **27** |
| `stock/Explosion` | **28** |
| `stock/Fountain` (FountainLightweight) | 0 |
| `ours/EdgeTrail` | **0** |

and dumped the raw shape rather than only the count, which is what makes it
unarguable — same call, same key, same shape:

```
ours/EdgeTrail  particleSpawnScript
    { "scriptName": "ParticleSpawnScript", "modules": [] }

stock/RadialBurst / RibbonTrailFollower  particleSpawnScript
    { "scriptName": "ParticleSpawnScript",
      "modules": [ { "moduleName": "InitializeParticle", ... "inputs": [ ... 66 ] } ] }
```

This is the defect the engine log had been naming all along:

```
LogNiagara: Warning: [AssetLog] ...NS_SW_Core_<any>.uasset:
    无法找到通向类型为4的输出节点的任何连接！
    无法找到通向类型为5的输出节点的任何连接！
    ("could not find any connection to the output node of type 4 / of type 5")
```

Types 4 and 5 in `ENiagaraScriptUsage` are `ParticleSpawnScriptInterpolated`
and `ParticleUpdateScript`. Nothing is connected to those output nodes because
there are no modules to connect. Emitters **Wave** and **SpatialScar** carry
one more line:

```
LogNiagara: Warning: [AssetLog] ...: 未在已调用图表上找到输入节点 - Node: 发射器Minimal 更新
("could not find the input node on the called graph - Node: Emitter Minimal Update")
```

### 3.2 `AddModule` cannot fix them — it asserts and takes the editor down

`p51` called `AddModule` once on `E_Trail`'s empty `ParticleSpawnScript` stack,
with a module asset that exists, and the editor died:

```
Assertion failed: StackNodeGroups.Num() >= 2
[File:D:\build\++UE5\Sync\Engine\Plugins\FX\Niagara\Source\NiagaraEditor\
 Private\ViewModels\...]

Callstack: UnrealEditor-ToolsetRegistry.dll → CoreUObject.dll →
           PythonScriptPlugin.dll → python311.dll → Slate.dll →
           UnrealEditor-Cmd.exe
```

The baseline read immediately before it was `total=0` on all four stacks, and
the five module assets it was about to use all reported `exists=True`. So the
module phase cannot be scripted on an empty stack in this build: the editor
asserts before a module can be placed.

**This is §0 of the brief, measured.** The brief said a Niagara graph cannot be
reliably built or authorised by script and required the fallback to a
`MANUAL EDITOR STEP`; that is now a fact with a callstack rather than a policy.

### 3.3 The one measurement that separates the assets from the environment

`p46`, `p47` and `p48` progressively cleared the session, the world type and the
code path. `p48` is the one that stands, because it gave every arm the same
treatment and enough time:

- 90-tick warm-up (~30 s) after the assets are assigned, against a compile
  measured at **6.7 s** (`Compiling System ... took 6.7341 s`, ×9 in the log)
- both subjects at the same location, only one visible at a time
- all three frames from the same camera pose
- `activate(True)`, then reads at +30 and +60 ticks

| Arm | after `activate(True)` | +30 ticks | +60 ticks |
|---|---|---|---|
| stock `/Niagara/DefaultAssets/Templates/Systems/FountainLightweight` | **True** | **True** | **True** |
| ours `NS_SW_Core_EdgeTrail` | False | False | False |

A stock, never-edited engine system activates and **stays** active through the
same code path in the same session. Ours never activates. So this is not the
session — it is the assets, which §3.1 then explains.

p47 is **not** evidence, and it is recorded here because it was the run that
appeared to prove the opposite:

| Run | What it actually established |
|---|---|
| `p11` | Read its own nine systems back: 8 of 9 `compiling=True`. It also reported `links confirmed 37 modules, 49 pins, unverified pins 0`. **§3.1 shows the disk has 0 modules and 0 pins**, so that report describes something other than what was saved. `EXACT_BUILD.md` is generated from `p11_report.json` and inherits this — see §5. |
| `p32` | All nine `GetSystemCompileState` calls time out at 40 s each (361.8 s, 42765 ticks), then the engine access-violates on quit. |
| `p33` | 18 frames, nine `_before`/`_after` pairs **byte-identical** (`0 / 921600` px, max channel delta 0), with `activate(reset=True)` reported successful and 0 tick errors. |
| `p36` | The same capture **does** render geometry: two quads changed 85320 px (9.258% of frame, delta 121). The capture, the level and the rasterizer all work. |
| `p37` | Forcing `User.Lifetime` to 5.0 s changed nothing: five timed frames, spread `0.00`. Timing was never the explanation. |
| `p38`/`p39` | `comp.is_active()` False, `tick` False, while the `SceneCapture` component in the same world reported its own tick enabled. Every lever to switch ticking on was refused, including `b_tick_in_editor` (not exposed), `start_with_tick_enabled` (reverts), `set_component_tick_enabled(True)` (reverts), `set_tickable_when_paused` (does not exist), and `spawn_system_at_location` (also inactive). |
| `p40`/`p41` | **Void on the game world.** Both enumerated with `EditorLevelLibrary.get_all_level_actors()`, an editor-only call that ignores its world argument, so their "game world" rows were the editor world's actors. |
| `p42` | Ten cumulative lever configurations produced a frame **byte-identical to twelve decimal places** (`luma=102.21387833723654`). The levers that should stick did stick. |
| `p45` | First correct world enumeration. Found `SceneCapture2D` is absent in a fresh editor world (p40 *spawned* one and never saved), and — the trap that cost it a run — a module-level `raise SystemExit(0)` left the editor alive for the full 300 s timeout, because the runner passes only `-ExecCmds="py <script>"` and the script owns the exit. |
| `p46` | PIE entered correctly (`UEDPIE_0_L_SwordVFX_Lab`), the capture **was** duplicated into the game world, 9 of 9 rows provably PIE — and `activate(True)` on all nine gave `before=0 after=0`, with `_p46_game` byte-identical to `_p46_editor`. World type cleared. |
| `p47` | Ran the right experiment too early: **6.1 s total** against a 6.7 s compile, and it moved the camera between arms. Its "stock does not come up either" verdict is a timing artifact and is retracted. |
| `p48` | The control, with the warm-up. Table above. |
| `p49` | All 11 emitters: 0 modules in all four script stacks. |
| `p50` | The reader proven on stock: 27 and 28 modules. Ours: 0. |
| `p51` | `AddModule` asserts `StackNodeGroups.Num() >= 2` and terminates the editor. |

`GetStackIssues` and `GetSystemCompileState` **never answered for any system,
healthy or not** (p50 asked all four subjects, stock included: `unanswered
within 25 s`). They are not usable instruments in this session type, and that
also settles p32 and p43 — the timeouts were not about the nine assets.

### 3.4 The second blocker: a scripted session does not render Niagara

`p48`'s three arms were all `luma=102.21387833723654` — byte-identical, including
the arm where the stock system was **active**. Active is not the same as
drawing, and this session type does not draw Niagara into a `SceneCapture2D`.
`p38`/`p39` located why: the component's tick is never enabled in an editor
session, so nothing simulates.

So there are two independent blockers, and fixing §3.1 alone would not produce a
frame:

| # | Blocker | Consequence |
|---|---|---|
| 1 | The nine cores are empty shells | Must be built — in the editor, because `AddModule` crashes a script (§3.2) |
| 2 | A scripted editor session neither ticks nor renders Niagara | Frames must come from a real editor session, or from Movie Render Queue |

---

## 4. The remaining critical path

The whole path is one human pass, and it is now **specific** rather than
generic. Per system, in the **Niagara editor**:

1. Open `NS_SW_Core_<Name>`.
2. Build the four script stacks against `docs/EXACT_BUILD.md` — the emitters are
   there and empty; nothing needs to be created, only filled.
3. Work around `StackNodeGroups.Num() >= 2`: the assert fires when a module is
   added to a stack that has no module group. Add the **first** module by hand
   in the stack (drag it in, or use the `+` in the stack menu) rather than
   through any bulk tool; after the first group exists the stack is normal.
4. Save the package. Compiling without saving leaves the asset exactly as it was
   — the step neither p11 nor p43 could do from a script.

Then, in the **viewport**, verify — `p44_verify_after_manual_pass.py` asks the
two questions that decide the batch:

- do the nine systems now report `compiling=False`?
- do the nine components now activate, and does a frame change?

```
cd sword_vfx/scripts
./run_ue.sh p44_verify_after_manual_pass.py --render
python ../tools/frame_pairs.py ../render/pass01_check
```

It takes two frames per core because one frame cannot separate "dead" from
"nothing yet" — a distinction that cost `p33` a run. Read §3.4 before trusting a
negative frame: use `p44` for the **component state**, and a real viewport for
the pixels.

---

## 5. Corrections, including two of mine

**A self-correction that was itself wrong.** Earlier in this session I wrote that
the "no connection to the output node" messages did not exist anywhere in the
logs and called the "unwired stacks" claim void. I had grepped the **English**
string against a log this engine writes in **Chinese**. The messages were there
the whole time:

```
LogNiagara: Warning: [AssetLog] ...: 无法找到通向类型为4的输出节点的任何连接！
```

and they are, per §3.1, correct. `grep` for a literal English phrase against a
localized log produces a criterion that looks hard and has no source — the same
shape of error as quoting a log transcribed into a comment, which is the other
mistake recorded below. **Search localized logs for the concept, not the
string.**

**Two claims of mine that were wrong, kept because they were both instructive:**
- "the nine systems are structurally broken / the stacks are unwired" — I then
  *refuted* this on bad grounds (§5 above), and §3.1 now shows the conclusion
  was right and the refutation was wrong. The wording that was wrong was
  "structurally broken": they are not broken, they are **empty**.
- "an instance exists but nothing draws" (p42's first verdict) — the
  `get_all_emitters()` probe returns
  `<NiagaraFunctionLibrary: Failed to convert parameter>`, so it is **void**. The
  verdict read that error string as evidence of a live instance because the
  string does not start with `"0 "`. **A probe that cannot tell "empty" from
  "failed" must say "void", not "zero".**

**`EXACT_BUILD.md` is not independent evidence.** It is generated by
`tools/gen_build_sheets.py` from `exports/p11_report.json`, and its
"Links verified" column therefore inherits p11's self-report — the same report
§3.1 shows does not describe the disk. Read that column as "what the build
script believed it did", and `NIAGARA_REPAIR_SHEET.md` as what is actually
there.

---

## 6. Reusable findings from this batch

These cost engine runs; they are recorded so they do not cost more.

- **The engine log's timestamps are UTC; file mtimes are local (+8).** This
  nearly cost the whole diagnosis: the `AssetLog` warnings that identify the
  defect are stamped `09:54:49` and were read as "an early-morning session",
  when `09:54:49 UTC` is `17:54:49 local` — i.e. during the failing run. Compare
  a log line's time to a file's mtime before dating it.
- **An early exit never quits the editor.** `run_ue.sh` passes exactly
  `-ExecCmds="py <script>"`, with no trailing `quit_editor`. The script owns the
  exit, so a module-level `raise SystemExit(0)` ends the file and leaves the
  editor alive until the runner's timeout kills it, with nothing in the log to
  say so. `p45` burned 300 s on this. Every exit must go through the tick
  callback's finish path.
- **`GetEmitterTopology` reads stacks without waiting on a compile;**
  `GetStackIssues` and `GetSystemCompileState` wait forever. One description
  says "所有字段始终填充", the others say "等待任何正在进行的编译完成". Read the
  tool description before spending a session on the tool.
- **A stock engine asset is the control for any "our asset is broken" claim**,
  and it needs the same time budget: p47's negative was taken at 6.1 s against a
  6.7 s compile. An A/B is only an instrument if both arms got to run.
- **Both worlds report the same `get_world_delta_seconds`** (0.333 s ≈ 3 fps in
  that session), so it is not a test of "is this world advancing".
- **`get_all_actors_of_class(world_context_object, actor_class) -> Array[Actor]`**
  is the only world-aware actor enumeration, and `EditorLevelLibrary.
  get_all_level_actors()` silently ignores the world you pass it.
- **The editor world and the PIE world share `get_name()`** — both are
  `L_SwordVFX_Lab`. Use `get_path_name()` (`UEDPIE_0_` prefix) as the identity
  test, or a comparison of the two worlds compares a world with itself.
- **PIE does duplicate a runtime-spawned `SceneCapture2D`** into the game world
  (p46 measured it), so a capture built in the editor world is a usable camera
  for a PIE frame.
- **Toolset names are per-toolset.** `ConstructNiagaraBPWrapperFromSystem` lives
  in `NiagaraToolset_Blueprint`, not `NiagaraToolset_System`; asking the wrong
  desk returns `Unknown tool`, which reads as "this build cannot do it".
  `swvfx.call/call_quiet/call_async` now take an explicit `toolset`.
- **The watchdog grace was in ticks while every real deadline was in seconds.**
  `install_watchdog(4000)` at ~71 ticks/s is 56 s, so it killed a poll that was
  allowed 200 s, and the message ("the script body never reached its finish
  path") reads as a hung script. `install_watchdog` now takes `grace_seconds`.
  Tick rate is not constant: measured ~2.9/s in `--render` with a level, ~9/s
  without.
- **`GameplayStatics` has no actor spawn in this build** (170 members, none of
  them a spawn-actor); `KismetSystemLibrary` is not present at all.
  `EditorActorSubsystem.spawn_actor_from_class` and
  `EditorLevelLibrary.spawn_actor_from_class` are editor-world only.
  `get_all_level_actors()` returns every actor **twice** — dedupe by path name,
  not by label.
- **`unreal.*` enum names are not the C++ names.** The age-update enum is
  `NiagaraAgeUpdateMode`, not `ENiagaraAgeUpdateMode` /
  `NiagaraComponentAgeUpdateMode`; guessing cost the whole `DESIRED_AGE` lever in
  p42's first sweep. `dir(unreal)` answers this in seconds.
- **`seek_to_desired_age()` takes an argument** — `required argument
  'desired_age' (pos 1) not found`.
- **`.uasset` files are compressed**, so a `strings` grep finds no object names.
  Content must be verified through the engine, not the bytes.
- **`swimg.collect()` prefers an existing `<name>.png`**, so a loop re-exporting
  one name returns the previous image. Every A/B frame needs a distinct name.
