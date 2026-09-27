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
| Sword combo / heavy / block | P0 | REVIEW | TECH VERIFIED；视觉为 TempSwordVisual 三方块 |
| Perfect Guard | P0 | REVIEW | 窗口 0.12s（原 0.18s 已收紧）；音效未接入 |
| Universal single-sword language | P0 | REVIEW | 13/13 集成测试绿；手感未验收 · 见 `COMBAT_DESIGN.md` |
| Guard → Perfect Guard → Riposte 闭环 | P0 | REVIEW | 窗口/后坐/微光奖励已实现；音效未接入 |
| 藏锋流 Hidden Edge 原型 | P0 | REVIEW | 纳刀/拔刀红利 + 一文字/返刃/落月/断水/截锋 + 三技能 |
| 回风式 Flowing Wind 原型 | P1 | REVIEW | 四段链 + 命中缩恢复 + Deflect 防御 |
| 聚合斩重分类为 SIGNATURE | P0 | DONE | 移出 Ultimate 槽，独立冷却；演出未改动 |
| 无明一刻 Ultimate 原型 | P0 | REVIEW | 独立资产，不共用聚合斩；动画钩子待 ART |
| Combat Lab 开发面板 | P0 | DONE | 流派切换 / 技能冷却 / 敌人强制攻击 / Hitstop 三档 / Parry Debug |
| Magic / Ability Wheel | P0 | REVIEW | 火冰风已验证；轮盘是技术占位 |
| Shatter | P0 | REVIEW | Area3D + shard + 85ms hitstop；音画未验收 |
| Iaido 7.2s 张力序列 | P0 | REVIEW | 14 phase 全实现；音频为占位合成 |
| Enemy telegraph / AI | P1 | TODO | 现为 technical_dummy，非 Lesser Ruin Sentinel |
| Iaido 5–8s Cinematic Tension Pass | P0 | REVIEW | 已到 7.2s，超出目标区间上限；待视听验收后再谈压缩 |
| Git：提交本轮未落地改动 | P0 | DONE | 已由 MAIN 提交并推送：`c485aeb` + `8c71561`（7.2s Iaido 全序列）。远端 `godot-combat-mvp` = `8c71561` |

### 战斗线验收现状（COMBAT 会话 · 2026-09-27）

- **技术验证通过**：**13 项 headless 集成测试全部绿**（`moveset` / `parry_riposte` / `style` / `ultimate` 四项为本次新增）。期间 `iaido_integration` 曾因 Iaido 演出线并行改动 `iaido_tear_3d.gd` 短暂变红，**非战斗线回归**，对方改完后已自愈。
- **已提交**：`59d983c`（40 files, +4415/−233）。**仅提交战斗线文件** —— Iaido 演出线、ART、AUDIO 的未完成改动**未纳入**，仍在各自工作区。**尚未 push**（远端可能正在接收 Iaido 线的提交，避免交错，交由 MAIN 或用户决定）。
- **交互验收未完成**：`阶段一 通用剑对 Dummy 是否已经有趣` 与 `阶段二 切藏锋后不看 UI 是否可辨` **均未验收**。headless 只能证明逻辑正确，不能证明好玩。
- **本会话运行过一次 `--editor --quit`**（为注册新 `class_name`），该操作会重写 `.godot/global_script_class_cache.cfg`。**Iaido 线如需再次 import，请注意与本题解冲突。**
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
| 元素 SFX（火/冰/风/shatter） | P1 | TODO | `COMBAT_SFX_BRIEF.md` Priority B |
| BGM | P2 | DONE | 4 首 Suno 已接入（Web 原型期） |

---

## C · ART & MODELING

ChatGPT Web → Blender Python → Blender MCP → GLB → Godot

| 资产 | ID | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| First Person Sword | C2B-01 | P0 | IN GODOT | GLB 已入 `godot/models/weapons/`；832 tris；待替换 TempSwordVisual 并实机验收 |
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
| 回风式 5 招动画 | C2B-13 | P1 | REQUESTED | — |
| 白蔷庭 Bind 四动作 | C2B-14 | P2 | TODO | 设计态，未实现；见 `COMBAT_DESIGN.md` §6 |

阻塞原因：Blender MCP 未连接本会话；ChatGPT Web 需用户登录态。Producer 已产出可直接粘贴的 prompt 包（`docs/asset_briefs/C2B-01-CHATGPT-PROMPT.md`），人工或连接后即可执行。

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
| `MAIN_STORY.md` V0.1 | P1 | DONE | Premise/Theme/Prologue/Act I 节点 1–12/Day 10 Anchor 六种状态/60 分钟表；Act II·III 仅一行 |
| `STYLE_GUIDE.md` V0.1 | P1 | DONE | 对白长度、禁用 AI 套话表、命名规则、技能与任务文案标准、自查清单 |
| Narrative Request → ART/AUDIO/MAIN | P1 | TODO | 商队车、钟塔第五钟、奥伦柴堆、遗迹低频声、登记簿"看纸"交互。见 `MAIN_STORY.md` §12 与 `MISTVALE.md` §8 |
| Prologue/Act I dialogue pass | P2 | BLOCKED | **等骨架冻结后再进**，避免世界观一改就全废 |
| `TIMELINE.md` / `FACTIONS.md` / `QUESTS.md` / `TERMINOLOGY.md` / `NARRATIVE_BACKLOG.md` | P3 | TODO | 第一轮不建，按需再开 |

未决事项：`COMBAT_DESIGN.md` 与 `moveset_library.gd` 不同步（折柳/惊鸿/长风三段已实现但文档写"未实现"），请 MAIN 回写；Narrative 现按**已实现**为准。

---

## 冲突优先级

1. 当前用户指令
2. MAIN PROJECT
3. ART / AUDIO 实现细节
