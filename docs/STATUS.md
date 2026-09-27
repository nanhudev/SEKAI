# SEKAI MVP 0.1 状态

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
