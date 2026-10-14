# tools/character — CHARACTER LINE 工具

全部为**只读审计 / 测量 / 渲染**或**可逆变换**脚本。Blender = `G:/blender.exe`（5.1.2）。
headless 调用格式（bash 可直接跑）：

```bash
"/g/blender.exe" -b --factory-startup --python <script> -- <args>
```

> ⚠️ 不要用 `G:\blender\blender.exe` —— 那是残缺的 4.4.3 拷贝，启动报「并行配置不正确」。

---

## 1. `lia_audit.py` — 全量机器审计

```bash
"/g/blender.exe" -b --factory-startup --python tools/character/lia_audit.py -- \
  --fbx assets_source/characters/lia/01_v0_original/LIA_v0_original.fbx \
  --out assets_source/characters/lia/00_reference
```

输出 `LIA_V0_AUDIT.json` / `.txt`：对象与变换、逐 mesh 几何（verts/tris/quads/ngons/非流形/
边界边/自相交边/松散/重复顶点/重复面/面积）、UV（bbox/越界/面积/texel density/镜像面）、
材质与贴图、骨架与骨骼层级、顶点组与权重统计（未加权/超 4 influence/未归一）、形态键、AABB 互相重叠。

## 2. `lia_topology.py` — 拓扑与比例

边长方差与分位、瘦长面比例、**连通壳数量**（拆件可行性的判据）、120 层 Z 切片宽度剖面、
稳健镜像面对称性。

## 3. `lia_landmarks.py` — 定点地标

中线带前/后轮廓（找鼻/下巴）、头核心宽度、躯干/肩（排除手臂与后飘发）、
**腿部 X 分离run**（找胯高/膝/靴口）、手臂外扩范围。

## 4. `lia_symmetry.py` — 分区镜像对称性

按 z 区间 + \|x\| 掩码分区算镜像 rms / p50 / p95。**决定能否镜像刷权重、能否 Symmetrize。**

## 5. `lia_measure.py` — 米制测量图（可分区）

```bash
# 全身 5 cm 网格剪影
"/g/blender.exe" -b --factory-startup --python tools/character/lia_measure.py -- \
  --fbx <fbx> --out <dir> --tag LIA_V0 --grid 0.05 --resx 1000 --resy 1400

# 头部 2 cm 网格 + 着色
"... lia_measure.py" -- --fbx <fbx> --out <dir> --tag LIA_V0_head \
  --zlo 0.84 --zhi 1.14 --grid 0.02 --resx 1700 --resy 640 --style form
```

蓝/绿 = 每 `--grid`，红/黄 = 每 0.10 m，品红 = 身体中轴。
同时输出 CSV 与 2.5 cm 步进剖面表（轮廓宽度 / 深度，单位米）。

## 6. `lia_query_head.py` — 头部定点查询

z 分带的前 15 % 表面 \|x\| 展开（区分"鼻"与"刘海"）、
**真正中线列（\|x−XC\|<12 mm）逐 1 mm 的 y_min/y_max** —— 面部侧颜剖面最干净的读法。

## 7. `lia_render_views.py` — 审核渲染

```bash
"... lia_render_views.py" -- --fbx <fbx> --out <dir> --tag LIA_V0
"... lia_render_views.py" -- --blend <blend> --out <dir> --tag LIA_V1BASE
```

出：silhouette / form / matcap × front·right·back·3/4、头部特写 4 视角、躯干、腿、俯视剪影。

## 8. `make_contact_sheet.py` — 审核表

```bash
"... make_contact_sheet.py" -- --out <sheet.png> --cell 440x620 --cols 4 --bg 0.09 -- <img...>
```

纯 Blender 像素拷贝拼图，无需 Pillow / ImageMagick。**路径必须用绝对路径。**

## 9. `lia_make_base.py` — V1 归零基底

```bash
"... lia_make_base.py" -- --fbx <fbx> --out-blend <blend> --out-json <json> [--scale 1.508]
```

变换烘焙（FBX −90°X 烘进网格，物体 matrix → Identity）· 稳健扫描求镜像面并归 `x=0` ·
原点移到脚底中轴 · 可选统一缩放。**拓扑 / UV / 材质 / 法线均不改动。**

---

# B 组 · 绑定 / 权重 / 动画 / 导出（V3 起）

## 10. `lia_rig_build.py` — 生成骨架 + 自动权重

```bash
"... lia_rig_build.py" -- --blend <in.blend> --out-blend <out.blend> --out-json <out.json>
```

生成 **23 骨 / 22 变形骨**的整洁 humanoid 骨架（**不含 Rigify 控制层**），关节高度取自
V0 实测地标；顺带 Smart UV Project + 占位材质 + `ARMATURE_AUTO` 自动权重。
可选 `--clean 0` / `--uv 0` / `--weights 0` / `--base-color '#RRGGBB'`。

## 11. `lia_pose_test.py` — 变形 QA 渲染

```bash
"... lia_pose_test.py" -- --blend <rigged.blend> --out <dir> --tag LIA_V3 [--only 03_arm] [--resx 520 --resy 780]
```

12 组极限姿势 × 3 视角（front / right / q34）。姿势表在脚本顶部，**世界轴约定**：
`X` = 前后摆（负 X on 大腿 = 抬腿向前）、`Y` = 左右摆 / 外展、`Z` = 扭转。

## 12. `lia_deform_probe.py` — 变形诊断（最重要的一个）

```bash
"... lia_deform_probe.py" -- --blend <rigged.blend> --pose arm_up [--out report.txt] [--min-move 0.12]
```

摆姿势 → 评估变形后网格 → 输出：位移超阈值的顶点数、它们的**主导权重组分布**、
rest 坐标分位、到手臂骨链的距离分布、最差 12 个顶点的详细权重，外加全网格 `d_arm` 直方图。
**"某姿势下某块几何乱飞"时先用它，不要看图猜。**

## 13. `lia_weight_cleanup.py` — 权重清理

```bash
"... lia_weight_cleanup.py" -- --blend <rigged.blend> --out-blend <out.blend> \
  --r-arm 0.070 --margin 0.045 --max-influences 4 --smooth 2 --smooth-factor 0.35
```

剥离手臂骨影响 → 丢弃 <0.006 → 限制 ≤4 影响 → 归一化 →（可选）平滑 → 再剥离 → 再限制。
**结尾带 `assert`**：`unassigned` / `over_max` / `forbidden_verts_still_armed` 任一非 0 即失败退出。

## 14. `lia_weight_region.py` — 区域 / 测地版清理（留档）

凹折痕区域生长 + 区域级归属，或 `--mode geodesic` 测地 Voronoi。
**在本角色上均未成功**（QuadriFlow 表面太平滑，19958/20456 顶点同一区域），保留供后续网格复用。

## 15. `lia_anim_idle.py` — authored Idle

```bash
"... lia_anim_idle.py" -- --blend <rigged.blend> --out-blend <anim.blend> --name Idle --fps 24
```

5 s 呼吸循环（骨盆微沉 + 胸腔起伏 + 头微动 + 臂微张），BEZIER / AUTO_CLAMPED。

## 16. `lia_export_glb.py` — 导出 + 自检

```bash
"... lia_export_glb.py" -- --blend <anim.blend> --out <dir> --name lia_v3 [--animations 1]
```

导前 pre-flight（UV / 材质 / armature modifier / 顶点组 / deform 骨是否都有组），
导后**二进制解析 GLB** 并断言 `skins==1` / `joints>0` / `JOINTS_0 & WEIGHTS_0 & NORMAL 存在` / `materials>=1`。

---

# C 组 · 外部占位角色线（人形 + 动作）

规格文档：`docs/characters/THIRD_PARTY_CHARACTER_ASSETS.md`。

## 17. `asset_inspect.py` — 任意角色资产结构审计

```bash
"C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe" \
  tools/character/asset_inspect.py --in <a.fbx> --out r.json --bone-dump
```

吃 fbx / glb / blend / obj，输出 mesh（verts/tris/quads/UV/顶点组/形态键/材质/修改器）、
骨架（骨数/变形骨/根骨/全部骨名）、材质、贴图、action、bbox + 身高。
**拿到一个陌生资产第一步就跑它**（两个 Quaternius 包的手指命名差异就是这么发现的）。

## 18. `glb_extents.py` — 不靠引擎量 GLB 尺寸

```bash
"C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe" \
  tools/character/glb_extents.py assets_source/characters/placeholders/*.glb
```

直接解析 GLB 容器（JSON chunk + POSITION accessor 的 min/max），合成节点变换；
**skinned mesh 按 glTF 规范改用骨架根的 world matrix**（蒙皮网格忽略自身节点变换）。

**为什么必须单独有它**：Godot 的 `MeshInstance3D.get_aabb()` 给的是 **bind-space**
AABB、不含骨骼缩放，会低报（本次 1.58 实测 vs 1.70 实际）。
**永远不要拿引擎的 AABB 报身高。**

## 19. `retarget_humanoid.py` — 世界增量旋转重定向（核心）

```bash
bash tools/character/bake_placeholders.sh lpg_witch_w
```

原理、映射规则、手指为何默认排除，见
`docs/characters/THIRD_PARTY_CHARACTER_ASSETS.md §3`。

## 20. `bake_placeholders.sh` + 两张表 —— 清单式烘焙

```bash
bash tools/character/bake_placeholders.sh            # 全部 21 个
bash tools/character/bake_placeholders.sh lpg_king_m # 指定
```

- `placeholders.tsv` — `名字 <TAB> 源FBX <TAB> 身高`，21 个角色
- `clips_standard.txt` — 37 条精选剪辑（**不用 `--clips all`**，理由见文档 §5）

旧产物会先存成 `.glb.prev`，让回归**可 diff** 而不是静默。

## 21. `render_review_sheet.sh` — 六视图审查图（一个进程出全部）

```bash
bash tools/character/render_review_sheet.sh <out_dir> lpg_witch_w ...
```

每角色 6 张 + 一张 `_CONTACT.png`。内部走 Godot 的 `--plan`
（**不是**循环调 `--capture`：一次启动 ~85 s，40 帧只要 0.7 s）。

## 22. `render_cast_sheet.sh` — 全员证件照（一张图看完整个角色库）

```bash
bash tools/character/render_cast_sheet.sh                      # 默认 21 个 → CAST_all.png
bash tools/character/render_cast_sheet.sh out.png list.txt 6   # 自定义
```

**一次进程出 N 个角色**（`--cast-file` / `--cast-cols`）。逐角色启动要付 ~85 s/次，
21 个 ≈ 30 min；单进程实测 **65 s**。

- 单元格尺寸 = `--resolution`，用 `Image.blit_rect` 直接拼版 → **不依赖任何图像库**，
  也就不存在"拼版工具和渲染结果不一致"的可能
- 角色名由 CanvasLayer 的 `Label` **烧进画面**，所以图自带标注、不会和渲染脱节
- 环境变量可覆盖：`CELL_W CELL_H COLS ANIM PHASE PIVOT_Y DIST TIMEOUT`

清单 `tools/character/cast_all.txt`（`<名>|<res://路径>`，`#` 注释）由
`placeholders.tsv` 派生，顺序 = 烘焙顺序（先女后男）。

Godot 侧对应 `godot/scenes/characters/CharacterAssetTest.tscn` +
`godot/scripts/characters/character_asset_test.gd`（`--report` / `--capture` /
`--plan` / `--cast-file` / `--bone-probe` / `--stay`）。

> 默认 `--resolution 360x480 x 7 列` → **2520x1440**。要更大的单人格子就调大
> `CELL_W/CELL_H`（总数不变，拼版尺寸按列数×格尺寸算）。

## 23. `glb_anim_probe.py` — 动画通道探针（不靠引擎）

```bash
python tools/character/glb_anim_probe.py <glb> --clips Idle_Loop,Sitting_Idle_Loop \
       --path translation --nodes Hips,Root
python tools/character/glb_anim_probe.py <glb> --channels      # 哪些 clip 动了哪些骨
```

逐 clip / 逐骨 / 逐轴打出 key 数与 min/max/span，`<-- moves` 标出真正有位移的轴。
**"坐姿看起来不对"这类问题最终是它 + 骨骼探针定位的**：它证明髋部位移**没丢**，
从而把嫌疑从"重定向数学"转到"骨架层级"。

> glTF 里节点的 TRS 是**相对父骨**的。父骨静止时髋部下沉会原样显现；父骨也动时
> 要连着看。别把它当成世界坐标。

## 24. `validate_cast.py` — DEMO_CAST 清单校验（对磁盘 / 对烘焙）

```bash
python tools/character/validate_cast.py
```

查的是**声明**不是语法：每个 model 在 source 与 Godot 两棵树里都存在；
每个 `skeleton_profile` 的骨头数 / 身高 / clip 数 / rig 修复**与该角色自己的
`_retarget.json` 相符**；`base_motions` 引用的 clip 真实存在；`character_id` 唯一
且**不像模型名**（`lpg_*` 直接判 FAIL —— 那正是 ROLE ≠ MODEL 要防的）。

clip 名**优先读一份 Godot `--report`**（权威），读不到才退化成"剥 `_loop` 推断"，
并在输出里注明用的是哪种。

引擎侧的另一半在 `godot/tools/cast_check.gd`（见下）——它能抓到 Python 抓不到的：
**磁盘上存在但导入失败、因而不是资源的 GLB**。

## 25. `cast_check.gd` — 引擎内清单审计

```bash
G=/g/Godot/Godot_v4.4.1-stable_win64_console.exe
"$G" --headless --path F:/SEKAI/godot --script res://tools/cast_check.gd \
     > assets_source/characters/placeholders/_review/cast_audit.txt 2>&1
```

打印每个角色的可加载性、动作待办计数、`base_motions` 的
**covered / partial / missing** 三分（这就是"还缺哪些动作"的权威清单），以及各池的
模型可加载性。

> `print()` 是块缓冲，**重定向到文件**再读；直接管道会看不到输出，看起来像挂死。

---

## 已知坑

| 坑 | 现象 | 对策 |
| --- | --- | --- |
| 渲染后立刻读回像素 | `img.pixels` 全 0 → 轮廓宽度恒等于画布宽 | 测量走几何；网格 burn-in 读改写正常 |
| `Mesh.faces` | `AttributeError` | 是 `.polygons` |
| 镜像面公式 | 平移后 rms 反而变大 | 镜像 across x=c 是 `2c − x`；验证带宽必须与扫描带宽一致 |
| 相对路径给 `images.load` | `Cannot read ...: No such file` | 一律绝对路径 |
| **`vertex_groups[i].remove()` 后读 `v.groups`** | 拿到**旧缓存**，脚本把刚剥离的权重原样写回，**不报错** | 权重读进 Python dict → 处理 → `vertex_groups.clear()` → 重建 |
| **Blender 4.4+ `Action.fcurves`** | `AttributeError`（slotted actions） | 别自己 `actions.new()`，让 `keyframe_insert` 建 action 再改名 |
| `mesh.use_auto_smooth` | 4.1+ 已移除 | `shade_smooth()` 仍可用，别设 auto_smooth |
| **QuadriFlow 默认对称** | 发型/披风被强制折中 | 必须 `use_mesh_symmetry=False` |
| **QuadriFlow 后无折痕可分割** | 凹折痕区域分割退化成单一区域 | 不要指望它做部件分割；部件分割必须先于重拓扑 |
| **`transform_apply` 缩放"父子都选"的层级** | 网格是骨架 `parent_type=OBJECT` 的子物体、**已继承父缩放**；父与子都乘 k → **k 乘了两次**，身高 = `h0·k²` | **只缩放层级根**（`o.parent` 不在目标集合内者），并在应用后**重新测量断言** |
| **请求值被当成实测值写进元数据** | 身高偏了 7 % 却记录 `target_height_m: 1.7` | 元数据区分 `*_requested` 与**实测**值；drift > 1 % 报红 |
| **Godot `MeshInstance3D.get_aabb()`** | 给 bind-space AABB、不含骨骼缩放 → 低报身高（1.58 vs 1.70） | 量尺寸用 `glb_extents.py`，不用引擎 |
| **`--clips all` 撞上 `__src__` 前缀** | 源动作改名后取 `a.name` 得带前缀名，配对时比的是剥前缀名 → 两集合不相交 → **烘 0 条 clip** | `all` 分支先剥前缀；本项目默认走显式清单 |
| **`--report` 落到交互模式** | 进程永不退出 → 调用它的 `for` 循环**静默卡死** | 批处理模式必须自己 `quit()`；要交互显式 `--stay` |
| **GDScript 协程赋值不带 `await`** | `Parse Error: ... must be called with "await"` → 场景脚本整个 load 失败、无脚本可跑、无人 `quit()` → **Godot 永久挂起** | 取协程返回值必须 `await`；批处理里给 Godot 套 `timeout` |
| **按视点逐个启动 Godot** | 一次启动 ~85 s（启动+载入+首帧编译），40 帧只要 0.7 s → 6 视图 ≈ 9 分钟 | 用 `--plan` 单进程出全部视图（≈ 1 分钟） |
| **TaskStop 杀不掉脚本的 `for` 循环** | shell 循环存活、持续重生 Godot 进程 | 按 `CommandLine` 认领 **bash 循环 + Godot** 一起杀；别按映像名杀（编辑器是同名进程） |
| **`--headless` + 截屏** | 截屏在等 `frame_post_draw`，headless 无渲染设备 → **永久挂起** | 出图/出片一律**不加** `--headless`；它只给 `stow_diag.gd` / `tests/*.gd` |
| **`--cast-*` 没给 `--resolution`** | 视口尺寸为 0 → 拼版无从下手 | 显式给 `--resolution WxH`；**单元格尺寸就是视口尺寸** |
| **两个 Quaternius 包的 rig 不是同一个** | 女包（51 骨）把 `UpperLeg.L/R` 挂在**根骨**上，男包（62 骨）挂**骨盆**。重定向只写旋转 ⇒ 女角色坐下时骨盆下沉、腿冻在原位 → **"坐在看不见的椅子上"**；蹲/跪同样错 | 导入后跑 `normalise_leg_chain()` 把腿链重挂骨盆；**改动前后量 head 位移并断言**（实测 drift 0.000000 m）；`use_connect=False` |
| **相对路径传给 Godot** | `FileAccess` 以**工程根**（`godot/`）为基准，不是 shell CWD → 清单读成空、`quit(1)` | shell 脚本里 `abspath()` 绝对化；**失败时不许把原因吞掉** |
| **失败信息被管道里的 `grep` 吃掉** | 只看到 `FAILED`，看不到为什么 | 输出先落 `mktemp` 日志，grep 用于展示，失败时 `tail` 原始日志 |
| **烘焙元数据的 clip 名 ≠ 运行时 clip 名** | 元数据记 `Idle_Loop`，Godot 里叫 `Idle`（导入剥 `_loop`/`-loop`） | **以 Godot `--report` 为准**，别猜剥离规则；校验器注明来源 authoritative/inferred |
| **GDScript `PackedStringArray` 是值类型** | `dict[k].append(x)` 改的是临时副本 → 统计**恒为 0**、不报错 | 用局部变量累加，或累完整体写回 `dict[k] = arr` |

