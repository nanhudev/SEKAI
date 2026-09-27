# AUDIO STATUS

状态值沿用 `PRODUCTION_BOARD.md`。未在游戏中以正常音量听过的 cue 一律不得称为 approved。

## 实测：Iaido 占位音（2026-09-27）

来源：`godot/tools/generate_iaido_placeholders.py` 合成，非 Suno，非授权素材。全部统一归一化到 peak 0.898。

| 文件 | 时长 s | peak | rms | 触发点 s | 时间轴 key |
| --- | ---: | ---: | ---: | ---: | --- |
| iaido_air_suck.wav | 0.900 | 0.898 | 0.237 | 0.20 | air_suck |
| iaido_sheath_move.wav | 0.750 | 0.898 | 0.189 | 0.80 | sheath_move |
| iaido_reverse_wave.wav | 1.150 | 0.898 | 0.179 | 1.20 | reverse_wave |
| iaido_pressure.wav | 1.050 | 0.898 | 0.282 | 2.20 | pressure |
| iaido_lock_click.wav | 0.140 | 0.898 | 0.061 | 2.85 | lock_click |
| iaido_draw.wav | 0.240 | 0.898 | 0.093 | 2.97 | draw |
| iaido_world_cut.wav | 0.600 | 0.898 | 0.126 | 3.10 | world_cut |
| iaido_void_open.wav | 1.600 | 0.898 | 0.304 | 3.40 | void_open |
| iaido_glass_stress.wav | 0.650 | 0.898 | 0.172 | 4.25 | glass_stress |
| iaido_glass_break.wav | 1.250 | 0.898 | 0.147 | 4.58 | glass_break |
| iaido_spin.wav | 1.000 | 0.898 | 0.196 | 4.60 | spin |
| iaido_slow_sheathe.wav | 0.900 | 0.898 | 0.179 | 5.50 | slow_sheathe |
| iaido_final_click.wav | 0.300 | 0.898 | 0.080 | 6.20 | final_click |
| iaido_glass_break.wav | 1.250 | 0.898 | 0.147 | 6.25 | collapse（复用，pitch 0.78） |
| iaido_reality_restore.wav | 1.050 | 0.898 | 0.255 | 6.80 | reality_restore |
| dodge_temp.wav | 0.300 | 0.393 | 0.127 | — | 闪避占位 |

全部 44100 Hz 单声道 16-bit。时间轴 15 个 cue 与 `IaidoTuning.tres` 无断链。

## 已发现的问题

1. **全部是占位合成音。** peak 统一 0.898 说明脚本归一化，不是真实素材。Suno signature 一个都还没替换。
2. **collapse 溢出总时长。** 6.25 触发 + 1.25s = 7.50s，超过 `restore_end` 7.20s。`finish_iaido()` 会 `stop_all()` 硬截断，收尾会有突然静音。替换素材时 collapse 长度须压到 ≤0.95s，或把触发点提前。
3. **void_open 覆盖玻璃段。** 3.40 触发 1.60s 到 5.00s，压住 glass_stress(4.25) 与 shard_burst(4.58)。替换时需分层让位，或缩短到 ≤1.2s。
4. **rms 差异大。** pressure 0.282 / void_open 0.304 明显比 lock_click 0.061 响。虽然已配 volume_db，替换素材后需重新对齐响度。

## 待产

### Basic atoms（自组合）

metal · air · cloth · body · glass · ice · fire · wind · stone

### Signature SFX（Suno）

Iaido Reality Cut · Blue Void · Reality Collapse · Special Sheathe · Reality Restore

### 未落地的 gameplay cue

`COMBAT_SFX_BRIEF.md` Priority A（sword_light_01/02/03、sword_heavy、guard、perfect_guard）全部 TODO。
Priority B（fire/frost/wind/shatter）全部 TODO。

## 规则

- 每次导入候选必须记录：cue ID、来源工具、作者/模型、授权、生成 prompt 或 URL、下载日期、文件 hash、触发点、试听结论。见 `COMBAT_SFX_BRIEF.md` 模板。
- 淘汰候选不得留在 `godot/audio/` 下。
- 峰值不得削波；响度与 `first-encounter.mp3` 战斗音乐对比后确定。
- AUDIO 不改战斗 gameplay；需要改 Godot trigger 只做最小必要接入，大型逻辑交回 MAIN。
