# 缚星链 · 美术资产拆分（CHN）

> **用户 2026-09-29 裁定**：锁链优先级现在最高，因为战斗侧正在真实开发它。
> 资产**直接拆成命名件**，`而不是再生成那坨程序圆盘`；待机的四层受控浮链
> **直接做成 authored mesh / curve asset，由 Combat 只控制显隐和释放比例**。
>
> 本文是这条裁定的落地规格。它**不**描述当前实现状态 —— 当前实现在
> `godot/scripts/combat/chain_visual.gd`（2936 行，COMBAT 所有），
> 数值在 `chain_moveset.gd` / `chain_library.gd`，取景与啮合的判据在
> `docs/CHAIN_STOW_TUNING.md`。

---

## 0. 为什么这条裁定是对的（以及它真正的代价）

现在的链是**程序生成的**：`_build_links()` 按 `LINK_FILL` / `ARC_*` 一类的常数
在每个采样点放一个链节，收纳时用四层开放弧排布。它已经做得相当好了 —— 有实测过
的 `stow_interpenetration() = 0`、`stow_frame_reach() = 0.925`、逐层 NDC 读数。

但它是**用参数描述一堆盒子**，所以有三件事它做不了：

1. **表面质量封顶。** 每个链节都是一个 loft 出来的实体，永远做不出锻造的圆角、
   焊口的偏心、以及一根真链子该有的重量分布。
2. **`docs/CHAIN_STOW_TUNING.md` 里已经算死了一条约束**：压扁椭圆
   `ρ = b²/a` 比这张链的最小弯曲半径**紧 5–8 倍** ⇒ 降节距没用 ⇒
   **这根链做不出「小·扁·贴髋」的四层扇面**。程序生成永远受这条物理约束。
3. **判据全都在几何上。** 一旦链节不再是参数，`stow_ring_readings()` /
   `stow_interpenetration()` 就失去了被测对象。

**代价必须写清楚，否则会被当成免费升级：**

> authored arc **可以**画出那根链物理上弯不出来的、小·扁·贴髋的四层扇面 ——
> 这正是做它的最大理由。但这样一来，**释放过程也必须 authored**，
> 不能再从绳的真节距推出来。**画面可以说谎，姿态必须自洽。**

所以「authored arc」不是「把程序圆盘换成好看的 mesh」，而是把收纳与释放从
**几何推导**改成**关键帧表演 + Combat 控制显隐/比例**。这是一次演出范式的更换，
不是一次换模型。

---

## 1. 七个命名件

按裁定原文。命名走 `WPN_CHAIN_<ROLE>`，**不带序号**（它们是可复用件，
不是某个变体）。

| 资产 | 角色 | 数量关系 | 关键要求 |
|---|---|---|---|
| `WPN_CHAIN_HANDLE` | 柄 | 1 | 唯一手持件。origin 在**柄尾连接环**（§2 契约）。握持区要按第一人称 0.3–1 m 做细节 |
| `WPN_CHAIN_LINK` | 链节 | 实例化 N 次 | **一个**链节，被实例化出整根绳。必须保留现有实测的三个半尺寸 |
| `WPN_CHAIN_TRIDENT` | 三叉链头 | 1 | 全族记忆点。**禁黑点/小球**（`docs/` 已两次记录该失败）。中刺 + 两侧后掠叉，叉角**近并行、只留小张角** |
| `WPN_CHAIN_HELD_ARC_A` | 收纳第 1 层（最内，离拳最近） | 1 | 见 §3 |
| `WPN_CHAIN_HELD_ARC_B` | 收纳第 2 层 | 1 | 见 §3 |
| `WPN_CHAIN_HELD_ARC_C` | 收纳第 3 层 | 1 | 见 §3 |
| `WPN_CHAIN_HELD_ARC_D` | 收纳第 4 层（最外，最先放出去） | 1 | 见 §3 |

### 为什么 HANDLE / LINK / TRIDENT 必须是三个独立资产

它们的三条通道完全不同，混在一起就全都改不动：

- **HANDLE** 是**被手驱动的**（姿态键在相机空间，武器驱动 = 指数滞后弹簧 +
  tremor + look_lag）。它的几何必须贴在握持点上。
- **LINK** 是**被数量驱动的**。它唯一重要的是链节尺寸与啮合约束，而
  `LINK_FILL > 1` 时箱体模型失效 ⇒ 判据要走 `stow_ring_readings()`。
- **TRIDENT** 是**被姿态驱动的**（`world_hit_position` + `surface_normal` 的
  固定锚点姿态，墙/敌命中禁用物理摆动）。

---

## 2. 轴向契约

`CHN` 这一行在 `WEAPON_LINE_STANDARD.md` §2 已有，此处只重申并补充链头的：

| 件 | origin | +Y | 备注 |
|---|---|---|---|
| `WPN_CHAIN_HANDLE` | **柄尾连接环** | 链条出去的方向 | 与链节实例化链的第一节对齐 |
| `WPN_CHAIN_LINK` | 链节自身的**接合中心** | 沿链的方向 | 实例化时由 Combat 给姿态 |
| `WPN_CHAIN_TRIDENT` | **连接环** | 指向头部尖端 | `-normal` 是它自己的轴，叉向后张开 |
| `WPN_CHAIN_HELD_ARC_*` | **拳侧的弧起点** | 沿弧的切线 | 四层共用同一个起点族，只有半径不同 |

**四层弧必须共用同一个 origin 约定**，否则 Combat 无法用「显隐 + 释放比例」
控制它们 —— 每一层各自带偏移，就等于把排布数学又搬回了美术资产里。

---

## 3. 四层弧：从参数推导改成 authored

### 现有实现的参数（会被替换，先记下来对照）

| 常数 | 值 | 含义 |
|---|---|---|
| `coil_max` | **4** | 层数。用户 2026-09-29 裁定：余链在**左腰侧**、非闭合圆 |
| `ARC_R_INNERMOST` | 0.130 m | 最内层的弧半径 |
| `ARC_R_GROW` | 0.045 m | 每层向外张开的量 |
| `ARC_SWEEP` | 2.30 rad (132°) | 每层的弧长，留 228° 缺口 ⇒ 读作**开放弧**而不是线轴 |
| `ARC_DEPTH` | 0.048 m | 沿共享法线的深度。**取景主因**：符号/大小错了扇面会从画面边缘走出去 |
| `ARC_START` | −1.15 rad | 弧的入口，在扇形右下、离拳最近 |
| `STOW_ANCHOR` | (−1.040, 0.260, −0.270) | 左腰侧锚点 |
| `STOW_YAW` / `STOW_PITCH` / `STOW_ROLL` | −0.38 / 0.42 / −0.26 | 收纳姿态 |

⚠️ **`ARC_DEPTH` / `ARC_LEAN` / `ARC_LEAD_SLACK` 不是口味值是承重值，而且不单调**
⇒ 调参要**扫不要推**（工装 `.render/sweep_stow.py`，且**每行必须从快照重置**，
否则会读出假解）。authored 之后这条仍然成立：弧的**摆位**还是这几个自由度。

### authored 之后 Combat 只控两件事

1. **显隐**：第 D 层最先放出去，第 A 层最后。`_place_coils` 现有的语义是
   「最外层最先隐藏」——**这条语义必须保留**，否则武器不会像绳子那样从收纳里散开。
2. **释放比例**（0..1）：整组弧从收纳姿态到"全部放掉"的插值量。
   逐层的错开**由 Combat 决定**，不由资产决定。

### 判据（必须继续通过，不能因为换成 mesh 就失效）

- `stow_frame_reach() < 1.0` —— ⚠️ **取景是独立于 breach 的第二种失败**。
  `stow_breach()` 只看画面**中间**，扇面太大**不会 breach，会从边缘走出去**，
  而 breach 恒 0.0000。所以只测 breach 会得到"全绿但画面已经出框"。
- `stow_interpenetration()` = 0（23–27 个链节盒）
- `stow_ring_readings()` —— 环中线 + **段—段**距离。
  `LINK_FILL > 1` 时箱体模型失效，**必须**换这个判据。
- 逐层 NDC 盒（`tools/stow_diag.gd`）+ `tests/chain_v4_slice.gd` 的 **§STOW 组**

### 一个未结的账（不要假装它是绿的）

`coil_max` 从 8 降到 4 之后，`chain_physicality` 断言 **3/7**
（它要求 6–10 圈）**必然红**。这是采信用户裁定的结果、**不是回归**。
状态：**待裁决** —— 要么改断言的门槛，要么接受「收纳不再声称自己物理真实」。
全文见 `.workbuddy/memory/2026-09-29.md`。

---

## 4. 链节的尺寸（不许改，但也不许手抄）

`LINK` 是唯一需要严格保持尺寸的件 —— 因为啮合约束是**尺度不变**的
（`legal = pitch·(LINK_FILL·LINK_TUBE_RATIO − 1)`），**等比缩链节无用**。

⚠️ **本文这里原先写的三个半尺寸（0.0312 / 0.0114 / 0.0473 m）是错的，已更正。**
前两个是 `LINK_FILL = 1.82` 时的值（`0.0473 = link_spacing · 1.82 / 2`），
而 `LINK_FILL` 已经是 **1.752**；第三个在两种取值下都对不上它自己的闭式。
它们是**从注释里抄来的**，不是从运行代码读的常数算出来的 —— 这正是本仓
「不要手抄权威值」那条规矩的又一个实例。

**权威算法只有一处，在 `stow_diag.gd`**（`_bake_links` / `stow_ring_readings`
读的就是它）：

| 量 | 闭式 | 现值（`link_spacing` 0.052，`LINK_FILL` 1.752） |
|---|---|---|
| 沿绳长 | `link_spacing · link_fill` | **0.09110 m** |
| 横绳宽 | `× LINK_WIDTH_SCALE` (0.66) | **0.06013 m** |
| 沿孔轴厚 | `× (1 − LINK_TUBE_RATIO) · 0.5` | **0.01367 m** |
| 管半径 `r` | `link_spacing · link_fill · (1 − LINK_TUBE_RATIO) · 0.25` | **0.006833 m** |

`r` 就是 `stow_ring_readings()` 报净空时**减两次**的那个量，所以 authored 链节必须
和它一致，而不只是「看着差不多」。

| 常数 | 值 | 来源 |
|---|---|---|
| `LINK_TUBE_RATIO` | 0.7 | `chain_visual.gd` |
| `LINK_WIDTH_SCALE` | 0.66 | 同上 |
| `LINK_METALLIC` | **0.20** | 金属陷阱：0.45 仍把收纳包渲染成黑团 |
| `LINK_FILL` | 1.752 | > 1 ⇒ 箱体模型失效，判据换环中线 |

`tools/blender/wpn_chn_build.py` 的 `link_metrics()` 把这四条闭式写在**唯一一处**，
并且 `assert_contract` 用 `extent_band` 断言实测 AABB 落在带内 ——
所以常数一动，构建会**红**，而不是悄悄漂移。

### 一个刻意留下的差别（换 mesh 时必须知道）

authored 链节**把 0.66 的椭圆烘进 mesh**，而不是靠 `_link_basis` 的非均匀缩放。
**外包络完全不变**（啮合读的就是它），但**管是圆的**，不再被压扁到横绳方向的 0.66。
净效果：横绳方向金属更多、孔更小 —— 正是 `LINK_TUBE_RATIO` 注释要求的那个方向，
而且去掉了非均匀缩放。代价是 **`_link_basis` 的 `LINK_WIDTH_SCALE` 那一行必须改成
1.0**，否则 authored 的椭圆会被压第二次。见 REQ-9。

### 圆周分段不是外观选择（20 段）

环在某轴上的**极值只在顶点正好落在那根轴上时才存在**。第一次构建用 18 段
（20° 一步），长轴落在两个顶点之间，链节实测 0.0897 m 而不是 0.09110 m ——
**静默小 1.6%**，而所有断言都过，因为尺寸带容得下。20 段是 18° 一步，
顶点正好落在 0°/90°/180°/270°。（Godot 自己的 TorusMesh 用 `rings = 12`，
30° 一步，90/30 是整数 —— 程序链节是打到极值的，authored 的也必须打到。）

---

## 5. 材质（金属陷阱已经在这条线上踩过两次）

| 件 | albedo | metallic | 备注 |
|---|---|---|---|
| 链节 | 0.72/0.74/0.79 | **0.20** | 0.45 仍读作黑团（实测） |
| 链头 | 0.45/0.47/0.52 | **0.30** | 0.95 是纯黑斑点；0.84 albedo 直接过曝成白纸片 |
| 柄 | 0.26/0.24/0.22 | 0.0 | 深色锚点 |

**框架层已把 `metallic > 0.75` 写成硬断言**（`weapon_common.METALLIC_CEILING`），
链这三件全部低于它。注意链原先是在**代码里**设材质的 —— 搬进 builder 之后
这条断言才第一次真的守得住它。

---

## 6. 交付顺序与状态

1. `WPN_CHAIN_TRIDENT` —— **已交付** `assets/models/weapons/wpn_chain_trident.glb`
   （0.7800 m，1096 tris，与程序链头的 0.796 m 齐平 —— 见 REQ-9 为什么要齐平）
2. `WPN_CHAIN_LINK` —— **已交付** `wpn_chain_link.glb`（0.0911 × 0.0601 × 0.0137 m，320 tris）
3. `WPN_CHAIN_HANDLE` —— **已交付** `wpn_chain_handle.glb`（0.2805 m，1624 tris）
4. `HELD_ARC_A..D` —— **未做，被 REQ-9 挡着**：它牵着演出范式的更换，
   需要 COMBAT 先给出「显隐 + 释放比例」的接口

前 3 件做完，`chain_visual.gd` 就有了可以用 authored mesh 替换的**几何接口**
（三个替换点、各自必须保持的量、以及一个刻意留下的差别，全部写在
`docs/ART_INTEGRATION_REQUESTS.md` 的 **REQ-9** 里）。

Master（可编辑源，Git LFS）：`assets_source/weapons/masters/chn/wpn_chain_*.blend`
规格：`assets_source/weapons/specs/chn_variants.json`
构建器：`tools/blender/wpn_chn_build.py`
出片：`assets_source/review/weapon/wpn_chn/`（9 张）+ `wpn_chn_sheet/SHEET.png`

---

## 7. 这份文档不是什么

- 不是当前实现状态。状态在 `docs/PRODUCTION_BOARD.md`。
- 不是数值权威。数值在 `chain_moveset.gd` / `chain_library.gd`。
- 不是调参指南。取景/啮合的调参在 `docs/CHAIN_STOW_TUNING.md`，**不要往回抄**。
