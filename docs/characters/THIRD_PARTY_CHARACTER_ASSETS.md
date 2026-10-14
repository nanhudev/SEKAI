# 外部角色素材接入（CLOTHES LINE / 占位角色）

> 状态：**PIPELINE VERIFIED**（管线已验证可用）
> 登记表见 `third_party/README.md`。本文只讲**怎么用、为什么这样做、限制在哪**。

---

## 1. 为什么走这条路

原先的路线是把用户给的 `Lia v-.fbx` 一步步做成正式角色。PHASE 01 审计结论是：
那是一团 **499,748 tris 的单壳三角汤**，无 UV / 无材质 / 无骨骼 / 无权重，**连通壳数 = 1**
（身＋发＋衣＋靴全焊死）。它可以重拓扑，但**不能"修"**。

实测又证明：**整体一次重拓扑不够用**——QuadriFlow 出来的 20k 四边面形体可用，
但脸被抹平、手指并成手套、头发糊成一团，而且**布料与手臂在网格上融合**，
导致蒙皮时腰侧布片被手臂骨拽成三角翼（三种修法全部失败，见 `LIA_V3_RIG.md §5`）。

用户决策：**先简单绑定跑起来，高精度美术素材后期再加**，并且
**去网上找可用的现成素材（人形 + 动作）来替代**。

所以本线做的是：**找一个风格中性的、可直接使用的、许可干净的人形 + 一整套动画，
把"角色能在 Godot 里真的动起来"这件事彻底打通**，让后续所有系统（对话、AI、
摄像机、任务）都能在有活动角色的前提下继续推进。

---

## 2. 选了什么，为什么

| | 素材 | 许可 | 为什么是它 |
| --- | --- | --- | --- |
| **动作** | Quaternius **Universal Animation Library** | CC0 | 46 个剪辑 / 53 骨骼，**Godot 原生 GLB**，含手指骨，Directly 可重定向。这是本次最有长期价值的一件事——**动画与美术风格无关**，将来换成高精度 Lia 本体，这套动画照样能重定向过去 |
| **人形** | Quaternius **Ultimate Modular Women / Characters** | CC0 | 21 个角色、同一套简化人形骨架、**已经分好件**（Body / Head / Legs / Feet 各自独立 mesh，自带 UV）、每个仅 3–10k tris。低模，但是**能用、能立刻动画**的 |

三件一起来：**21 个可动角色池** + **46 个可重定向剪辑**，全部 CC0（商用、可改、免署名）。

另外拉了 Khronos 的 `CesiumMan`（CC-BY 4.0）作为**真人比例 rigged 参照物**，
用来对照检查重定向有没有把人拧歪。

### ⚠️ 美术方向声明（重要）

本仓规则是 **禁 generic low-poly / mobile toy**，禁止把这种风格当成品。

**这些是占位素材（PLACEHOLDER），不是 Lia 的最终外观。** 它们的价值在于：

- 让管线、动画系统、对话系统、摄像机有真实可动的对象可以对接；
- 让 `Lia` 的高精度版本在**不必同时解决"她怎么走路"**的前提下推进。

将来 Lia 的正式外观有两条现实路径（都无需本仓自研）：

1. **VRoid Studio**（免费、本地、动漫风）→ VRM → Godot 用 `godot-vrm` 插件导入
   —— 这是目前唯一免费且真正**动漫风**的可用路线；
2. **Mixamo**（免费骨骼+动画库，真人比例）→ 需要 Adobe 账号登录，属手工步骤；
3. 或者回到本仓 CHARACTER LINE 自己的高精度重拓扑（`docs/characters/CHARACTER_LINE.md`）。

无论走哪条，**本线的重定向工具都能复用**——它只要求目标是人形骨架。

---

## 3. 重定向管线

脚本：`tools/character/retarget_humanoid.py`

```
角色 FBX + 动画库 GLB  →  一个自包含 GLB（网格 + 骨架 + N 个 clip）
```

### 3.1 方法：世界增量旋转重定向

不用约束、不用第三方 retargeter。对每一对骨骼、每一帧：

```
D        = pose_source @ rest_source⁻¹      # 源骨骼发生的那次"世界旋转"
R_desired= D @ rest_target                  # 把同一次旋转施加到目标 rest 上
R_basis  = (R_parent_desired @ R_rest_offset)⁻¹ @ R_desired
```

全部在 **armature space** 里算，所以：

- 导入器给物体加的旋转/缩放**自动抵消**；
- **骨骼 roll、骨骼朝向约定完全不影响结果**——这是它能同时吃 Rigify、Mixamo、
  Quaternius 三种完全不同的命名的原因；
- 源骨架与目标骨架如果朝向不同，会经过一次共轭 `C = M_target⁻¹ @ M_source`
  换算（本次实测 `conjugation = 0.00 deg`，是 no-op，但这条不能省）。

比例差异靠 **髋部平移按髋高比例缩放**处理，其余骨骼**只取旋转**——
这样脚/手的接触点在不同腿长的骨架之间才不会漂。

### 3.2 骨骼映射：按归一化名字 + 链序位配对

**不要用固定字典。** Quaternius 自家两个包的手指命名就不一样：

| 包 | 骨架 | 手指标法 |
| --- | --- | --- |
| Ultimate Modular Women | 51 骨 | `Index1/2/3.L` |
| Ultimate Modular Characters | 62 骨 | `Index2/3/4.L` + `_end` 叶骨 |

固定字典的结果是**只映射到 20/62 骨，然后你得到一个手臂永远不动的角色，而且不报错**。

现在的做法：名字归一化（去 `DEF-` 前缀、去 `_end`、去侧标记）→ 查同义词表
（`thigh/upperleg`、`shin/lowerleg`、`forearm/lowerarm`、`abdomen/spine1`…）→
按 `(部位, 左右)` 配对；**手指按每条链的顺序位次配对**，与具体编号无关。

实测：女性 51 骨 → 映射 20/20（除 `Root` 与 30 根手指）；男性 62 骨 → 21/21（除 `Root` 与 `_end`）。

### 3.3 手指默认不重定向

**这是有意为之，不是偷懒。**

动画库里的人偶**始终握着拳**：探针显示 `Index1.L` 在世界空间有 ~162° 的恒定旋转
（= 手臂下垂 ~80° + 指节弯曲 ~80°），**不随动画变化**。低模手是为一双"放松的手"
建模的，按同一条世界轴反转 80° 会把手指**折穿手背**，渲染出来是一排尖刺。

所以默认 `--exclude "^(Index|Middle|Ring|Pinky|Thumb)\d\.[LR]$"`：手指保持**作者建模时的姿态**，
手腕仍然参与动画。需要精细手指时用 `--exclude ""` 打开，但要自己确认目标手能承受。

> 验证方法写在脚本里：`A_TPose` 这一条 clip 的**每一根骨骼增量都恰好是 0°**
> ——这说明两套 rig 的 rest 是对齐的、数学是对的。任何"重定向把人拧歪"的怀疑，
> 先跑这个。

### 3.4 顺手修掉的一个静默 bug

Quaternius 的 FBX **每个材质的 Principled `Alpha` 都是 0**。Blender 会忠实地把它写成
`baseColorFactor` 的 alpha = 0 → **在 Godot 里整个角色完全透明，什么都不渲染，也不报错**。
脚本现在强制 alpha = 1 并把混合模式设为不透明。

排查它花了一整轮（画面全黑 → 查 AABB → 查 mesh visible → 最后解析 GLB 二进制才看到）。
写在这里是为了下次不用再花一轮。

### 3.5 身高归一的 bug：k 被乘了两次

`--target-height` 靠"量出当前高度 → 乘 `k = target/h0` → `transform_apply`"实现。
原写法把**骨架和网格都乘了 k**，但 FBX 导入的网格是 `parent=CharacterArmature`
（`parent_type=OBJECT`）的**子物体，本身已经继承骨架的缩放**，于是 k 被施加两次：

```
实际高度 = h0 · k²        而不是 h0 · k
```

后果：三个首批角色落在 **1.539 / 1.556 / 1.581 m**（各不相等），而元数据里
照样写着 `target_height_m: 1.7`——**请求值被当成实测值记录，所以没人发现**。

现在只缩放**层级根**（`o.parent` 不在目标集合里的对象），并且**应用后重新测量**：

```
[RETGT] rescale height 1.8281 -> 1.7000 (x0.92994) via 1 root object(s): ['CharacterArmature']
[RETGT] rescale verify h=1.7000 (target 1.7000, drift +0.00%)
```

drift > 1% 会打 `!! HEIGHT OFF BY ...` 并写进日志。JSON 现在同时记录
`target_height_m`（**实测**）、`target_height_requested`、`rescale_k`。

修之前这批素材的源高在 1.83–2.05 m 之间，二次缩放会把它们压到 **1.41–1.58 m 且各不相同**；
修之后 21 个全部恰好 1.7000 m。

### 3.6 `--clips all` 曾经烘出 0 条

源动作导入后被改名为 `__src__<clip>` 以避免导出时混入。但 `--clips all` 取的是
`a.name`（**带前缀**），而配对时比较的是剥掉前缀的名字 → 两个集合永不相交 →
**烘 0 条 clip，且只打一行 `baked 0 clips`**。

现在 `all` 分支先剥前缀。不过本项目**默认不用 `all`**，见 §5。

---

## 4. 产物

```
third_party/quaternius/universal_animation_library/     # 原始包（含 License.txt）
tools/character/placeholders.tsv                        # 21 个角色的清单（数据源）
tools/character/clips_standard.txt                      # 37 条精选剪辑（数据源）
assets_source/characters/placeholders/                  # 21 个角色，各 2.2–2.9 MB / 37 clips
  lpg_adventurer_w.glb   lpg_medieval_w.glb   lpg_adventurer_m.glb
  lpg_witch_w.glb  lpg_king_m.glb  lpg_swat_m.glb  ... （共 21 个）
  *_retarget.json                                       # 每个的映射/剪辑/身高（可核查）
  _review/CAST_all.png                                  # 全员证件照 2520x1440（21 个一格）
  _review/<角色>_CONTACT.png                            # 六视图审查拼版（按需生成）
godot/assets/characters/placeholders/                   # 同步给 Godot 的副本
godot/assets/characters/_third_party/AnimationLibrary_Godot_Standard.glb
```

**21 个角色**（女性 10 / 男性 11），全部由同一个脚本、同一套动画烘出：

| 女 | Adventurer · Casual · Formal · Medieval · Punk · SciFi · Soldier · Suit · Witch · Worker |
| --- | --- |
| 男 | Adventurer · Beach · Casual · Casual2 · Farmer · King · Punk · Spacesuit · Suit · Swat · Worker |

37 个剪辑：`Idle · Idle_Talking · Idle_Torch · Walk · Walk_Formal · Jog_Fwd · Sprint ·
Crouch_Idle · Crouch_Fwd · Sitting_Enter/Idle/Talking/Exit · Interact · PickUp_Table ·
Push · Jump_Start/Loop/Land · Roll · Hit_Chest · Hit_Head · Death01 · Dance ·
Sword_Idle · Sword_Attack · Spell_Simple_Enter/Idle/Shoot/Exit · Fixing_Kneeling ·
Swim_Idle · Swim_Fwd · Driving · Punch_Jab/Cross/Enter`

**全部身高 1.7000 m，实测校验**（`glb_extents.py` 直接解析 GLB 的 POSITION
accessor，不经过引擎；21/21 全部 `H=1.700`）。统一身高是**刻意**的：
一台摄像机 rig、一个落地偏移、一套状态机就能吃下全部角色。

> ⚠️ **不要用 Godot 的 `MeshInstance3D.get_aabb()` 报身高。** 它给的是网格的
> **bind-space** AABB，不含骨骼节点的缩放，会低报几个百分点（本次即 1.58 vs 1.70）。
> 量身高用 `tools/character/glb_extents.py`。

---

## 5. 怎么看 / 怎么再生成

### 检验台（任意 GLB，可交互）

```bash
"/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --path F:/SEKAI/godot \
  --resolution 900x1000 res://scenes/characters/CharacterAssetTest.tscn -- \
  --glb res://assets/characters/placeholders/lpg_adventurer_w.glb \
  --report out.json --capture sheet.png --anim Idle --yaw 0.0 --pitch 0.06 --dist 3.2
```

`LMB` 环绕 · 滚轮缩放 · `SPACE` 骨架叠加 · `TAB` 切 clip · `R` 复位。
带 `--report` 会输出**真实导入了什么**（骨骼名、clip 列表与长度、mesh、AABB、相机位）
——"导进来了"从此是可核查的断言，不是感觉。

**`--report` / `--capture` / `--plan` 都会自己退出**，可以直接丢进 shell 的 `for` 循环；
只有想用手看时才加 `--stay`。（没有这条时 `--report` 会落到交互模式、永不退出，
把调用它的循环**静默卡死**。）

> Godot 导入时会**把 clip 名的 `_loop` / `-loop` 后缀剥掉**并设为循环模式：
> 文件里叫 `Idle_Loop`，Godot 里叫 `Idle`。

### 多视图审查图（一次进程出全部视图）

```bash
bash tools/character/render_review_sheet.sh F:/SEKAI/.tmp_assets/placeholders lpg_witch_w
```

每个角色出 6 张（idle 正面 / walk 3-4 / jog 侧面 / 坐姿 / 持剑 / 交互）+
一张 `_CONTACT.png` 拼版。已审过的三张存档在
`assets_source/characters/placeholders/_review/`（其余角色按需再跑）。

**为什么是 `--plan` 而不是循环调 `--capture`**：每次启动 Godot 要付 ~85 s
（启动 + 资源载入 + 首帧编译），而 40 帧只要 0.7 s。分开调 6 次 ≈ 9 分钟；
`--plan` 一个进程出 6 视图 ≈ 1 分钟。

```bash
  --plan "idle:0.0:0.06:3.2:Idle:0.6;walk:0.75:0.08:3.2:Walk:0.5" \
  --out-prefix /path/to/<name>__
```
格式 `名字:yaw:pitch:dist:clip:相位秒`。

相位是**让 clip 真实播放到**的时刻，靠逐帧推进（不是 `seek`）——跳时钟会造出
游戏里根本不存在的姿势。日志里的 `played=` 是**实际播到的 clip 名**，
请求打错时会打 `<none>` 并告警：否则一张审查图会六格全是同一个 idle 而声称是六个剪辑。

### 全员证件照（想要"现在有哪些角色"看这一张）

```bash
bash tools/character/render_cast_sheet.sh          # 21 个角色 → CAST_all.png
```

一次进程出**整个角色库**，7 列 × 3 行、单元格 360×480 → 拼版 **2520×1440**，
实测 **65 s**（逐角色启动要 ≈ 30 min）。角色名由 `Label` 烧进画面，
所以图自带标注、不会和渲染脱节。

产物：`assets_source/characters/placeholders/_review/CAST_all.png`

拼版用 Godot 的 `Image.blit_rect` 完成，**不经任何图像库**——
避免"拼版工具和渲染结果不一致"这一类问题。清单 `tools/character/cast_all.txt`
（`<名>|<res://路径>`）由 `placeholders.tsv` 派生，顺序 = 烘焙顺序（先女后男）。

### 重新烘焙

清单驱动，不用手敲路径：

```bash
bash tools/character/bake_placeholders.sh                      # 全部 21 个
bash tools/character/bake_placeholders.sh lpg_witch_w lpg_king_m   # 指定
```

角色表在 `tools/character/placeholders.tsv`，剪辑表在 `tools/character/clips_standard.txt`。

**默认用 `clips_standard.txt` 的 37 条，不用 `--clips all`。** 库里有 46 条，
我们**刻意不要**这 9 条：

| 排除 | 原因 |
| --- | --- |
| `A_TPose` | rest 姿态检查，不是动画 |
| `Pistol_*`（6 条） | SEKAI 没有枪械，烘进去只是让每个 GLB 变胖 |
| `Roll_RM` / `Sword_Attack_RM` | **根运动变体**：把髋部位移烘进 clip，会和 `external_velocity` 这个唯一的位移载体打架 |

需要时单独拉某一条即可：

```bash
"/g/blender.exe" -b --factory-startup --python tools/character/retarget_humanoid.py -- \
  --target "<角色.fbx>" \
  --lib "F:/SEKAI/third_party/quaternius/universal_animation_library/Animation Library[Standard]/Godot/AnimationLibrary_Godot_Standard.glb" \
  --name lpg_xxx --out-glb "F:/SEKAI/assets_source/characters/placeholders" \
  --target-height 1.70 --clips "Idle_Loop,Walk_Loop,Jog_Fwd_Loop"
```

另有 `--probe <骨名,…>` 打逐帧角度、`--debug` 打最大旋转骨骼榜、
`--exclude <regex>` 控制哪些骨保持目标 rest（`--exclude ""` 打开手指）。

---

## 6. 已知限制（带进正式素材阶段）

| # | 限制 | 说明 |
| --- | --- | --- |
| 1 | **风格不符** | 低模卡通，违反本仓 `禁 generic low-poly` 规则。**只能当占位** |
| 2 | 无贴图 | 纯色材质（原包就没有贴图），无 PBR 贴图集 |
| 3 | 手指不参与动画 | 见 §3.3，这是刻意选择 |
| 4 | 无面部/口型 | 无 shape key，`Talk` 只有身体与头部动作 |
| 5 | 无头发/披风辅骨 | 只有 `Hair_Brown` 之类材质，没有独立发骨 |
| 6 | 根运动 | 库的 Standard 版是原地动画；移动由游戏逻辑驱动 |
| 7 | 髋部缩放是线性近似 | 髋高比例缩放，跨极端比例骨架会略有滑动 |
| 8 | 手腕姿态 | 源人偶的腕部 rest 与低模角色略异，手腕朝向有轻微偏差（不影响读懂动作） |

---

## 7. 与 LIA 线的关系

两条线**不冲突**，可以并行：

- `assets_source/characters/lia/` 与 V3 绑定/导出物**原样保留**，没有被动过。
- 本线新增的都只是新目录（`third_party/`、`assets_source/characters/placeholders/`、
  `godot/assets/characters/placeholders/`）和自己的一份文档。
- **动画是共享资产**：Lia 的高精度版本做出来之后，用同一个
  `retarget_humanoid.py` 把 46 条剪辑重定向到她的骨架上即可，不需要重新做动画。

顺序建议：**先用占位角色把游戏跑起来**（含移动/对话/摄像机），
Lia 的正式外观在该线自己的节奏里推进，做出 V4 之后直接替换。
