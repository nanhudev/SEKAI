# SEKAI DESIGN BACKLOG

想法存放区。规则：**Idea ≠ Task**。写进本文件的任何条目都不会自动变成开发任务。
只有满足「能提高当前 Gate」或「能解锁当前 Milestone」时，才由 DESIGN 升级为 MAIN / AUDIO / ART 的任务，同时写入 `PRODUCTION_BOARD.md`。

当前 Gate：**GATE 1 · 30 秒战斗是否有爽点**（Combat Feel MVP）
升级判据（三条都要能答上来，否则继续留在这里）：

1. 它是否改善当前核心循环（不是未来循环）？
2. 它是否解锁当前 Milestone？
3. 它是否便宜到可以现在就做原型？

---

## A · FROZEN DESIGN（明确不启动）

Combat MVP 成立前不动。可以继续讨论、继续写设定，不允许开实现任务。

| 条目 | 为什么冻结 |
| --- | --- |
| 勇者候选人 / 命运节点 / Soul Echo / WorldState | 叙事抢跑：战斗与探索都还没成立，先做这些只是在给空壳挂装饰。**例外：NARRATIVE 线可以在 `docs/narrative/` 里做设计（概念定义 + 事件设计），但实现仍冻结** |
| NPCE 日程 / 记忆 / 关系系统 | 需要先有一个"活着的世界"能站住，否则只是聊天机器人 |
| 第二座城市 / 新区域 / 经济系统 / Boss Raid | 纯内容扩张，对 GATE 1–4 零贡献 |
| 完整职业替代成长树 | 与 LAW 2 相关但属 Vertical Slice 之后；当前敌人都还是 dummy |

---

## B · SIGNATURE 候选（等 CORE FEEL 站住再谈）

SIGNATURE 不得长期挤压 CORE FEEL（见设计警报：演出越来越高级、基础战斗仍然普通）。

| 条目 | 状态 | 前置条件 |
| --- | --- | --- |
| Iaido / 聚合斩 二次打磨 | 进行中 | 用户实际试玩 7.2s 版本，给出"太快 / 没重量 / 看不懂"级别的反馈 |
| 高阶技能改变 Perception / Space / Time 而非数值 | 原则已定 | 至少一个敌人的战斗节奏成立之后 |
| Reality Cut 的空间几何化（斩线变成可交互的空间结构） | IDEA | Iaido 手感验收通过 |
| 魔法需要形成空间几何、环境可改变魔法 | IDEA | 三系魔法的可读性与差异化验收通过 |

---

## C · INTERACTION 候选（System A × System B）

优先来自系统之间，而不是不断增加孤立系统。每个候选必须能一句话说清"玩家会因此做什么新决策"。

| 组合 | 预期玩家行为 | 状态 |
| --- | --- | --- |
| Frost → Frozen → Heavy → Shatter | 已有；需要验证是否真的产生组合玩法，而不只是脚本连招 | VERIFY（GATE 1） |
| Wind × Fire → 火焰沿风向蔓延 / 改变火球轨迹 | 用风改写火焰的落点与覆盖面 | IDEA |
| Frozen × 物理力 → 碰撞 / 破碎位移 | 用冲撞把冻结目标当成武器或地形 | IDEA |
| 环境 × 魔法 → 同一法术在不同场景产生不同结果 | 观察环境再决定放什么 | IDEA |

---

## D · 已降级 / 观察中

| 条目 | 说明 |
| --- | --- |
| Ability Wheel 轮盘 | 当前为技术占位；Combat Feel 阶段不投入美术 |
| 正式第一人称剑（C2B-01） | 已在 ART 排期，作为 TempSwordVisual 的替换项，不阻塞战斗调优 |
| Web 原型遗留内容（雾栖村、五名 NPC） | 保留为参考，不在 Godot 线复活 |

---

## E · 每次 Milestone Review 要复查的问题

- SIGNATURE 是否已经挤压 CORE FEEL？
- 本文件的条目有没有因为"最近一直在讨论"而被误当成任务？
- 有没有出现重复劳动（例如 MAIN 与 ART 同时在做剑）？
