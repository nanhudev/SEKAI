# SEKAI 武器线 · WEAPON LINE

> 入口文档。三份文件各管一段，别互相抄。

| 文件 | 管什么 | 什么时候读 |
|---|---|---|
| `WEAPON_LINE_STANDARD.md` | **怎么造**：命名 / 轴向契约 / 部件 / 材质族 / 三角面 / 挂点 / 导出入库 / DONE 条件 / 自审八问 / 与现有代码的接口 | 每次动手之前 |
| `WEAPON_FAMILY_TABLE.md` | **造什么**：18 类的定义、草案方向、Hero 选型与理由、扩散清单、状态总表 | 决定做什么的时候 |
| `README.md`（本文） | **按什么顺序做**：批次、里程碑、DONE 条件、当前进度 | 每轮开工与收工 |

上一轮的资产交付报告在 `docs/HERO_ASSET_REPORTS.md`（PART W 六段式，每轮追加）。

---

## 素材分档（用户 2026-09-29 裁定）

「100+」保留，但拆成三档，**每档的完成度要求不同**——把「每个变体都要 Production Ready」
取消掉，是因为那等于要求 100 件都走完 11 段流程，产能上不成立，结果一定是 100 个半成品。

| 档 | 数量 | 要求 | 落在哪 |
|---|---|---|---|
| **Concept Variant** | 100+ | 轮廓明确，可由参数化即时生成 | `assets_source/weapons/prototypes/`（gitignore） |
| **Game Candidate** | 30–50 | 材质 / 比例 / 第一人称近景做到能接入游戏 | `assets/models/weapons/`（入库） |
| **Production Hero** | 15–25 | 完整建模 + 材质 + Godot 近景 + 动作 + VFX 挂点检查 | `masters/`（LFS）+ `assets/models/weapons/`（入库） |

**Hero 的质量要求不降。** 降的只是「中间档必须全部推到成品」这一条。

---

## `.blend` 三级策略（已裁定，取代本文之前的「待裁决」）

| 类型 | 去哪 | 理由 |
|---|---|---|
| **Hero / Master** `.blend` | `assets_source/weapons/masters/<CODE>/` — **Git LFS** | 它定义家族语言，是唯一值得版本化的源文件 |
| **可再生 Variant** `.blend` | `assets_source/weapons/prototypes/` — **gitignore** | builder + JSON 能重建，存 100 份是不可维护的二进制堆 |
| **运行时 GLB** | `assets/models/weapons/` — 正常 Git | 游戏加载的就是它 |
| **参数行** | `assets_source/weapons/specs/<code>_variants.json` — 正常 Git | 变体的真身是这几行数字，不是 mesh |

> Master Art Direction + Builder + Parameter Spec → GLB

这才是**可再生资产链**。实现见 `.gitattributes`（LFS 规则）与 `.gitignore`
（宽忽略 + `!masters/**` 反选），两条必须一起读，顺序错了 master 会被吞掉。

⚠️ **master 目录按武器类别码命名（`kat` / `swd` / `chn` / `stf`），不按家族俗名。**
简报草稿里写的是 `masters/sword/`，但那会出事：**现在出货的那把刀属于 `KAT` 族，不是
`SWD` 族**——两者共用轴向契约但是不同家族。按俗名会在 `sword/` 里撞车。

---

## 参数化 ≠ 参数随机化

这是这条线最容易翻车的地方，也是用户明确点名的。

如果 18 类 × 6 行参数是 `blade_length 0.9→1.1 / guard_radius 0.12→0.16 / color blue→red`，
产出的是**一百把同一把武器的不同随机种子**。所以每类的 10 个变体必须是
**结构性 archetype**（截面不同 / 曲率不同 / 质量分布不同 / 护手机构不同 / 握持方式不同），
builder 的参数不是为了「生成随机剑」，而是为了高效实现十个**已经设计过**的方案。

`swd_variants.json` 就是这条规则的样板：10 行分别改的是截面、反曲方向与量、宽度曲线上的
台阶、护手机构、柄长与单双手档位——**颜色和材质排在最后**。

---

## Combat Family × Visual Family

**「moveset 才是扩散单位」只对一半。** 正确的关系是两条轴：

```
Combat Family（剑语言：动作 / 节奏 / 窗口 / 声音 / 反馈）
        ×
Visual Family（玩家手里到底拿着什么）
```

同一个招式流派**可以有多个真正不同的武器**——开放世界的拾取、剧情奖励、NPC 身份、
文化差异都需要视觉资产量。约束不是「一个流派只能一把武器」，而是
**不能 10 把只有 skin 差异**。

藏锋流可以同时有黑鞘细刀 / 断刃重铸刀 / 无护手古刀 / 宫廷仪礼刀 / 遗迹拼合刀，
它们共享动作语言，但通过下列通道产生**轻微而可感知**的差异：

`reach ± small` · 重量档 · 拖尾起点 · 鞘的几何 · 打击音色 · 第一人称姿态偏移

这正是 `swd_variants.json` 第 5 行（`two_hand`，唯一进入双手尺寸档）存在的意义：
它验证了「同流派、不同重量档」这条通道真的能用。

---

## 与简报的其余刻意偏离（先说清，避免被当成漏做）

简报要求 18 类**齐头并进**铺量。本文按**「系统是否已存在」**排序，理由是一个实测事实：


**项目目前只有两套战斗系统** —— 剑（`universal` / `hidden_edge` / `flowing_wind` / `white_rose` 四流派）
与缚星链（`缚星链` 三形态，已在 REVIEW）。其余 15 类**没有任何招式系统**。

对没有系统的品类铺量，产出的是**只能看不能挥**的资产。这不代表不做 ——
而是**先做设计语言与 blockout**，把「能挥」的那几类优先推到 game-ready。
数量目标不变（18 类 / 108 方案 / 12 Hero），只是**顺序按系统排**。

---

## 推进批次

### 第零批 · 三个极端家族先证明系统（用户 2026-09-29 裁定）

**不要一上来铺 18 类。** 框架先拿三个**结构上最不相似**的家族证明能吃住，之后枪 / 锤 /
弓 / 权杖 / 拳套才有资格铺量：

| 家族 | 验证什么结构 |
|---|---|
| `SWD` 剑 | 刚性单体：一个连续放样体 + 若干贴合件 |
| `CHN` 缚星链 | 模块化装配：`Handle + Link + Head + Held Bundle` 四个独立族的拼装与实例化 |
| `STF` 法杖 | 放样之外的结构：晶体、镂空、悬浮环、Emission / VFX 挂点 |

这三门过了，框架才算成立。**锁链优先级最高**，因为战斗侧正在真实开发它。

### 第一批 · 系统已存在（能直接验收手感）

| 序 | 类 | 为什么优先 | 现状 |
|---|---|---|---|
| 1 | `KAT` 刀 / 太刀 / 居合 | **Hero 已出货**，是全项目唯一走完 11 段流程的武器 | 几何 100%，配件 30% |
| 2 | `CHN` 锁链武器 | 缚星链已在 REVIEW，三形态设计已定，头部还是 blockout | 0% |
| 3 | `SWD` 剑 / 长剑系 | 与 KAT 共用同一套轴向契约与注册表，扩散成本最低 | 0% |

这一批做完，游戏里能拿在手上的武器从「1 把半」变成「一门多把 + 锁链头部真实化」。

### 第二批 · 高辨识度、高性价比

`STF` 法杖（三尺寸）· `RIT` 佛门法器 · `EAS` 东方武学 · `DGR` 匕首 · `SHD` 盾 · `THR` 符器。
选择理由：这六类的**轮廓天生好认**，参数化程度高（环 / 辐 / 薄板 / 弧），
单位工时产出的「方案数」最多。

### 第三批 · 体量大、成本高

`GSW` 巨剑 · `HAM` 锤 · `PLM` 长柄 · `BOW` 弓 · `XBW` 弩 · `SCP` 权杖 · `SCY` 镰 · `GNT` 拳套。
这八类的共同点是**机构或体量成本高**（弓臂受力、弩的绞盘、拳套的指关节），
做一件的时间够前两批做三件。

### 贯穿批 · 传奇兵器

`LGD` 不排批次。它的每一件都必须**由对应家族的扩散终点长出来**，
所以它只能跟着 `SWD` / `KAT` 的成熟度走 —— 现在做传奇武器等于凭空发明一套语言。

---

## 里程碑与 DONE 条件

| 里程碑 | DONE 条件（可验证） |
|---|---|
| **M1 · PHASE 01 完成** | 18 类家族总表 + 技术规范落库；每类有 Hero 选型与理由；每类有 10 个扩散方向 |
| **M2 · 共享构建器框架跑通** | `weapon_common.py` 统一单位 / 轴向 / 原点 / 材质槽 / Socket / GLB 导出 / AABB 断言 / 第一人称取景；**回读 GLB 校验轴向**；断言失败非零退出 |
| **M2.5 · 三个极端家族证明系统** | 剑（刚性单体）· 缚星链（模块化 Handle+Link+Head+Held Bundle）· 法杖（晶体 / 镂空 / 悬浮环 / Emission 挂点）三门各跑通 builder |
| **M3 · 第一个新 Hero 出货** | `WPN-01 SWD` Hero 走完 11 段流程 >=2 次迭代，GLB 入 `godot/models/weapons/`，训练场实机复核通过 |
| **M4 · 第一批三门完成** | `KAT` 配件 PASS 2 + `CHN` 真实头部 + `SWD` Hero，全部进注册表并在游戏里可挥 |
| **M5 · 108 件 Concept Variant** | 18 份构建器 × 6 行参数，产出 contact sheet（原型 / 变体 / 关键近景 / silhouette） |
| **M6 · 30–50 件 Game Candidate** | 从 Concept 按剪影评审挑出并推到能接入游戏 |
| **M7 · 15–25 件 Production Hero** | 完成建模 + 材质 + Godot 近景 + 动作 + VFX 挂点检查 |

**判据上限**：只到 **TECHNICALLY VERIFIED / VISUALLY REVIEWED**。
**USER GAMEPLAY VERIFIED 只属于用户** —— 手感验收必须在用户可见的桌面上完成，不由我代签。

---

## 当前进度

- **M1 完成**：`WEAPON_LINE_STANDARD.md` + `WEAPON_FAMILY_TABLE.md` 已落库（18 类，方向与 Hero 选型全定）
- **素材分档 + `.blend` 三级策略已裁定并落地**：`masters/`（LFS，已存 `kat/kat_master.blend`
  与 `kat/saya_master.blend`）+ `specs/`（参数行）+ `prototypes/`（可再生，gitignore）
- **M2 完成**：`tools/blender/weapon_common.py` —— 框架承担全部基础设施，家族 builder 只回答「形状是什么」
- **M2.5 进行中**：`SWD` 一门已跑通（10 个结构 archetype，全部通过断言 + GLB 回读 + 出片）；
  `CHN` 与 `STF` 未开始
- **已有可复用资产**：`WPN-03` 的剑（10,378 tris）与鞘（803 mm）—— 家族基因与构建器范式都从它们派生

**下一步按序**：`CHN` 与 `STF` 两门 builder（证明框架能吃模块化装配体与放样以外的结构），
然后才是 M3。

---

## 已知风险（写在前面，别等踩了才记录）

1. **断言必须回读 GLB，不能只量 Blender 场景。** 已实测到两类静默失败：
   ① `obj.bound_box` 在 `mesh.transform()` 之后**是过期缓存**——不 `view_layer.update()`
   就会读到烘焙前的盒子；② 烘焙后 Blender 里的长轴是 **Z**，契约说的 **+Y 是导出文件**
   的轴，两者差一个 glTF 轴转换。只量场景的断言会对这两件事全部放过。见 `weapon_common.py`
   的 `GLTF_TO_BLENDER` / `part_aabb` / `verify_glb`。
2. **新增 GLB 后不跑 `--headless --import`**，Godot 会静默用旧缓存 —— 必须重导入。
3. **构建器不写断言 = 108 件以不同方式错位**，而错位在 Godot 里是静默的（不会报错，只会不对）。
4. **材料分区的金属陷阱**：`metallic` 0.75+ 在无反射源场景里渲染成纯黑剪影，第一人称武器尤其明显。
5. **15 类没有战斗系统** —— 它们做完之后在游戏里**不可玩**。这不是缺陷，是顺序问题，
   但如果有人把这 15 类的完成度读成「游戏内容增加了」，那是误读。
6. **Blender 的相对 `render.filepath` 按 blend 文件目录解析**，而这个工具用 `-b` 且从不保存
   blend —— 相对路径会静默写到别处，日志照样打印成功，目录照样是空的。
   `render_previews` 已强制 `abspath` 并在写完后 `isfile` 校验。
