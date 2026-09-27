# SEKAI 战斗音效 · Suno 生成执行表

音频线（B）所有物。状态：**尚未生成 / 尚未试听 / 未 approved**。
本表只做生产准备，任何 cue 在 Godot 战斗场景正常音量下实机听过之前，不得称为 approved。

## 生成方式（Suno V6）

1. `suno.com` → **Create** → **Sounds** 模式（2026-01 上线，做 one-shot 与 loop，不是完整歌曲）。
2. 模型：`v6`（精确优先）。要意外质感时才用 `v6-wild`，探索用 `v6-mini`。
3. 每条 prompt 用四段结构：**声源 + 声学环境 + 时长/动态 + 参考形容词**。
4. 每条至少两版（A / B），页面播放器逐条试听后再下载。
5. 下载原文件放 `audio_source/suno/raw/`，**不要**直接放进 `godot/audio/sfx/`。
6. 淘汰版本放 `audio_source/suno/rejected/`，不留在游戏目录。
7. 进入 Godot 的成品：单声道或立体声 44.1 kHz，峰值不削顶，去除首尾静音，长度贴合下表 Target。

## 硬性风格约束

- 无音乐、无人声、无环境床、无 trailer 式鼓点。
- 干声（dry）优先，混响只在该 cue 明确要求空间感时少量保留。
- 短、干净、保留瞬态；玩家操作反馈优先于"好听"。
- 感知响度对标已接入的战斗 BGM `first-encounter.mp3`，不要压过音乐。

## 批次 1 · 剑与防御（Priority A）

| Cue ID | Suno prompt（原样粘贴） | Target | 触发 | 替换对象 |
| --- | --- | --- | --- | --- |
| `sword_light_01` | `A single narrow steel blade cutting through air, one fast pass, faint cloth sleeve movement at the end, recorded dry in a small neutral room, extremely short 0.18 second one-shot with instant attack and fast decay, clean game sound design, no music, no reverb tail, no whoosh trail.` | 0.18 s | 轻击一段起手 | new |
| `sword_light_02` | `A single steel sword whoosh passing in the reverse direction with a subtle leather grip shift, dry close recording in a neutral room, 0.22 second one-shot, sharp transient then quick decay, utilitarian game combat foley, no music, no ambience.` | 0.22 s | 轻击二段起手 | new |
| `sword_light_03` | `A short forward thrust air snap from a blade followed by one firm boot step on packed earth, dry in a small outdoor space, 0.28 second one-shot, crisp attack with a tight body thud at the end, gameplay foley, no music, no crowd.` | 0.28 s | 轻击三段踏步 | new |
| `sword_heavy` | `A heavy weighted blade swing with low body effort and a slight leather creak, dry close recording, 0.38 second one-shot, slower attack than a light swing and a thicker low-mid body, gritty game combat sound design, no music, no cinematic boom.` | 0.38 s | 重击起手 | new |
| `guard` | `A compact steel-on-steel contact with a muted body impact behind it, recorded dry in a small room, 0.20 second one-shot, hard short transient and very short decay, functional combat foley, no metallic ringing tail, no music.` | 0.20 s | 普通格挡 | new |
| `perfect_guard` | `A bright metallic parry transient with a solid body impact, a very short low punch underneath and a tiny spark sizzle tail, dry studio recording, 0.35 second one-shot, immediate attack then controlled decay, stylized anime game combat sound design, no music, no long reverb.` | 0.35 s | 完美格挡窗口 | new |

## 批次 2 · 聚合斩签名技（Priority C，替换现有合成占位）

现有 `godot/audio/sfx/iaido_*.wav` 是 `godot/tools/generate_iaido_placeholders.py` 合成的占位件，节奏对、质感假。Suno 版只换文件，**不改 `iaido_audio_timeline.gd` 的触发时间点**。

### 时间预算（`IaidoTuning.tres` 实测，restore_end = 7.20 s 硬截断）

| Cue | 触发点 | 下一个事件 | 允许长度 | 现占位 | 结论 |
| --- | --- | --- | ---: | ---: | --- |
| `air_suck` | 0.20 | sheath_move 0.80 | ≤ 0.60 | 0.90 | 超长，压住拔刀准备 |
| `sheath_move` | 0.80 | reverse_wave 1.20 | ≤ 0.40 | 0.75 | 超长 |
| `reverse_wave` | 1.20 | pressure 2.20 | ≤ 1.00 | 1.15 | 超长 |
| `pressure` | 2.20 | lock_click 2.85 | ≤ 0.65 | 1.05 | 超长，会盖住锁扣与拔刀 |
| `lock_click` | 2.85 | draw 2.97 | ≤ 0.12 | 0.14 | 略长 |
| `draw` | 2.97 | world_cut 3.10 | ≤ 0.28（尾音可压在斩击下） | 0.24 | 可用 |
| `world_cut` | 3.10 | void_open 3.40 | ≤ 0.30 | 0.60 | 超长 |
| `void_open` | 3.40 | glass_stress 4.25 | ≤ 0.85 | 1.60 | **超长一倍，压住整段玻璃** |
| `glass_stress` | 4.25 | shard_burst 4.58 | ≤ 0.50（尾音可压在破裂下） | 0.65 | 略长 |
| `glass_break` | 4.58 | slow_sheathe 5.50 | ≤ 0.92 | 1.25 | 超长 |
| `spin` | 4.60 | slow_sheathe 5.50 | ≤ 0.90 | 1.00 | 略长 |
| `slow_sheathe` | 5.50 | final_click 6.20 | ≤ 0.70 | 0.90 | 超长 |
| `final_click` | 6.20 | collapse 6.25 | ≤ 0.25 | 0.30 | 略长 |
| `collapse` | 6.25 | restore_end 7.20 | ≤ 0.95 | 1.25 | **溢出总时长，会被硬截断** |
| `reality_restore` | 6.80 | restore_end 7.20 | ≤ 0.40 | 1.05 | **溢出，收尾被切** |

### 生成清单

| Cue ID | Suno prompt（原样粘贴） | Target | 替换占位 |
| --- | --- | --- | --- |
| `iaido_draw` | `A sword drawn from a lacquered wooden scabbard in one fast motion, tight sheath friction with a restrained human breath, recorded dry and very close, 0.28 second one-shot, immediate friction rise then a small release, intimate Japanese sword foley, no music, no room tail.` | 0.28 s | `iaido_draw.wav` |
| `iaido_world_cut` | `An extremely fast single blade cut that seems to slice the space itself, one thin tearing edge layered over the steel, dry hyper-close recording, 0.25 second one-shot, instant attack and very short decay, reality-cut anime sound design, no music, no explosion.` | 0.25 s | `iaido_world_cut.wav` |
| `iaido_void_open` | `A brief silence that opens into a widening brittle crack followed by a deep low impact, dry dark recording, 0.55 second one-shot, delayed onset then sudden widening and a heavy low body at the end, dimensional rupture sound design, no music, no drums.` | 0.55 s | `iaido_void_open.wav` |
| `iaido_final_click` | `One distinct hard scabbard click as a sword is fully seated, dry close recording with a very short room tail, 0.22 second one-shot, sharp wooden and steel click then quick natural decay, precise Japanese sword foley, no music.` | 0.22 s | `iaido_final_click.wav` |
| `iaido_reality_restore` | `Reality snapping back into place after a cut, air rushing back in with glass-like fragments settling, dry recording with a fast natural decay, 0.40 second one-shot, quick reversed intake then a settling body, subtle anime space restoration sound design, no music, no riser.` | 0.40 s | `iaido_reality_restore.wav` |
| `iaido_pressure` | `Deep sub pressure building under a held sword stance, a low non-musical rumble with air being compressed, dry dark recording, 0.65 second one-shot, fast swell with no pitch movement, tension sound design, no music, no drums, no impact.` | 0.65 s | `iaido_pressure.wav` |
| `iaido_glass_stress` | `Thin glass under stress before breaking, microscopic creaks and high ticks rising in density, extremely dry close recording, 0.50 second one-shot, quiet start and rising tension with no break yet, sound design texture, no music.` | 0.50 s | `iaido_glass_stress.wav` |
| `iaido_glass_break` | `A sheet of thin glass bursting into many sharp shards, bright brittle transient then short scattered debris, dry close recording, 0.70 second one-shot, instant attack and quick granular decay, no music, no low boom.` | 0.70 s | `iaido_glass_break.wav`（同时供 collapse，pitch 0.78） |
| `iaido_reverse_wave` | `A reversed air waveform being pulled inward, a short inhale-like sweep that rises in pitch then stops abruptly, dry recording, 0.60 second one-shot, smooth build then hard stop, abstract anime space sound design, no music, no drums.` | 0.60 s | `iaido_reverse_wave.wav` |
| `iaido_slow_sheathe` | `A sword sliding slowly back into a scabbard, controlled friction with faint cloth, dry close recording, 0.70 second one-shot, steady movement with no click at the end, restrained Japanese sword foley, no music.` | 0.70 s | `iaido_slow_sheathe.wav` |
| `iaido_spin` | `A single sword spun once through the air after a strike, controlled mid-speed blade whoosh with a faint metal shimmer, dry recording, 0.45 second one-shot, smooth attack and decay, gameplay weapon foley, no music.` | 0.45 s | `iaido_spin.wav` |
| `iaido_air_suck` | `All air being pulled out of a space in one instant, a very short inward vacuum gasp, hyper-dry recording, 0.25 second one-shot, instant attack and abrupt end, negative-space sound design, no music.` | 0.25 s | `iaido_air_suck.wav` |
| `iaido_lock_click` | `A small mechanical lock engaging, one precise metallic click with a tiny spring, dry close recording, 0.12 second one-shot, extremely short, UI-grade precision foley, no music, no tail.` | 0.12 s | `iaido_lock_click.wav` |
| `iaido_sheath_move` | `A scabbard shifting slightly at the hip, soft leather and wood movement with cloth, dry close recording, 0.30 second one-shot, quiet body and quick decay, Japanese sword foley, no music.` | 0.30 s | `iaido_sheath_move.wav` |

## 批次 3 · 元素与连携（Priority B）

| Cue ID | Suno prompt（原样粘贴） | Target | 触发 |
| --- | --- | --- | --- |
| `fire_cast` | `Embers being inhaled then igniting into a small flame, a breathy intake followed by one ignition snap, dry close recording, 0.45 second one-shot, soft start then a crisp mid transient, fantasy spell sound design, no music.` | 0.45 s | 火成形/释放 |
| `fire_impact` | `A focused flame burst hitting a surface with a small scorched stone crackle behind it, dry recording, 0.45 second one-shot, fast attack then a short crackling decay, elemental impact foley, no music, no explosion boom.` | 0.45 s | 火命中 |
| `frost_loop` | `A seamless loop of close granular ice hiss with a cold airy sustain, steady intensity with no events, dry frozen texture, 1.50 second perfectly loopable texture, fantasy ice magic ambience, no music, no rhythm.` | 1.50 s loop | 冰霜持续 |
| `freeze` | `Tiny crystal ticks tightening into a short hard lock, several small ice fractures converging then one solid frozen hit, dry close recording, 0.50 second one-shot, rising density then a hard stop, freeze status sound design, no music.` | 0.50 s | 冻结阈值 |
| `wind_burst` | `A broad displacement of air pushing outward with dust and dry leaves moving and a low pressure push underneath, dry outdoor recording, 0.55 second one-shot, wide attack then a natural scatter, elemental wind foley, no music.` | 0.55 s | 风释放/推力 |
| `shatter` | `A high ice crack combined with stone breaking, a low punch underneath and a short magic shimmer tail, dry close recording, 0.70 second one-shot, instant brittle attack then layered decay, frozen shatter sound design, no music.` | 0.70 s | 冻结→重击碎裂 |

## 后处理（下载后统一做）

1. `audio_source/suno/raw/` 保留原始下载，文件名 `cueid_variant_model.wav|mp3`。
2. 裁掉首尾静音，截到 Target 长度（用 ffmpeg，本机 `/d/oopz/ffmpeg.exe`）。
3. 峰值归一到 -1 dBFS 以下，感知响度对齐 `first-encounter.mp3`。
4. 输出 `godot/audio/sfx/<cue_id>.wav`，Godot 自动导入；如需循环（只有 `frost_loop`）在 `.import` 里开 loop。
5. 淘汰版本立刻移到 `audio_source/suno/rejected/`。

## 记录模板（每入库一条填一行）

cue ID · 来源/工具 · 模型 · 完整 prompt · 生成/下载日期 · 文件 hash · 峰值/响度 · 触发点 · 试听结论。
未实机试听 = 未 approved。
