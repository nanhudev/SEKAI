# SEKAI · DEMO CAST（C-PH 外部占位角色线）

> **这一行现在做的事情：CAST → STORY → SCENE → ACTION。**
> 不是"给 21 个低模做万能动作库"。
>
> 这批低模是 **REHEARSAL ACTORS**（排练演员）。它们可以丑，但**不许改变角色设计**。
> 本阶段唯一的问题不是"这个模型好不好看"，而是：
>
> > **"这个模型现在能不能把我们已经写好的剧情演出来？"**
>
> 与 `docs/characters/THIRD_PARTY_CHARACTER_ASSETS.md` 的分工：那份讲**素材从哪来、
> 许可、管线怎么跑**；这份讲**谁演谁、数据层怎么绑、还缺什么动作**。

---

## 0. 本轮交付物一览

| 产物 | 位置 | 怎么核查 |
| --- | --- | --- |
| 角色→演员裁定图（A/B 对比） | `assets_source/characters/placeholders/_review/CAST_ROLES_AB.png` | 12 格，每格名字烧进画面 |
| **CAST 清单（唯一真相源）** | `godot/resources/cast/demo_cast.json` | 见 §5 两个校验器 |
| 清单校验（对磁盘/烘焙） | `tools/character/validate_cast.py` | `python tools/character/validate_cast.py` |
| 清单校验（对引擎） | `godot/tools/cast_check.gd` | `godot --headless --path godot --script res://tools/cast_check.gd` |
| 引擎内审计报告 | `.../\_review/cast_audit.txt` | 上面那条命令的输出 |
| 加载器 | `godot/scripts/characters/demo_cast.gd` | 无 `class_name`（见 §5.3） |
| 动作缺口清单 | `demo_cast.json` → `base_motions` | 见 §6 |

---

## 1. CAST AUDIT（TASK A）

**结论：用户清单里的 21 个名字与磁盘上的真实文件逐字一致，零差异，无需造名、无需重命名。**

| 包 | 目录 | 数量 | 骨骼 | 联合来源 |
| --- | --- | --- | --- | --- |
| 女 | `third_party/quaternius/ultimate_modular_women/Humanoid Rigs/...` | 10 | **51** | CC0 |
| 男 | `third_party/quaternius/ultimate_modular_characters/Humanoid Rig/...` | 11 | **62** | CC0 |

```
女  lpg_adventurer_w  casual_w  formal_w  medieval_w  punk_w
    scifi_w  soldier_w  suit_w  witch_w  worker_w
男  lpg_adventurer_m  beach_m  casual_m  casual2_m  farmer_m
    king_m  punk_m  spacesuit_m  suit_m  swat_m  worker_m
```

21/21 实测 **身高 1.7000 m**、**37 clips**、`drift +0.00%`（`glb_extents.py` 直接解析 GLB，
不信引擎的 `get_aabb()`——那是 bind-space，不含骨骼缩放）。

> 注意用户清单里的 "lpg_casual2_m" 与实际 `Casual2.fbx` → `lpg_casual2_m.glb` 一致。
> 没有发现需要"以真实资产为准"的差异。

---

## 2. PROVISIONAL CAST MAP（TASK B）

**这不是角色美术设计。这只是"当前 Demo 拍剧情时谁来演谁"。**

| character_id | 中文 | placeholder_model | 骨架档 | 优先级 | 一句话理由 |
| --- | --- | --- | --- | --- | --- |
| `lia` | 莉娅 | `lpg_adventurer_w` | female | P0 | 功能型装束、靴子、马尾，无装饰。她在河上，不在厅里 |
| `oren` | 奥伦 | **`lpg_farmer_m`** | male | P0 | **偏离提案**，见 §2.2 |
| `mira` | 米拉 | `lpg_scifi_w` | female | P1 | 不对称现代机能装；尖帽会在她开口前先宣布"传统女巫" |
| `vell` | 薇尔 | `lpg_formal_w` | female | P0 | **真实两难**，见 §2.3。ID 用 `vell`，见 §2.1 |
| `taim` | 泰姆 | `lpg_casual_m` | male | P0 | 不能像英雄。他是玩家第一战"撞上"的普通人 |
| `garran` | 格兰 | `lpg_worker_m` | male | P1 | **我加的**：他有 DAILY PRESENCE 条目，是玩家第一个屋顶与第一份工 |
| `arn` | 阿诺 | `lpg_casual2_m` | male | P1 | **我加的**：全镇唯一主动靠近玩家的人，十六岁 → 用最朴素的男模 |
| `brann` | 布兰 | `lpg_swat_m` | male | P1 | **我加的**：玩家登记失败的那道卡口。他属"程序"，不属"英雄" |
| `rusk` | 鲁斯克 | `lpg_suit_m` | male | P1 | 用户表里的"公会负责人"。他整个人是纸面与疲惫，不是甲胄权威 |
| `second_candidate` | 第二候选者 | `lpg_adventurer_m` | male | P2 | **登记但不做动作**，见 §2.4 |

### 2.1 必须提出的 ID 冲突：`vell` vs `veil`

用户的任务书写的是 **VEIL / 薇尔**。而权威文档 `docs/narrative/CHARACTERS.md` §6 写的是
**薇尔 Vell**。

**清单采用 `vell`**，理由与用户自己定的规则一致——"以真实资产为准，不要为了符合文字
造出假资源"。这条规则同样适用于 ID：如果剧情/对白/场景引用先绑到 `veil`，将来所有人
按 narrative 找 `vell`，两侧会一起炸。这正是用户说的那件事。

→ **请裁定**：若 narrative 决定改名为 Veil，改 `CHARACTERS.md` 与清单各一行即可；在
narrative 改口之前，`veil` 不是合法别名（`demo_cast.gd` 会明确报错并列出合法 ID）。

### 2.2 偏离 1：奥伦 —— 建议从 `worker_m` 改为 `farmer_m`

提案里奥伦首选 `lpg_worker_m`，备选 `lpg_farmer_m`。看过实机 A/B 后**建议对调**：

- `lpg_worker_m` 戴**黄色安全帽 + 橙色反光背心**。那是**现代工地**的强符号。放进雾谷，
  它先说的是"市政施工队"，不是"木匠"。
- `lpg_farmer_m` 是草帽 + 布衬衫 + 背带裤。"靠手在户外吃饭的人"——正是这个角色。

奥伦的定义是"已退出冒险生活的人 / 劈柴 / 修东西"。**这不是口味问题，是符号冲突**：
一个硬性现代符号会盖过一个尚未被玩家理解的角色。

**依据是图，不是这段话**：`_review/CAST_ROLES_AB.png` 第 1 行第 3、4 格。

### 2.3 偏离 2：薇尔 —— `formal_w` vs `suit_w`，请裁定

这是真正的两难，两边都站得住：

| | 读作 | 代价 |
| --- | --- | --- |
| `formal_w`（提案首选，现用） | 镇上人穿着正装 | 读作"穿裙子的市民"，行政感弱 |
| `suit_w` | 行政 / 档案 / 办公 | 黑色西装是**现代公司符号**，和反光背心同类问题 |

她的核心是 ORDER / RECORD / CONTROL。`suit_w` 的"档案员"读感更锐利，但把一个现代
办公符号带进奇幻语境。**默认保留提案的选择**，因为至少它没有引入现代符号。
改一行即可（`placeholder_model` + `placeholder_model_alt` 对调）。

### 2.4 第二候选者：登记，但不给动作

提案说"首选 `adventurer_m`，备选 `king_m`，如果更像'被世界选中的标准英雄'可以占位"。

**`king_m` 被否决。** 它戴着王冠——那是一个硬性的"他就是国王"符号，会泄漏
narrative 还没做的设计决定。而 §8 的世界法则写着：Act I 里这个角色**只能以传闻出现，
没人见过他**。一个普通冒险者的轮廓才是对的。

清单里 `animation_profile` 为空字符串——**这是有意的**，不是遗漏。`demo_cast.gd` 把
空档位当合法值，`animation` 字段写着 `NONE BY DESIGN`。

### 2.5 座位池

| 池 | 模型 | 纪律 |
| --- | --- | --- |
| `town_crowd` | casual_w, worker_w, medieval_w, beach_m, soldier_w | 命名 `town_citizen_01…`，**永不给稳定剧情 ID** |
| `guard` | soldier_w, medieval_w | 守卫演员。**不导入现实部队含义** |
| `hostile_humanoid_test` | punk_m, punk_w, swat_m | 仅测试用。**Act I 第一敌人仍是遗迹哨兵，不是人类** |
| `not_cast_as_villagers` | king_m, spacesuit_m, witch_w, punk_w, punk_m | 各带硬性出格符号，放进雾谷人群会**浪费一次尚未发生的第一次印象** |

`swat_m` 从 `guard` 池移除：它已经是布兰。否则背景守卫可能被读成具名角色。

### 2.6 明确不启用的角色

| 角色 | 原因 |
| --- | --- |
| 精灵少女 | 这批模型没有任何一个读作非人。**不许为了套上模型就把她改成人类** |
| 观察者代理 | 第一次印象是叙事资产。用通用 casual 模型花掉它，不如不出现 |
| 锁链流派导师 / 猎人 | 尚不需要正式出场前，不做资产绑定 |

原则：**PLACEHOLDER 可以丑，但不能改变角色设计。如果模型不对，换模型。**

---

## 3. 动作缺口（TASK E/F 的输入）

`demo_cast.json` → `base_motions` 把共享动作词表（提案 §7）逐条对照**当前库里真实存在的
clip**，并标状态。跑 `cast_check.gd` 会打印：

```
covered  16  Idle, Idle_Talk, Walk, Run, Sprint, Crouch, Sit, Sit_Enter, Sit_Exit,
             Kneel, Pickup, Interact, Push, HitReact, Death, Jump
partial   2  Carry, Stand
missing   5  Look, Point, Turn, Start, Stop
```

- **missing 5 条是必须先补的**：`Look`（Taim/Mira 都要）、`Point`（Taim 指路、Mira 指发现）、
  `Turn`/`Start`/`Stop`（NPC 一旦 `walk_to(marker)` 就需要）。库人偶是站桩的，这三条
  本质是 Walk 的入/出混合与姿态变体，不是新动作。
- **partial 2 条**：`Carry` 现在只有 `Interact`（伸手，不是抱东西）；`Stand` 只有
  `Sitting_Exit`（且绑着座椅高度）。镇民生活动作 `town_carry_crate` / `town_move_sack`
  依赖前者。

每个角色的 `animation_profile` 里 `actions` 就是**该角色的动作待办**，
`cast_audit.txt` 的 `acts` 列是计数：

```
vell 8 · oren 7 · lia 6 · taim 6 · mira 5 · garran 3 · arn 3 · brann 3 · rusk 2 · second_candidate 0
```

**动作档位不是四套重做。** 提案 §6 要求的是同一份 Base Motion + 每角色的
Pose/Timing 变体。清单里以 `walk.speed_scale` / `walk.posture` / `talk.gesture_amount`
这种形式记录意图（莉娅轻快 1.08、奥伦低重心 0.88、米拉略快 1.15、薇尔克制 0.92、
泰姆受伤 0.45 直接替换走姿）。**这些数字是意图声明，尚未实现**——实现它们属于 TASK E。

---

## 4. 骨架档：两个包的 rig 不是同一个（并且修掉了一个静默缺陷）

`skeleton_profiles` 存在的理由：**换模只有在骨架行为相同时才是安全的。**

| 档 | 包 | 骨骼 | rig 修复 |
| --- | --- | --- | --- |
| `female_medium` | `ultimate_modular_women`（`Humanoid Rigs/`） | 51 | **`legs_reparented_to_pelvis`** |
| `male_medium` | `ultimate_modular_characters`（`Humanoid Rig/`） | 62 | 无 |

### 4.1 坐姿"坐在看不见的椅子上"—— 完整诊断

**症状**：用户报"座下的动作有些不对"。审查图里角色躯干沉下去，腿却留在原地旋转。

**排查过程（每一步都是测量，不是猜）**：

1. 先怀疑"髋部位移丢了"。解析 GLB 动画通道 → **没丢**：
   源库 `Idle_Loop` hips RZ 0.8772 → `Sitting_Idle_Loop` 0.5415，烘焙后
   `Idle` hips Y 0.8919 → `Sitting` 0.5506。比例正确。
2. 于是怀疑"父级不对"。用骨骼世界坐标探针（`--bone-probe`）测四个姿势：

   | | Hips | UpperLeg.L | Foot.L |
   | --- | --- | --- | --- |
   | 男 rig Idle → Sitting | 0.783 → **0.484** | 0.846 → **0.548** | 0.033 → 0.097 |
   | 女 rig Idle → Sitting | 0.891 → **0.551** | 0.964 → **0.964** ✗ | 0.075 → **0.482** ✗ |

   同一条 clip、同一条管线，**结果不同**。
3. 导出骨骼层级 → **根因**：

   ```
   源库（Rigify 人偶）        root → DEF-hips → DEF-thigh.L → DEF-shin.L
   男包（62 骨）              Root → Hips → UpperLeg.L → LowerLeg.L
   女包（51 骨）              Root → { Hips, UpperLeg.L, UpperLeg.R }   ← 腿是骨盆的兄弟
   ```

   Quaternius **女包**把腿链挂在根骨上（模块化 rig 的遗留），男包挂骨盆。
   重定向只写旋转，所以骨盆下沉时女包的腿**不跟着走**——躯干沉、腿留在 0.964 m 旋转。
   同一个缺陷让 `Crouch`（0.964 冻结）和 `Fixing_Kneeling` 同样错。

**修法**：`retarget_humanoid.py` 在导入后做一次 rig 归一化——
`normalise_leg_chain()` 把挂在根骨上的 `UpperLeg.L/R` 重挂到骨盆。

- Blender 编辑模式下改 `parent` **不移动骨骼**（`EditBone.head/tail` 是 armature-space），
  所以 rest pose、`matrix_local`、蒙皮绑定全部不变，只改链条。
- **这一点是被测出来的，不是被信任的**：改动前后量 `head` 位移并断言，实测
  `head drift 0.000000 m`，超过 1e-5 直接 abort 而不是烘出一份坏绑定。
- `use_connect=False` 必须设，否则 Blender 会把头吸到父骨尾巴上。

**结果**（女 rig，修后）：`Sitting` Hips 0.551 / UpperLeg **0.583** / Foot **0.101**；
`Crouch` UpperLeg **0.505** / Foot 0.134；`Fixing_Kneeling` UpperLeg **0.452** / Foot 0.110。
男 rig 的对照值是 Sitting UpperLeg 0.548 / Foot 0.097 —— **两条独立管线收敛到同一组数**。

### 4.2 顺带加的守卫

- 烘焙循环里，若某骨的**父级也被重定向但尚未计算**，旧代码会静默退化成用父级 rest 矩阵。
  现在直接 `SystemExit`——宁可失败，不可烘出一条静默错误的链。
- 元数据新增 `rig_repairs` 与 `leg_head_drift_m`：**换模时 `rig_repairs` 变了，
  就是换了骨架档，不是 drop-in**。`validate_cast.py` 会对这条报错。

---

## 5. 数据层（TASK C）

### 5.1 ROLE ≠ MODEL

```text
character_id      = lia               # 剧情身份。永不变。剧情/对白/场景只能引用它
placeholder_model = lpg_adventurer_w  # 排练戏服。预期被替换
```

`demo_cast.json` 里每个角色都有 `cast_reason`：**为什么是它**。
以后 Lia V2 到了，改 `placeholder_model` 一行，剧情、动画、对白、场景引用**全部不动**。

`validate_cast.py` 会把 `character_id` 长得像模型名（`lpg_*`）**直接判 FAIL**——
那正是 ROLE ≠ MODEL 要防的失败。

### 5.2 两个校验器，各管一半

```bash
# 对磁盘与烘焙：路径存在、profile 的骨头/身高/clip 数与该角色自己的 _retarget.json 一致、
# base_motions 引用的 clip 真实存在、character_id 唯一且不像模型名
python tools/character/validate_cast.py

# 对引擎：每个 model 是否真的成为可加载资源（磁盘上存在但导入失败 → 只有这里能发现）
godot --headless --path F:/SEKAI/godot --script res://tools/cast_check.gd \
      > assets_source/characters/placeholders/_review/cast_audit.txt 2>&1
```

两者都独立于手写的文档：**profile 里写的骨头数/身高必须与该角色自己的烘焙记录相符**，
不一致就报错（这条抓过一次真问题）。

**clip 名以 Godot 报告为准，不猜剥离规则。** `_retarget.json` 记的是烘焙名
（`Idle_Loop`），运行时用的是 Godot 导入名（`Idle`，剥掉 `_loop`/`-loop`）。
校验器**优先读一份 Godot `--report`**，并在输出里注明来源（`authoritative` / `inferred`）。

### 5.3 为什么不给加载器加 `class_name`

`demo_cast.gd` 故意不加 `class_name`：那会重写 Godot 的全局类缓存，而本仓是**多会话共享
工作树**，用户的编辑器当时正开着。消费方式：

```gdscript
const DemoCast = preload("res://scripts/characters/demo_cast.gd")

var a := DemoCast.actor("vell")            # 完整记录（含 cast_reason）
var role := DemoCast.scene_role("vell")    # "tower_recorder"
var acts := DemoCast.required_actions("vell")   # 该角色的动作待办
var node := DemoCast.spawn("vell")         # 实例化占位模型，带 character_id 元数据
var bad := DemoCast.problems()             # 引擎侧自检
```

`spawn()` 支持 `{"model": <path>}` 覆盖——**排练台做 A/B 时不改清单**。

---

## 6. 与其它文档的关系

- `docs/characters/THIRD_PARTY_CHARACTER_ASSETS.md` = 素材来源 / 许可 / 管线。
- `docs/characters/DEMO_CAST.md`（本文）= 谁演谁 / 数据层 / 动作缺口。
- `docs/narrative/CHARACTERS.md` = 角色本身是谁。**ID 冲突以 narrative 为准。**
- `docs/PRODUCTION_BOARD.md` → `## C-PH` = 状态。

---

## 7. 本轮没做的（下一步）

| 步骤 | 状态 |
| --- | --- |
| TASK D 统一骨架 / Retarget | **DONE**（含 §4 的缺陷修复，21/21 重烘） |
| TASK E 基础动作 Idle/Walk/Run/Talk | 库已覆盖大部分；**缺 Look / Point / Turn / Start / Stop / Carry** |
| TASK F 角色特化动作（Taim/Vell/Oren/Lia/Mira） | **待做**，43 条 action id 已登记在清单里 |
| TASK G 放进真实 Mistvale | 未开始（需要 COMBAT 侧移动对接） |
| TASK H `mistvale_cast_vertical_slice.mp4` | 未开始 |
| TASK I 看片自迭代 | 未开始 |

**⚠️ 美术方向**：这批是 generic low-poly，违反本仓 `禁 generic low-poly / mobile toy`。
**仅作管线/动画/系统联调，不得作为发行外观。**
