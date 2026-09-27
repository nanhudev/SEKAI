# SEKAI MVP 0.1 状态

## 2026-09-27 · 聚合斩 · 世界切裂 V3（虚空为什么一直像一根深蓝棒子）

用户对上一版逐帧录影的判定是：结构对，但每一段仍像原型；P0 是「把粗蓝斜光带变成真正的世界切裂 + 细蓝虚空缝」。
放大 3 倍、扫描线取像素值、再对单一变量做 A/B 差图之后，找到**四个可测量的原因** —— 都不是"效果不够强"，
是参数和数学错了：

- **裂口宽度被写成 `gap + separation`**（1080p 下 23px、横向 41px），而预算是 10–16px。真正在卖位移的
  separation 只有 20px：**裂口比它自己的位移还宽，把证据盖住了**。现在 `half_gap = 0.5 * gap_px`，
  裂口严格等于 `gap_px`（2 → 6 → 16）；`separation_px` 改为**每一半沿斩法线的刚体平移**，两侧错位 = 2×separation。
- **缝隙填色是「中间黑、两侧亮」的对称渐变**，这就是圆柱着色 —— 在纯色场地上必然读成一根躺着的棒子。
  改为**非对称**：近边全黑，远壁微弱受光。扫描线现在能依次读出 WORLD → 亮唇 `#b3b8b7` → 黑 `#00020d`
  → 逐级受光的远壁 `#061933` → 透出来的远侧 `#666a6b` → WORLD。**这才叫「看进去」。**
- **缺口噪声被缩到亚像素**（±0.67px），两条边在数学上完全笔直、且互为镜像。镜像是冲切模具，不是断裂。
  现在两个面各用独立噪声，以 authored px 计量（`void_edge_width_px` 1 → 3）。
- **裂缝的 `push` 是对称的、且沿斩法线** —— 主裂缝本身沿法线生长，等于**沿着裂缝推**，两侧同向位移，
  永远不分离，所以只剩一条灰线。正确解是带符号的**垂直剪切**（新增 `crack_shear()`）。

一并改掉的：玻璃失效改为「暗槽 + 亮斜面 + 跨缝可见台阶」，缝按噪声打断（连续等宽蜂窝 = 网格，不是损伤）；
`edge_px` 更名 `cut_face_px` 并新增 `cut_lip_px`（断裂截面厚度 / 外缘亮唇），四处同步。

**验证方法**（这一轮的教训不在美术判断，在怎么验）：

- **单变量 A/B 差图**：渲染器新增 `arg5` 调参覆盖。`separation_px=0` vs `12` 在同一 debug-hold 时刻 →
  6.18% 像素变化、分块峰值 103。位移**确实存在且可见** —— 靠肉眼盯柱体边缘永远得不出这个结论。
- **先算再看**：扫描线找亮阶，y=340 处所有边缘一致位移 **+4px**，恰好等于 `12 × 0.667 × cos60°` + 视差。
- **`print()` 是块缓冲**：重定向到管道会整段丢失，一次**成功**的渲染看起来像挂死。一律重定向到文件，
  用帧文件数判断进度。
- **AMD OpenGL 驱动会被重着色器卡死**：把 `crack_field` 改成返回 `vec3` 并在展开循环里累加向量后，
  第一帧永远不呈现（`timeout` 退出、0 帧）。用只加载着色器的 `godot/tools/frame_probe.gd -- shader` 二分定位。
  修法 = 保留已验证能编译的 float 距离场，另加一个**无分支**的小函数。**GPU 编程里「能编译」是约束条件，不是细节。**
- **并发**：另一条线在跑 `tests/element_integration.gd`，会重写 `.godot/global_script_class_cache.cfg`，
  让渲染进程满屏 `Could not find type`；渲染窗口被遮挡时 `frame_post_draw` 永不触发。**只 kill 自己的 PID。**

渲染器新增能力：`arg4` 分镜表（直接产出具名验收帧，跳过 pre-roll/tail）、`arg5` 调参覆盖、
`_clear_existing_frames()` 现在清理目录内**全部** PNG（旧命名残留曾混进视频）。

**状态：IMPLEMENTED / TECHNICALLY VERIFIED。** 六张验收帧已产出并逐张核对像素结构：
`F:\SEKAI\.render\verify\01_SHEATH_READY.png` … `06_FINAL_COLLAPSE.png`；完整录影
`F:\SEKAI\.render\iaido_signature_ceremony.mp4`。
**尚未 VISUALLY VERIFIED**：「两侧世界错位」这一条在 720p 静帧上偏克制，必须在**动起来的录影**上判定。
本环境 Godot 无可见窗口句柄，观感验收只能由用户在可见桌面完成 —— 不因为技术跑通就宣布视觉完成。

## 2026-09-27 · 单手剑通用语言与三个流派原型

把战斗层从"几招散装的连击"重做成**一套通用剑语言 + 流派数据改写**：`CombatController` 只认识剑语言，
从不 `if style_id == ...`；一个流派 = 一份 `SwordMoveset` 数据（节奏、方向、取消窗口、位移、架势、反击、技能）。

新增数据结构：`SwordMove` / `SwordGuardProfile` / `SwordSkill` / `SwordMoveset` / `SwordPoseSampler`，
全部流派集中在 `moveset_library.gd` 里构建 —— 这是唯一新增流派的地方。
武器运动从 Transform tween 换成**按招式写死的权重曲线 + 指数滞后弹簧 + 真实刀光**（14 点刀尖采样），
解决了"剑像飘"的问题。设计文档见 `docs/COMBAT_DESIGN.md`。

落地内容：

- **通用层**：三段轻击（第三段改成收鞘一拍 + 快速突刺来换节奏）、Tap/Hold 分家的重击
  （蓄力改的是**姿势伤害**不是伤害 ×2）、冲刺/后撤攻击、快速短突刺反击。
- **防御闭环**：防御非无敌（重击双倍扣耐力、破防带相机冲击与武器后坐）；完美格挡窗口收到 **0.12s**，
  在同一时刻给五个通道的反馈（后坐 / hitstop / 敌人中断 / 火花 / 金属瞬态），并开启 0.75s 反击窗口。
  按住防御超出窗口**不算**完美格挡 —— 这条退化路径被测试专门锁死。
- **藏锋流**：纳刀/拔刀红利（带刀出鞘起手 ×0.72）与"连段会打断纳刀"的节奏约束；
  一文字 / 返刃（命中更快、空挥更慢，差 2.3 倍）/ 落月 / 断水（0.3s 绝对静止后极快横斩）；
  截锋奖励以**刀锋微光**表现而非 UI 增益条；三技能 纳息 / 燕返（空挥无第二段）/ 断章。
- **回风式**：四段链、命中才缩短恢复（`flow_on_hit_recovery 0.60`）、转向权 >2× 藏锋、Deflect 型防御。
- **聚合斩**保留为 **SIGNATURE**（移出 Ultimate 槽，独立冷却，演出未改动）。
- **无明一刻**为独立 Ultimate 原型：静默 → 单色 → 细线标记 → 一次几乎看不见的拔刀 → 纳刀 → CLICK → 同时激活。
  四个动画钩子独立产线，**不共用聚合斩资产**。
- **Technical Dummy** 变成测量仪器：电报环生效帧猝然闭合，可强制指定 Sweep/Heavy/Lunge，攻击 poise 让重击能打断玩家。
- **Combat Lab** 开发面板：即时切换流派、技能冷却、强制敌人攻击、Hitstop 三档（Off/Normal/Exaggerated）、Parry Timing Debug。

测试：**13 项 headless 集成测试全部通过**，其中 `moveset` / `parry_riposte` / `style` / `ultimate`
四项为本轮新增。（期间 `iaido_integration` 曾短暂变红，原因是 Iaido 演出线正在并行改动
`iaido_tear_3d.gd` 的 `_draw_drain()` 签名；战斗层未触碰该文件，Iaido 线改完后已自愈。）

已提交为 `59d983c`（40 files, +4415/−233），**只含战斗线文件**；Iaido 演出线、ART、AUDIO 的未完成改动未纳入。尚未 push。

**必须明确的边界**：以上全部为技术验证。用户验收标准里的
「阶段一：只用通用剑对 Dummy 打必须已经有趣」与「阶段二：切藏锋后不看 UI 就知道是另一把剑」
**尚未验收** —— 本环境 Godot 无可见窗口句柄，手感类验收只能由用户在可见桌面完成。
视觉仍为 `TempSwordVisual` 程序化姿态，**无手部、无骨骼动画**，需求见 `docs/COMBAT_ANIMATION_REQUIREMENTS.md`。

## 2026-09-27 · Iaido 演出逐帧渲染校验与修正

用真实 GL 上下文把整套 7.2 秒演出逐帧渲染出来（`godot/tools/iaido_movie_renderer.gd`，用 debug-hold 把时间轴钉在精确时刻，与帧率无关），再合成 MP4（`godot/tools/encode_iaido_movie.sh`，按同一时序混入占位音轨）。产物在 `F:\SEKAI\.render\iaido_signature_ceremony.mp4`，仅用于试玩前预审，不进版本库。

逐帧检查推翻了此前基于单帧静图的判断，修掉三个只有动起来才暴露的缺陷：

- **反向波在纯色场地里完全不可见**。折射只改变已有画面，而这个沙盒是纯色天空加纯白地板，没有内容可扭曲。现在压缩前沿自带自适应密度边（亮背景走暗带、暗背景走亮带，避免在白地板上过曝成能量圈），并把环半径衰减从末端陡降改成前段平缓，可见窗口从约 0.1 秒扩到整段。
- **虚空在窄缝时整条被蓝白核心填满**，读起来是发光管子。核心改为固定像素宽度的发丝，缝隙主体保持深蓝。
- **玻璃裂纹用的是 Voronoi f2-f1**，呈现规整六边网格；而且用亮线画在白地板上等于隐形。现在改为从斩线放射生长的分支（12 主 + 8 细，带游走与渐细尖端、随机止点），并按背景明暗自适应暗缝/亮边。

其它修正：新增 `ArenaDressing`（`godot/scripts/systems/arena_dressing.gd`，挂在 `CombatSandbox`）——确定性、无碰撞的占位场地。空旷沙盒里斩线两侧都是纯色，分离和切裂没有可作用的轮廓，既无法评估也无法试玩；这是占位，等 ART 线替换。玻璃碎片材质从亮蓝白改为暗蓝灰透明体加亮边，避免在亮场景里像纸片。

9 个集成测试全绿；`iaido_integration` 继续锁住总长 5–8 秒与停顿下限。

## 2026-09-24 · MVP 0.2/0.3 进展

- 现有项目继续沿用本地 `mvp02-first20min` 分支。MVP 0.2 体验审计、实时开场、引导、剑与魔法反馈、村庄/森林视觉调整已推进；完整 15–25 分钟陌生玩家通关验收尚未完成。
- Suno Pro 当日生成四组、每组两版，选用四首 MP3 接入 Opening / Village / Forest / Combat。记录见 `SUNO_LOG.md`，音源见 `ASSET_LICENSES.md`。
- MVP 0.3 已加入独立主菜单 Key Art、可继续的 v2 持续存档、自动存档与三个人工存档位、地点揭示和 HUD 视觉方向。刷新后 Continue、独立存档位读写通过浏览器可见测试。
- 声音管理已有 Master / Music / Ambience / SFX / UI / Voice 总线与初步河流、鸟鸣、打铁空间声；完整 SFX 清单和混音尚未完成。
- Chat2Blender 第一组模块化建筑件已经网页端 GPT-5.6 Sol → 可见 Blender → 12 个 GLB → 游戏内验收。流程见 `AGENT_CONSTITUTION.md` 与 `CHAT2BLENDER_LOG.md`。
- 桌面 `试玩SEKAI.cmd` 调用 `F:\SEKAI\play-sekai.ps1`，检查或启动本地服务器并打开浏览器。已实测脚本执行和 HTTP 200。
- 1080p Low/Medium/High 性能矩阵、完整流程和多浏览器 QA 仍待完成。不要把本阶段视为最终验收完成。

## 已完成的可运行原型

- Vite + TypeScript + Three.js Web 工程，能构建并通过预览服务运行。
- 标题、继续/新游戏、设置、暂停、读取、版本化本地存档。
- 程序化雾栖村地貌与生活布景，河流、桥、农田、竹林、森林、遗迹、五名 NPC 和三个古代构造体。
- 第一人称移动、冲刺、跳跃、蹲下、短闪避。
- 角色对话、获得剑与法杖、剑连击/重击/格挡/风切、火/冰/风三种基础法术、冻结后重击碎裂、隐藏符文与观察者伏笔。
- WebAudio 合成的基础交互/战斗提示音。

## 运行

`npm install` 后运行 `npm run dev`。若开发服务器在当前受限环境遇到依赖预构建权限错误，可运行 `npm run build` 与 `npm run preview`。

## 已知不足

- 本版是可交互原型，尚未达到原设定的 30 分钟高品质垂直切片验收。开场目前约 20 秒，缺少完整 60–90 秒镜头表演与角色动画。
- 室内空间暂未真正开放；物理碰撞、台阶与坡面处理、敌人招式与命中判定仍需升级。
- NPC 为程序化几何和简单位移动画；尚无正式骨骼动画、日程、手势与表情。
- 武器没有第一人称手部与模型动画；击打反馈、VFX、音乐、环境声还很简略。
- 未接入 Rapier；当前地面碰撞为简单高度约束。
- 尚未进行完整链路游玩、FPS 基准测试与跨浏览器 QA。

## 下一阶段

### 2026-09-24 续作进展

- MVP 0.3 的标题画、继续/载入、三个人工存档与自动存档、地点揭示、HUD、音量分组和四首 Suno 曲目已接入。
- ChatGPT → Blender → GLB 的雾栖村模块建筑流程已执行并记录；村东房屋已换为新模块。
- 植被已从均匀散布改为村口、河岸和森林的树丛片区，并使用实例化草木降低绘制调用。道路与关键场地保留空地。
- 桌面试玩入口和 F 盘启动脚本已建立。构建通过；完整 20 分钟链路与 1080p 低/中/高性能矩阵仍待验收。

1. 完成角色、手部、剑与法杖模型动画，打磨剑击、格挡、受击与 VFX。
2. 用 Rapier 建立可进入室内与可靠碰撞，扩建地形并优化实例与加载。
3. 补足 60–90 秒实时演出、原创音乐与环境声，并完整跑通 30 分钟体验。

## GODOT COMBAT MVP · 2026-09-27 · Iaido重新导演（Signature Skill）

- Iaido / 聚合斩已按 7.2 秒 Signature Skill 时间轴重排（PHASE A–N：世界静止 → 归鞘 → 三层反向波 → 压缩停顿 → 鞘锁 → 瞬斩 → 世界切开 → 分离 → 张力冻结 → 玻璃失效 → 双转剑 → 慢归鞘 → 现实崩解 → 回收恢复）。出刀只占 130ms，其余时长用于压迫感与期待。所有时间点集中在 `IaidoTuning.tres`，禁止擅自压缩。
- 世界切裂改为真正的 Void Gap：斜切线中间是深蓝→靛青→蓝白核心的虚空（雾、微粒、镜像不可能视差、极慢向内运动），两侧世界沿斩线法线缓慢分离；已删除"上半幅直接滑落"的 UI 错位表现，重力滑落只允许出现在玻璃破碎之后。
- 玻璃改为三层：着色器应力裂纹（Voronoi 细裂纹 + 分支随机停止 + 折射 UV 偏移）+ 新增 `IaidoGlassLayer` 前景独立 SubViewport 中的 8–20 片有厚度物理碎片（30–80ms 延迟、阻尼减速、悬停、恢复期倒放回吸）。
- 前景武器层保留；新增 `void_exposure` 冷色刃缘让剑在黑暗画面中保持可读并仍属于场景。
- 音频时间轴已建立：`IaidoAudioTimeline` 按 tuning 触发 14 个节点。Suno 本轮不可用，`godot/tools/generate_iaido_placeholders.py` 已合成占位音效并接入，后续只换文件不动时间轴。
- 相机在演出期间进入 `iaido_still`：步频 bob、sway、微震全部衰减到零，与战斗形成反差；Iaido FOV 不再受相机预设影响。
- Developer Panel（F8）新增 Iaido Timeline Scrub 滑块、12 个阶段跳转按钮与 0.25x/0.5x/1.0x/2.0x 速度。
- Fail-safe：`finish_iaido` / `_exit_tree` 全量恢复 FOV、饱和度、世界暂停、音乐、前景层、裂口、虚空、玻璃与相机；`tests/iaido_integration.gd` 现在校验时间轴长度、静止站位、延迟命中、调试跳转与全量恢复。全部 9 个集成测试通过。
- 已知限制：视觉与手感仍未做人工试玩验收；Iaido 冷却改为 `restore_end + 2.0s`（演出全程 + 后摇）。

## GODOT COMBAT MVP · 2026-09-27

- TEMPORARY RENDERER FALLBACK: Forward+ on this AMD Radeon RX 6650 XT shows 2D UI/background but not 3D meshes. Compatibility restores the independent RenderProbe and Main → Start combat capture. Interactive desktop click and gameplay feel remain pending. See `BLACK_SCREEN_DIAGNOSIS.md`.

- Godot version: 4.4.1 Stable, Forward+, GDScript.
- Branch: godot-combat-mvp, based on origin/main 5c2d4c409b53a27a597193c0c807f3138c2cea1a. For the current development commit, run `git rev-parse HEAD`.
- Migration: official full Git clone verified; reviewed Godot files moved from the isolated temporary workspace into /godot. Legacy Web prototype remains intact.
- Boot/Menu Gate: IMPLEMENTED and TECHNICALLY VERIFIED for main menu → combat sandbox → pause → settings → title → restart. Visible desktop and human interaction remain unverified.
- Movement Gate: IMPLEMENTED and TECHNICALLY VERIFIED; NOT VISUALLY VERIFIED or GAMEPLAY VERIFIED. WASD, sprint, jump, mouse look and dodge exist; feel remains untested.
- Camera Feedback: Normal, Exaggerated and Off presets are IMPLEMENTED and TECHNICALLY VERIFIED with fixed-input runtime output; F8 developer panel can cycle them. Visual readability and feel are pending interactive acceptance.
- Sword Gate: IMPLEMENTED and TECHNICALLY VERIFIED for Area3D light combo, heavy, block and buffered cancel. A TEMP primitive first-person sword (blade, guard, grip) is VISUALLY VERIFIED in recorded idle and light-swing frames; formal Chat2Blender asset and hands remain pending. NOT GAMEPLAY VERIFIED.
- Magic Gate: IMPLEMENTED and TECHNICALLY VERIFIED for Fire burn/damage, Frost freeze, Wind push/stagger. Native combat HUD and Tab element wheel now select the ability used by E cast, with time restored on release. MagicCircle3D is VISUALLY VERIFIED in a recorded frost-cast frame after reducing its radius and moving it fully inside the first-person view. The wheel remains a technical visual placeholder; magic feel is NOT GAMEPLAY VERIFIED.
- Shatter Gate: IMPLEMENTED and TECHNICALLY VERIFIED through an Area3D physics integration check. Shatter now triggers a reusable shard effect, camera impulse, screen flash, and centralized 85 ms hitstop; visual and sound quality remain unverified. NOT GAMEPLAY VERIFIED.
- Iaido Gate: technical sequence IMPLEMENTED and TECHNICALLY VERIFIED for physical step, active-frame delayed hit, time/FOV/screen state restoration. Spatial tear, sound and visual rhythm are incomplete; NOT VISUALLY VERIFIED or GAMEPLAY VERIFIED.
- Enemy technical gate: three Area3D attack patterns (sweep, charged heavy, physical lunge) cycle with separate anticipation and active windows; automated physics check passed. Pose/color cues are coded, but sound cues and visible telegraph readability remain pending.
- Audio: existing Suno Pro track `first-encounter.mp3` is reused in the Godot sandbox on a Music bus. Scene import, playback startup, title/restart and resource cleanup passed technical checks. Combat SFX remain pending; the cue/layer production brief is in `COMBAT_SFX_BRIEF.md`, while existing music provenance is documented in `ASSET_LICENSES.md` and `SUNO_LOG.md`.
- Known bugs/limits: this execution environment starts Godot processes without visible window handles; therefore visual and hand-feel acceptance cannot be claimed. Technical enemy is a primitive test target, not the designed Lesser Ruin Sentinel. Combat SFX are pending.
- Next immediate step: run editor import and physics integration checks in the official branch, then commit and push the stable technical foundation. Continue enemy telegraphs, audio and visual validation when a visible desktop path is available.

## PRODUCER · 三对话并行 · 2026-09-27

Producer / Integration 角色启动，建立三条工作流的共享状态。

- 新增 `docs/PRODUCTION_BOARD.md`：MAIN / AUDIO / ART 三线任务板，是唯一权威状态源。三条对话改状态必须写回该文件，不得依赖聊天记忆。
- 新增 `docs/ART_PIPELINE.md`：Chat2Blender 固定产线、角色边界、状态机、目录所有权。
- 新增 `docs/AUDIO_STATUS.md`：13 个 iaido 占位音的实测时长、峰值、rms 与触发点台账。
- 新增 `docs/asset_briefs/C2B-02 / C2B-03 / C2B-04`：FP Hand、Lesser Ruin Sentinel、Magic Catalyst。C2B-01 brief 此前已存在，本次补 `C2B-01-CHATGPT-PROMPT.md` 可直接粘贴的提交包。

### 实测结论

- Iaido 时间轴 15 个 cue 与 `IaidoTuning.tres` 全部对齐，无断链；13 个 wav 均存在。
- 13 个 wav 全部 peak 0.898，来源为 `godot/tools/generate_iaido_placeholders.py` 合成占位音。Suno signature 一个都未替换。AUDIO 线的真实状态是"时间轴就绪、素材未产"，不是"音效完成"。
- `collapse` cue 在 6.25 s 触发、素材长 1.25 s，结束于 7.50 s，超过 `restore_end` 7.20 s，会被 `finish_iaido()` 的 `stop_all()` 硬截断。替换素材时长度须压到 0.95 s 以内。
- `void_open` 3.40 s 起持续 1.60 s，覆盖 `glass_stress`(4.25) 与 `shard_burst`(4.58)。替换时需分层让位或缩到 1.2 s 以内。

### 技术债（MAIN）

- `godot/scripts/player/temp_sword_visual.gd` 的 `CombatController.State.IAIDO` 分支引用 `timing.focus_start`、`focus_end`、`draw_slow_end`、`draw_fast_end`、`recovery_end`，这些字段在重构后的 `IaidoTuning` 中已不存在。该分支因 `_process` 开头 `if combat.state == IAIDO: return` 而永不执行，属于死代码。武器姿态实际由 `IaidoDirector._apply_weapon_pose()` 接管。应删除该分支，避免后续误改。

### 未提交改动

已清空。MAIN 于 2026-09-27 将 7.2 秒 Iaido 全序列落成两次提交并推送：`c485aeb`（前置铺垫：前景武器层、world pause manager、Chat2Blender 工具、C2B briefs）与 `8c71561`（Iaido 7.2s 签名演出 + 蓝虚空 + 玻璃层 + 13 个占位音）。远端 `godot-combat-mvp` 现为 `8c71561`。

推送通道说明见 `PRODUCTION_BOARD.md` 环境备注：沙箱代理封锁 `github.com`，需走本机 v2RayN SOCKS5（`127.0.0.1:10808`）。

## NARRATIVE · 开线 · 2026-09-27

NARRATIVE / WORLD BUILDING 线启动，与 Combat Sandbox 并行，**不等待战斗完成**。文档全部落在 `docs/narrative/`。

- **审计**：对全仓叙事设定做了一次彻底对账（Web 原型 / Godot / docs / 资产 / 音频命名），结论与命名裁决写入 `WORLD_BIBLE.md` §0。裁决：区域 = **雾谷 Mistvale**、据点 = **雾栖镇**（不再用"雾栖村"）、森林 = **雾谷东林**（其中片区**青竹林**）、敌人族 = **遗迹哨兵**（民间称"古代构造体"，`Technical Dummy` 只是开发占位名）、**信标（装置）+ 观察者（通过信标看世界的东西）**。
- **V0.1 文档**：`WORLD_BIBLE.md`（魔法=理解性质；三种剑=信息/位置/距离；历史悬念只留三件物证）、`MISTVALE.md`（空间 0–9 段 + 三股力量 + 三条独特文化）、`CHARACTERS.md`（7 位 Act I 人物 + 1 影子角色）、`MAIN_STORY.md`（Prologue / Act I 节点 1–12 / Day 10 Anchor 六种状态 / 60 分钟表）、`STYLE_GUIDE.md`（禁用 AI 套话、命名规则、文案标准）。
- **纪律**：本阶段**不写完整对白**，先钉"世界为什么这样运转"。骨架冻结后再进 dialogue pass，避免世界观一改全部报废。
- **未决**：`COMBAT_DESIGN.md` 与 `moveset_library.gd` 不同步（折柳/惊鸿/长风三段已实现、文档写未实现），请 MAIN 回写；Narrative 现按已实现为准。

### NARRATIVE PASS 02 · 可玩故事骨架

从"世界 Bible"进入**可玩 Act I 场景骨架**，仍然**不写完整对白**（只写 scene purpose / intent / 信息给出 / 情绪转折 / 台词碎片）。

- 三项裁决正式通过并落地：**莉娅**不做引导（天亮前出船、白天在河上，玩家第一次到渡口可能只见一条离岸的船）；**Soul Echo** Act I 严格两次（① 钟塔旧记录 ② 一句被 NPC 自己否认的口误）；**魔法升格为世界底层规则**（火=转化 / 霜=停滞 / 风=动量，渗进生活、生产、交通、职业、教育、宗教；每种性质 3 个生活应用）。
- 新增 `docs/narrative/ACT1_BEATS.md`：Prologue beat sheet **P0–P6（15–25 分钟）**、**Arrival A1–A7**、Act I 任务脊椎 **Q1–Q7**、ECHO-01/02 场景规格、**FA-01**（原 Day 10，不与日历绑定）完整设计（信号阶梯 4 级 / PATH A·B·C / 五条硬性要求 / 6 条持久后果）。
- 新增 `docs/narrative/RELATIONSHIPS.md`：关系矩阵（公开关系 / 真实态度 / 过去事件 / 潜在冲突）+ 新增两个配角（**鲁斯克** 公会负责人、**泰姆** 赶车人）+ 作息表 + FA-01 后的关系变化触发器。
- `WORLD_BIBLE.md` 新增 §9 连续性规则（**代码为准**；prototype/experimental 不写 Lore；DOCUMENTATION DEBT 清单）；`CHARACTERS.md` 新增初次相遇设计；`MISTVALE.md` 新增 §8 魔法生活痕迹。
- 请求已编号并进板：`NAR-ART-01/02/03/04`、`NAR-AUDIO-01/02`、`NAR-MAIN-01/02`。
- **下一步**：交 DESIGN / MAIN Review，确认可实施为 Narrative Vertical Slice。**通过前不推进 Act II、不开始 Dialogue Pass。**

### NARRATIVE PASS 03 / 04 · 可实施叙事 + 槽位回填

PASS 03 已产出 `NARRATIVE_VERTICAL_SLICE_N01.md`（Scene Spec P00–P06 / A1–A7、8 个 Dialogue Scene、Readable R-01·R-02、16 条环境对白、Cluster 五状态、VO 11 句、分钟级 Playthrough）与 `NARRATIVE_STATE_V01.md`（flag / INFORMATION GRAPH F1–F10 / HARD vs SOFT / MISS MATRIX / 最小存档结构）。
**ECHO-01 采纳方案 EC**：钟塔「无主物拾得登记」里三年前一条记录，描述玩家身上那枚未被任何人见过的铜扣 + 一截不属于衣服的短带，登记人未署名；薇尔只说"这行没署名。不对。"。EA / EB（写玩家名字 / 直接描述本人）**已淘汰**——它们会让 Act I 变成"天选之子"。

PASS 04 **顺序调整**（提前于 MAIN Review）：ART 的 `docs/LD-01-MISTVALE-REGION-MASTERPLAN.md` 已把 `NAR-01..07` + 22 个微叙事槽位的位置留好并写明「文案填内容，地编保位置」，回填是时间敏感的，因此先交付：

- `MICRO_NARRATIVE_SLOTS.md`：NAR-01..07 内容 + **22 槽位逐条**（是什么 / 读到什么 / 形态 / 可错过）+ 4 个 Readable（R-03..R-06）。规则：**槽位不弹提示、90% 纯视觉、全部 SOFT、不写答案**。
- `ACT1_QUESTS.md`：**无 XP / 无等级**，奖励只有钱 / 住处 / 担保 / 路线知识 / 一句信息；MQ-C 五状态机；`took_cart_blade` 在 C2 造成"记录与事实"的第一次裂缝；五条支线（S-01 屋顶 / S-02 今天不冷 / S-03 河西·第三日 / S-04 木桩不算任务 / S-05 被划掉的那一行）+ 模板黑名单 + 11 个 flag 增量 + MAIN 实施顺序 6 步。
- `DIALOGUE_PASS_02.md`：第二层 6 场 + **三条能力入口（藏锋 / 回风 / 魔法，不规定顺序，只给动作不给招式名与理论）** + 环境对白 Pass 02（18 条）+ VO 增量 11 句。

**一条顺序硬约束**：S-05 必须先于 ECHO-01 可被遇到——薇尔得先变成"关心记错了"的人，才会在三年前那行前皱眉。做反了 ECHO-01 白写。

### NARRATIVE PASS 05 · FIRST DAY / FIRST NIGHT / SECOND MORNING

停止扩张世界设定，改为向下深化——**玩家今晚睡哪，明天为什么还愿意留在这里**。

- `ACT1_QUESTS.md` V0.2（§10–§20）：三条主线程 A 立足 / B 商队事故 / C 人 + 交叉表；**THREAD B 明确"不是任务"**（无条目、无日志、无完成态，全靠别人随口的话拼起来）；**第一天节奏表**（进镇 → 白天 → 傍晚 → 第一夜 → 第二天早晨）；第一夜**只有声音、没有演出**；第二天三个必做变化（消息传开**且走样** / 北门关得早 / 空摊位还空着）；四条新支线 **S-06 渡口的活 / S-07 炉子不听话 / S-08 少了一件 / S-09 有人要一封信**；**FA-01 信号网络 8 个 × 6 渠道**；四条 NON-FAILURE FAILURE；**Readables V0.2（R-07..R-11 全文）**；Paper Playtest V0.2（0–120 分钟）。
- `DIALOGUE_PASS_02.md` V0.2（§11–§22）：新增 **D15–D22 八场**正式对白 + **第一次能力习得三条入口**（E1 藏锋 / E2 回风 / E3 性质，共同结构：发生一件事 → 演示 → 练 → **失败** → 一句不是理论的话 → Unlock）+ 18 条 bark + **VO-023..034** + 关系纹理映射。
- `INFORMATION_GRAPH.md`（新）：**玩家知识 K001–K017** + **NPC 信息差表** + **关系纹理**（不是好感度）。
- `CHARACTERS.md` §14 DAILY PRESENCE：9 位角色的日常在场；**奥伦三层认识**没有任何 NPC 告诉他。
- `MISTVALE.md` §11–§14：本地文化六问 + 空间叙事层（9 区密度 3→0，**四处必须安静**）+ `NAR-AUDIO-10..17` + UI TEXT SPEC。

**两条新硬约束**：`day_index` 只能是 0 或 1（睡一次，不做日历 / 不做第三天）；**第一夜不弹任何休息 UI、不放过场、不给"新的一天"大字**。

## COMBAT · 战斗矩阵第一版 · 2026-09-27（COMBAT 会话）

本轮把"一个流派 + 一把剑"扩成 **Universal + 藏锋 + 回风（可玩）+ 白蔷庭（早期）+ 火 / 冰 / 风 + 五种剑 × 魔法交互**，并交付了第一条 **SEKAI Combat Matrix**。

### 交付

| 项 | 内容 |
| --- | --- |
| 回风式补齐 | 势(Flow) 内部值（**不加伤害**，只买恢复/转向/衔接）、流云、折柳（`SwordSkill.Kind.SLIP`，让攻击落空）、惊鸿、**长风**三段（`player_aimed` + `followup_from_start`，玩家定向、不锁动画） |
| 白蔷庭 Prototype | **Measure**（正前方 55° 锥内 `combat_target` 分组最近者，三档：close / ideal / far → 起手、伸距、姿态变化，**零伤害加成**）、三段短链（第三式**回接第一式**，命中才开）、重击 **穿庭**（短起手 + 长伸距）、防御 = **缠剑**（完美格挡不弹开、不侧移，0.30s 三岔：轻=合围刺 / 重=脱手斩（负 lunge）/ 闪=侧步）、技能 **假章**（`feint_cancel_from`，唯一在 startup 内开出口的字段）与 **白蔷刺** |
| 元素数据层 | `ElementDefinition` / `ElementState` / `ElementField` / `ElementLibrary`。**敌人里已无 `if element == ...`**；三系定义为**共享单例**，改 definition 行为即变 |
| 魔法层 | `SpellDefinition` / `MagicSchool` / `MagicLibrary`，三系各 2 法术，数值与原 `.tres` 对齐 |
| 五种交互 | Shatter（参考组）/ 风吹撞墙 / 风扩火场 / Frosted + 断水 = Brittle Break / 风步喂势 |
| 环境占位 | `WindProps`：一面墙 + 2 个可推 `RigidBody3D`，`blow()` 真施加冲量 |
| Combat Lab | 升级为 **style × magic × enemy state × environment 矩阵**（F8） |
| 藏锋 P2 | 只做 **loop polish**：完美格挡（截锋）免除归鞘前摇（`guard.parry_sheath_waiver = 1.2`）。**未加任何新招**，并有测试钉住这一点 |
| 第四剑术 坠星式 | **仅设计**（`COMBAT_DESIGN.md` §10），不实现 |

### 测试

- **18 项 headless 集成测试全部通过**。本轮新增：`element_magic_integration`、`white_rose_integration`、`combat_lab_integration`、`hidden_edge_loop_integration`。
- 新增的断言都是**行为性**的，不是数值性的：
  - 元素：改 definition 行为必须跟着变（"规则即数据"）；三系必须**结构上**不同（火无阶梯有 DOT、冰四阶、风按重量）；风必须能真推物体并撞墙。
  - 白蔷：Measure 在三个距离上**伤害完全相同**但起手/伸距/姿态不同；第三式命中才续链；假章的出口**在自己的起手之内**打开而真招不行；缠剑三岔各自的出口，以及窗口关闭后 Heavy 必须退回普通重击。
  - Lab：4 流派 × 3 元素**全排列**；敌人状态预设走真实 `_on_hit`；墙体距离必须在一推可达范围内。
  - 藏锋：截锋必须**真的**让归鞘提前，且豁免不得泄漏到其它流派。
- **稳定但非确定**：`combat_music_integration` 连续快速重跑时偶发退出即段错误（rc=139），判定仍为 PASS；单跑 3/3 rc=0。属 headless 音频设备关闭竞态。

### 本轮修掉的真问题（不是测试凑数）

1. `ElementLibrary` 每次调用都新建 definition → "唯一书写处"是假的，且每击都在分配资源。改为**共享单例**。
2. `WindProps.blow()` 未压平方向 → 低头瞄准会把阵风打进地板，**俯仰角悄悄变成风的强度乘数**，且与敌人 `_push_from`（本就水平）不一致。
3. Combat Lab 的 `wind_props` 用 `@onready` 解析 → 子节点先于父节点 `_ready`，**整个环境区是死的**；改为使用时解析。
4. `moveset_integration` 的"riposte 窗口必须 0.5–0.9s"规则与缠剑设计冲突 → 给绑剑流派留**显式例外**（0.2–0.4s），而不是把白蔷硬掰成别的流派。
5. 藏锋的 `guard_recoil` 只有 0.31s 生命（是镜头量），最初拿它当归鞘豁免的判据不合适 → 改为 guard 上的独立时长 `parry_sheath_waiver`。

### 未验收（诚实标注）

- **所有"是否有趣"的验收都没做，本环境 Godot 无可见窗口句柄**：阶段一（通用剑）、阶段二（换流派可辨）、回风"为不断势而主动跑"、白蔷"主动控制距离"、三系"只看行为能否分辨"，全部需要**动起来看**。
- 动画：无手部、无骨骼动画（`TempSwordVisual` 程序化姿态）。本轮新增需求见 `COMBAT_ANIMATION_REQUIREMENTS.md`。
- 音效：`COMBAT_SFX_BRIEF.md` Priority A / A2 / D / E 全未落地；本轮新增 **Priority F（元素行为音层）** 与白蔷庭 10 个 cue。
- 环境：`WindProps` 是程序化盒子，ART 可整体替换网格。

### 对账

- 本会话**未** `git add -A`，只暂存战斗线文件；Iaido 演出线 / ART / AUDIO 的未提交改动仍留在各自工作区。
  本轮提交 = **`b33a12f`**（41 files, +3798/−154），**仅战斗线**。ART 的 `ENV-01` 行（`SPEC READY → IN GODOT`）**保持未暂存**，由 ART 自己发布 —— 每条线只发布自己那一行。
- **未 push**：提交后本地领先远端 1 个提交（提交前 `godot-combat-mvp` = `origin/godot-combat-mvp` = `282e9eb`）。推送渠道是本机 v2RayN SOCKS5，是否推交由 MAIN / 用户决定。
- 为注册 8 个新 `class_name` 跑过 1 次 `--editor --quit`。**该次之后 `IaidoTuning.tres` 的 md5 未变**（`d8437620…`），此前记录过的 `.tres` 重写与 import 之间不是稳定因果。**Iaido 线请自行确认当前 diff 是否是自己的意图。**
- 下一步：把"任何一行 × 任何一列"在可见桌面上跑一遍（`F8` → 切流派 → 切法术 → 切敌人状态 → 就位撞墙），
  先回答 §53 的五个自问，再谈平衡数值。
