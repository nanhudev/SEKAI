# SEKAI PRODUCTION BOARD

三线共享状态。任何对话改了状态必须写回本文件，不能依赖聊天记忆。
路径根：`F:\SEKAI` · 分支：`godot-combat-mvp` · Godot 4.4.1

状态值：`TODO` `DOING` `BLOCKED` `REVIEW` `DONE`
资产状态值：`REQUESTED` `SPEC READY` `GENERATING` `BLENDER RUN` `VISUAL REVIEW` `FIXING` `EXPORT READY` `IN GODOT` `IN-GAME VERIFIED`

DONE 定义（不满足不能标 DONE）：
- MAIN：technically verified + gameplay verified
- AUDIO：integrated + auditioned in game
- ART：GLB integrated + visible in Godot

---

## A · MAIN PROJECT

Godot / Gameplay / Combat / Camera / UI / VFX / Save / Git / Testing

| 任务 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- |
| Boot / Menu / Pause gate | P0 | REVIEW | TECH VERIFIED；桌面可见交互未验收 |
| Movement（WASD/sprint/jump/dodge） | P0 | REVIEW | TECH VERIFIED；手感未验收 |
| Running camera feedback | P0 | REVIEW | 三档预设 + F8 面板；可读性未验收 |
| Sword combo / heavy / block | P0 | REVIEW | TECH VERIFIED；视觉已换真剑（10,378 tris · `Sword_FP.tscn`），不再是三方块 |
| Perfect Guard | P0 | REVIEW | 窗口 0.12s（原 0.18s 已收紧）；音效未接入 |
| Universal single-sword language | P0 | REVIEW | **18/18 集成测试绿**；手感未验收 · 见 `COMBAT_DESIGN.md` |
| Guard → Perfect Guard → Riposte 闭环 | P0 | REVIEW | 窗口/后坐/微光奖励已实现；音效未接入 |
| 藏锋流 Hidden Edge 原型 | P0 | DONE | 纳刀/拔刀红利 + 8 招 + 三技能。本轮 P2 只做 **loop polish**（截锋 → 立刻归鞘），**未加新招** |
| 回风式 Flowing Wind 原型 | P1 | **DONE** | 四段链 + 势(Flow) + 流云/折柳/惊鸿 + 长风三段（玩家定向）。`flowing_wind_integration` 绿 |
| **白蔷庭剑术 White Rose Prototype** | P1 | **REVIEW** | Measure（无资源条）+ 三段短链 + 穿庭 + 缠剑三岔 + 假章/白蔷刺。`white_rose_integration` 绿；手感未验收 |
| **元素数据层（ElementDefinition / State / Field / Library）** | P0 | **DONE** | 敌人里已无 `if element == ...`；改 definition 行为即变（`element_magic_integration` 断言）。三系实例为共享单例 |
| **魔法层（SpellDefinition / MagicSchool / MagicLibrary）** | P0 | **DONE** | 火/冰/风各 2 法术，数字与原 `.tres` 对齐；能力轮盘不再 segfault |
| **剑 × 魔法 5 种交互** | P1 | **DONE** | Shatter（参考组）/ 撞墙 / 风扩火场 / Frosted+断水 / 风步喂势 |
| **风的环境（墙 + 轻物）** | P1 | **PLACEHOLDER** | `WindProps` 程序化：一面墙 + 2 个可推 RigidBody。ART 可换网格，物理角色必须保留 |
| 聚合斩重分类为 SIGNATURE | P0 | DONE | 移出 Ultimate 槽，独立冷却；演出未改动 |
| 无明一刻 Ultimate 原型 | P0 | REVIEW | 独立资产，不共用聚合斩；动画钩子待 ART |
| Combat Lab 开发面板 | P0 | **DONE** | 现在是 **style × magic × enemy state × environment 矩阵**；预设走真实 `_on_hit` 路径（`combat_lab_integration` 绿） |
| Magic / Ability Wheel | P0 | REVIEW | 火冰风已验证；轮盘是技术占位 |
| Shatter | P0 | REVIEW | Area3D + shard + 85ms hitstop；音画未验收 |
| **第四剑术 坠星式** | P3 | **DESIGN ONLY** | `COMBAT_DESIGN.md` §10。**不实现** —— 藏锋若已覆盖"重"，它就是第四种换皮 |
| Iaido 7.2s 张力序列 | P0 | REVIEW | 14 phase 全实现；音频为占位合成 |
| Enemy telegraph / AI | P1 | TODO | 现为 technical_dummy，非 Lesser Ruin Sentinel |
| Iaido 5–8s Cinematic Tension Pass | P0 | REVIEW | 已到 7.2s，超出目标区间上限；待视听验收后再谈压缩 |
| Git：提交本轮未落地改动 | P0 | DONE | 已由 MAIN 提交并推送：`c485aeb` + `8c71561`（7.2s Iaido 全序列）。远端 `godot-combat-mvp` = `8c71561` |
| `NAR-MAIN-01` 可复用 `Readable` 阅读物 | P1 | REQUESTED | 看向纸/书/登记簿 → Interact → 可阅读 → 关闭。第一版不做书籍系统；ECHO-01、货单、告示、信件、日记共用 |
| `NAR-MAIN-02` 雾的可视距离 + 南岸"回不去"暗示 | P2 | REQUESTED | 让"晚上不出门"成为体感；用塌方/水涨代替不可见墙 |
| 回写 `COMBAT_DESIGN.md`（DOCUMENTATION DEBT） | P2 | **DONE** | 已补 §5 回风 / §6 白蔷庭 / §7 元素三系 / §8 五种交互 / §9 战斗矩阵 / §10 坠星式；旧 §7–15 顺延为 §11–19 |

### 战斗线验收现状（COMBAT 会话 · 2026-09-27）

- **技术验证通过**：**18 项 headless 集成测试全部绿**。本轮新增 3 项：`element_magic_integration`（三系行为差异 + 规则即数据 + 5 种交互）、`white_rose_integration`（Measure 给手感不给伤害 / 缠剑是选择）、`combat_lab_integration`（4 流派 × 3 元素全排列）。另有 `hidden_edge_loop_integration` 把 P2 的藏锋循环钉住。
- **已提交**：`59d983c`（通用剑语言层，40 files）、`cd4cbad`（回风 Prototype）。本轮（元素数据层 + 魔法层 + 白蔷庭 + Combat Lab + 文档）单独一个提交：`b33a12f`（41 files, +3798/−154），**仅含战斗线文件**。
- **纪律**：本会话**未** `git add -A`。Iaido 演出线、ART、AUDIO 的未提交改动仍留在各自工作区。
- **交互验收未完成**：字面意义上的"是否有趣"仍未验收 —— 阶段一（通用剑）、阶段二（换流派可辨）、回风"为不断势而主动跑"、白蔷"主动控制距离"、三系魔法"只看行为能否分辨"，**全部需要动起来看**。headless 只能证明逻辑正确。
- **`--editor --quit` 副作用（需对账）**：本会话为注册 8 个新 `class_name`（`WindProps` / `ElementField` / `MagicSchool` / `MagicLibrary` / `SpellDefinition` / `ElementDefinition` / `ElementState` / `ElementLibrary`）跑了 import 一次。**本轮该次 import 后 `IaidoTuning.tres` 的 md5 未变**（`d8437620…`，与 import 前一致），说明此前的 `.tres` 重写与 import 之间不是稳定因果。**Iaido 线请自行确认 `IaidoTuning.tres` 的当前 diff 是否为你的意图。**
- **稳定但非确定**：`combat_music_integration` 在连续快速重跑时偶发退出即段错误（rc=139），**判定仍为 PASS**，单跑 3 次全 rc=0。属 headless 音频设备关闭竞态，非回归。
- 视觉当前为 `TempSwordVisual` 程序化姿态 + 刀光，**无手部、无骨骼动画**；需求见 `docs/COMBAT_ANIMATION_REQUIREMENTS.md`。

阻塞原因：本环境启动 Godot 无可见窗口句柄；AMD RX 6650 XT 上 Forward+ 黑屏，已回退 Compatibility（见 `BLACK_SCREEN_DIAGNOSIS.md`）。所有 gameplay verified 必须在用户可见桌面上完成。

### 环境备注：git push 通道

沙箱默认 HTTP 代理对 `github.com:443` 返回 502（`api.github.com` 正常），因此直接 `git push` 会失败。可行通道是本机 v2RayN SOCKS5：

```bash
export GH_TOKEN=$(gh auth token)
git -c http.proxy=socks5h://127.0.0.1:10808 \
    -c credential.helper= \
    -c credential.helper='!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f' \
    push origin godot-combat-mvp
```

`gh` 当前登录账号 `y13077816460-eng` 对本仓库有 push 权限；本机 SSH key（`nanhuyiqiu`）无该仓库写权限，不要用 SSH 通道。

---

## B · AUDIO

Suno / SFX / 裁切 / 分层 / FFmpeg / Godot 总线 / 战斗时序

| 任务 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- |
| Iaido 时间轴 15 cue 接入 | P0 | REVIEW | 已对齐 IaidoTuning，无断链；素材为占位 |
| 占位合成音替换（Suno） | P0 | TODO | 13 个 wav 全部 peak 0.898，见 `AUDIO_STATUS.md` |
| Signature SFX：Reality Cut / Blue Void / Collapse | P0 | TODO | Suno 未生成 |
| Basic atoms：metal / air / cloth / glass / stone | P1 | TODO | 需自建可复用库 |
| Sword / guard / perfect guard SFX | P0 | TODO | `COMBAT_SFX_BRIEF.md` Priority A 全未落地 |
| Guard 闭环补充（`guard_hold`/`guard_break`/`riposte`/`blade_glint`） | P0 | TODO | `COMBAT_SFX_BRIEF.md` Priority A2 |
| 流派辨识音（藏锋 / 回风） | P1 | TODO | `COMBAT_SFX_BRIEF.md` Priority D；不看 UI 也能分辨流派 |
| 无明一刻 8 cue（含 `mom_click`） | P0 | TODO | `COMBAT_SFX_BRIEF.md` Priority E；与聚合斩 cue 严格分开 |
| 元素 SFX（火/冰/风/shatter） | P1 | TODO | `COMBAT_SFX_BRIEF.md` Priority B —— **已被 Priority F 取代/扩展，见下** |
| **元素"行为"音层（Priority F）** | P1 | TODO | `mag_burn_loop`（必须不规则）/ `mag_frost_stage` 三声 / `mag_shatter` 两段 / `mag_wind_light` vs `mag_wind_heavy`（同输入不同结果，是本元素的论点）/ `mag_wall_impact` |
| **白蔷庭辨识音（Priority D 扩展）** | P1 | TODO | 10 个 cue，含 `wr_bind_lock` / `wr_bind_thrust` / `wr_bind_disengage`。**硬约束：`wr_jiazhang_read` 前 200ms 必须与 `wr_chuanting_drive` 同源**，否则假章会被听出来 |
| **回风补齐（Priority D 扩展）** | P1 | TODO | `fw_zheliu_slip`（必须听起来像"攻击落空"而不是"挡下"，否则折柳失去身份）/ `fw_changfeng_a/b/c` |
| **藏锋 loop（Priority D 补充）** | P2 | TODO | 截锋之后立刻归鞘的那一下 `he_sheathe` 会**更早**触发；P2 只改了时序，未加 cue |
| BGM | P2 | DONE | 4 首 Suno 已接入（Web 原型期） |
| `NAR-AUDIO-01` 第五次钟声 | P1 | REQUESTED | 独立音型，但**不要"恐怖片第五声"**——只是让细心玩家觉得节奏不太对 |
| `NAR-AUDIO-02` 遗迹方向夜间极低频 | P1 | REQUESTED | barely audible：玩家应该不确定那是风，还是别的东西 |

---

## C · ART & MODELING

ChatGPT Web → Blender Python → Blender MCP → GLB → Godot

> **英雄武器线的例外（用户 2026-09-29 指令）**：`# 这一批资产不要走 GPT / Chat2Blender` / `# DIRECTLY MODEL IN BLENDER`。
> 武器家族由 `tools/blender/wpn_<fam>_build.py` 在 headless Blender 里**直接建模**，`weapon_common.py` 出契约/断言/导出。流程仍是
> `BLOCKOUT → SILHOUETTE REVIEW → SECONDARY FORM → MATERIAL PASS → DETAIL PASS → BLENDER RENDER → CRITIQUE → FIX → GODOT → IN-GAME REVIEW → FIX AGAIN`，
> **≥2 次视觉迭代**；`BUILD FEWER. BUILD BETTER. ITERATE HARD.`

| 资产 | ID | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| First Person Sword | C2B-01 | P0 | **DONE · 待用户手感验收** | 真剑已入 `godot/models/weapons/fp_sword.glb`（**10,378 tris**，AABB 1.0570 × 0.0777 × 0.0697，4 材质）。**换模型未动位置与技能**：作为子节点挂进 `TempSwordVisual`，`Player.tscn` 一行未改，`SwordHitbox` 仍是 `(0, −0.2, −1.4)` / `1.4×1.2×1.6`。训练场武器架摆出货本体。见 `HERO_ASSET_REPORTS.md` W01 |
| First Person Saya（剑鞘） | C2B-01b | P0 | **几何 DONE · PASS 2 待做** | 803 mm，膛内衬 790 mm；鞘口 x −3.405 对齐剑护手 x −3.400，刃 47.3 × 8.0 整根在膛内**不穿模**。金具/栗形/口沿磨损仍是 blockout。见 `HERO_ASSET_REPORTS.md` W02 |
| Star-Bind Chain · 柄 / 链节 / 三叉刀头 | C2B-01c | P0 | **英雄模型 DONE（3 件）· 未入 Godot** | 柄 0.2805 m / 1624 tris；链节 0.09110 × 0.06013 × 0.01367 m / 320 tris（与 `stow_diag.gd` 闭式逐位一致）；三叉头 0.7800 m / 1096 tris。三件均通过 `ASSERT` + `verify_glb`。**手持束 `HELD_ARC_A..D` 未开始**，被 REQ-9 挡住（要 COMBAT 先发 `visible` + `release 0..1`）。三件均**未做 IN-GAME REVIEW**。见 `HERO_ASSET_REPORTS.md` W03 · `docs/weapons/CHAIN_ASSET_DECOMPOSITION.md` |
| FP Hand / Forearm | C2B-02 | P0 | SPEC READY | brief 本次补写 |
| Lesser Ruin Sentinel | C2B-03 | P0 | SPEC READY | brief 本次补写 |
| Magic Catalyst | C2B-04 | P1 | SPEC READY | brief 本次补写 |
| World Beacon | C2B-05 | P2 | TODO | Combat MVP 之后 |
| Adventurer Guild | C2B-06 | P2 | TODO | 同上 |
| Mistvale Stair / Terrace Kit | C2B-07 | P2 | TODO | 同上 |
| Town Props | C2B-08 | P2 | TODO | 同上 |
| Oren / Mira 人物 | — | P2 | TODO | Tripo / Hunyuan3D 候选，Rig 不阻塞 |
| Sword Pose Anchors ×5（Idle/Guard/Sheath/HeavyWindup/Sprint） | C2B-09 | P0 | REQUESTED | 招式动画的前置；锚点不对则所有招式首尾帧返工 |
| Ultimate 钩子（Ready/Draw/Hold/Sheathe） | C2B-10 | P0 | REQUESTED | 无明一刻专用，独立产线，**禁止复用聚合斩资产** |
| 通用层 7 招动画 | C2B-11 | P0 | REQUESTED | 依赖 C2B-02 + 锚点 |
| 藏锋流 8 招动画 | C2B-12 | P1 | REQUESTED | 需 SheathAnchor 左腰变体 |
| 回风式 8 招动画 | C2B-13 | P1 | REQUESTED | 含 折柳 / 惊鸿 / 长风三段；**长风需要一个侧向镜像版本**（方向由玩家输入决定） |
| 白蔷庭 8 招动画 + `BindHold` | C2B-14 | **P1（本轮升级）** | REQUESTED | 已从"设计态"变为"已实现但无动画"。硬约束：剑尖**始终在中线附近**；`wr_jiazhang` 与 `wr_chuanting` 起手帧需可互换 |
| **风的环境：墙 + 可推动轻物** | C2B-15 | P2 | **PLACEHOLDER** | `WindProps` 现为程序化盒子。ART 可整体替换网格，但**"一面可撞的墙 + 两个轻到能被推的物体"这两个物理角色必须保留**——没有它们，风只是一个击退数字 |
| **施法姿态：QuickMagic / HeavyMagic** | C2B-16 | P2 | REQUESTED | 硬约束：**Quick Magic 时主手剑不得消失**。见 `COMBAT_ANIMATION_REQUIREMENTS.md` |
| **剑身附魔材质通道（火刃 / 霜刃）** | C2B-17 | P2 | REQUESTED | 不需要新动画，需要剑身材质能"泛红/泛白"而不是一层均匀自发光 |
| `NAR-ART-01` 翻倒的商队车（**模块化**） | — | P1 | REQUESTED | cart / wheel / crates / cloth / rope / cargo 可重组；不要一张固定"事故照片" |
| `NAR-ART-02` 钟塔（远景 Landmark） | — | P1 | REQUESTED | 重点 **Silhouette**；雾起时只剩轮廓 |
| `NAR-ART-03` 奥伦后院道具 | — | P1 | REQUESTED | chopping block / wood pile / tool rack。是普通后院，不是训练场；木桩有积年切痕 |
| `NAR-ART-04` 魔法在日常的痕迹 | — | P1 | REQUESTED | 渡口定向磨痕 / 市场结霜库房 / 铁匠铺"看火"。**不做发光特效** |

### C2 · ART 地编 / 道具 / UI（本轮新增）

规划全文见 `docs/ART_KIT_PLAN.md`，UI 规范见 `docs/UI_STYLE_BOARD.md`。

| 资产 | ID | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| Mistvale Ground / Stair / Terrace Kit（12 件） | ENV-01 | P0 | SPEC READY | brief 已成文；替代 `arena_dressing.gd` 占位几何 |
| Adventurer Guild Exterior Set（8 件） | ENV-02 | P0 | REQUESTED | — |
| Town Prop Set A（12 件） | ENV-05 | P0 | REQUESTED | 道具家族制，见 KIT PLAN §4 |
| UI Style Board + UI Kit V1 | UI-01 | P0 | DONE | 5 件 SVG 已入 `godot/ui/kit_v1/`；场景接入待 MAIN |
| 主菜单 V1 | UI-02 | P0 | REQUESTED | 依赖 ENV-01 + ENV-02 作为实景背景 |
| Ability Wheel V1 | UI-03 | P0 | REQUESTED | 环与扇区资产已备；逻辑沿用 `radial_wheel.gd` |
| HUD Frame V1 + 状态条 | UI-04 | P0 | REQUESTED | 底板与三态已备；接入 `CombatHUD.tscn` |
| Town House Kit A（9 件） | ENV-03 | P1 | REQUESTED | **须先与 `assets/models/mistvale/` 既有 12 件做一致性审计再合并** |
| Town Market / Stall Kit（7 件） | ENV-04 | P1 | REQUESTED | — |

### C3 · 里程碑问题（须长期对账）

- `assets/models/mistvale/` 的 12 件 GLB 此前被记为 "Integrated"，实际**从未接入 Godot**，`godot/` 下无任何 `mistvale` 引用。已更正。
- `godot/scenes/ui/*.tscn` 各 7–10 行，`radial_wheel.gd` 为纯 `_draw()` 占位 —— UI 此前完全没有视觉资产。UI Kit V1 是首次补齐。

### C4 · 阻塞与工具链

- **美术线浏览器已独立**：ART 用 Chrome `:9333` + profile `F:\tools\chrome-profile-art`；音频线保留 `:9222` + `F:\tools\chrome-profile`。两者不再互相抢标签页。
- `:9222` 实例的 CDP 浏览器级通道已失效（WebSocket 可连、握手无响应），人类窗口仍可用，但**任何 agent 都无法再连上它** —— 音频线如需自动化，须重启该实例。
- 阻塞原因（原）：Blender MCP 未连接本会话；ChatGPT Web 需用户登录态。Producer 已产出可直接粘贴的 prompt 包（`docs/asset_briefs/C2B-01-CHATGPT-PROMPT.md`，以及新的 `docs/asset_briefs/prompts/ENV-01-01-send.txt`）。
- 已解除：Blender MCP 直连 `127.0.0.1:9876` 可用（裸 JSON over TCP，`execute_code` / `get_scene_info` / `get_viewport_screenshot`），Blender 5.1.2 在线。

---

## D · NARRATIVE & WORLD

世界观 / 主线 / 角色 / 区域叙事 / 文案体系。文档在 `docs/narrative/`。
**定位：Sandbox 证明"怎么玩"，NARRATIVE 决定"为什么值得继续玩"。**
本线不做手感、不写战斗代码、不建模。**实现类的 Fate/Soul Echo/WorldState 仍为 FROZEN**（见 `DESIGN_BACKLOG.md`），本线只做设计。

| 任务 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- |
| 既有叙事设定审计 + 命名裁决 | P1 | DONE | 结论写入 `narrative/WORLD_BIBLE.md` §0；裁决：雾谷 / 雾栖镇 / 雾谷东林·青竹林 / 遗迹哨兵 / 信标+观察者 |
| `WORLD_BIBLE.md` V0.1 | P1 | DONE | 魔法=理解性质；三种剑=信息/位置/距离；最大悬念=古代文明"不再需要留在这里" |
| `MISTVALE.md` V0.1 | P1 | DONE | 空间 0–9 段各设叙事功能；三股力量（公会/商团/钟塔）+ 治安官；三条独特文化 |
| `CHARACTERS.md` V0.1 | P1 | DONE | 7 位 Act I 人物 + 1 影子角色；每人回答"玩家不在时在做什么"；含学习来源表 |
| `MAIN_STORY.md` V0.1 | P1 | DONE | Premise/Theme/Prologue/Act I 节点/FA-01 六种参与状态/第一段可玩体验 50–70 分钟表；PASS 02 已细化并指向 `ACT1_BEATS.md` |
| `STYLE_GUIDE.md` V0.1 | P1 | DONE | 对白长度、禁用 AI 套话表、命名规则、技能与任务文案标准、自查清单 |
| Narrative Request → ART/AUDIO/MAIN | P1 | DONE | 已编号并入各线：`NAR-ART-01/02/03/04`、`NAR-AUDIO-01/02`、`NAR-MAIN-01/02`。权威清单见 `narrative/ACT1_BEATS.md` §7 |
| `ACT1_BEATS.md`（PASS 02） | P1 | DONE | 七个问题答案 / Prologue beat sheet P0–P6 / Arrival A1–A7 / Act I 脊椎 Q1–Q7 / ECHO-01·02 规格 / FA-01 完整设计 / 请求清单 |
| `RELATIONSHIPS.md`（PASS 02） | P1 | DONE | 关系矩阵（公开关系/真实态度/过去事件/潜在冲突）+ 鲁斯克 + 泰姆 + 作息表 + FA-01 后关系变化 |
| PASS 02 修正落地 | P1 | DONE | 莉娅作息（可被错过）/ Soul Echo #2 改为 NPC 自我否认 / 魔法升格为世界底层规则 + 日常使用 3 例 |
| 连续性规则 + 文档债 | P1 | DONE | 写入 `WORLD_BIBLE.md` §9：代码为准；prototype 不写 Lore；`COMBAT_DESIGN.md` 待 MAIN 回写 |
| **Review：Prologue + Act I Early Game** | P0 | DONE | PASS 02 Review 已通过，三条裁决落地：A 奥伦重心移到"记录≠事实" / B 战后 3–6 秒安静 + 人的声音 / C 能力线不规定顺序 |
| **`NARRATIVE_VERTICAL_SLICE_N01.md`（PASS 03）** | P0 | DONE | **可实施规格**：Scene Spec P00–P06 + A1–A7 / 8 个 Dialogue Scene / Readable R-01 货单 + R-02 ECHO-01（三方案比较，采纳 EC）/ 16 条环境对白 / Cluster 五状态 / VO 表 11 句 / 分钟级 Playthrough / 空间·音频·MAIN 请求 V0.2 |
| **`NARRATIVE_STATE_V01.md`（PASS 03）** | P0 | DONE | 最小状态模型：flag 表 / **INFORMATION GRAPH F1–F10** / HARD vs SOFT / MISS MATRIX / 最小存档结构 / 给 MAIN 的接入优先级 5 步 |
| `CHARACTERS.md` §13 SPEECH PROFILE | P1 | DONE | 8 人说话方式表（句长/用词/直接度/解释欲/停顿/礼貌/注意力）+ 三条跨角色纪律 |
| `STYLE_GUIDE.md` §12 PLAYER VOICE V0.1 | P1 | DONE | 低频发声；禁三个同义句选项；沉默/点头/看向是合法选项 |
| **`NAR-MAIN-01..06` 交 MAIN 实施** | P0 | TODO | `Readable`、最小 flag、`took_cart_blade`、N01 背景信号三件套、**南岸"路还在但没意义"不用空气墙**。详见 slice 文档 §12.3 |
| **`NAR-SPATIAL-01..06` 交 ART（地编）** | P1 | TODO | 事故点声学开放 / Reveal 视角 / 进镇第一帧的魔法生活痕迹 / 奥伦后院不在主街正面 / 渡口看得到不好走 / 南岸不可见墙。见 `MISTVALE.md` §10 |
| **`NAR-AUDIO-01..07` V0.2 交 AUDIO** | P1 | TODO | 第五钟独立音型 / 遗迹低频 / **泰姆远处声音（有距离感的空间声）** / 醒来点来源不明低频 / 镇子生活层 / 冷屋子声 / 后院只有劈柴 |
| `MICRO_NARRATIVE_SLOTS.md`（PASS 04） | P0 | DONE | **回填 LD-01 §10/§11**：NAR-01..07 内容 + 22 槽位逐条（是什么/读到什么/形态/可错过）+ 4 个 Readable（R-03..R-06）+ `NAR-ART-05..08` / `NAR-AUDIO-08..09`。**地编保位置，文案填内容** |
| `ACT1_QUESTS.md`（PASS 04） | P0 | DONE | 八条设计规则（**无 XP/无等级**）/ MQ-C 五状态机 / `took_cart_blade` 裂缝 / Q1–Q7 展开 / 五条支线（S-01..S-05）/ 模板黑名单 / 奖励表 / 11 个 flag 增量 / MAIN 实施顺序 6 步 |
| `DIALOGUE_PASS_02.md`（PASS 04） | P1 | DONE | 第二层 6 场（奥伦木桩/米拉/莉娅/薇尔/格兰/阿诺）+ **三条能力入口（不规定顺序）** + 环境对白 Pass 02（18 条）+ VO 增量 11 句 + 自查 8 项 |
| `VO_PIPELINE.md`（Narrative 侧接口契约） | P1 | DONE | 链路 `Scene → VO Spec → TTS Router → Raw → Post → QA → Manifest → Dialogue Player` 的**划界表**；补两环：**Voice Identity 在 Router 之前** / **Manifest 必带 `text_hash` 做改词检测**；字段标准 + 文本清洗规则 + 9 个 `voice_id` 画像 + **VO MASTER LIST 22 句（`VO-001..022`）** + Player 体验需求 |
| **`VO-001..006`（泰姆）先做** | P1 | TODO | **第一批只验这 6 句**：空间声 + 可中断 + "战后把世界接回来"的节奏。成立才扩到 22 句。交 AUDIO（后端与后期）+ MAIN（Player） |
| Dialogue Pass | P2 | DONE | 五条冻结门已过（`MAIN_STORY.md` §13）；PASS 02 只覆盖 Act I 前半第二层，**Act I 后半对白仍冻结** |
| `TIMELINE.md` / `FACTIONS.md` / `TERMINOLOGY.md` / `NARRATIVE_BACKLOG.md` | P3 | TODO | 第一轮不建，按需再开（`QUESTS.md` 已由 `ACT1_QUESTS.md` 承担） |
| **`ACT1_QUESTS.md` V0.2（PASS 05）** | P0 | DONE | **第一天**：§10 三条主线程（A 立足 / B 商队事故 / C 人）+ 交叉表（**B 不是任务**）/ §11 **进镇→傍晚→第一夜→第二天早晨**节奏 + 第一夜只有声音 / §12 第二天三个变化 / §13 四条新支线 **S-06..S-09** / §14 **FA-01 信号网络 8 个 × 6 渠道** / §15 四条 NON-FAILURE FAILURE / §16 任务 UI 措辞 / §17 **Readables V0.2（R-07..R-11 全文）** / §18 Paper Playtest V0.2 / §19 flag 增量 |
| **`DIALOGUE_PASS_02.md` V0.2（PASS 05）** | P0 | DONE | 新增 **8 场（D15–D22）**：渡口干活 / 炉子 / 少了一件 / 奥伦搬柴 / 一封信 / 第一夜 / 第二天早晨 / 北门没开 + **第一次能力习得三条入口（E1 藏锋 / E2 回风 / E3 性质）** + 18 条 bark + **VO-023..034** + 关系纹理映射 |
| **`INFORMATION_GRAPH.md`（PASS 05）** | P1 | DONE | **玩家知识 K001–K017**（来源 / H·S / 能错过吗 / 还有谁知道 / 以后咬回哪）+ **NPC 信息差表**（谁不知道什么、谁自以为知道但错）+ **关系纹理**（不是好感度）+ 三条对白纪律 |
| `CHARACTERS.md` §14 DAILY PRESENCE | P1 | DONE | 9 位角色的**在哪 / 何时 / 做什么 / 为什么在那 / 玩家不在时**；**奥伦三层认识**（Layer1 普通 → Layer2 动作熟练 → Layer3 木桩切痕，**没人告诉他**） |
| `MISTVALE.md` §11–§14 | P1 | DONE | **本地文化六问**（打招呼 / 外来的 / 四下钟 / 怎么看公会 / 怎么看遗迹 / 失踪不写死）+ **空间叙事层**（9 区密度 3→0 + **四处必须安静**）+ `NAR-AUDIO-10..17` + UI TEXT SPEC V0.1 |
| **`NAR-AUDIO-10..17` V0.2 交 AUDIO** | P1 | TODO | market day / **market close** / **first night**（钟·河·酒馆·北山极低频）/ north gate alert / bell schedule / **ferry ambience** / **forge ambience（风箱要给出节奏，D16 依赖它）** / oren backyard |

未决事项：`COMBAT_DESIGN.md` 与 `moveset_library.gd` 不同步（折柳/惊鸿/长风三段已实现但文档写"未实现"），请 MAIN 回写；Narrative 现按**已实现**为准。
**Combat 同步（PASS 03 只读）**：`white_rose`（白蔷庭）当前为 **prototype** → 本轮**不写它的 Lore**（continuity rule）；三系法术已实现 `火矢/焚环`、`寒流/凝霜`、`风压/风步`，与"火=转化 / 霜=停滞 / 风=动量"的底层规则一致，已用于 §8 的生活痕迹设计。聚合斩来历仍不解释。

**PASS 04 顺序调整说明**：原计划先等 MAIN Review N01 再做 Act I Quest + Dialogue 02，本轮**提前做**，原因是 ART 的 `LD-01` 已把 `NAR-01..07` + 22 个槽位的位置留好并写明「文案填内容，地编保位置」——**槽位回填是时间敏感的，等地编铺完再给就要返工**。任务与对白因此全部**锚定 LD-01 的真实坐标**（Z-01..Z-12 / C-01..C-08 / V1..V9）。

**PASS 05 说明（第一天 / 第一夜 / 第二天早晨）**：本轮把"世界设定扩张"停掉，改为向下深化——玩家今晚睡哪、明天为什么还留在这。**THREAD B（商队事故）明确不是任务**：没有条目、没有日志、没有完成态，全靠别人随口的话拼起来。`day_index` **只能是 0 或 1**（睡一次），**不做日历、不做第三天**。

**PASS 06 门**：MAIN Review 通过 `ACT1_QUESTS.md` V0.2 + `DIALOGUE_PASS_02.md` V0.2 的可实施性 → 才进 Act I 后半与 FA-01 本体。**仍不进 Act II。**
**新增硬约束（交 MAIN / AUDIO / UI）**：
- **第一夜不弹任何"休息"UI、不放过场、不给"新的一天"大字** —— 睡觉只是屏幕暗下去，然后声音先回来（`ACT1_QUESTS.md` §11.1）。
- **`NAR-AUDIO-16` 风箱必须给出节奏信息**，否则 D16「跟着我的手」没法玩。
- **`[沉默]` 必须是真实可点的选项，视觉上不比说话的选项弱**（UI TEXT SPEC）。
**顺序硬约束**：S-05（薇尔·被划掉的那一行）**必须先于** ECHO-01 可被遇到，否则 ECHO-01 效果减半（见 `ACT1_QUESTS.md` §4.6）。

---

## 冲突优先级

1. 当前用户指令
2. MAIN PROJECT
3. ART / AUDIO 实现细节
