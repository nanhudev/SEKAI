# SEKAI MVP 0.1 状态

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
