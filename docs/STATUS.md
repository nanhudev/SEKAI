# SEKAI MVP 0.1 状态

## 2026-09-28 · 单手剑 · PART J §27–§32 六通道审计：剑终于会回答"我碰到了什么"

这一轮做的是「把手感变成断言」，但真正的产出是**三个一直存在、一直没人看得见的 bug**。
它们都不是调参问题，都是"测量在说谎"或"信号来自错误的地方"，所以先说 bug，再说数字。

### 1 · 接触形变一直由抖动触发（生产 bug）

`temp_sword_visual._on_sword_hit` 用 `_pose_tip() - _tip_prev` 求刀的行进方向，而
`_tip_prev` 在 `_contact_step()` 末尾就被赋成本帧刀尖。`hit_landed` 是**信号**，不是
`_process` 里的调用点，所以这个差值恒等于 0——唯一让它非零的是 tremor 在
`_contact_step` 之后又改了一次 `pose_position`。

**结论：剑的接触方向一直是 47rad/s 抖动的随机方向，不是挥砍方向。**
去掉 tremor 后实测 travel = `0.000000`（真实挥砍是 `0.1733` m/帧，约 10 m/s）。

修法：在 `_contact_step` 里把本帧行进量存成 `_travel_step`（**在 tremor 之前**），
handler 只读这份记录。这同时也是"下一次接触不和上一次吵架"的唯一保证。

### 2 · 战斗窗口的时钟从墙钟换成游戏时间后，t=0 的窗口全部"开着"（生产 bug）

`combat_time` 从 0 开始，而 `riposte_until` / `bind_until` / `followup_until` /
`slip_until` 默认也是 `0.0`。判据 `now <= until` 在 `0 <= 0` 时为真，于是
**一局游戏的第一刀是反击招式**（`uni_riposte`）。墙钟起始值是 1.1s，恰好把它藏住了。

修法：所有窗口判据改为**严格 `<`**——`until` 到点即关闭，`0.0`（从未开启过的窗口）
天然关闭。新增 `godot/tests/combat_clock_integration.gd` 专门守住这件事，并且它
**必须在第一帧之前问**（晚一帧时钟就是 0.016，整类 bug 消失，测试会全绿地骗人）。

### 3 · 三个测试把生产代码的时钟重写了一遍（测试 bug）

`parry_riposte` / `white_rose` / `flowing_wind` 里硬编码 `Time.get_ticks_msec()/1000.0`
当作战斗时钟。控制器一换时钟，它们就全红。改成向 `combat._now()` 要时间。

### 4 · 回风测试其实在测另一首歌（测试 bug，表现为"抖动"）

`_frames_until_dodge_cancel()` 在折柳刚开完 0.9s 反击窗口之后立刻 `request(&"light")`，
落在窗口里就拿到 `uni_riposte`，取消窗口完全不同。机器快慢决定采到哪一首，
所以它 1/4 概率红 —— 报的是"基线轻击根本不可取消"，而它测的从来不是基线轻击。
加了 `_neutralise()`，并断言采到的招式确实在 light chain 里。

### 5 · 六通道读数（`sword_feel_channels`，噪声底 0.0000m）

| 通道 | 断言 | 实测 |
| --- | --- | --- |
| A 接触 vs 落空 | 手要真的给答案 | 入肉形变 `0.0330m`，落空 `0.0000m` |
| A 形状 | 路径偏离要打赢"两次落空之间"的底 | 偏离 `0.0303m`，底 `0.0000m` |
| A 第二次接触 | 方向仍须是挥砍方向，不是弹簧回弹 | 与姿态行进夹角余弦 `0.88`（-1 = 直接弹回） |
| A §31 恢复 | 命中比落空收得更快 | 命中 24 帧 · 落空 29 帧 |
| B 出刀时刻 | 音效/相机属于刀离开那一刻 | startup `0.085s` · 信号 `0.090s` · whoosh `0.097s` |
| C hitstop | 轻/重/格挡/碎 是四个答案 | 轻 `0.026` 重 `0.058` 挡 `0.022` 完美 `0.060` 碎 `0.105` |
| D 窗口不被吃 | hitstop 不能收走玩家的决策时间 | 干净 `0.261s` · 冻结后 `0.253s`（97%） |

**噪声底做到 0.0000 的手段**：把控制器和武器从树的时钟上摘下来，用固定 `1/60` 手动步进。
在此之前所有指标（逐帧、相位、弧长重参数化、路径长度）量到的都是循环本身，噪声底等于信号。

### 6 · 变异验证：15/15 全部打红

`/f/tmp/_mutations.py`（M1–M7 打六通道，C-riposte/bind/followup/slip/wall/stop 打时钟）。
**一个突变没被打红 = 那条断言是装饰**。这一轮真的抓到过两条装饰断言：
- 时钟测试最初晚了一帧才问 → C1 全绿。改成在 t=0 问。
- bind / followup 窗口有第二重条件（`state == PARRY`、`pending_followup_id != ""`），
  不满足时断言恒真 → 现在先把条件满足，再问。

**不装的突变**：把形变回读进行进量（`_pose_tip() + _contact_offset`）**没被打红**，
原因是物理而非测试弱——命中后 4 帧弹簧正在峰值附近，每帧 `0.018m` 对上挥砍的 `0.17m`，
只把方向拧了几度。喊狼来了的突变比没有突变更糟，所以跑的是更狠的版本
（方向直接取自弹簧 → `-1.00`，被打红）。

### 7 · 判定口径

全部结论为 **TECHNICALLY VERIFIED / INTERNAL CANDIDATE**。
第一人称手感**没有**在可见桌面上跑过（本环境无窗口句柄），
`USER GAMEPLAY VERIFIED` 只归用户。

## 2026-09-28 · 闪避 · PART J §27–§32 四时刻：它现在会走，也会说话

闪避是游戏里唯一一个"位移"动作——0.36s 内把玩家搬两米。而它之前是：

```gdscript
State.DODGE:
    position = moveset.idle_pose + Vector3(-side * 0.16, -0.12, 0.1)
```

整个状态一个常量偏移。手在第 4 帧出去，然后一直撑到状态结束才回家。
测出来是 `=*#%%%%%%%%%%%%%%%%%%` —— 一个台阶，不是一次移动。**没有"到达"的位移 = 带时长的瞬移。**

### 1 · 三拍姿态曲线（`_dodge_pose_k`）

按闪避自身时长走三拍：

| 段 | 含义 |
| --- | --- |
| `0.00–0.18` | **离开**——身体走了手没跟上。这是第一人称里唯一能说"是我动了"的东西 |
| `0.18–0.62` | **追上并越过静止位**——身体在减速，刀继续走；越过才是"停"读起来像"停" |
| `0.62–1.00` | **归位**，且在状态结束前就到家，最后几帧玩家可以出手而不是等弹回 |

测出来 `:=*%%%%#*+-. .:...`：峰值 `0.1446m` @ 第 5 帧 / 共 21 帧，末帧 `0.0068m`。

### 2 · 闪避成功之前完全没有回答

`_on_player_hit` 里是 `if state == State.DODGE and state_time < 0.2: return` ——
hitstop 0、相机 0、无信号。**一次成功的闪避和一次落空完全无法区分。**
§30 说落空要读起来像落空，它的镜像就是"躲开要读起来像躲开"。

新增 `dodge_evaded` 信号 + `dodges_landed` 计数 + `0.045s` 顿帧 + trauma `0.14`。
**刻意比任何命中的顿帧都短**：这是擦身而过，不是挨打，给它一击的分量
会让"躲开"比"挨上"更重。顺带把埋在控制器里的 `0.36` / `0.2` 提成
`tuning.dodge_duration` / `dodge_iframes`。

### 3 · `dodge_channels` 读数与变异 5/5

| 通道 | 实测 |
| --- | --- |
| A 四时刻 | 峰值 `0.1446m` @ 第5帧/21（首 `0.0357` · 末 `0.0068` · 最大单帧 `0.0418`） |
| B 方向 | 左右手位相差 `0.3018m` |
| C 躲开的回答 | 顿帧 `0.045` · trauma `+0.14` · 信号 ✓ · 计数 +1 |
| D 收势 | `0.0012m → 0.0009m` · 最大跳 `0.0004m` |

变异 5/5 全红：不归位 · 无视方向 · 躲开裸 return(3) · 不落家 · 无位移(4)。

**两条断言是被变异逼出来加强的**：
- 「末帧离位」从 `0.75×峰值` 收到 `0.25×峰值`——0.75 会放过"只回了一半"的同款缺陷。
- 新增「闪避过程中不得瞬移」（单帧 < `45%` 峰值）。原四时刻断言会被
  「渐进出去 + 一帧跳回」骗过（峰值在中段、两端都靠近静止位，全绿）。
  `45%` 不是 `10%` 是因为**离开就该快**（闪避是爆发），要禁的是台阶不是陡坡；
  台阶是 100%+，实测突变 135%。

### 4 · 本轮新踩的两个坑

1. **GDScript lambda 按值捕获**：`var answered := false` + `connect(func(): answered = true)`
   —— 信号确实发了，测试永远读到 false。要用成员变量或容器。
2. **突变脚本 `if n != 1: skip` 会跳过还原**：`* k` 在文件里有两处，替换 2 处后被判定
   "未应用"且不还原，突变留在树里活了一整轮，表现为"峰值位移掉到 0.0043m"。
   → 模式要匹配整条语句保证唯一；还原必须在 `finally` 里。

回归 25/25（含新增 `dodge_channels`）。结论仍为 TECHNICALLY VERIFIED / INTERNAL CANDIDATE；
第一人称手感未在可见桌面跑过，`USER GAMEPLAY VERIFIED` 只归用户。

## 2026-09-28 · 缚星链 · WEAPON SYSTEM PASS：三个形态的设计 + 实链手感通道

用户这一轮给的是 `WEAPON SYSTEM PASS — CHAIN EVOLUTION + CROSS-WEAPON COMBOS`（§0–§52），
核心约束一句话：**只保留已有单链原型，不推翻；升级 ≠ 替换**。

### 1 · 交付物一：`docs/CHAIN_DESIGN.md`（CHAIN SYSTEM DESIGN V2）

三形态不是强度阶梯，而是**三个不同的"链是什么"的答案**：

- **实链**——重量 / 冲击 / 张力的答案（本轮在手感上落地的那一个）
- **游链**——动量 / 移动 / 轨迹的答案（锚点钟摆）
- **律链**——**关系**的答案（虚锚、敌↔敌、敌↔环境）

外加两条正交轴（**武器形态 × 强化重量**：轻 折轨 / 中 连衡 / 重 坠星只在第一批量做）、
元素附魔层（火/冰/风，**元素是行为不是伤害数字**）、机会标签 + 武器链接
（**明确不是 QTE**，是可忽略的轻提示）、学/忆/悟 与剑大招「无间」草案（**只设计不实现**）。

**§52 判定口径已写进文档**：若三形态最终读起来是"短链 / 长链 / 四条链"，即 **FAIL**；
每形态必须提出自己的问题（实链：我能把什么拉过来？游链：我能从哪里借势？律链：我能让哪些东西彼此产生关系？）。

### 2 · 交付物二：实链 §43 手感通道（冲击 / 回收 / 绷紧）

**这一轮做的是"把手感变成断言"，不是调参。** 三条通道各自有可测量、可变异验证的检查：

| 通道 | 做法 | 实测 |
| --- | --- | --- |
| **冲击** | 落点代价 = 目标重量 × 头部速度 → 扣势能 + 弧线偏折 + hitstop(0.55–1.35×) + 相机 | 轻 势=0.282 偏=-106.4° · 重 势=0.215 偏=-102.4° |
| **回收** | 回程先**外漂再收**（过冲 + 半径外漂），输入锁不变 | 外漂 +0.13m · 过冲 10.8° |
| **绷紧** | 链线**垂直抖动**（两端为零）＋ 相机 1.80° 挤压 ＋ 沿链冲量 | 紧 离直 0.0059m · 松 0.7820m |

`max_radius 4.6` 是**保留项不是 TODO**：短链是残酷的中近距离武器，本轮不拉长。

### 3 · 交付物三：`chain_tour_clean.mp4`（**无 Debug HUD 也要看得懂**）

733 帧 / 41.40s / 1280×720 h264。**Clean 模式只剩形态名，`R=`/`M=`/`T=` 全部隐藏**
（§46）；字幕改为自动换行（此前被右边缘裁掉）。新增第 10 章「钩住头顶横杆」，
唯一一章只有"抛出跟准心"才拍得出来的内容。

### 4 · 本轮附带落地

- **§45 高阶锚点**：双柱龙门 + 可钩横杆；锚体挂在臂**下方**（扫掠射线先测实体世界）。
- **§13 抛出跟准心**：`aim_pitch_scale` opt-in（仅 `ch_hook`）。没有它，世界里所有高的东西都钩不到。
- **§46 开发者读数闸门**：非开发者模式只显示形态名（非空，HUD 不会空行）。
- **§49 事件接口**：`tug(step,total,amount)` / `wall_impact(strength)`，AUDIO 订阅；记数有断言守着。

### 5 · 验证

- `chain_integration` **PASS**；`movement_lane` / `combat_lab` / `hitbox` / `combo` 回归全绿。
- **每条新断言都单独做过一次变异测试**（下一步那条 15 倍 bug 的教训：断言必须会红）。

| 变异 | 期望 | 结果 |
| --- | --- | --- |
| 落点代价归零 | 冲击两断言转红 | **FAIL 2** ✔ |
| 回收过冲归零 | 回收两断言转红 | **FAIL 2** ✔ |
| 拆 §46 闸门 | 读数泄漏 | **FAIL 4** ✔ |
| 抛出不跟准心 | 高阶锚点抓不到 | **FAIL 1** ✔ |
| 拉扯不广播 tug | 记数不符 | **FAIL 1** ✔ |

每次变异后逐字恢复并核对 md5（`chain_moveset` `bff0e173…` / `chain_library` `4a2ace6a…` / `chain_director` `09e6c68d…`）。

**仍未验收**：手感本身（§51/§53 需要可见桌面）；游链是否进入实现，待实链手感过关后再决定。

## 2026-09-28 · 缚星链 · 拉扯的顿挫 + 一个假了 15 倍的距离口径

用户这一轮的要求只有一句：**"可以做长一点，有拉扯的顿挫感"**。
链的 Phase 0–1（SWEEP / MOMENTUM / TENSION / HOOK）已经能跑，这一轮做的是**拉扯（pull）的节奏**，
过程中挖出一个比节奏重要得多的问题。

### 1 · 拉扯现在是「五记递减的顿挫」

一次位移交付的拉扯读起来是**吸附** —— 身体刚才在那儿，现在在这儿，中间没有任何东西抵抗过，
所以"重"永远只是表格里的一个数字。

- `ChainMoveset` 新增 `pull_tugs = 5` / `pull_tug_gap = 0.24s` /
  `pull_tug_curve = [0.28, 0.24, 0.20, 0.16, 0.12]`（求和 = 1.0）／每记的 hitstop / 相机抖动 / **有方向冲量**。
- `ChainDirector._apply_pull()` 改成**只武装**，`_step_tugs()` 按曲线逐记交付，
  所以身体在两次拉扯之间会真的停一下。
- **share 决定距离，gap 只决定节奏。** 5 记的总位移与 1 记完全相同 —— 调节奏不会再悄悄改平衡。
- 链「松脱」**不取消**已经拉出去的那几记（绳子已经拉过了；而且地砸 / 拉近斩是"拉且松"，
  取消就等于它们撤回自己那一记）。

### 2 · 找到并修掉：`pull()` 声称的距离假了 15 倍（本轮真正的收获）

"player_share 0.35" 声称"0.8m 的被拽"。实测**不是**。

`PlayerMovement.push()` 每帧把推力**加进 `velocity`**，而行走求解器的加速度斜坡
（`acceleration = 14`，每帧只收 0.233 m/s）远慢于推力本该有的衰减，
于是同一笔推力被 `move_and_slide` 反复花掉，直到斜坡把它磨平。

- 探针实测：`pull(0.25)` → 玩家移动 **3.75m**（**15.0 倍**）；`pull(0.5)` → 6.6m。
- 修法：把推力当**瞬态** —— `move_and_slide()` 之后从 `velocity` 里扣回，
  `external_velocity` 成为唯一载体。逐帧积分正好等于请求的位移。
- 修完实测：`pull(0.5)` → 0.500m（比值 1.00）；重量表中 / 重两行与声称值差 **1% 以内**
  （medium 1.02 vs 1.035，heavy 0.80 vs 0.805）。
- 顺带删掉 `_tug_residual()` —— 那个 `(1 - exp(-k·gap))` 补偿本来就是为了抵消这个泄漏，
  修好之后它会在**反方向**错 31%。**是删掉，不是重新调参。**

**为什么这个 bug 能活这么久**：整套测试都在断言"**哪个身体动了、朝哪个方向**"，
从来没有断言过"**动了多远**"。而 15 倍在截图上完全看不出来 —— 被拽 3.75m 看起来很正常，
它只是不是那个机制。新增 `_check_a_pull_moves_the_distance_it_states()`（±15% + 方向 + 推力已清空），
变异测试（把泄漏放回去）→ `FAIL: 5 problem(s)`，其中一条正是 `factor 37.13`。

### 3 · 渲染暴露的两个真问题（不是测试凑数）

把钩系章节的时间线拉长以便看清顿挫，结果：

- **出口输入落到了窗口外**：轻行 `缚` 开 1.00s，而把 `拉近斩` 推到 2.35s（＝窗口关闭后 0.6s），
  渲染器直接打了 `!! light refused`。**拉扯比缚窗口长是设计**（见 `_release_hook` 注释），
  出口是另一条截止线 —— 两者不能混为一谈。
- **重行的失败是静默的**：重型 `缚` 只开 **0.40s**，`地砸` 被推到窗口外之后
  **没有报错**，它安静地播了 `蓄势回旋 → 甩星`。字幕说的和画面上演的不是同一件事，
  日志里一个字都没有。现在时间写在注释里：**出口必须落在它要退出的那个窗口内**
  （轻 0.75s 处 / 重 0.25s 处）。

### 4 · 交付物

- 集成测试：`chain_integration` **全绿**（新增 2 项：距离口径 + 顿挫 5 记；两项都做了变异测试）。
- 回归：`movement_lane` / `combat_lab` / `hitbox` / `combo` 全绿（`player_movement.gd` 是共享文件）。
- 影片：`.render/chain_tug` → `chain_tour_clean.mp4`（9 章，钩系四章全部重排时间线）。
- 文档：`COMBAT_DESIGN.md` 新增 **§19 缚星链**（此前**链一条文档都没有**）；
  `COMBAT_SFX_BRIEF.md` 新增 **Priority G**（19 条链音效，核心是 `ch_tug` 三阶递减）。

### 5 · 未验收 / 风险（诚实标注）

- **§51 / §53「3 分钟试玩」手感验收**：未验收，需要用户可见桌面。
- **拉扯的"停"有多明显，仍未在可见桌面确认**：`gap 0.24s` 下，一记拉扯的 88% 在 0.20s 内花完，
  所以两次之间只有约 0.04s 是真正静止的。数值上它是锯齿（速度掉到 ~10% 再跳回去），
  但"看起来是不是顿挫"必须动起来看。**如果不够顿，要调的是 `pull_tug_gap`（不是曲线）。**
- **这是一次对链的隐性削弱**：拉力小了 15 倍，`缚` 把重型敌人拉过来的 0.8m
  现在真的是 0.8m。所有依赖"被拽多远"的手感都需要重新确认。
- 重行的 `缚` 窗口只有 0.40s，是全程最紧的时序；8fps 下一帧 0.125s，余量很小。
  **这是设计（重型给最短窗口是反制手段），不是 bug**，但演示必须把事件放在窗口靠前处。
- 链的音效、手 / 前臂动画全部未到位。

## 2026-09-28 · 聚合斩 · 玻璃被裂缝真正切开（V7.1）

用户复看视频后报了三个症状：**玻璃那一段出现了两次 / 斩不对 / 玻璃还是没有被裂缝斩开**。
定位与修复（全部量化验证，非目测）：

1. **玻璃层从未携带 A/B 分离（根因之一）**。pane mosaic 覆盖 92% 画面（6.7→8.7s），
   但两个半边焊死——裂缝在玻璃上只是一条墨线，世界切开的伤口在玻璃接管瞬间"愈合"。
   修复：`IaidoDirector` 把它推给世界 pass 的同一个 `separation_px` / `split_shear`
   传进 `IaidoGlassLayer.stage()`；每片 pane 按其所在侧（**shader 坐标系的 side，注意
   与 bake 的 y-up across 关于 y 镜像**）位移 `separation×bias_amp(0.9/1.1)×(法线+剪切)`。
   新消融开关 `SEKAI_NO_PANE_SPLIT`：关掉后远场差异归零（0.6–1.1%）、差异集中在
   伤口带 |ad| 25–90px（16–18%）——玻璃的伤口是几何性的，不是画上去的。
2. **采样补偿**。冻结捕获本身已含分离，pane 位移后必须以 **+δ**（自身 uv 位移）补偿
   `world_capture` 采样，内容才钉在世界"已分离表面"的材质上；取 **−δ** 会叠三层位移
   （整幅滑动），不补偿则在换手瞬间内容跳一整格 separation。裂缝贴图（crack/edge/flow
   mask）仍用未补偿 uv——网络焊在表面上，不焊在屏幕上。
3. **"出现两次"= 暗色闪烁（根因之二）**。世界 shader 的 stream 楔形原在 pane 不透明
   之前就开始吃世界（lead−0.14 vs pane 在 lead+0.06 才不透明），前缘扫过的每个像素
   都"世界→变暗→玻璃"闪一下，读成第二个亮世界盖回来。修复：吃世界楔形改为
   `lead+IAIDO_EAT_AFTER_PANE(0.07)` 起（pane 不透明之后）、`IAIDO_EAT_TAIL(0.20)` 收尾；
   stream=1 时 lead=1.14 仍覆盖全行程，角落照常被吃。
4. `split_shear`（0.50）从世界 shader 硬编码升格为 `IaidoTuning` 字段，世界与玻璃共用。
5. 测试：`_verify_glass_carries_the_split()` 五条断言（分离传递 / 消融开关存在 /
   side 取 shader 坐标系 / bias 携带 / 采样补偿为 +δ，负向测试确认守卫会红）；
   吃世界晚于 pane 不透明由 include 常量数值比较断言。全套 PASS。

遗留：**"斩不对"的具体所指未确认**（斩线方向？位置？挥刀轨迹？）——玻璃修复后斩痕
在 6.7s 后不再消失，若仍不对需用户指认。UE5 烘焙仍是无主切均匀 202 格 Voronoi
（§12–17 的分层拓扑未满足，交接已写入 `docs/UE5_VFX_LAB.md`）。§28 音频请求已转
`docs/AUDIO_STATUS.md`。并行会话正在重写 Mistvale 场景/链系，跨进程渲染对比有
~3% 场景噪声，本轮全部对比均为同进程内消融。

## 2026-09-28 · 聚合斩 · 演出时序 V6（时间暂停终于真的暂停了）

用户这一轮给的是**一次逻辑重排**加**四条修正**，两者都已落到 `IaidoTuning` 一处权威。

**V6 时序（总长 9.90s）**

```
0.00-0.26 A 世界静止      0.26-1.06 B 刀归鞘位     1.06-3.06 C 蓄力 2.0s
3.06-3.24 D 灰化落地      3.24-3.58 D 时间暂停      3.58-3.68 E 落座
3.68      E 入鞘咔哒      3.68-4.68 E 整整一秒      4.68-4.78 F 瞬拔
4.78-6.10 G 玻璃化流       4.90-    G 逐片脱落        5.35-5.50 I 英雄定格
6.10-7.30 H 漂浮旋转      7.30-8.40 J 归鞘          8.40      J 末次咔哒
8.46-9.15 K 吞噬          9.15-9.90 L 回复
```

四条修正：① 灰化改成**从鞘口扩散**（`grey_spread` 是前缘，不是全局滤片）；② 吞噬要**连手和剑那层一起吞**
（`temp_sword_visual.swallowed`），并且玻璃面板也要被吞（它们是最远离虚空的一层）；
③ 蓄力的扭曲**不许断电**；④ 裂缝**放大**。

### 可测量结果（这一轮全部是量出来的，不是看出来的）

| 断言 | 修前 | 修后 | 控制组 |
| --- | --- | --- | --- |
| 灰化+暂停窗口 3.24–3.58 像素变化 | 9.96% | **0.00%** | 27.40%（4.90–5.10 流式玻璃化） |
| 「整整一秒」3.68–4.68 像素变化 | 0.78% | **0.00%** | 同上 |
| 末帧平均亮度（仪式结尾） | 0.0995（虚空） | **0.6725** | 0.6683（开场帧） |
| 蓄力扭曲空窗 | 0.26s | **0s** | — |

### 找到并修掉的五个缺陷

1. **`stream` 楔形永远不释放** → 世界从 5.3s 起被吞且再也回不来，仪式**结束在一个空帧上**，剑浮在里面。
   末帧亮度 0.0995 vs 开场 0.6683。像素差是唯一抓到它的手段。修法：`eaten *= 1.0 - dissolve`
   ——`dissolve` 本来就是裂缝与玻璃化读取的「回复正在倒带」项。
2. **SubViewport 陈旧帧被继续合成**。`UPDATE_DISABLED` 不**清空**纹理，只**冻结**它；`image_rect`
   是全屏 blit，于是最后一片玻璃一被剔除，整层玻璃就永久挂在画面上（吞噬与回复全程）。
   同一个 t=9.20，**新进程**渲染出正确虚空，**同进程顺序步进**则渲染出满屏亮面板。修法：
   `_publish()` 统一移动 blit 与 viewport，四个调用点不再各写一半。
3. **相机半度呼吸写在墙钟上**。它从 `time_stop_end`（3.58）跑到 `fov_pull_end`（4.78），而窗口二
   恰好是 3.68–4.68 —— 于是「绝对静止的一秒」里相机一直在微动。差分图上所有变化像素**都落在轮廓边**、
   平坦天空与地面零变化，这是**亚像素相机位移**的独有指纹。修法：时长与进度都改到 stopped clock 上量，
   呼吸于是**停在半度的峰值上**、世界在那一刻死掉、再由那一口气呼进瞬拔。
4. **裂缝放大时把 V1 的「蓝棒子」判据又踩了**。初版把 `gap_max_px` 提到 22 而 `separation_px` 只有 14，
   裂口比揭示它的位移还宽，正是 V1 从另一侧回来。改为两项一起放大、比值保持从属（13px 裂口 vs 每侧 20px
   位移 = 40px 错位），并且**判据从像素预算改成比值** —— 预算是错的守卫，它会放过棒子、卡住正确的改动。
5. **蓄力扭曲 0.26s 断电**。`suck_end` 停在 3.10，而窗口 3.24 才关：最后 0.26s 三个壳与真空全部停在鞘口。
   修法：壳与壳**真实重叠**（0.60/0.52/0.44，各自在上一壳塌陷途中开），真空跑到 `time_stop_start`。

### 新增守卫（两条都做过负向测试）

- `_verify_timeline`：**任何压缩都不得有死瞬间**。用真实的窗口做结构判定（窗口并集无孔 + 覆盖到
  `time_stop_start`），不是采样曲线。负向测试把 `suck_end` 改回 2.98 → 报
  `already stopped by 2.98s, 0.26s before it should`，与手算一致。
- `_verify_camera_is_dead_in_stops`：在每个窗口内取三个时刻，逐项比对 `iaido_pitch / iaido_still /
  fov_hold / iaido_frame`。负向测试把呼吸改回墙钟 → 报
  `camera iaido_pitch keeps moving inside the dead window at 3.68s (0.00393 -> 0.00785)`，
  即 0.225° → 0.45°，正是那半度。**这条能说出是哪个量在动，像素差分说不出。**

### 新增工具

- `godot/tools/sync_iaido_tuning.gd` — 从脚本默认值重写 `.tres` 并**回读校验**。此前的正则法已经害过一次
  （陈旧 `.tres` 静默回退整条时间轴）。首次运行抓出 15 个字段不同步。注意 `CACHE_MODE_IGNORE` 是必需的：
  `load()` 按路径缓存，否则「校验」比的是刚加载的旧对象，永远自证通过。
- `godot/tools/dump_iaido_cues.gd` — 编码时向引擎索取 cue 表。手抄的镜像已经漂了：
  `pressure` 2.50（实为 2.14）、`spin` 6.25（实为 6.45），影片音频最远偏 0.36s 而无人报警。
- `encode_iaido_movie.sh` — 新增**结尾亮度守卫**（末帧 vs 首帧比值，低于 75% 直接失败）。
  本次：`luma: first=178 last=184`，330 帧 → 11.000s，15 条 cue 取自时间轴。

### 尚未验证 / 风险

- 放大后的裂缝只在 1280x720 + `CombatSandbox` 占位场地验过；真正的高对比度环境（有近景轮廓、有天空渐变）
  下 13px 裂口是否仍读成「伤口」而不是「缝」，需要 ART 线换掉 `ArenaDressing` 后再看。
- 玻璃面板的吞噬沿斩击方向 `travel` 错开 0.35，是设计判断而非用户要求；若用户想要「整体一次性吞掉」，
  改一个系数即可。
- 手感类验收（蓄力节奏、瞬拔的暴力感）本环境无可见窗口，仍需用户在可见桌面确认。

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


---

## IAIDO 线 · FINAL LOCK PASS 4（2026-09-28）

> 本节由 Iaido 线追加，只涉及本线文件。COMBAT 的未暂存改动未被触碰。

**结论：PART A–F/J/K/Q 已落地并可复现；PART B 的「只留位移」极限情形不成立，如实标注。**

### 两个根因（都是量出来的）

1. **应力门被当成「世界被吃掉多少」的门。** 前缘 `FRONT_PER_FRACTURE` 360 时在切口两侧各吃掉 ±148 authored px（720p ≈197px 的近黑楔形）。用户说的"世界裂口像 Overlay"是**经由 EAT** 到达的，不是经由 slot。→ 360→90，`FRONT_CORE` 0.78→0.50，`FRONT_TAIL` 2.0→1.0。
2. **一个门在干两件事。** 裂纹网是细缝、该宽；被删掉的世界是**填充区域**、宽度就是画面损失。拆成 `iaido_grown()`（STRESS，宽）+ `iaido_claimed()`（GLASS，窄）：只有后者能删世界，且同时门住 pane 的 alpha，所以洞和盖住洞的玻璃**按构造同形**，不再靠调参对齐。GDScript 侧镜像 `claimed_at()`。
3. **敌人不在刀面上**（独立 bug）。`collector.collect_targets()` / `executions` 一直是健康的 —— 不是管线断了，是几何：`signed_dist` origin 0.25m / head 1.15m，刀面从身体上方掠过。`TechnicalDummy` → `(-2.45, 0.25, -3)` 后两侧异号。

### 新增不变量（已做双向突变检验）

`CLAIM_TAIL * FRONT_PER_FRACTURE ≥ slit_half`（否则洞内露出活世界）**且** `≤ slit_half + 14 authored px`（否则读成「带子」）。`gap_ratio` 仍受项目原有 0.75 硬顶约束。

### 关键数值

`separation_px` 26→11｜`gap_ratio` 0.34→0.60｜`CLAIM_CORE/TAIL` 0.07/0.32→0.05/0.16｜`void_edge_width_px` 3→4.5｜`collapse_gap_px` 8→18｜void 三色 −45%｜`drained_world_*` 与 void 对齐。

### 消融（PART S）

| 检验 | 结果 |
|---|---|
| TEST 1 关玻璃 | 仍读成世界断开 ✓ |
| TEST 2 关裂纹贴图 | 仍读成世界断开 ✓ |
| 额外：删掉洞、只留位移 | ✗ 8–14px 位移在这套白亮低对比构图里单独读不出来 |

第三项**未修**：项目有 `gap_ratio < 0.75` 的既有硬规则（洞必须比位移窄），且真正的问题是机位把切口放在了天空与空地上。

### 交付

`.render/iaido_final_pass4.mp4`（330 帧 / 11.0s，15 条 cue 由 `dump_iaido_cues.gd` 读出）、`iaido_pass4_split_hold.png` / `_pre_click.png` / `_post_click.png`、`iaido_pass4_before_after.png`（`tools/iaido_pass_compare.py` 生成）。编码脚本自带的首/末帧 luma 检查通过（178 → 183）→ restore 确实把世界还回来了。

### 未做

PART J 的敌人断面视觉未在最终帧里单独验收；PART L 的 SPLIT VARIANT 走的是现有 `cleave` 回退；PART R 的 UE5 fracture topology 未动。
