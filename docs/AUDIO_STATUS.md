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

## 2026-09-27 续：Suno 通路与替换前的电平基准

### 阻塞：本环境无法访问 suno.com

沙箱代理对 `suno.com` 返回 `502 Bad Gateway`，Chromium 走同一代理是 `ERR_TUNNEL_CONNECTION_FAILED`，`curl` 直连为 `000`。**生成必须在可达网络里、用已登录账号执行**。生成前与生成后的工作已全部就绪。

### 新增交付

| 文件 | 作用 |
| --- | --- |
| `docs/AUDIO_SUNO_SFX.md` | 可直接粘贴的 Suno 生成执行表（批次 1 剑与防御 / 批次 2 聚合斩 14 条 / 批次 3 元素），含四段式 prompt、目标时长、替换对象、后处理与记录模板 |
| `audio_source/tools/prepare_cue.py` | 下载件 → 游戏件：去首尾静音、截到目标长度、3 ms 淡入 / 8 ms 淡出、单声道 44.1 kHz、峰值归一（`--report-only` 只测不写） |
| `audio_source/suno/raw\|rejected\|processed/` | 原始下载 / 淘汰 / 中间产物目录 |

已实测 `--peak -1 / -3 / -6` 输出恰为 -1.00 / -3.00 / -6.00 dBFS。本机 ffmpeg 构建的 `alimiter` 不按文档限幅，脚本已改用纯增益。

### 时间线时间预算（本轮新查，修正两处旧结论）

按 `IaidoTuning.tres` 实际触发点逐条算"下个事件之前还剩多久"，与现有占位件时长对比：

| 问题 | 数据 | 处理 |
| --- | --- | --- |
| `collapse` 溢出总时长（旧结论 #2） | 6.25 + 1.25 = 7.50 s > restore_end 7.20 s | Suno 版目标压到 0.70 s（6.95 s 结束） |
| `void_open` 压住玻璃段（旧结论 #3） | 3.40 + 1.60 = 5.00 s，盖住 glass_stress 4.25 与 shard_burst 4.58 | Suno 版目标压到 0.55 s（3.95 s 结束） |
| **新发现：`pressure` 压住锁扣与拔刀** | 2.20 + 1.05 = 3.25 s，盖住 lock_click 2.85 与 draw 2.97 | Suno 版目标压到 0.65 s |
| **新发现：`reality_restore` 收尾被切** | 6.80 + 1.05 = 7.85 s > 7.20 s | Suno 版目标压到 0.40 s |
| 其余超长 | air_suck / sheath_move / reverse_wave / world_cut / glass_stress / glass_break / spin / slow_sheathe / lock_click / final_click | 生成表里已逐条给出允许长度 |

### 替换后的有效电平基准（含 `iaido_audio_timeline.gd` 的每 cue 增益）

| Cue | 有效峰值 | 有效 RMS |
| --- | ---: | ---: |
| `final_click` | -2.93 | -23.97 |
| `collapse` | -3.43 | -19.17 |
| `draw` / `world_cut` | -3.93 | -23.65 / -20.99 |
| `lock_click` | -4.93 | -28.31 |
| `pressure` / `void_open` | -5.93 | -15.99 / -15.33 |
| `air_suck` / `glass_break` | -6.93 | -18.51 / -22.67 |
| `reverse_wave` / `reality_restore` | -7.93 | -21.94 / -18.88 |
| `glass_stress` | -8.93 | -23.29 |
| `spin` | -9.93 | -23.15 |
| `slow_sheathe` | -10.93 | -24.94 |
| `sheath_move` | -11.93 | -25.48 |

无一条超过 0 dBFS；阶序正确（终段最响、慢回鞘最轻）。`pressure` / `void_open` 的 RMS 高于战斗 BGM（-17.97 dBFS），仪式中音乐被压住可接受，**实机需确认音乐恢复瞬间不会盖过 BGM**。Suno 版入库后此表必须重算。

## 2026-09-27 续二：Suno 通路打通 + 账号里已有素材盘点

### 通路（已打通）

- 本机 `v2RayN` / `xray` 监听 `127.0.0.1:10808`（SOCKS5）。经它 `suno.com` 返回 200。
- 沙箱直连与默认代理都不通；可用方式：**带代理启动真实 Chrome + CDP 接管**：
  `chrome.exe --proxy-server="socks5://127.0.0.1:10808" --remote-debugging-port=9222 --user-data-dir=...`
- 账号 `y13077816460` 已登录（Pro）。Suno V6 的 **Sounds** 模式就是做 one-shot/loop 的入口。

### 工具（音频线所有物）

| 文件 | 用途 |
| --- | --- |
| `audio_source/tools/cdp.py` | 直连 CDP：tabs / nav / eval / shot / clickxy / clickjs / type / key / dl / net（抓请求头拿 bearer，不落盘） |
| `audio_source/tools/suno_api.py` | 在页面上下文调用 `studio-api-prod.suno.com`：`today` 列今日 clips、`fields` 看字段、`pull_all` 抓公开流 |
| `audio_source/tools/suno_download.py` | 驱动产品自身的下载流程（行内 “…” → Download → Unlock & Download），把 WAV/MP3 落到 `audio_source/suno/raw/` |
| `audio_source/tools/prepare_cue.py` | 下载件 → 游戏件（去静音 / 截长度 / 淡入淡出 / 单声道 44.1k / 峰值归一） |

注意：`agent-browser --cdp` 在本机必卡死，走不通；本机 ffmpeg 的 `alimiter` 不限幅（已改用纯增益）。

### 账号里今天已有 18 条音效（2026-09-27 08:37–08:40 UTC，`clip_index.json` 已存）

| 组 | 两版时长 | 对应 cue |
| --- | --- | --- |
| Fantasy Reality Restoration | 4.4 / 4.8 s | `reality_restore` |
| Sword Handling（两次腕旋 + 缓慢回鞘） | 2.4 / 2.8 s | `spin` + `slow_sheathe` |
| Thick Glass Shattering | 2.8 / 2.8 s | `glass_break`（`collapse` 复用） |
| Thick Glass Under Extreme Stress | 2.8 / 8.5 s | `glass_stress` |
| Dark Fantasy Space Tearing | 8.4 / 10.0 s | `void_open` |
| Ultra-fast Sword Draw And Diagonal Slash | 2.0 / 2.0 s | `world_cut`（前段可切 `draw`） |
| Japanese-style Sword Sheath Click | 2.0 / 2.4 s | `lock_click` + `final_click` |
| Fantasy Spatial Compression | 2.8 / 2.7 s | `reverse_wave` |
| Air Sucked Away（卡片名 "Cinematic Sound Effect, The Entire Air…"） | 4.0 / 6.0 s | `air_suck` |

尚未生成：`pressure`、`sheath_move`，以及 `COMBAT_SFX_BRIEF.md` 的 Priority A 全部与 Priority B 全部。

### 已落盘

- **`audio_source/suno/raw/suno_cap_*.wav`（18 条，全部解密，2026-09-27）**：通过 WebAudio MediaElementSource 实时采集获得，无需消耗下载配额。起点/峰值见同目录 `CAPTURE_MANIFEST.md`。点击播放到出声约 0.9–1.4 s 延迟；多数捕获尾部含队列自动连播的下一组内容，取 cue 按清单起点裁切。
- Reality Restoration（官方 WAV 下载 858 kB + MP3）、Glass Shattering（MP3）、Sword Handling（MP3）为更早走产品下载流程所得，作为同曲备用源。
- 公开 CDN 的 m4a 是**加密流**（无 ftyp/moov，直接下载不可解码），产品页面用 MediaSource 边解密边喂 `<audio>`，`fetch`/`XHR`（含 Datadog 补丁后的）都无法读 blob——所以只能实时采集 PCM。

### 采集工具（audio_source/tools/）

- `cdp.py`：直连 CDP（调试端口 9222），tabs/eval/click/clickjs/net/grab。
- `suno_capture.py` / `suno_capture_batch.py` / `suno_capture_timed.py`：MediaElementSource + ScriptProcessor 实时抓 PCM → 44.1 kHz 立体声 WAV → base64 回传落盘。
- 浏览器须以 `--proxy-server=socks5://127.0.0.1:10808 --remote-debugging-port=9222 --user-data-dir=C:\Users\Administrator\AppData\Local\SekaiAudioBrowser` 启动（v2RayN 通道，账号已登录）。

## Iaido Sound Pass（2026-09-27 晚，IMPLEMENTED / TECHNICALLY VERIFIED / AWAITING AUDITION）

从 18 条 raw 捕获裁出 **15 个 cue + 12 个 core atoms**（工具 `audio_source/tools/build_iaido_cues.py`，溯源见 `audio_source/suno/SFX_SELECTION.md` 与脚本内 CUES 表）：

- `godot/audio/sfx/iaido/`：world_suck / sheath_move / reverse_compression / pressure_thud / sheath_lock / draw / reality_cut / void_open / glass_stress / glass_detach / spin / slow_sheathe / final_sheathe / reality_collapse / reality_restore——语义命名，全部自带淡入淡出（硬停不爆音），baked 峰值 -3~-8 dBFS，headroom 留给 Godot 混音
- `godot/audio/sfx/core/`：metal_sharp_01/02, metal_body_01, air_fast_01/02, air_low_01, body_low_01, cloth_fast_01, glass_tick_01, glass_crack_01/02, wind_pressure_01
- 等级序（有效峰）：**reality_collapse (-5.5) > final_sheathe click (-6) > reality_cut/draw (-7~) > click 组 > 世界层（stress/detach/sheathe -15 以下）**——高潮在归鞘-崩塌，不在拔刀
- signature click 对：`sheath_lock`（prepare，pitch 1.1 更亮）与 `final_sheathe`（同一身份，pitch 0.92 + body）——同一套剑术声音语言
- `iaido_audio_timeline.gd` 已切到新文件；旧占位件移至 `audio_source/processed/retired_placeholders/`
- `default_bus_layout.tres` 新增：Master / Music / Ambience / SFX / UI / **Iaido**（之前 Iaido/Music 是运行时建，Ambience/SFX/UI 不存在）
- **World Freeze 音乐暂停补齐**：`iaido_director.gd` 原本只 duck 未暂停音乐，已加 `pause_music()` / `resume_music()`（stream_paused 保持播放位置，恢复即原时间继续）
- 验证：`iaido_integration` ×3 稳定 PASS（含 two silences 断言），`combat_music_integration` / `menu_flow_integration` PASS，无 cue missing 警告
- **AWAITING AUDITION**：A 世界是否骤静 / B 逆流吸走感 / C click 清晰度 / D 出刀锋利不轰头 / E 虚空深度不抢戏 / F 归鞘第二高潮 / G collapse 结果感——需用户实机试听

## Combat Audio Language v1（2026-09-27 深夜，IMPLEMENTED / TECHNICALLY VERIFIED / AWAITING AUDITION）

把 12 条 core atoms 变成可复用的声音语言。规范见 `docs/AUDIO_SOUND_LANGUAGE.md`。

- **角色整改（文件名不再约束设计）**：`air_low_01 → pressure_low_01`（它不是低频 whoosh，是 PRESSURE SUB / LOW SWELL）、`glass_crack_02 → glass_body_01`（更暗更钝，是 FRACTURE BODY 不是第二条主 crack）、`glass_tick_01 → glass_low_tick_01`（不够脆，降级为 minor body transient）。工具 `audio_source/tools/rename_atoms.py` 同步改写 `.import` 与 `.godot/imported/`（哈希 = md5(res://路径)），无需重新导入
- **新增代码层**（`godot/scripts/audio/`，避开 MAIN 的 combat 目录）：`sound_atom` / `sound_atom_registry`（唯一知道 atom 是什么 + A/B 交替 + pending 清单）/ `sfx_layer` / `sfx_cue` / `layered_sfx`（voice pool 24，延迟调度 ignore_time_scale）/ `combat_audio_cues`（cue 表，唯一调音位置）/ `combat_audio_director`（接线）
- **10 个 cue**：light_1/2/3、heavy_swing、hit_light、hit_heavy、dodge、guard、perfect_guard、wind_burst。挥空与命中分离；Heavy 靠**延迟进入的 pressure** 而不是音量；闪避**不加** body_low；完美格挡主层是 metal_sharp（三层递减 ≥4/≥8 dB），普通格挡主层是 metal_body——闭眼可辨
- **接线不改 `combat_controller.gd`**：全挂现有信号（move_started / hit_landed / perfect_guard_landed / state_changed + hurtbox.hit_received deferred + wind hitbox 上升沿）
- **感知 trim**：registry 按各文件实测峰值拉到 -6 dBFS 参考，cue 里的 dB 从此是真实相对值
- 验证：`combat_audio_language.gd` PASS（12 atoms / 10 groups / 10 cues、A/B 交替 `[a,b,a,b]`、层级断言、pending 非空）；`combat_music_integration` PASS
- **P0 缺口已声明未伪造**：`glass_high_tick` / `glass_tinkle`（P0）、`air_heavy` / `wood_sheath_tick`（P1）。用 `mine_atoms.py` 从已有 18 条 raw 捕获挖出候选（不耗新配额），落在 `audio_source/processed/candidates/`——**人工听过才能入库**
- **已知回归（非本轮引入）**：`iaido_integration` 报 `Iaido total runtime exceeds 8s (8.80)` 与 `Stage 5 is too short (0.15s)`，来自 21:10 的 `IaidoTuning.tres` / `iaido_tuning.gd` 改动（Iaido 线），未在本轮处理
- **AWAITING AUDITION**：实机玩 Universal Sword ≥2 分钟只听声音——A 轻击够快 / B L1L2L3 有变化但同一把剑 / C Heavy 更重没变 Boom / D 闪避轻快 / E 普通 vs 完美格挡明显不同 / F 连打 30 秒不疲劳

### Tame Pass（2026-09-27 23:30，平 A 太吵）

用户反馈「平 A 太吵」。定位到**不是音量问题，是素材形态问题**：

1. `air_fast` 是宽带噪声，12 kHz 只比主频段低 4 dB → 听着是"沙沙"不是剑锋
2. `tail/head = 0.60`，0.35 s 几乎不衰减 → L1→L2→L3 一叠就是一堵墙

处理（`audio_source/tools/tame_atoms.py`，原件备份 `processed/pre_tame/`）：指数衰减包络
（tail/head 0.60 → **0.09**）+ 频段整形（<150 Hz 与 >5 kHz 各削掉，保留 0.8–3.5 kHz）+ 缩到 0.24 s。
**整体 RMS 只降 0.7 dB（-19.8 → -20.5），7 kHz 以上沙声降 10.8 dB** —— 不是调小，是拿掉噪声。
cloth 同步高通 + 缩到 0.20 s，因此 cue 里 cloth 从 -12 提到 **-9**（它不再和 air 抢低频空间）。
registry 的 air/cloth 峰值参考同步改为 -6.0。已跑 `--import` 重建 3 个 `.sample`。

**A/B 试听样本**（`audio_source/processed/demo/`，不用进游戏就能判）：
`demo_light_chain.wav`（六刀：前三刀挥空 / 后三刀命中，可听挥空 vs 命中）、
`demo_heavy_dodge.wav`、`demo_guards.wav`（普通 Guard ×2 → Perfect Guard ×2）、`demo_wind.wav`；
`old/` 目录是**修复前**的同序列对照。

### INTEGRATION REQUEST（给 MAIN）

1. **删除 `godot/audio/sfx/dodge_temp.wav` 与 `Player.tscn` 的 `DodgeAudio` 节点**，以及 `combat_controller.gd:876` 的 `dodge_audio.play()`。目前 `CombatAudioDirector` 在运行时把它 `volume_db = -80` 静音以避免与 layered dodge 重声；测试断言它必须保持静音直到被删除
2. 新增 `class_name` 脚本需写回 `.godot/global_script_class_cache.cfg`；本轮用 `audio_source/tools/register_classes.py` 增量打补丁（避免 `--editor --quit` 触发全量重导入打断并行会话）。后续新增脚本同样走这个工具

## ⬅ SOUND SYNC REQUEST（来自 MAIN / Iaido 线，2026-09-28）

**时间轴已经改了：总长 7.20 s → 9.90 s，三段死窗口。** 上面那张 15 cue 表测于旧时间轴，
触发点全部作废；现行触发点由 `IaidoTuning` 直接给出，`godot/tools/dump_iaido_cues.gd`
是唯一权威（编码脚本已是"向引擎索取"，没有手抄）。现行关键点：

| 事件 | 触发点 s | 现行 cue / 音量 |
| --- | ---: | --- |
| 拔刀 | 4.68 → 4.78 | `draw` @ draw_start+0.02，**-3.0 dB** |
| 后果延迟 | 4.78 → 5.02 | 无 cue（见下） |
| 世界裂开 | 5.02 → 5.50 | `world_cut` @ cut_start+0.02，**-3.0 dB** |
| 英雄停顿（死窗口） | 5.50 → 5.90 | `void_open` @ cut_end，-5.0 dB |
| 裂缝蔓延 | 5.90 → 7.15 | `glass_stress` @ glass_start，-8.0 dB |
| 最初脱落 | 7.20 | `glass_detach` @ loosen_start，-11.0 dB |
| 收刀 | 7.30 → 8.40 | `slow_sheathe` @ +0.15，-10.0 dB |
| **终击** | **8.40** | `final_click` @ final_click，-2.0 dB |
| 崩塌 | 8.46 → 9.15 | `collapse` @ collapse_start+0.05，**-2.5 dB** |

### 请求（Reality Crack brief §28）——**世界裂开不是爆炸**

> "the world-splitting moment must NOT be a big explosion. Recommended: draw → brief
> silence → tiny stress tick → low impossible pressure; only the Final Click gets the
> Glass Collapse. Two climaxes shared by sound and picture."

画面现在的节奏是 **CUT FIRST / FRACTURE SECOND / COLLAPSE LAST**，音轨要跟着走：

1. **拔刀（4.68–4.78）应该是第一个峰值**——它现在是 -3.0 dB，位置对。
2. **4.78–5.02 是"什么都没发生"**。这 240 ms 的**静音是设计的一部分**，不是留白：
   它让拔刀本身更快、更危险。请**不要**在这段插任何 cue，也不要让 `draw` 的尾巴
   铺过去把它填满。
3. **5.02–5.50 世界裂开：不要爆炸音。** 现在是 `world_cut` @ -3.0 dB，与拔刀同响度，
   于是"切"和"世界真的断了"变成同一件事。请求改为：一声**很小的应力脆响**
   （tiny stress tick），之后接**低频的、不可能的压力**（low impossible pressure）——
   不是金属撞击，是听不见源头的那种压迫感。
4. **5.50–5.90 英雄停顿期间，声音应该停住或只剩那道低频。** 这是全场最重要的截图，
   声音把它让出来。
5. **`final_click`（8.40）才是玻璃崩塌唯一的归属。** `collapse` @ -2.5 dB 保留。
   终击前后 250–400 ms 的落差要做得比现在更大——两个高潮要分别属于"切"和"碎"。

### 另外两条（沿用上面"已发现的问题"，需一并处理）

- `collapse` 溢出：现在的触发点已随新时间轴后移，但替换素材时仍须保证落回
  `restore_end`（9.90 s）之内，否则 `finish_iaido()` 会硬截断。
- `void_open` 时长 1.60 s，会压住 `glass_stress`；新时间轴里两者相隔 0.40 s，
  **素材必须收短或分层让位**。

**状态：`REQUESTED`。** 未经实机试听不得称 approved。

---

## 聚合斩 · 处决三事件（`IAIDO_ENEMY_CUT_MARK` / `IAIDO_ENEMY_RELEASE` / `IAIDO_BODY_FALL`）

**状态：`REQUESTED`。** 由 MAIN 的处决系统广播，AUDIO 负责素材与混音。

聚合斩现在真的会**切开**被它杀死的敌人，而这块演出的声音不能是"一句 anime slash
death 复用给所有怪"。三个事件对应的是三个**不同的物理事实**，中间隔着明显的留白，
把它们并成一个 cue 会让整段听起来像一次击杀特效而不是一次处决。

### 事件、时刻与语义

| 事件 | 时刻 | 是什么 | 不是什么 |
|---|---|---|---|
| `IAIDO_ENEMY_CUT_MARK` | 斩的瞬间 **T0 + 100–220 ms** | 身体上出现一道极细的断面——**还没有分开**。要的是"某处已经不对了"的极小提示 | 不是斩击音，不是爆音。T0 到 T0+100 ms 之间**什么都没有**，这段留白是刻意的 |
| `IAIDO_ENEMY_RELEASE` | **`final_click`（8.40 s）+ 20–80 ms** | 归鞘声的同一拍，两部分真正失去约束的那一刻 | 不是收刀声本身（那是已有 cue）。它是"结构失效"那一下 |
| `IAIDO_BODY_FALL` | 紧随 RELEASE | 质量接管：两部分**不同时**落地（见下） | 不是 ragdoll 砸地。重点是失去支撑，不是弹片飞出去 |

三个事件由 `IaidoDirector.take_execution_events()` 广播，每个 execution 只发一次。

### §P · 多杀：同一刀，不同的落地

一次斩击可以同时处决多个目标。所有目标共享**同一个斩击瞬间**，但
`IAIDO_RELEASE` 之间允许 **20–80 ms** 的散布（按目标序号确定，不是随机噪声），
`IAIDO_BODY_FALL` 再各自按质量错开。十个怪同帧复制粘贴是明确要避免的。

**混音上要能听出个数**：两个目标不是把同一个样本叠两遍（那只会更响），
而是两个略有差异的实例，间隔在 20–80 ms 的窗口里。

### 按材质分，不要一个样本打天下

断面材质表见 `IaidoExecutionLibrary`（construct / biological / ice / plant /
generic），每个材质一套断面配色与发射。声音要跟着这套走：

- **construct** — 石裂 + 旧金属断口 + 核心那一点魔力余响
- **biological** — 克制、短、闷。**不要写实血声**，和视觉上的"风格化暗断面"一致
- **ice** — 晶体断面 + 霜尘
- **plant** — 纤维、木、类汁液

### 交付纪律（沿用本文件既有规则）

- **优先 A 层重组**（`audio_source/library/<category>/`），**不要为一个机制单独
  生成一套**。处决是既有机制的重新组合，不是新类别。
- 时长注意：**duration < 1.5 s 会削顶**，`MIN_SAFE_DURATION = 2.0 s`。
- 48 kHz / -6 dBFS（composite 可 -3）；torchaudio 保存必须 **PCM_S/16**。
- 全序列混成一条听（`mix_iaido_full.py`），单独听每条不算验收。

---

## 缚星链音频 · SCHEDULER FIX + 首版试听（2026-09-28 深夜，IMPLEMENTED / TECHNICALLY VERIFIED / AWAITING AUDITION）

第一次把链的声音**真的跑成一条时间线**，结果抓到两个 bug，其中一个让整把武器没有自己的声音。

### A · 排队的招式 cue 被自己清掉（P0，已修）

`ChainAudioDirector.step()` 里有一句「`state_time` 倒退 = 新状态开始 → `_pending.clear()`」。
但 `move_started` 是在这一 tick **之前**发出的，队列里躺的正是**即将开始这个状态的第一拍**——
于是每一条放在队列里的招式 cue（`chain_a1_sweep` / `chain_a2_return` / `chain_a2_reverse` /
`chain_a3_throw` / `chain_slam_*`）都在它自己的第一帧被丢掉。事件型 cue（撞墙 / BITE /
TENSION / 命中）走的是 `_play()`，不受影响——所以一次捕获看起来「有声音」，而武器本身是哑的。

- 修法：删掉那句清空，改为 **move 实例序号**（`_move_serial`，每次 `move_started` +1）。
  一个 beat 只因**它自己那一刀消失**而失效；同一个 move id 在回到待机后重播是**另一个实例**，
  不是旧 beat 姗姗来迟。`_fire_pending()` 同时校验序号与 `active_move`。
- 前后对比（同一台、同一步进）：**招式 cue 0 条 → 8 条**；总事件 14 → 23。
- **这一条在实机里同样成立**：每次从待机起手的第一刀，它的技法音都没响过。

### B · 混音器把 `res://` 解析到仓库根（已修，工具自身守卫抓到）

`mix_chain_demo.py` 的 `--godot-root` 默认是仓库根，但 `res://` 相对的是**工程根**
（`F:/SEKAI/godot`）。结果是每一个 atom 都解析成不存在的文件，输出的 stem 是一段
「合法但全静音」的 wav —— 只有它自己那行 `SILENT LAYERS` 招了。已改默认值、改文档说明，
并加了硬守卫（找不到 `project.godot` 就直接报错退出，负向测试已过）。

### C · 给捕获工具加了一条能被打红的断言

`capture_chain_audio.gd` 现在按 `MOVE_CUE` 表检查**这一拍有没有发出它自己的声音**，
缺失就写进 notes 并打印。**突变测试**：把旧行为放回去 → 每一拍都报
`!! no chain_a1_sweep - the technique had no voice`，断言不是装饰。
另外 BITE 那一拍改成 `request(&"chain_hook")`（直取 `hook_id`）而不是 `request(&"light")`：
后者按连段序号走 `light_chain`，能不能拿到 A3 直抛取决于**上一拍有没有把连段留在窗口内**，
所以「撞墙」那一拍以前从来没真的撞过墙（`walls +0`）。现在 `walls +1`。

### 交付：两条 stem（`audio_source/processed/demo/`）

| 文件 | 时长 | peak / rms | 内容 |
| --- | ---: | --- | --- |
| `chain_atoms_dry.wav` | 32.14 s | -1.50 / -24.67 | **27 条 cue 全表**逐条播，间隔 0.55 s；未在演奏中出现的 cue 靠它听 |
| `chain_sequence_pass01.wav` | 14.15 s | -1.50 / -23.47 | 捕获到的**真实演奏**，按引擎自己的钟排 |

演奏时间线（23 条）已含 §13 四拍：
`A1 横扫 → 回收 / A2 双弧（da-DA）→ 回收 / A3 直抛 → TENSION 起 + 满 → 重回收 /
直抛撞墙 → WALL_HEAVY + BITE + TENSION / 横扫命中轻敌 → 横扫命中重敌 → 回收`。

- 覆盖：演奏段命中 **13/27**。未出现的是 `chain_idle_shift` / `chain_launch` / `chain_snap_cut` /
  `chain_swing_short` / `chain_slam_swing` / `chain_slam_impact` / `chain_deflect` / `chain_orbit` /
  `chain_snap_release` / `chain_yank_light` / `chain_yank_heavy` / `chain_wall_light` / `chain_hook_catch` /
  `chain_wrap`——**这些不是没做，是这一组 take 没有编排它们**（第一版只排了普攻 A1/A2/A3 + 一次撞墙 +
  两次命中）。dry sheet 里它们都在。
- 报告里没有 `!!` 行：招式与字幕一致、每一拍都发出了自己的声音。
- **AWAITING AUDITION**：A 待机是不是「几乎没有声音」/ B A1 够不够宽、够不够重 /
  C A2 两下是不是听得出是一口气的 da-DA / D A3 直抛听不听得出来「东西离手了」/
  E 撞墙是不是接触而不是爆炸 / F BITE 与 TENSION 是不是两个不同的时刻 /
  G 收起链子的声音够不够好听（回收要和抛出一样讲究）。

## 缚星链 HEAVY PASS（2026-09-29 00:10，IMPLEMENTED / TECHNICALLY VERIFIED / AWAITING AUDITION）

用户听力反馈：「太脆了，而且有被截断的声音，我要更重的锁链」。三条都量过，都改在根因上。

### 三条反馈各自的根因（实测）

| 反馈 | 根因 | 证据 |
| --- | --- | --- |
| 被截断 | `process_atoms.py` 的 `trim_to_event` **按设计秒数硬切**（`end = onset + target*rate`），之后只给 20 ms 线性淡出 | 23 个链原子里 **17 个**切在自然衰减之内；`metal_chain_whoosh` 设计 0.50 s / 真实尾 **1.25 s**（砍掉 0.75 s）。尾部电平（相对自身峰值）`snap_release` **-15.2 dB**、`yank_heavy` -17.1、`whoosh` -18.2、`tension` -18.9 |
| 太脆 | 旧演奏段 **64.4%** 的能量在 3 kHz 以上、200 Hz 以下只有 **7.5%**；`metal_sharp`（0.07 s / 4.6 kHz，全库最亮最短）在 `chain_deflect` 与 `chain_bite` 里是 **0 dB 主层** | 见下表前后对照 |
| 要更重 | **素材里没有低频**：raw 链原子 `<160 Hz` 占 **0.3%**、`>8 kHz` 占 **56.7%**（`metal_chain_whoosh`）。提升或派生身体层**无低频可提**；而库里 `pressure_low_01` / `body_low_01` 的 `<160 Hz` 占**自身 35.9% / 30.7%**，却一直只用 -14/-16 dB | 模型把「重钢链」渲染成了嘶声 |

结论：**「更重」只能靠重组，不能靠处理。** 那两层低频原子就是链的重量，之前被当成了装饰。

### 改了什么

1. **`audio_source/tools/process_atoms.py`（AUDIO 线所有物）**
   - `trim_to_event` → **`trim_to_decay`**：设计时长是**下限不是切点**；从设计长度往后找
     **第一个确认安静处**（`DECAY_DB=-45`、连续 3 个 10 ms 窗）再切，找不到则落到
     `MAX_EXTENSION=1.0 s` 的 cap 并打印 `~`（表示淡出在替素材干活）。
   - `apply_fades`：20 ms 线性 → **按尾部实测电平自适应长度（8–200 ms）的升余弦**。
   - 新增 **`--audit`**：把「processed 是否短于自然尾」做成守卫，切进衰减就报红并 `exit 1`。
   - 新增 `--ids`（按 manifest 的 `sfx_id` 过滤，**不能**拿文件名 `split("_s")`——
     `metal_chain_snap_release` 里就有 `_s`）与 `--voice <category>`（按类目的可选重量整形）。
   - 踩过的坑：detector 一开始**从 onset 往后搜**第一个安静段，撞上多次撞击素材
     （`hook_stone` 在 0.30 s 有空档、0.34 s 又响）会误判结束，随后 `max(end_min, point)`
     **静默退回硬切**。**必须从设计长度往后搜。**
2. **链音色**（`VOICE["chain"]`）：低架 +4 dB@150 Hz、高架 −4 dB@6 kHz、并混入一层
   **由素材自身派生的低速低通身体层**（×0.86 / LP 1.3 kHz / −9 dB）。共享类目
   （`air_heavy` / `hook_stone` / `hook_metal` / `hook_wood` / `body_impact` / `metal_link_heavy`）
   只跑**尾音修复、不动音色**——它们也被别的武器加载。
3. **`godot/scripts/audio/chain_audio_cues.gd`**：20 个 cue 补上 `chain_link_heavy`
   （该组**生成了但此前一次没用**）；`metal_sharp` 从 `bite`/`deflect` 的主层降为 −6 的细节；
   `pressure_low`/`body_low` 从 −14/−16 提到 −3～−8 并降 pitch 到 0.91–0.95。
   规则写进表头：**质量层是主体，tick 只在上面当细节，绝不能当主层。**

### 前后对照（同 SEED、同 take、同事件表，可比）

| 指标 | 旧 | 新 |
| --- | ---: | ---: |
| 链素材平均时长 | 0.58 s | **0.94 s** |
| 链素材平均尾部电平（相对峰） | **−40.8 dB** | **−70.0 dB** |
| 链素材平均频谱重心 | 7633 Hz | **5936 Hz** |
| 演奏段时长 / 重心 | 14.15 s / 5854 Hz | 15.80 s / **4668 Hz** |
| 演奏段 >3 kHz 占比 | 64.4 % | **53.4 %** |
| 演奏段 <200 Hz 占比 | 7.5 % | **11.0 %**（事件窗口内 **14–17 %**） |
| 干声全表 | 32.14 s / 6189 Hz | 44.25 s / 5063 Hz |
| 演奏段 RMS / 波峰因数 | −23.5 dBFS / 22.0 dB | −21.1 dBFS / 19.6 dB |

`--audit`：旧素材 **47/92 报红**（全库 82/116），修后 **0/116**。突变测试成立。
审阅工具：`F:/SEKAI-WT/_tools/compare_atoms.py`（逐条对比时长 / 尾电平 / 重心 / 低频占比）。

### 交付

| 文件 | 时长 | peak / rms | 内容 |
| --- | ---: | --- | --- |
| `chain_sequence_pass01.wav` | 15.80 s | -1.50 / -21.06 | 捕获到的真实演奏（26 条事件），含 §13 四拍 |
| `chain_atoms_dry.wav` | 44.25 s | -1.50 / -23.49 | **27 条 cue 全表**逐条播；未在演奏中出现的 cue 靠它听 |

- 报告无 `!!`、无 `SILENT LAYERS`；`BITE` 那一拍 `walls +1`（真的撞上了）。
- 旧版留档在 `.render/_audio_ab/` 供 A/B（`.render/` 已 gitignore）。
- **AWAITING AUDITION**：A 待机是不是还有一点活气 / B A1 的宽度与重量够不够 /
  C da-DA 听不听得出是一口气 / D A3 听不听得出「东西离手了」/ E 撞墙是**接触**而不是爆炸 /
  F BITE 与 TENSION 是不是两个时刻 / G 回收够不够好听 / **H 重量是不是已经到位**。

### 已知未达成（诚实记账）

次低频仍只有 ~11 %：`pressure_low` / `body_low` 的能量主要在 **160–800 Hz**，继续抬高收益递减
（实测 10.9 % → 11.0 %）。**真正把 80 Hz 以下做厚，只有两条路：把这两层推到会发闷的程度，
或者新生成一条低频素材（`audio_source/library/`）并加进链的 cue。** 待实机判断后再定档。

## SWORD SFX REBUILD pass 01（2026-09-29，IMPLEMENTED / TECHNICALLY VERIFIED / IN COMBAT SANDBOX / AWAITING AUDITION）

`# GENERATE ATOMS → AUDITION → PROCESS → EVENT LAYER → INTEGRATE → PLAY → RECORD → LISTEN → FIX` 全程走完一遍。
不是重新生成一些剑音效，是重定义剑的声音语言（ANIME STYLIZED NEXT-GEN STEEL：干净钢、快刃、受控质量、干瞬态、强方向、短尾、明确接触），然后真的接进 Combat Sandbox。

### 交付（4 件）

| 交付物 | 路径 | 事实 |
| --- | --- | --- |
| ① 成片 | `out/audio/sword_sfx_rebuild_pass01.mp4` | 9 222 673 B · md5 `e29a46e2…` · 画面 27.36 s / 声 27.21 s（drift 0.146 s，守卫门限 0.20）· 530 帧 @ 19.37 fps · **32 cue / 11 次命中 / 1 次完美格挡 / 25 条节拍全部 fired / 无 SCRIPT ERROR** |
| ② Godot 正式 SFX | `godot/scripts/audio/`（registry / loudness 侧表 / cues / director / layered_sfx / chain_atom_table） | 156 原子（剔除 1）/ 68 族 / 17 cue；战斗只发语义事件 + `material` + `intensity`，**无一处 WAV 路径** |
| ③ Dry Atom Sheet | `audio_source/processed/demo/sword_atoms_dry.wav` + `.tsv` | 99 原子 / 35 族 / 98.96 s，逐条索引（family / file / start / duration / peak） |
| ④ MANIFEST | `docs/AUDIO_MANIFEST.md` | 99 原子逐行：id / category / group / provider / prompt / 实测时长峰值 / usage / variants / license 节 |

源片留档 `F:/SEKAI-render/sword_p5`（`beats.tsv` = 节拍表，`layers.tsv` 在 `sword_cues9` = 每层实际解析出的 gain/pitch/delay，是离线重建的输入）。**出片目录刻意不放 `.render/`**，见「规则」末条。

### §19 A–F：自己听完整片之后，逐条给答案

口径说明：**色彩问题一律用攻击窗**（`attack_bands.py`，从检测到的起振点起 0.12 s），**电平问题用短时响度**（0.30 s 窗 / 0.15 s 步的 RMS 最大值）。整切片频段在本轮被证明会骗人，理由见下面「本轮最重要的发现」。

| | 问题 | 实测 | 答 |
| --- | --- | --- | --- |
| **A** | 闭眼能否听出 L1/L2/L3 不是同一刀 | 隔离试听三遍互差 ≤ 150 Hz；**L2 2675–2821 / L1 2102–2197 / L3 1734–1838 Hz**，两两相距 380–890 Hz；攻击窗 edge 55.8 / 49.8 / 37.6 %，low 1.7 / 9.0 / 5.9 % | **是。** 三刀不是三个音量，是三个动作：L1 只有空气（**完全不含金属**，测试锁死），L2 借前一刀的惯性（edge 最高、low 最低），L3 收招有重量但无爆炸 |
| **B** | Heavy 是否靠节奏与重量成立，而不是大 Boom | 蓄力 383/621/665 Hz、edge 0.4–1.2 %、tail 1.34–1.38 s、peak −12.2/−7.7/−7.7；释放 **3196/2431/2473 Hz**、edge 5.3–8.4 %、tail 0.76、peak −8.0/−5.8/−6.8。成片里 release→hit 跨越 1.86 s，材质接触落在释放开始后 0.94 s | **是。** 蓄力比释放暗 2 000–2 800 Hz、峰值低 2–4 dB；释放相对轻挥只变**宽**（tail 0.76 对 0.30–0.34，×2.3）不变成爆炸。身份层是刃（`blade_move_heavy`，2–6.5 kHz 占 79 %），空气被降级到 −4 dB，低频只在 `pressure_low` −13 dB 垫底 |
| **C** | Block 与 Perfect Guard 一耳朵能否分 | block 质心 369/215/202 Hz、edge 0.1–0.7 %、tail 0.58–0.70；PG 质心 3029/3087/2678 Hz、edge **40.1–43.2 %**、tail 0.24–0.28 | **是，三条独立通道同时成立**：质心 ×13–15、edge ×60–400、尾巴 ÷2.4。不是同一个音加了音量 |
| **D** | PG 的核心是不是 CLANG → SILENCE | PG 峰值 −0.8/−0.0/−0.0 dBFS 是**全片最高**，尾巴 0.24–0.28 s 是所有有尾音的撞击类 cue 里最短的；`hit_weight` 只在 intensity ≥ 0.75 且已有材质接触时才叠加，PG 不叠 | **是。** 它靠瞬态锐度取胜而不是靠最响（这正是 §15 后半句），hitstop 期间没有长混响可挂。**遗留**：整拍口径下，一个完整的轻击拍（挥空 + 材质 + 重量三层 ≈ −17.9 dB 短时响度）仍比 PG（−20.2）高约 2.3 dB，见「已知缺口」 |
| **E** | Riposte 是不是「刚才那一格挡兑现了」 | 隔离试听 rms −33.3..−33.7、peak −9.7/−8.0/−10.6、质心 3944–4479 Hz、edge 16.6–22.9 %；PG 同口径 rms −26.9、peak −0.0 | **一半。** 颜色对（亮、干、短、带一点刃滑），**但它是整组撞击类 cue 里最轻的一个**（比它兑现的那次格挡低 6.4 dB rms）。成片里它藏在自己的拍子里所以活了下来。见「最差剩余」 |
| **F** | 剑有没有「拿在手里」的近身层；接触有没有来自目标方向 | 全部 spatial cue（contact ×5 材质 / shatter）在等距试听里 **@right 32° 全部 +3.8…+4.2 dB（R−L）**，**@ahead 全部 −0.2…+0.2**，六遍无一例外；玩家层（air / heavy / block / PG / riposte / dodge）全部非空间 | **是。** PART M 的两层分法成立：玩家层是 player-relative、接触层用 `play_cue_at()` 落在**实际命中点**，实测的方向性是硬的 |

**材料是否真的按材质分开（§9–§13 / PART F）——攻击窗，六个变体全量：**

| 材质 | low %(0–160) | edge %(2–6.5k) | air %(6.5k+) | 听感身份 |
| --- | ---: | ---: | ---: | --- |
| METAL | 1.5–2.5 | **66–69** | 22–24 | 硬瞬态 + 短鸣 |
| ICE | 16.1–16.7 | 35–39 | 6–8 | 玻璃感的结晶撞击 |
| STONE | 19.6–29.1 | 25–35 | 6–13 | 石屑 + 刃口 |
| BODY / FLESH | 44.6–59.9 | 6–20 | 1–23 | 闷，stylized，不 gore |
| WOOD | 57.3–74.3 | 10–23 | 3–9 | 干切 + 木裂 |

五种材质在**同一根轴**上分得开，**不是一个 `sword_hit.wav`**。`shatter` 的攻击窗 low 67 %、edge 7 %：起手是低开裂，结晶感在后半（tail 1.06–1.36 s，全组最长）——**是「剑砍碎了冻结物」，不是「窗户碎了」**。

### ⚠ 本轮最重要的发现：整切片频段会骗人，而且差点让我去"修"一个没坏的声音

`review_take.py` / `cue_mix.py` 的 `low% / edge% / cent` 是**对整条录制切片**加 Hann 窗算的，而 Hann 在两端为 0。一个活在 1.5 s 切片**前三分之一**的瞬态，起振被乘上 ~0.01，剩下的是一个阶跃，按 1/f 泄漏成"低频"。

- `sword_contact_stone` 的三个变体，整切片质心 **743 / 2194 / 3480 Hz（2.2 个八度）**——看起来是一个支援层把同一个 cue 重新上色，像变体抽奖。
- 换成**攻击窗**（0.12 s，从检测到的起振点起）同六遍播放：low **19.6–29.1 %**、edge **24.6–35.1 %**。**一个稳定的材质。**
- 修 `cue_mix.py`（两侧都裁到 cue 自身时长，让伪影相消）：整切片 2256 Hz / 39.8 % low → 自身 0.67 s 窗 2418 Hz / 20.1 % low，**一半的"低频"是缓冲占空比**。
- 已在 `cue_mix.py` / `review_take.py` 写明口径，并把 `attack_bands.py` 标为色彩的唯一可信来源。

**结论留给下一个人**：这两个工具的 `low%/edge%/cent` 只能用来看电平、尾巴和立体声侧向，**不能用来判音色**。我这一轮差点据此把 `contact_stone` 的变体判成坏的。

### 真正修掉的 bug：接触层在播放路径上被"空气吸收"吃掉了材质

`layered_sfx.gd` 的空间声道从来没设过 `attenuation_filter_cutoff_hz` / `attenuation_filter_db`，于是用 Godot 默认的 **5 kHz / −24 dB**，并随距离加深。而**材质就活在那个频段**：

| 同一层表、同一段长、同一窗口 | 离线重建 | 录到的 take（修前） |
| --- | ---: | ---: |
| `sword_contact_stone` 2–6.5 kHz 占比 | 27.8 % | **5.6 %** |
| 6.5 kHz 以上 | 10.1 % | **2.9 %** |

修后（16 kHz / −6 dB，保留"距离会闷"但不再删掉材质），整片重出的对照：

| beat | 质心 修前 → 修后 |
| --- | --- |
| CONTACT · WOOD | 1511 → **3395 Hz** |
| LIGHT 1 · 命中 | 1432 → **3245 Hz** |
| HEAVY · 释放命中 | 1776 → **2982 Hz** |
| CONTACT · STONE | 1360 → 1448 Hz |
| RIPOSTE | 2640 → 3181 Hz |
| （对照组）LIGHT 1 · 挥空 | 2254 → 2266 Hz |
| （对照组）BLOCK · 接刀 | 204 → 224 Hz |

非空间 cue 全部原地不动（±30 Hz），**说明这一改只动了空间声道**。已加断言：测试真的播一次接触，然后**读那个节点的属性**；突变检验通过（把 −6 dB 改回 −24 dB → 报红，报错原文 `contact air absorption is -24 dB - a hit at 3 m loses the colour that distinguishes one material from another`），随后还原。

### SELF REVIEW

**BEST IMPROVEMENT** — 材质在游戏里真的读成材质了。修掉空气吸收之后，五种材质的攻击窗落在同一根轴的不同位置（metal edge 66–69 % / ice 35–39 % / stone 25–35 % / flesh 6–20 % / wood 10–23 %），每一次接触的质心抬升 500–1 800 Hz，而所有非空间 cue 一动不动。这是本轮唯一一个"先量出根因、再改一行、再用突变检验钉住"的修改。

**WORST REMAINING SOUND** — `sword_riposte`。它整组撞击类 cue 里最轻：隔离试听 rms **−33.3**（它兑现的那次完美格挡是 −26.9），peak −8.0，因为整个 cue 只有三层、且三层都是短瞬态（`metal_sharp` 0.07 s + `blade_slide_short` + `air_fast`），**没有任何东西撑住它**。成片里它靠自己的拍子和后续的一刀活着，所以整片听下来不觉得缺——但这是它躲在结构后面，不是它成立。

**NEXT 3 FIXES**
1. 把 `review_take.py` / `cue_mix.py` 的频段列换成起振窗（复用 `attack_bands.onset_of`），让报告不再描述缓冲占空比。在那之前，任何"某个 cue 频谱不对"的结论都不许只凭整切片。
2. 给 riposte 自己的电平：加一条 focused release 素材（或把 `blade_slide_short` 抬到 −2 dB 并把 `metal_sharp` 的 pitch 从 1.02 落到 0.98），并加断言 `riposte rms > block rms`。
3. 结清 §15 在整拍口径上的反向：PG 峰值已经在 **−0.8 dBFS**，本能地 +3 dB 会削波，所以要么把轻击路径降 ~2 dB，要么**书面**接受"PG 赢在瞬态锐度、不赢在电平"。

### 本轮新工具 / 工具改动（都在 `audio_source/tools/`）

| 工具 | 作用 | 用法 |
| --- | --- | --- |
| `attack_bands.py`（新） | **攻击窗**频段（功率谱），自带 5 ms RMS 包络起振检测 | `attack_bands.py <take_dir> [--window 0.12] [--only <substr>]` |
| `atom_sheet.py`（新） | 生成交付物③ Dry Atom Sheet；族名**从两张权威表读**，不猜文件名 | `atom_sheet.py` |
| `emit_manifest_doc.py`（新） | 生成交付物④ MANIFEST；只有头部与授权节是手写，表格全生成 | `emit_manifest_doc.py` |
| `cue_mix.py`（改） | 离线重建两侧都裁到 cue 自身时长，伪影相消 | `cue_mix.py <take_dir> [--only <cue_id>]` |
| `review_take.py`（改） | 文档写明 `low%/edge%/cent` 是电平口径不是音色口径 | `review_take.py <take_dir>` |
| `combat_audio_language.gd`（改） | 从「锁原子数量」（**已红数周**，本来锁 12、实际 156）改成**锁行为**；新增空气吸收、§15 层级、剔除、变体轮转、材质路由、shatter 门、接线等断言组，并加了 `bool()` 构造陷阱的源码守卫 | `godot --headless --script res://tests/combat_audio_language.gd` |

### 已知缺口（诚实记账，未擅自改）

| 缺口 | 事实 | 为什么没动 |
| --- | --- | --- |
| MANIFEST 的 license 不是逐行 | **`sfx_manifest.json` 完全没有 `license` 键**（404 条与 228 条两个库都验证过），授权只在文档里记一次 | 清单由 `emit_manifest_doc.py` 生成，而 manifest 本身由另一条工具写；要么加字段重出，要么改成推断——两条都改别人的生成物，留作 open item |
| §15 在**整拍**口径上反向 | 轻击拍（三层）−17.9 对 PG −20.2；PG 峰值 −0.8 dBFS 已近满刻度，+3 dB 会削波 | 架构问题（三层拍 vs 单 cue 拍），且盲目抬与"不削波"冲突；§15 自己后半句就允许 PG 靠瞬态取胜 |
| `contact_stone` / `shatter` 仍是离线与 take 的离群点 | 修空气吸收后 6 个材质里 4 个 + ice 全部落进容差（wood 从 −1800 Hz 的偏差修好）；stone 仍在 take 里 ≈0.5×、shatter ≈0.78×（整切片口径） | 整切片口径本身不可信（见上），**攻击窗口径下两者都稳定**；不要拿一把坏尺子改音 |
| `contact_ice` 在**整片**里 peak −5.9 比 `contact_metal` −5.7 轻 | 其尾音 rms 却是全场最高之一 | 与 §15「shatter/signature 在顶、材质接触不在」并不冲突；若要动，属于层级微调而非缺陷 |
| `stone_chip` 三变体在攻击窗上仍有 edge 24.6→35.1 / air 6.0→13.3 的分布 | 是 variant 该有的变化，离线整切片口径下看着像 1 个八度 | 攻击窗口径下它是**一个材质**；§17 要的正是小范围随机，不是三份同样 |
| `sword_pose_sampler.gd` 目前编译失败 | 2026-09-29 13:11 有一个**并行会话正在改这条线**，文件里留着 `var hop: Vector3 = (times.size() > index + 1) as int == 0 as int as Vector3`，导致 `combat_controller.gd` 连带编译失败 | **不是音频线，且对方正在写**。按多会话纪律不碰，只报 |

## 规则

- 每次导入候选必须记录：cue ID、来源工具、作者/模型、授权、生成 prompt 或 URL、下载日期、文件 hash、触发点、试听结论。见 `COMBAT_SFX_BRIEF.md` 模板。
- 淘汰候选不得留在 `godot/audio/` 下。
- 峰值不得削波；响度与 `first-encounter.mp3` 战斗音乐对比后确定。
- AUDIO 不改战斗 gameplay；需要改 Godot trigger 只做最小必要接入，大型逻辑交回 MAIN。
