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

## 规则

- 每次导入候选必须记录：cue ID、来源工具、作者/模型、授权、生成 prompt 或 URL、下载日期、文件 hash、触发点、试听结论。见 `COMBAT_SFX_BRIEF.md` 模板。
- 淘汰候选不得留在 `godot/audio/` 下。
- 峰值不得削波；响度与 `first-encounter.mp3` 战斗音乐对比后确定。
- AUDIO 不改战斗 gameplay；需要改 Godot trigger 只做最小必要接入，大型逻辑交回 MAIN。
