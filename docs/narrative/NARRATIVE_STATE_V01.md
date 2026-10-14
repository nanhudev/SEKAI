# SEKAI · NARRATIVE STATE V0.1（PASS 03）

> 状态：**交 MAIN 的最小状态模型**。目的：让 Act I 的任务不靠"线性阶段编号"，而靠**玩家知道什么 / 做过什么 / 错过什么**。
> **不要开发复杂 WorldState。** 这里只有一堆 flag + 一张信息图。不要 LLM NPC，不要 Tick 模拟。
> 配套：`NARRATIVE_VERTICAL_SLICE_N01.md`（Scene / 对白 / Readable）。

---

## §0 三条原则

1. **Flag 只记录"发生了什么"，不记录"剧本走到第几步"。** 没有 `prologue_stage == 3` 这种东西。
2. **每一条重要事实必须有 ≥ 2 个来源。** 只有一个来源的事实 = 设计缺陷（Information Graph §2 用来抓这个）。
3. **没有任何 flag 会因为"玩家没做"而卡住世界。** 世界继续往前，flag 只负责记录玩家走的是哪条路。

---

## §1 FLAG 表（VERTICAL SLICE N01）

类型：`bool` / `int` / `enum`。写入者统一标注 —— N = Narrative 内容触发，W = 世界/系统自动（与时间或场景无关）。

### 1.1 Prologue

| flag | 类型 | 默认 | 由谁置位 | 错过会怎样 |
| --- | --- | --- | --- | --- |
| `woke_up` | bool | false | W（开场） | —— |
| `cart_inspected_count` | int | 0 | N（每观察一处 +1，不显示） | 0 也能进镇；只是少了自己亲眼看到的版本 |
| `read_manifest` | bool | false | N（R-01 打开过） | 仍有别的来源告知目的地（F1） |
| `took_cart_blade` | bool | false | N（从货车取走长物） | **false → 公会那场没有"数目对不上"这一幕**；true → 记录与事实第一次裂缝 |
| `sentinel_first_down` | bool | false | N | 逃走也是有效路径 |
| `met_taim` | bool | false | N | 错过了也仍能到镇上；只是 D04 里没人替他说话 |
| `taim_leg_freed` | bool | false | N | 影响泰姆到公会的早晚与态度，**不影响任何解锁** |
| `knows_dont_go_north` | bool | false | N（泰姆最后一句） | 可以在别处听到类似的说法（SOFT，F5） |

### 1.2 Arrival / Act I Early

| flag | 类型 | 默认 | 由谁置位 | 错过会怎样 |
| --- | --- | --- | --- | --- |
| `entered_mistvale` | bool | false | W（进下城区） | —— |
| `spoke_to_brann` | bool | false | N | 可绕过；但若没担保人，门口这条路会反复撞回 |
| `spoke_to_garran` | bool | false | N | 错过 = 少一条最快的钱/住/保路 |
| `spoke_to_rusk` | bool | false | N | 世界不卡；但泰姆会先到公会替他"说了一半"的版本 |
| `has_temp_pass` | bool | false | N（D04 结束） | 这是 Cluster 的第 2 个状态，不是一定要拿，但没它就进不了担保环节 |
| `has_guarantor` | enum | `none` | N | `none / garran / lia / mira`。**三条路必须真的不同**，且**允许一直 none** |
| `has_shelter` | bool | false | N | 第一晚也可以露宿；只是很难受，且夜里会听到遗迹低频 |
| `met_mira` | bool | false | N | 允许只"看见"（`heard_mira`）而从不交谈 |
| `heard_mira` | bool | false | W（进入争论范围内） | 最低接触：知道有个女人跟人吵架很专业 |
| `met_oren` | bool | false | N | **允许全程为 false。** 不设二次机会、不设补偿台词 |
| `saw_lia_state` | enum | `not_heard` | W/N | `not_heard / heard_name / saw_boat / spoken`。**大多数玩家会停在 `heard_name`** |
| `read_echo_01` | bool | false | N（R-02 打开过） | **完全允许错过。Act I 内没有任何后续。** |
| `has_identity` | bool | false | N（Cluster 终点） | 这是 N01 的结束条件，不是 Act I 的结束条件 |

### 1.3 背景信号（FA-01 的 PRE-EVENT，本轮只铺不发动）

| flag | 默认 | 由谁置位 | 备注 |
| --- | --- | --- | --- |
| `heard_fifth_bell` | false | W（事件触发，与玩家无关） | **世界不看玩家在不在。** 只对"在场的人"置位 |
| `heard_ruins_low_freq` | false | W（夜里在户外） | 玩家可能以为是风。**不做任何判定** |
| `noticed_frost_fail` | false | N（近擦近 cold room 或 §7#14） | 极轻。可完全错过 |
| `knows_sentinel_out_of_range` | false | N/W（多来源） | **SOFT**。这是"也许不对劲"的最低版本，不是"我已知道真相" |

> **纪律**：这四个 flag **不接任务、不上 UI、不写日志、不给提示**。它们是噪声，不是线索——至少在 N01 范围内是。

---

## §2 INFORMATION GRAPH（Act I Early）

> 用法：**任何 writing 前先在这里查这条事实有没有第二个来源。** 只有一个来源 → 补一个，或降级为 SOFT。

| # | FACT | POSSIBLE SOURCES | HARD / SOFT | CAN MISS? | ALTERNATE SOURCE |
| --- | --- | --- | --- | --- | --- |
| **F1** | 附近有个地方叫雾栖镇，那里有公会 | R-01 货单 / 旧路路牌 / 泰姆 D01 / 进镇后的公告板 | **HARD** | 基本不可（4 源） | 任一 |
| **F2** | 发生了一起商队事故 | 亲眼 N01-P02 / 泰姆 D01 / §7 第 5 条（有人在议论那趟没到的车）/ 鲁斯克在问"谁在路上" | **HARD** | 否（4 源） | 任一 |
| **F3** | 车上的货是公会的 | R-01 / 泰姆 D01 / 鲁斯克 D04 | **HARD** | 否 | 任一 |
| **F4** | 没有身份就不能留下 | 布兰 D02 / 格兰顺口 / 公告板上的登记字样 | **HARD** | 否 | 任一 |
| **F5** | 北面最近"不太对"（石头走得比人勤） | 泰姆"别往北" / 格兰（若玩家问北面）/ §7 第 8 条孩子 / §7 第 15 条女佣 | SOFT | **可以** | 四个来源互相独立，缺一个没事 |
| **F6** | 今天钟多敲了一次 | 第五钟事件 + §7 第 9 条 | SOFT | **很容易错过**（故意的） | 无补偿 |
| **F7** | 市场那间"冷的屋子"今天没那么冷 | §7 第 14 条（唯一来源，故意） | SOFT | **多数玩家会错过** | 无（这一条本来就是给回头看的人的） |
| **F8** | 奥伦会用剑 | 传闻 / 后院木桩上的切痕 / 他本人绝口否认 | SOFT | **可以完全不知道** | —— |
| **F9** | 那批货的数目和实际对不上 | 仅当 `took_cart_blade == true` 时，在 N01-D04 由鲁斯克念单子触发 | SOFT | 可以没有 | —— |
| **F10** | 三年前那一行拾得记录 | **仅** R-02（Readable） | SOFT | **可以完全没有** | —— |

### HARD / SOFT 的定义（§29）

- **HARD INFORMATION**：主线最终必须让玩家知道（F1–F4）。**但获取途径完全自由** —— 玩家可以亲眼看到、听人说、到镇上听闲话。
- **SOFT INFORMATION**：可以错过、可以换顺序、可以换来源（F5–F10）。**不因为它被错过而补发。**

> 这就是 SEKAI 应该大量使用的叙事结构：**事实是硬的，路径是软的。**

---

## §3 MISS MATRIX（§28 · 错过/失败具体怎么办）

| 玩家没做的事 | 世界怎么办 | 会失去什么 | 会不会被补偿 |
| --- | --- | --- | --- |
| 完全没看那辆车 | 照常。到镇上后会从别人嘴里听到这件事（F2） | 少了"自己亲眼看到的版本" | **不补偿** |
| 没读货单 | 目的地方向由路牌 / 泰姆 / 钟提供（F1） | 少一次 `Readable` 的自然教学 | 不补偿（Readable 之后还会出现） |
| 和哨兵打的时候逃了 | 允许。泰姆照样在沟里 | 没有"取走货车长物"这一分支 | 不补偿 |
| 听完泰姆就走，不救他 | 泰姆晚点到公会，先替自己说了一半的版本 | 鲁斯克对玩家的第一印象不同 | 不补偿，也不惩罚 |
| 直接绕过一切 NPC 冲进镇、谁也不跟说话 | 允许 | Cluster 停留在 `ARRIVED` | NPC 还在原地，没有倒计时 |
| 没有去那条侧道，没见过奥伦 | 允许。他在劈柴 | 藏锋流的门这一轮不开 | **不设二次出现机会** |
| 到了渡口没见到莉娅 | **大概率事件** | —— | **绝不因为她被错过就让她回来** |
| 没翻那本旧册子 | ECHO-01 不发生 | Act I 内没有任何损失 | 不补偿、不追问、不设问号 |
| 一直没找到担保人 | 世界不卡：他仍可以打零工、睡炉边、被人认出是"现场那个人" | 进不了身份环节 | Cluster 停在 `GUARANTEED` 之前，由玩家自己决定要不要继续 |

**唯一不允许发生的事**：世界因为玩家没做某件事而 **停住**。没有一个 flag 是"世界的推进条件"。

---

## §4 最小存档结构（交 MAIN · 不要过度工程）

```text
narrative_state_version : int   # 当前 = 1
flags                   : Dictionary[StringName, Variant]
guarantor               : StringName   # none / garran / lia / mira
```

**约束**

1. **只用 bool / int / 字符串 enum。** 不要嵌套对象，不要序列化对白状态。
2. **不要存"当前任务 ID"** —— Cluster 的五个状态是从 flag **推出来的**（见下文），不是单独存的。
3. 写入时机只在 Scene 的 EXIT CONDITION 处；**战斗中不写任何 narrative flag**。
4. 读档时 flag 缺失一律回默认值，**不做迁移**。

**Cluster 状态是推导值，不是存储值**

| 推导 | 条件 |
| --- | --- |
| `ARRIVED` | `entered_mistvale == true` |
| `REPORTED` | `has_temp_pass == true` |
| `GUARANTEED` | `has_guarantor != none` |
| `SPENDING_NIGHT` | `has_shelter == true` |
| `REGISTERED` | `has_identity == true` |

> UI 目标行（≤15 字）由这五个推导值决定，见 `NARRATIVE_VERTICAL_SLICE_N01.md` §8。

---

## §5 给 MAIN 的接入优先级

**不要一次性实现全部。** 按这个顺序，做完一步就能跑：

1. **`Readable`（`NAR-MAIN-01`）** —— R-01 货单是最简单的一次原型，先有它就能验证 F1 与昵称是否成立。
2. **`took_cart_blade` / `met_taim` / `read_manifest`** —— Prologue 只靠这三个就能全部成立。
3. **Cluster 的五个推导值** —— 有了它们就能做 Q1–Q4（Act I 前半）。
4. **`has_guarantor` enum（三值）** —— Act I 中段之前再做，因为要三条不同写法的内容。
5. **背景信号四个 flag** —— 最后做，而且**真的只要 flag**，不要事件系统。

---

## §5A V0.2 增量指针（PASS 05 · FIRST DAY / FIRST NIGHT）

> 完整表见 `ACT1_QUESTS.md` §19。这里只记**与状态模型有关的四条纪律**，避免实现的人做反。

| 纪律 | 内容 |
| --- | --- |
| **`day_index` 只能是 0 或 1** | 睡一次 +1。**不做日历、不做时钟、不做第三天。** 玩家想逛多久逛多久，世界不按天推进内容 |
| **`slept_where` 不是惩罚状态** | `none / garran_hearth / outside`。露宿只让夜里低频听得更清楚，**没有 debuff、没有提示** |
| **八个 FA-01 信号只是 flag** | 见 `ACT1_QUESTS.md` §14。**不接任务、不上 UI、不写日志、不做"5/8"进度** |
| **关系纹理不是数值** | `Dictionary[StringName, StringName]`，见 `INFORMATION_GRAPH.md` §3。不是好感度 |

**玩家知识（K001–K017）与 NPC 信息差**另见 `INFORMATION_GRAPH.md` §1–§2 —— **那边是"谁知道什么"，这边是"系统记什么"，不要混。**

---

## §6 本轮明确不做

- 不做天数 / 时钟 / 日历系统（FA-01 的"第五钟"是**事件**，不是时间）
- 不做 NPC 记忆、声望、好感度数值
- 不做玩家选择 → 世界 Branch 的自动推理
- 不做 `worldState`（那是很久以后的事；Web 原型里那个雏形**不要照搬进 Godot**）
