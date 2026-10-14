# SEKAI Combat Audio Language

> 这一份定义 SEKAI 的**声音语言**：12 个 core atoms 是什么、怎么叠成 cue、哪些还不能做。
> 目标：玩家听出的是「空气 + 身体 + 武器 + 材质 + 空间」共同组成一个动作，
> 而不是「这一招有一个 WAV」。
>
> 新流派 / 新技能 / 新魔法：先尝试**重组现有 atoms**。只有现实中不存在的东西
> （聚合斩、无明一刻这类 Signature）才大量依赖 Suno。

对应代码：`godot/scripts/audio/`（registry / layered sfx / cues / director）
对应素材：`godot/audio/sfx/core/`
测试：`godot/tests/combat_audio_language.gd`

---

## 0. 为什么有这一层

之前的状态是「一招一个 WAV」：加一招就多一个文件，声音之间没有共同的物质。
现在的规则是：

```text
ATOM（素材） → LAYER（相对音量/延迟/音高） → CUE（一个事件） → CUE TABLE（一种风格）
```

gameplay 脚本**永远不** `load("res://audio/...")`。它只说「打出了 L2」或者
「完美格挡了」，由 `CombatAudioDirector` 去查 cue 表。

---

## 1. Core Atoms（12 条，角色已定稿）

角色按**实际听感**定，不按最初文件名定。名字错了就改名字（`rename_atoms.py`）。

| 文件 | 角色 | 类别 | 用途 | 不用于 |
| --- | --- | --- | --- | --- |
| `air_fast_01` | FAST AIR CUT A | air | 轻剑 / 快拔刀 / 闪避 / 短位移斩 | — |
| `air_fast_02` | FAST AIR CUT B | air | 与 A **交替**，不重复同一个 | — |
| `pressure_low_01` | PRESSURE SUB / LOW SWELL | pressure | 重击预备 / 聚合斩压缩 / 风力 / 大位移 / 现实压力 | 普通轻挥（它不是低频 whoosh） |
| `body_low_01` | IMPACT BODY LOW | body | 重击 / 防御 / 完美格挡 / 撞墙 / 碎裂 / 崩塌 | 每次攻击都加（否则全都 Boom） |
| `cloth_fast_01` | BODY / CLOTH MOTION | cloth | 轻击 / 重击蓄力 / 闪避 / 拔刀 / 收腕 | 主角（它不是让你听见衣服，是让人听见「人在挥剑」） |
| `metal_sharp_01` | METAL TRANSIENT A | metal | **完美格挡主层** / 轻金属接触 / 刀鞘合缝 / 精准对剑 | 纯空气挥剑 |
| `metal_sharp_02` | METAL TRANSIENT B | metal | 与 A 交替 | 同上 |
| `metal_body_01` | METAL CONTACT BODY | metal | 防御 / 兵器交缠 / 剑碰撞 / 重金属撞击 | 纯空气挥剑 |
| `glass_crack_01` | MAIN GLASS CRACK | glass | 现实受力 / 玻璃断裂 / 碎裂副层 | — |
| `glass_body_01` | FRACTURE BODY | glass | `glass_crack_01` 的下层支撑 | 当第二条主 crack 用（它更暗更钝） |
| `glass_low_tick_01` | LOW GLASS TICK（已降级） | glass | minor body transient | 承担高频玻璃细裂纹主 tick（不够脆） |
| `wind_pressure_01` | WIND FORCE BODY | wind | 风推 / 风爆 / 聚合斩空间压力 / 大力事件 | 剑的 whoosh（它不是挥剑声） |

### 分工要点

- `wind_pressure` 与 `pressure_low` **不是同一层**：前者是中低频「移动感」，后者是「深层压力」。
- `body_low` 通常是 **secondary layer**，不要每个攻击都加。
- `cloth_fast` 音量很低（相对主层 -8 ~ -16 dB），作用是让第一人称听起来像**人在挥剑**。

### 电平

所有 atom 由 registry 做**感知 trim**（`base_gain_db`），把各自的渲染峰值拉到
同一参考（-6 dBFS）。所以 cue 里的 `gain_db` 是**真实的相对值**，不是「这个
文件刚好有多响」。

**不要再全部 Normalize 到 0 dB。** 现有素材本身已有足够 headroom。

### 已整形（Tame Pass，2026-09-27）

`air_fast_01/02` 与 `cloth_fast_01` 经 `audio_source/tools/tame_atoms.py` 处理。
原因不是音量，是**素材形态**：

| | 修前 | 修后 |
| --- | --- | --- |
| air 时长 | 0.350 s | 0.240 s |
| tail/head（尾巴比头部） | **0.60**（几乎不衰减 → 连招叠成一堵墙） | **0.09** |
| 7 kHz 以上沙声 | -12.7 dB | **-23.5 dB** |
| 整体 RMS | -19.8 dBFS | -20.5 dBFS（**基本没变**） |

也就是说：**不是把它调小，是把沙声拿掉、把尾巴收掉**，响度几乎没动。
削掉的是 <150 Hz 的低频浑浊和 >5 kHz 的嘶声，保留 0.8–3.5 kHz 的「速度感」频段。
原件备份在 `audio_source/processed/pre_tame/`，可随时回滚。

---

## 2. 变化（Variation）

只有两种：

```text
random variant（A/B 交替，不是随机——连招里不会连着播同一个文件）
±2~5% pitch / ±1~2 dB volume
```

剑术需要**一致性**，不要夸张随机。registry 用 round-robin 游标保证 A/B 交替。

---

## 3. Cue 表（Universal Sword 第一版）

`godot/scripts/audio/combat_audio_cues.gd`。0 dB 层 = **身份层**（玩家第一个听到的东西）。

| cue | 主层（0 dB） | 支撑层 | 设计意图 |
| --- | --- | --- | --- |
| `light_1` | air_fast | cloth -12 | 快；身体只是被暗示 |
| `light_2` | air_fast（pitch 1.035） | cloth -12 | 同一把剑，略亮 |
| `light_3` | air_fast（pitch 0.94, -0.5） | cloth -13, body_low -18 | 连招在减速，只有第三刀配极轻的身体 |
| `heavy_swing` | air_fast (-1) | **pressure_low -6（延迟 0.05）**, cloth -10 | 重 = 因为有压力，不是因为更响 |
| `hit_light` | body_low | surface_*（P1，缺） | 命中才有 HIT LAYER |
| `hit_heavy` | body_low | pressure -12, surface_armor（P1，缺） | 重量先到，剑鸣其次 |
| `dodge` | air_fast (-3, pitch 1.06) | cloth -9 | **绝不加 body_low**，闪避要轻快 |
| `guard` | metal_body | metal_sharp -8 | 被挡住：钝，刃没有咬住 |
| `perfect_guard` | **metal_sharp** | metal_body -5.5, body_low -10 | 弹开：**锐利金属瞬态先到**，重量在下 |
| `wind_burst` | wind_pressure | air_fast -5, pressure_low -7（延迟 0.06） | 有推力的流动空气，不是挥剑 |

### 硬性差异（闭眼可辨）

- **挥空 ≠ 砍中**：挥空只有 air，命中才加 body/surface。
- **普通 Guard ≠ Perfect Guard**：主层不同（metal_body vs metal_sharp），
  层级关系也不同（完美格挡三层递减 ≥4 / ≥8 dB）。
- **Heavy 不是「全部调大」**：是 air + **延迟进入**的 pressure + cloth。
  pressure 从蓄力开始一直轰 = drone，必须在加速后半段才出现。

---

## 4. 调音规则（比数值更重要）

1. **太厚 → 删 Layer。** 不是把全部音量调小。
2. **太薄 → 加互补 Layer。** 不是去生成一个完全不同的「大音效」。
3. 三层不要一样响；主层必须第一个被感知到。
4. 延迟调度 `ignore_time_scale`，hitstop 不会把 40 ms 拖成 200 ms。

---

## 5. 风格怎么用同一套 Atoms

| 风格 | 做法 |
| --- | --- |
| 藏锋 | 干、短、锐，**动作之间留静默**；Stop / Burst |
| 回风 | 仍用 air_fast，但**允许 layer overlap**：上一刀 air tail 进下一刀 → Continuous Flow；少用 body_low |
| 白蔷 | 减少 air，增加 small sharp metal / precise cloth / thrust air；更短更细更准 |

三个流派**不建立三套资源**。风格差异来自 layering / timing / pitch / silence。

---

## 6. 聚合斩（Iaido）与 atoms 的关系

基础 atom **只用于让 Signature 和普通战斗属于同一个世界**：

```text
Draw:            signature draw + air_fast(subtle) + cloth_fast(subtle)
First Sheath Click: wood_sheath_tick(P1) + metal_sharp(极轻)
Reality Stress:  glass_high_tick(P0) + glass_crack(低)
Reality Collapse: signature collapse + glass_crack_01 + glass_body_01 + body_low
```

**Reality Glass 不要持续噼里啪啦。** 跟视觉同步：

```text
WORLD CUT → silence → small stress ticks → few cracks → FINAL CLICK → full collapse
```

尤其 **WORLD SPLIT Hero Frame 应该很安静**，不要一切开就满屏玻璃声。

---

## 7. 还缺的 Atoms（不要扩散，只补这几条）

registry 里以 `PENDING_GROUPS` 形式声明，cue 引用它们时标 `optional`，
所以 cue 在素材没到位时仍然可播。测试会断言「这份清单不为空」。

| 优先级 | group | 要求 |
| --- | --- | --- |
| P0 | `glass_high_tick` | very short / bright / dry / brittle / crystalline / 无混响 / 无乐音 |
| P0 | `glass_tinkle` | 小碎片落定，干，无乐音 |
| P1 | `air_heavy` | 比 air_fast 更厚，但**不是低频 boom** |
| P1 | `wood_sheath_tick` | 木 / 漆刀鞘 + 极小金属件，干、近讲瞬态 |

挖掘工具：`audio_source/tools/mine_atoms.py`（从已有 18 条 raw 捕获里用
频谱质心 + 衰减率扫瞬态，不消耗新生成配额）。候选落在
`audio_source/processed/candidates/`，**必须人工听过**才能入库。

---

## 8. Surface System（预留，未实现）

同一次挥剑保留 air layer；命中后按材质叠加。已预留 `surface_flesh` /
`surface_armor` optional 层，等素材到位即可接。不要用一个 `sword_hit.wav`
解决所有东西。

---

## 9. 代码位置与接线原则

| 文件 | 职责 |
| --- | --- |
| `scripts/audio/sound_atom.gd` | atom 资源定义（含感知 trim / pitch 范围 / variation group） |
| `scripts/audio/sound_atom_registry.gd` | 唯一知道 atom 是什么的地方；A/B 交替；pending 清单 |
| `scripts/audio/sfx_layer.gd` | 一层：group / 相对 dB / 延迟 / pitch / optional |
| `scripts/audio/sfx_cue.gd` | 一个 cue：层栈 + intent（写清楚玩家应先听到什么） |
| `scripts/audio/layered_sfx.gd` | 播放：voice pool（封顶 24，偷最旧）+ 延迟调度（忽略 time scale） |
| `scripts/audio/combat_audio_cues.gd` | cue 表（唯一调音位置） |
| `scripts/audio/combat_audio_director.gd` | 接线：只听 controller 的信号与公开状态 |

**接线原则：不改 combat_controller.gd。** director 全部挂在现有信号上：

```text
move_started        → 按 attack_kind / combo_index 选 light_1/2/3 / heavy_swing
hit_landed          → hit_light / hit_heavy（挥空与命中分离）
perfect_guard_landed→ perfect_guard
hurtbox.hit_received（deferred）→ state == BLOCK 时播 guard
state_changed       → DODGE 播 dodge
wind hitbox 上升沿  → wind_burst（风没有自己的信号，hitbox 变 live 就是事件）
```

---

## 10. 验收

- 技术：`godot --headless --path godot --script res://tests/combat_audio_language.gd`
  覆盖 atom 数、A/B 交替、轻击无 metal、heavy 有延迟 pressure、闪避无 body_low、
  完美格挡层级与「普通/完美格挡主层不同」、pending 清单非空。
- 主观：**必须实机玩 Universal Sword 至少 2 分钟，只听声音**。
  A 轻击够快？ / B L1L2L3 有变化但仍是同一把剑？ / C Heavy 更重但没变 Boom？ /
  D 闪避轻快？ / E 普通 Guard 与 Perfect Guard 明显不同？ / F 连打 30 秒会不会听觉疲劳？
