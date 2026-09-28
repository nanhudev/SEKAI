# SEKAI 武器线技术规范 · WEAPON LINE STANDARD

> 这份文件管**怎么造**，不管**造什么**。造什么在 `WEAPON_FAMILY_TABLE.md`。
> 违反本文件的资产会在**实机复核**阶段被打回，而不是在评审阶段被讨论。

---

## 0. 一句话

一把武器 = **一个模型 + 一套轴向契约 + 一组挂点 + 一行注册表**。

四样缺一，它在 Godot 里就一定会错位；而错位的代价是**招式首尾帧返工**。

---

## 1. 命名规范

| 层 | 规则 | 例 |
|---|---|---|
| 文档 id | `WPN-<两位类号>` / 变体 `WPN-<类号>-v<两位>` | `WPN-01`, `WPN-01-v07` |
| 文件名 | `WPN_<CODE>_<Role>_<NN>` | `WPN_SWD_Hero_01`, `WPN_CHN_Hook_Hero_01`, `WPN_BOW_Moon_03` |
| Role | `Hero`（原型）/ `Var`（变体）/ `Alt`（备用方向） | |
| Godot 侧 id | `StringName`，蛇形小写，**走注册表查表**，不是文件名 | `&"swd_hero"` |
| 材质 | `M_<部件>_<材质>` | `M_Blade_BlueSteel` |
| 挂点 | `FX_<用途>` | `FX_Edge_Tip` |

### 类别码表（18）

| # | 类 | CODE | # | 类 | CODE |
|---|---|---|---|---|---|
| 01 | 剑 / 长剑系 | `SWD` | 10 | 弓 | `BOW` |
| 02 | 大剑 / 巨剑系 | `GSW` | 11 | 弩 | `XBW` |
| 03 | 刀 / 太刀 / 居合刀 | `KAT` | 12 | 匕首 / 短兵 | `DGR` |
| 04 | 法杖（小 / 中 / 大） | `STF` | 13 | 镰刀 / 异形 | `SCY` |
| 05 | 权杖 / 仪式杖 | `SCP` | 14 | 盾 / 武装盾 | `SHD` |
| 06 | 锤 / 钝器 | `HAM` | 15 | 投掷 / 暗器 / 灵符载体 | `THR` |
| 07 | 长柄（枪 / 戟 / 矛 / 月刃） | `PLM` | 16 | 佛门 / 咒术 / 法器 | `RIT` |
| 08 | 锁链武器 | `CHN` | 17 | 东方武学兵器 | `EAS` |
| 09 | 拳套 / 臂铠 | `GNT` | 18 | 特殊传奇兵器 | `LGD` |

### Grandfather 条款（重要）

**已出货的 `fp_sword.glb` / `fp_saya.glb` 不改名。**

它们的路径被 `godot/scripts/weapons/sword_classes.gd`、`godot/scenes/weapons/Sword_FP.tscn`、
`godot/scripts/combat/weapon_manager.gd` 以及两场演出按字符串引用。
为了满足命名规范去改两个**已出货资产**的路径，正是「换建模影响位置与技能」的同一类风险。
新资产一律按本规范；老资产按原样引用，注册表里已有它们的实测行。

---

## 2. 原点与朝向契约

### 铁律三条

1. **origin 落在「手 / 机构真正接触或安装的那一点」** —— 不是包围盒中心，不是几何重心。
2. **+Y 永远指向这把武器的「攻击端」**（刃尖 / 杖头 / 枪头 / 链头 / 出拳方向）。
3. **主平面法线占 ±Z，副轴占 ±X。** 左右手镜像、上下翻转由**场景层**做，**不在模型里做**。

### 约定表

| 类 | origin | +Y | −X | +Z |
|---|---|---|---|---|
| `SWD` `GSW` `KAT` `DGR` `SCY` | 握把中心（护手面附近） | 指向刀尖 | 刃口侧 | 刀面法线 |
| `STF` `SCP` `PLM` `RIT` `EAS` | 握持中心（双手类取两手之间） | 指向杖头 / 枪头 | 正面 | — |
| `CHN` | 柄尾连接环 | 链条出去的方向 | — | — |
| `CHN` 链头 | 连接环 | 指向头部尖端 | — | — |
| `BOW` | 握把中心 | 上弓臂 | 箭侧（靠箭台） | 射手朝向 |
| `XBW` | 握把中心 | 指向射击方向 | — | 上膛面 |
| `GNT` | 掌骨中心 | 指尖方向 | 拇指侧 | 手背法线 |
| `SHD` | 握把中心 | 盾面上缘 | — | 外表面法线 |
| `THR` | 重心 | 飞行方向 | — | 自旋轴另行在注册表标注 |

`SWD` 这一行**与 `sword_classes.gd` 里已经成立的帧完全一致**（`origin` = 握把中心，
`+Y` = 刀尖，`−X` = 刃侧）。这不是新设计，是已实测通过的契约，直接继承。

**每条契约都要在构建器里写成断言**（见 §6），不能只写在文档里。

---

## 3. 尺寸规范

- 一律**米制**，与真实握持比例一致。
- 基准：现有出货剑全长 **0.765 m**，握把区 **−0.286 → +0.004 m**（握把长 0.29 m）。这是单手基准。
- 三档：

| 档 | 总长 | 适用 |
|---|---|---|
| 单手 | 0.30 – 1.20 m | `SWD` `KAT` `DGR` `SCP` `STF-small` `GNT` `THR` |
| 双手 | 1.10 – 1.80 m | `GSW` `STF-medium` `HAM` `PLM-short` `BOW` `XBW` |
| 超长柄 | 1.80 – 2.60 m | `PLM` `STF-large` `RIT-禅杖` `SCY` |

每类在家族总表里给出实测范围，构建器**打印实际值**并写回注册表。

---

## 4. 部件拆分与命名

每类必须按功能拆，部件名固定（用于动画挂点、材质复用、变体派生、局部替换）。

| 类 | 部件 |
|---|---|
| 剑 / 刀 | `Blade` `Blade_Edge` `Guard` `Grip` `Pommel` `Habaki` `Scabbard` `Scabbard_Mouth` `Strap` `Charm` |
| 法杖 | `Shaft` `Core` `Head_Frame` `Gem` `Ring_Float` `Ornament` `Cloth` |
| 锁链 | `Handle` `Chain_Segment` `Head_Blade` `Hook` `Weight` `Anchor` |
| 弓 | `Riser` `Limb_Upper` `Limb_Lower` `String` `Grip_Wrap` `Nock` |
| 弩 | `Stock` `Prod` `String` `Trigger` `Rail` `Bolt` |
| 拳套 | `Palm_Plate` `Knuckle` `Finger_Guard` `Cuff` `Blade_Stud` |
| 盾 | `Face` `Boss` `Rim` `Handle` `Strap` `Spike` |
| 锤 | `Haft` `Head_Core` `Head_Face` `Band` `Butt` |
| 长柄 | `Shaft` `Head_Socket` `Blade_Main` `Wing` `Tassel` |
| 通用 | `FX_*`（见 §8） |

---

## 5. 材质语言与材质族

### 白名单（必须属于同一个世界）

- **钢族**：钢 / 黑钢 / 青钢 / 锻钢
- **银族**：旧银 / 白银 / 月银
- **金族**：黄铜 / 古铜 / 暗金
- **木族**：漆木 / 深木 / 杖木芯
- **织物**：皮革 / 缠带 / 布条
- **骨石**：骨 / 角 / 石 / 晶
- **神秘**：古合金 / 发光晶 / 遗物矿

### 禁项

廉价塑料感 · 无逻辑的高饱和色块 · 纯写实军工件拼接而破坏幻想气质 · 细节堆满但主轮廓不清。

### 金属陷阱（本项目实测，必须遵守）

`metallic` 0.75 以上、场景里又没有反射源时，武器会渲染成**纯黑剪影**。
本项目第一人称武器层的实测结论：

- 武器金属件 `metallic` **上限 0.6**
- 链 / 剑用 **0.45**
- 刃 albedo 参考出货实测值 `(0.708, 0.717, 0.733)`，`roughness` **0.20**

### sRGB / linear 对照（实测）

| Blender 里写的 | Godot albedo 读到的 |
|---|---|
| 0.052 | 0.253 |
| 0.086 | 0.325 |
| 0.460 | 0.708 |

写材质参数时必须说明是**哪一侧**的值，否则同一件资产在两个 DCC 里颜色不同。

---

## 6. 构建器硬性要求（100+ 产能的前提）

100 件资产**不可能**靠手搓网格。正确形态是**一个家族一份参数化 bpy 构建器**，
吃 JSON 参数行输出 GLB —— 简报说的「家族化扩散」本身就是参数化的描述。

每个构建器必须：

1. 接受 `-- <params.json> <out.blend> <out.glb>`，无参数时用内建默认行
2. 生成后**回读并断言**：origin 落点、+Y 轴向、AABB、关键长度、三角面数
3. **断言失败 = 非零退出**。禁止「生成了但轴是错的」
4. 打印实测数值到 stdout（供注册表回填）。数值**从几何算**，不许抄文档
5. 材质分区落到 `M_*` 命名，不靠位置猜
6. 一律**二进制读写**（文本模式下 `\r\n` 匹配不到却会报成功 —— 这是本项目踩过的坑）
7. 打印三角面数

参考实现：`tools/blender/sword_build.py`、`tools/blender/saya_build.py`（这两个已经出货）。

---

## 7. 三角面预算

| 用途 | 区间 |
|---|---|
| 第一人称手持武器 | **20k – 80k** |
| NPC / 敌人手持 | 4k – 16k |
| 地面可拾取 / 掉落物 | 1k – 4k |
| 变体方向（blockout 级） | 200 – 2k |

现有出货剑 **10,378 tris**，低于第一人称下限。
下一代 Hero 要向 20k+ 走，但**不能靠堆装饰** —— 要靠刃横截面折面（shinogi-zukuri）、
护手纹样、柄部缠绕这些**在第一人称近景真的看得见**的结构。

---

## 8. 特效挂点

命名 `FX_<用途>`，一律**空 Object3D**（无网格），位置与朝向按 §2 的契约。

`FX_Edge_Root` `FX_Edge_Mid` `FX_Edge_Tip` `FX_Core` `FX_Muzzle` `FX_Chain_Head`
`FX_Rune_A` `FX_Rune_B` `FX_Rune_C` `FX_Trail_Root` `FX_Trail_Tip`

**硬性**：每个挂点必须**实际被某个特效消费过**，否则删掉。挂点不是装饰品 ——
一堆没人读的空节点等于伪造的接口。

---

## 9. 目录结构

```
assets_source/weapons/
  concepts/     草案、剪影探索、contact sheet 源图
  prototypes/   迭代中间态 .blend、旧版本、blockout
  final/        定型可交付 .blend
assets/models/weapons/        <- 简报的 exports（入库导出）
assets_source/review/weapon/  <- 简报的 previews（出片）
docs/weapons/                 <- 简报的 docs
```

**对简报的一处刻意偏离**：简报要求 `exports/` 与 `previews/` 各起一个目录。
项目已经有 `assets/models/weapons`（入库导出）与 `assets_source/review/weapon`（出片），
再起同名目录会出现**第二个真相源**，违反项目既有的「唯一真相源 + 生成而非手抄」。
所以这里**映射而不复制**。

---

## 10. 导出与入库链

```bash
# 1. 源 + 交付（Blender headless，本机唯一可用的 Blender 是 G:/blender.exe）
cmd //c "G:\blender.exe" --background --factory-startup \
    --python F:/SEKAI/tools/blender/<builder>.py -- \
    F:/SEKAI/assets_source/weapons/final/<name>.blend \
    F:/SEKAI/assets/models/weapons/<name>.glb

# 2. 运行时副本
cp assets/models/weapons/<name>.glb godot/models/weapons/

# 3. 必须重导入 —— 非编辑器实例不会自动重导入
cmd //c "G:\Godot\Godot_v4.4.1-stable_win64_console.exe" \
    --path F:/SEKAI/godot --headless --import

# 4. 实测回读（工具探针会打印世界 AABB 与三角面数）
cmd //c "G:\Godot\..." --path F:/SEKAI/godot --resolution 1600x900 \
    --audio-driver Dummy --script res://tools/shot_weapon_rack.gd
```

- `.blend` **当前被跟踪 0 个** —— 但注意：它**没有**被 `.gitignore` 排除，只是从未提交过。
  也就是说 `.blend` 既不在版本控制里，也不受忽略规则保护：一次 `git add -A`
  就会把二进制源文件扫进仓库。这是**待决问题**，见 `README.md` 的已知风险第 1 条。
- `.glb` **入库**
- 新增 GLB 后不跑 `--headless --import`，Godot 侧会**静默使用旧缓存**

---

## 11. DONE 条件

```
BLOCKOUT -> SILHOUETTE REVIEW -> SECONDARY FORM -> MATERIAL PASS
  -> DETAIL PASS -> BLENDER RENDER -> CRITIQUE -> FIX
  -> GODOT -> IN-GAME REVIEW -> FIX AGAIN
```

**不少于 2 次视觉迭代。禁止「一遍过」。**

判据只到 **TECHNICALLY VERIFIED / VISUALLY REVIEWED**。
**USER GAMEPLAY VERIFIED 只属于用户** —— 手感验收必须在用户可见的桌面上完成。

---

## 12. 自审八问（每件必答）

1. 黑色剪影好不好认？
2. 远看与近看是否都成立？
3. 是否太像素材站常见模板？
4. 是否真的适合这个世界？
5. 交给程序接进第一人称，会不会太无聊？
6. 是否只靠贴图，不靠结构？
7. 能不能扩散出 10 个变体？
8. 有没有一个让我能记住它的「点」？

答不强就继续改。这一轮不接受「差不多就行」。

---

## 13. 与现有代码的接口（不读这段就会破坏已有系统）

- `godot/scripts/weapons/sword_classes.gd` 是**已经存在**的注册表：一行一把剑，
  数值全部实测。新家族按同样形态扩展（或另开一张表），**不新建第二套真相源**。
- `weapon_id` 是 `WeaponSlot` 的**查表键**，不是文件名。
- 换模型必须**加子节点**而不是替换节点：
  `iaido_director.gd` 与 `moment_of_no_moon_director.gd` 会硬 `get_node()` `TempSwordVisual`
  并在整段技能里写它的 transform；拖尾 / 辉光 / 虚空描边 / 接触弹簧 / 位移反馈也都挂在它上面。
  把 `TempSwordVisual` 隐藏掉 = 把唯一被动画的节点藏了，代码全对、演出全废。
- 第一人称层由 `ForegroundWeaponLayer` 拥有 `WEAPON_LAYER`，**不要自己设 `layers`**。
- **不要**把第一人称武器加进 `WORLD_DRAWN`（`&"weapon_drawn_in_world"`）组 ——
  画在世界里的第一人称武器会插进玩家身边的几何。
- 换武器时可见性由 `weapon_manager.gd` 的 `rig.visible = sword_in_hand` 控制，
  子节点**继承**可见性，所以真模型必须挂在 `TempSwordVisual` 之下才跟着一起隐藏。
- 渲染侧：**绝不在片元着色器里写 `NORMAL`**；场景只有**一盏有效方向光 + 天空 ambient`。
