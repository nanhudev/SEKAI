# 缚星链 · CHAIN SYSTEM DESIGN V2

> **这份文件是什么**：武器系统的**设计意图**——三形态、两个层级（强化 / 魔法）、武器联结、成长哲学、路线图。
> **这份文件不是什么**：当前实现状态。**已实现的东西在 `COMBAT_DESIGN.md` §19**；数值在 `chain_moveset.gd` /
> `chain_library.gd`；姿态要求给 ART 的在 `COMBAT_ANIMATION_REQUIREMENTS.md`；音效在 `COMBAT_SFX_BRIEF.md`。
>
> 状态图例：**[已实现]** · **[已设计·未实现]** · **[待定]**
>
> 本文件里凡是标 [已实现] 的，都必须能在 `tests/chain_integration.gd` 里找到对应断言。设计意图
> 和可执行断言之间的差值，就是这个项目真正欠下的债。

---

## 0. 第一原则：UPGRADE ≠ REPLACEMENT

玩家没有职业。武器也不该是 `Lv1 → Lv2 → Lv3，旧版本报废`。链的成长线是：

```text
理解  →  获得新的使用方式  →  产生新的战斗语言
```

所以三形态**不是升级档位，是三种对"锁链是什么"的不同理解**，最终应该**可以主动切换 / 配装 / 使用**。
最高阶形态的持有者，在开阔地形依然可能主动换回实链——这就是判据：**如果没有任何场合会主动切回去，
那它就不是形态，是等级。**

## 1. 三形态不是三个强度等级

| Form | 控制什么 | 最强 | 短板 | 玩家问自己的问题 |
| --- | --- | --- | --- | --- |
| **实链** FORM I | WEIGHT | 单体力量 / 破架 / 拉扯 / 重击 | 跑图、群控、轨迹自由度 | **我能把什么拉过来？** |
| **游链** FORM II | MOMENTUM | 跑图 / 追击 / 脱离 / 空中转向 | 破架弱于实链、硬控弱于律链、操作要求高 | **我能从哪里借势？** |
| **律链** FORM III | CONNECTION | 群控 / 环境组合 / 多目标约束 | 直接伤害低、准备明显、消耗高、不适合高频跑图 | **我能让哪些东西彼此产生关系？** |

### §52 最终判据（这是验收条款，不是修辞）

如果三形态最后只是 **短链 / 长链 / 四条链**，**FAIL**。允许的差异必须落在
**动作、节奏、窗口、声音、反馈**上——和流派与剑的关系是同一条规矩：
**流派差异不体现在伤害数字上**，形态差异也不体现在链的数量上。

任何一条提案，如果它的核心卖点可以写成"伤害 +20% / 射程 +30%"，它就已经失败了。

---

## 2. FORM I · 实链（WEIGHT）— **[已实现]**

当前 Prototype 就是这一形态的基础，**保留、不推翻**。它的循环：

```text
Sweep → Return Sweep → Slam        （横缚 → 返扫 → 下砸：三击换轴）
Throw → Hook → Tension → Yank → Retract
```

**空间规则（最重要的机制）**：命中谁、谁被拉动，由**质量表**决定，不是由招式决定。
轻型 → 敌人被拉向你；中型 → 双方都动；重型 → **你被拉向它**（重型敌人不是受害者，是锚）。
石柱、横杆和一个重型敌人走的是**同一行代码**（`ChainAnchor` 只是回答了"我很重"）。

### 2.1 实链不要变成鞭子（§3/§43 IMPACT）**[本轮已实现]**

链头有重量，所以它**为命中付钱**。一个重物和一个鞭子的区别不是画得更重，而是：

| 通道 | 规则 | 数据位置 | 本轮实测 |
| --- | --- | --- | --- |
| **势的代价** | 命中时按**被打中物的重量**扣 MOMENTUM | `ChainMove.impact_momentum_cost` × `impact_cost_by_weight` | 轻目标后剩 **0.282**，重目标剩 **0.215** |
| **轨迹弯折** | 命中把弧线撞偏，越重偏越多 | `impact_deflect_degrees` × `impact_deflect_by_weight` | 轻偏到 **-106.4°**，重 **-102.4°**（差 4°） |
| **顿住** | hitstop 随**链头到达速度**与目标重量缩放 | `impact_hitstop` × `impact_hitstop_min/max` | 横缚 0.032s（剑的轻击同级） |
| **相机** | trauma / impulse 随速度缩放，而不是每招一个常数 | `_pay_for_the_impact()` | — |

**在玩法上意味着**：扫倒一群轻型敌人很便宜，链还在转；把一个投掷花在重型身体上，
换来的是"咚"一声和一截被吃掉的势。**实链的货币是动量**，这里就是它收费的地方。
（`ch_orbit` 是唯一**刻意不收费**的招式：它按 `orbit_hit_interval` 定时命中，
任何按次收费都会让"举着链冲进人群"变成一场必输的赛跑。）

### 2.2 回收不许瞬回（§43 RETURN）**[本轮已实现]**

一次位移交付的回收读起来像精灵被重置。链是有质量的绳子：**撒手不是停住它，只是停止喂它。**
所以回收会**过冲**——先往回转过去一点、往外漂一点，然后才被收回来。

- `retract_overshoot 0.55` / `retract_out 0.45`（相对剩余差距的比例，不是绝对值，所以链变长不会变成花活）
- 实测：**外漂 +0.13m，过冲 10.8°**，18 帧内完成，且 `radius` 永不超过链长。
- **代价没变**：`retract_time` 没动（0.30s），两个鼓包在收尾处都归零。这是外观变重，不是输入变钝。

### 2.3 绷紧必须三通道可感知（§43 TENSION）**[两通道已实现，音频见 §13]**

| 通道 | 实现 | 实测 |
| --- | --- | --- |
| **线** | 绷紧时链接高频微颤（`TREMOR_PER_TENSION` 2cm、7.5Hz） | 满绷时偏离直线 **0.0059m**，而松弛时 **0.7820m** —— 两张完全不同的画面 |
| **相机** | 绷紧瞬间的抖动 + FOV 前推 + **沿链身方向**的冲量；持续期 `sustain_fov` 收紧 | 挤压 **1.80°**，冲量 |x| < 0.06 rad（是"拽一下"，不是"转头跟链头"） |
| **音频** | **未做**（§49：占位即可，不阻塞玩法）。事件已发出：`taut_changed` / `tug` / `wall_impact` | 测试计数，防止无人读的接口烂掉 |

着色器/视觉禁忌仍然有效：**浅色场景里不要用亮色画线**；**不要用背景比例缩放发光核心**。

### 2.4 不要急着延长链（§44）

短链反而是 **BRUTAL CLOSE-MID RANGE WEAPON**。`max_radius 4.6` 是**保留值**，不是待办。
先确认"近距离暴力"好玩；只因为"链应该很长"就改 15m，是最容易丢掉力量感的方式。
（如果将来确实要长链，那是**游链的形态差异**，不是实链的数值调整。）

---

## 3. FORM II · 游链（MOMENTUM）— **[已设计·未实现]**

核心不是"链变长"，而是玩家理解**链可以改变自己的运动轨迹**。关键词：
`fluid / graceful / aerial / redirect / swing / momentum`。

**第一阶段只证明一件事**：

```text
Anchor → Pull → Momentum → Release
```

**不要**在这一阶段做完整 Spider-Man 系统。**不要**复制任何具体作品的动作。

- **Anchor 的来源**：墙 / 柱 / 树 / 废墟结构 / 敌人 / 横杆。**它们走同一份契约**（说自己多重）。
  → 三形态共用 `ChainAnchor`，律链的虚拟锚点只是另一个实现者。
- **双 Anchor**：允许同时持有两个锚点，玩家在它们之间切换。
  这应该创造 **route choice**，不是自动动画——"自动摆荡"会把这一形态最核心的操作乐趣拿掉。
- **Combat Movement**：荡过敌人时链头顺势攻击 ——**TRAVERSAL IS ATTACK**，
  但**不是所有跑图动作都自动造成巨大伤害**（那会让战斗变成找路线）。
- **接口预留（本轮已做）**：训练场已有**头顶横杆**，且抛出方向已跟着准心走（见 §11），
  所以"钩住一个高于头顶的点"这件事**今天已经成立**，游链不需要从零发明接口。

---

## 4. FORM III · 律链（CONNECTION）— **[已设计·未实现]**

概念进化：玩家不再认为链必须从自己手里出现。他理解的是 **CONNECTION**。

玩家抬手 → 目标周围虚空中出现 **Anchor Points**（例如四个）→ 四条链**从空间里直接出现**，
不是从手里飞过去。视觉上必须明确告诉玩家：**"我已经不再操纵一根实体链。"**

**它不是无限强**，它不能同时拥有实链最强重击 + 游链最好跑图 + 自己最强控制。短板写在 §1 的表里。

**它的爽点是"关系"，不是"数量"**：

| 关系 | 输入 | 结果 |
| --- | --- | --- |
| 敌人 A ↔ 敌人 B | Tension | 按重量：A 撞 B / 轻撞重 / 两者同时偏移 |
| 敌人 ↔ 石柱 | 建立关系 | 活动范围被约束（不是"定身"，是"半径"） |
| 敌人 ↔ 大石 | Heavy | **Pull Together**（把石头拖向敌人） |
| 敌人 ↔ 物理物件 | 任意 | 环境本身成为武器 |

**律链的 Virtual Chain 由 VFX 表现，不是四条固定 Blender 模型**（§47）。

---

## 5. 形态切换（Form Switching）— **[待定，只定边界]**

- **两个轴，不要混**：武器槽（剑 / 链）与形态（实 / 游 / 律）是**两件事**（§19）。
- **不做菜单操作**：形态切换如果要在菜单里选，它就变成了配装界面而不是战斗语言。
  倾向：**在战斗外配装 + 战斗内有限切换**（具体方案待定，见 §16 开放问题）。
- **切换必须有代价**，否则最优解永远是"每次动作前切到最合适的那一形态"，三形态就退化成三个按钮。
- **形态是数据，不是分支**：一个形态 = 一份 `ChainMoveset`（`form_id` / `form_name`），
  `ChainDirector` 里**不允许出现 `if form_id == ...`**——和"流派差异写在数据里"是同一条规矩。
  **[已实现]**：`ChainMoveset.form_name` / `form_id` 字段已经存在（当前只有 `实链`），
  因为 HUD、调试读数、渲染器都已经需要能说出"手里是哪一条链"。

---

## 6. 强化层 × 形态（两个正交轴）

**不要**把三形态等同于轻中重。它们是两个不同的轴：

```text
Weapon Form      ： 实链 / 游链 / 律链
Enhancement Weight： Light / Medium / Heavy
```

所以每一种形态理论上都可以有轻 / 中 / 重强化。**第一批只做三个，不要一次做十五个。**

### LIGHT — 折轨 **[已设计·未实现]**

链头运动途中输入技能，玩家**瞬间改变 Trajectory**。不是传送，是手部/势让链头快速 Redirect。
用途：绕盾、改变命中方向、防止落空、建立第二次攻击。
**重点：MOMENTUM IS PRESERVED**（这一条决定它是不是"链"的技能；如果改轨要清空动量，
它就退化成"再打一次"）。

### MEDIUM — 连衡 **[已设计·未实现]**

先连 A，短窗口内再连 B，建立真实 Tension 关系 `A ↔ B`，然后按重量/输入/环境产生不同结果。
这个技能在三形态下可以**表现完全不同**（实链：硬拉；游链：借力；律链：关系约束）。

### HEAVY — 坠星 **[已设计·未实现]**

地位类似剑的**聚合斩在强化层级中的位置**——**但不是 Ultimate**。
`BUILD MOMENTUM → RELEASE MASS`：允许短时间积累势，然后把全部势压进一次
**垂直 / 斜向下砸**。打地面 = 强冲击；打大型敌人 = **不需要把它砸飞**，
而是形成 **Extreme Tension**，然后**玩家被拉向目标**接 Follow-up。
（"打大型敌人时被拉过去"——这一条正好是实链质量表的自然延伸，不是新特例。）

---

## 7. 魔法灌输层（TAB 重做）— **[已设计·未实现]**

**TAB 不再主要承担"技能轮盘"**，改为 **ELEMENT / MAGIC IMBUEMENT LAYER**：
选 Neutral / Fire / Frost / Wind（或后续更多属性），然后 **WEAPON × MAGIC 产生玩法表达**，
**不是纯元素伤害**。

> 现状说明：TAB 当前仍是法术轮盘（HUD 的 `_feed_wheel()`），改动属 UI + 施法层，
> **本轮只设计，不动实现**。

### 链 × Frost

| 形态 | 表达 |
| --- | --- |
| 实链 | 缠住后 Tension 增加 Frost Buildup；重曳 → **Frozen Link Break**；目标已 Frozen → Shatter Interaction |
| 游链 | Anchor 可短暂变成 **Ice Anchor**（原本挂不住的表面 → 短时抓点，持续时间短） |
| 律链 | 四个 Virtual Anchor 变成 **Frozen Spatial Pins**（把敌人钉在空间里，**不是蓝色的链**） |

### 链 × Wind

| 形态 | 表达 |
| --- | --- |
| 实链 | 增加 Launch Velocity，**降低部分控制精度**（有得有失） |
| 游链 | **最强组合之一**：提高 Momentum Preservation，Release 时额外 Push / Lift → traversal build |
| 律链 | 改变 **Tension Center**（把两个目标的连接中心向某方向偏移）→ 群控有空间玩法 |

> **[已实现]** 实链目前只有两条魔法交互，且都写成了**数据**（`wind_momentum_bonus` /
> `pull_poise_elements`），武器不被硬绑任何元素：风加**自转**（链自己的货币），
> 冰让**拉扯的削势**更值钱。这两条是上面表格的第一行。

### 链 × Fire **[只设计]**

实链：连续使用金属逐渐 `dark → red → orange`，重击释放积累热（**不是 Burn Damage**）。
游链：短时 hot trail / ignition path。律链：Connection 成为 **Heat Transfer Path**。
**当前不做 Prototype，不要全部实现。**

---

## 8. Opportunity Tags 与武器联结（Weapon Link）— **[已设计·未实现]**

**不是传统 QTE。** 建立 **OPPORTUNITY TAGS**：

```text
BOUND · LAUNCHED · FROZEN · OFF_BALANCE · AIRBORNE · TENSIONED
```

每种武器对某些 Tag 有 **ENTRY RESPONSE**。例：律链给敌人上 `BOUND` → 玩家在短窗口内按 `2` 换剑
→ **不播普通切武器动画**，而是 **WEAPON LINK TRANSITION**：角色迅速进入被束缚目标附近的 Sword Entry
→ **然后玩家控制权归还**（**不要自动播放完整处决**），玩家继续决定轻 / 重 / 流派技 / 重强化，
甚至在条件满足时接**聚合斩**。

### 为什么不是 QTE（这是设计条款，不是偏好）

**不要**屏幕中央 `PRESS X NOW`。只给轻量提示：weapon icon pulse、小声效、轻微手柄反馈。
**玩家可以忽略它。** 它应该是 **Opportunity**，不是强制小游戏。
目标最终是让切换武器成为 **Combo Grammar**：

```text
Chain Bound → Sword
Wind Launch → Chain
Frozen      → Sword Heavy
Sword Off-Balance → Chain Hook
```

---

## 9. 技术记忆：学 / 忆 / 悟 — **[已设计·未实现]**

玩家不通过商城 / 抽卡 / 技能点获得代表性强化技能。主要方式：**EXPERIENCE THE TECHNIQUE.**

| 来源 | 内容 | 给什么 |
| --- | --- | --- |
| **学** | 从活着的人训练 | 基础招式 / 武器语言 |
| **忆** | 秘籍 / 遗物 / 记录 / 武器 / 残留意志 → **TECHNIQUE MEMORY** | **强化技能** |
| **悟** | 玩家自己的经历 / 选择 / 战斗方式 | **ULTIMATE** |

**Ultimate 不应该单纯捡秘籍**：真 Ultimate 尽量**不直接继承**，它更像"玩家自己最终形成的答案"。
这与 SEKAI 的"没有职业，只有经历"是同一条线。

**时长按叙事价值调整**（不是硬规则）：基础 30s–2min；Light 强化 2–5min；Medium 5–12min；
Heavy 15–30min 甚至一个完整短篇。

### 聚合斩的 Memory（Hero Technique Memory）

世界上**已经存在山脊永久斩痕**（Narrative 以后接）。玩家最初远远看到，**不解释**。
很久以后获得 Technique Memory，进入**山还没有被切开的过去**，体验创造/使用这一招的人**为什么拔刀**，
最后自己执行聚合斩，Memory 结束，回到现实——**远处那道一直存在的山痕突然拥有意义**。
这不是 Skill Unlock，是 **WORLD RECONTEXTUALIZATION**。

### 三形态对应的理解故事（方向，交给 Narrative）

实链 = 力量；游链 = 一个人如何利用锁链穿过崩塌空间 / 战场 / 城市；
律链 = 最高概念——创造者最终理解自己控制的**不是一根铁链，而是"两个事物必须产生关系"的规则**。
**Combat 只定义 Mechanic Meaning，不写故事。**

---

## 10. Sword Ultimate · 无间（**设计草案，不开发**）

**聚合斩是 Heavy Enhancement，不是 Ultimate。** 聚合斩的极致是 **ONE CUT**：
`all intention → one cut`。Ultimate 必须**与它相反**：`one sword principle → entire battlefield`。

玩家进入 **SWORD RULE STATE**：整个战斗区域暂时成为**可被斩击的空间**。
敌人移动可能触发**延迟斩击**；玩家一个动作在多个位置产生对应斩击；环境也出现 Cut Feedback；
最终阶段形成**无差别区域斩击**。

**视觉语言**：**不要**满屏白色飞行剑气。要 `delayed spatial cuts / air line / surface split /
environment cut / enemy delayed wounds` —— 环境看起来**持续被一把看不见的剑划开**。
重点：**SYSTEMIC SWORD DOMAIN**，不复制任何现成动漫技能的视觉。

UE5 侧以后可以研究：`mass spatial cut / surface fracture / delayed slice / air distortion`。
**本轮只完成设计草案，不要抢 Chain Prototype 的开发优先级。**

---

## 11. 舞台：CHAIN TEST AREA（§45）

训练场要为**三形态长期共用**。当前 `chain_lab.gd` 提供的：

| 需求 | 状态 |
| --- | --- |
| Light / Medium / Heavy Dummy | **[已实现]** 三个质量站在一个房间里（一张投掷距离内） |
| Wall | **[已实现]** 链头不能穿墙，撞墙掉势 |
| Pillar（固定锚点） | **[已实现]** `ChainAnchor`，说自己是重型 |
| Moveable Rock / Crate | **[已实现]** 3 个物理箱 |
| **High Anchor（头顶横杆）** | **[本轮已实现]** 见下 |
| Light Dummy 之外的 OPPORTUNITY TAG 靶子 | **[待定]** 需要 `LAUNCHED` / `FROZEN` / `AIRBORNE` 状态可视化 |

### 高阶锚点为什么是一个几何问题，不是放一个柱子

链头走的是**极坐标**：`radius` 是**水平距离**，`height` 是独立的绝对高度。
所以一次朝上的钩子落在 `radius = 水平距离`、`height = 1.15 + sin(俯仰) * radius`。
横杆中心因此被放在"站在自然投掷距离上需要抬头约 **28°**"的位置：

```text
横杆高 2.78m，水平 3.4m  →  需抬头 28.6°   →  实测：已钩住（heavy）
```

比这个更高，钩它就变成精准操作——训练场设施**永远不能是需要技巧才能用的东西**。
横杆的**可钩体积挂在横臂下方**：射线先测实体世界，所以一个和横臂重叠的可钩盒永远够不到，
链头会先撞到横臂当墙。这就是它**不是"一根更高的柱子"**的原因。

### 顺带确立的一件事（§13）：抛出方向跟着准心走 **[已实现]**

链头曾经在固定胸口高度出手，于是世界上**所有高的东西都钩不到**。现在
`ChainMove.aim_pitch_scale`（**逐招式 opt-in**，只有 `ch_hook` 是 1.0）让抛掷按
`sin(俯仰) * 半径` 抬起。**横缚不会因为玩家抬头而飘走**——那正是它必须 opt-in 的原因。
同时 `_step_tension` 改为保持"绷紧时的高度"，而不是硬拉回 1.05m
（否则一条钩在柱顶的链会被拉下去穿过柱子）。

---

## 12. Debug 规范（§46）

**仅 Developer Mode** 显示：`FORM / RADIUS / MOMENTUM / TENSION / ANCHORS / BOUND TARGETS /
OPPORTUNITY TAG`。**Clean：完全隐藏。**

**[已实现]**：`ChainDirector.debug_readout` 是显式开关；未开启时 `debug_state_line()` 只返回
**形态名**（玩家可以知道手里是哪条链——形态是真实选择，选择需要名字），三个数字与
`debug_flags_line()` 全部为空。开发者面板（F8）是项目的"开发者模式"，
链**询问**它而不是假设它（也不去改它的文件）。渲染器 `hud` 参数走同一条开关。

`ANCHORS` / `OPPORTUNITY TAG` 现在**不打印**：拥有它们的形态还不存在，
一个永远输出 "—" 的字段只会教人忽略它所在的那一行。

---

## 13. ART / VFX / AUDIO 请求

### ART（§47）

实链 Prototype 可以继续 Placeholder，但正式资产必须**分离**：
`Handle` / `Chain Link` / `Terminal Head` / `Connector`，**不要烘死固定长度**
（未来三形态共用同一套武器语言）。**律链的 Virtual Chain 由 VFX 表现，不做四条固定 Blender 模型。**

### VFX（§48）

**现在只准备接口。** 实链：`impact / tension / metal trail`；游链：`momentum trail / anchor / speed`；
律链：`void anchor / chain manifestation / constraint line`。
**Combat 线不自己堆特效**——等玩法成立，交 Skill / VFX 线。

### AUDIO（§49）

AUDIO 已切到本地 SFX 管线。链需要：`heavy chain / metal drag / rattle / tension / snap /
hook impact / slam / fast chain air`。**当前 Placeholder 即可，不要阻塞 Gameplay。**

**已发出的时序事件**（AUDIO 线可以直接挂）：

| 信号 | 参数 | 用途 |
| --- | --- | --- |
| `move_started` / `hit_landed` | move / hit | 挥击与命中 |
| `tug` | `step, total, amount` | **每记顿挫**（Priority G 的 `ch_tug` 三阶递减就靠这个） |
| `wall_impact` | `strength` | 撞墙（强度已算好，不要在监听端重算） |
| `taut_changed` | `bool` | 绷紧（TENSION 没有 UI，这条音效就是读数） |
| `message` | text | 面向玩家的公告条（渲染器字幕也是它） |

---

## 14. 路线图与门槛

| 阶段 | 只验证 | 通过的判据（3–5 分钟试玩） |
| --- | --- | --- |
| **Phase 1 · 实链**（当前） | weight / impact / tension / hook / yank | **我是否感觉自己在控制重量？** |
| **Phase 2 · 游链** | Anchor / Pull / Swing·Arc / Release / Momentum | **我是否开始把地图看成 Anchor？** |
| **Phase 3 · 律链** | Virtual Anchor / 4-chain bind / 敌人↔敌人 / 敌人↔环境 / Tension Resolution | **我是否开始把敌人与环境看成可以建立关系的对象？** |

**每一个形态先做 3–5 分钟测试。如果答案是否，不要增加技能，先修核心。**

---

## 15. 当前禁止（§50）

```text
Chain Ultimate          ·  20 chain skills        ·  完整技能树
把律链做成上位替代        ·  传统 QTE 弹窗          ·  所有元素组合一起实现
Sword Ultimate 完整开发  ·  Technique Memory 剧情编写
```

**先把实链做到好玩。** 一个形态的一个核心机制，胜过三个形态的半成品。

---

## 16. 本轮实现状态与未验收（诚实标注）

### 本轮做了什么 [已实现]

| 项 | 文件 | 断言 |
| --- | --- | --- |
| 落点代价（势 / 轨迹弯折 / hitstop / 相机按重量与速度缩放） | `chain_move.gd` `chain_moveset.gd` `chain_library.gd` `chain_director.gd` | `_check_landing_costs_the_head_its_spin()` |
| 回收跟随（过冲 + 外漂，不延长输入锁） | 同上 + `_step_retract` | `_check_the_return_swings_before_it_comes_home()` |
| 绷紧三通道（线微颤 / 相机挤压与拽动） | `chain_visual.gd` `_enter_tension` `_update_feedback` | `_check_tension_is_in_the_line_and_the_camera()` |
| 形态字段（`form_name` / `form_id`） | `chain_moveset.gd` `chain_library.gd` | 调试读数断言 |
| Debug 读数仅开发者模式 | `chain_director.gd` | `_check_the_numbers_are_a_developer_readout()` |
| 抛出方向跟着准心（`aim_pitch_scale`，opt-in） | `chain_move.gd` `chain_director.gd` `chain_library.gd` | `_check_the_high_anchor_can_be_hooked()` |
| 高阶锚点 + 龙门架 | `chain_lab.gd` | 同上 |
| 音频时序事件 `tug` / `wall_impact` | `chain_director.gd` | 计数断言（防止无人读的接口烂掉） |

### 未做 / 未验收

- **音频第三通道未做**（§49 允许占位）。**张力现在只有"看得见 + 感得到"，还没有"听得到"。**
- **§51/§53 的 3 分钟试玩手感验收未做**：需要用户的可见桌面。headless 只能证明**机制成立**，
  不能证明**好玩**。
- **顿挫够不够"顿"未确认**：`gap 0.24s` 下一记拉扯约 0.20s 花掉 88%，两次之间只有约 0.04s 真静止。
  要调就调 `pull_tug_gap`，**不要动曲线**（曲线管距离，gap 管节奏）。
- **实链的落点代价是一次隐性削弱**：先把普攻做有趣，再谈流派——现在轮到"这条规则是否让
  连续扫击变得不划算"，需要实机确认。

### 开放问题（# DESIGN QUESTION，不阻塞）

1. **形态切换的代价怎么表达？**（切换时间 / 势的损失 / 只能在某个窗口切）
2. **游链的 Anchor 上限**：同时两个是承诺，但"第二个锚点是否可以预挂"没有答案。
3. **律链的准备阶段**：如果准备明显，玩家在群战里真的会用吗？还是它只是对着单个强敌的控场？
4. **TAB 元素层与强化技能的关系**：元素是**一层**还是**一个轴**？现在倾向"层"，但
   "强化技能在元素被灌注时是否改变表现"会影响数据结构的形状。
