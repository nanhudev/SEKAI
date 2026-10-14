# LIA V3 — RIG CANDIDATE

> 角色线 PHASE 06–10 交付记录。上游：`LIA_V0_AUDIT.md`（PHASE 01）。
> 权威规格：`CHARACTER_LINE.md`。状态回写：`PRODUCTION_BOARD.md` → `## C-LIA`。

---

## 1. 本版定位

用户决定：**先简单绑定跑起来，高精度美术素材后期再加**。

因此 V3 **不是最终角色**，而是**管线验证版**：证明
`FBX → 重拓扑 → 骨架 → 蒙皮 → 权重清理 → 动画 → GLB → Godot` 全链路成立，
且顺带拿到一套可复用的绑定/权重工具。

绑定基底是 **QuadriFlow 自动重拓扑产物**（`02_working/LIA_v2_auto_quadriflow.blend`，
20,478 面 / 100 % 四边面），**不是** 499 k 三角汤原模。理由：面数合理、四边面拓扑
对自动权重友好、Godot 性能安全。代价是脸/手/发在重拓扑时已被抹平——这属于高精度
素材阶段要重做的事，本版不追。

---

## 2. 骨架（23 骨 / 22 变形骨）

**没有用 Rigify 的控制层**——直接生成最终要出给 Godot 的 DEFORM 骨架，
避免导出时再剥一层控制骨。

| 链 | 骨 | head z (m) | tail z (m) |
| --- | --- | --- | --- |
| 根 | `root`（不参与蒙皮） | 0.000 | — |
| 骨盆 | `pelvis` | 0.860 | 0.950 |
| 脊柱 | `spine_01` / `spine_02` / `spine_03` | 0.950 / 1.030 / 1.110 | 1.030 / 1.110 / 1.185 |
| 颈头 | `neck` / `head` | 1.215 / 1.330 | 1.330 / 1.580 |
| 臂 ×2 | `clavicle` / `upperarm` / `lowerarm` / `hand` | 1.205 / 1.205 / 0.972 / 0.754 | 1.205 / 0.972 / 0.754 / 0.620 |
| 腿 ×2 | `thigh` / `calf` / `foot` / `toe` | 0.860 / 0.482 / 0.105 / 0.028 | 0.482 / 0.105 / 0.028 / 0.022 |

- 关节高度**来自 V0 实测地标**（膝 0.482 / 下巴 1.375 / 颅顶 1.580 等），不是套模板比例。
- 命名 `snake_case` + `_l` / `_r`，无 `Bone.001`，可直接用于后续 retarget。
- roll 统一 `calculate_roll(GLOBAL_NEG_Y)`：局部 X = 前后摆、局部 Y = 骨长、局部 Z = 左右摆。
- **手指骨未建**：当前网格手指已被重拓扑抹平（并成手套），建了也没处用。
  高精度素材阶段补 `thumb/index/middle/ring/pinky`，编号方案已预留。
- **辅骨未建**（披风 / 头发）。V0 那条左肩"翼"目前跟随身体骨；需要次级运动时再加
  `cape_01..03`，方案见 `CHARACTER_LINE.md` §9。

## 3. Rest pose

Rest pose = 网格现状（**手臂自然下垂，接近 relaxed A-pose**，非严格 35–45°）。

原因：骨架 rest 必须匹配网格形状，否则蒙皮直接错位。把下垂臂拉成标准 A-pose
需要 `Apply Pose as Rest Pose` 重写网格，**这件事留到高精度素材阶段做**——
那时网格会重做，一起做代价为 0。

---

## 4. 蒙皮

```
自动权重（ARMATURE_AUTO，heat map）
  → 剥离"不该受手臂骨影响"的顶点
  → 丢弃 < 0.006 的微小权重
  → 限制到 ≤ 4 影响 / 顶点
  → 归一化
  → 2 轮 deform 组平滑（factor 0.35）
  → 再剥离 → 再限制 → 再归一化
```

**结果**：`unassigned = 0`、`over_max = 0`、`influences_median = 2`、`influences_p95 = 4`。

清理脚本用**断言自守**（`lia_weight_cleanup.py` 结尾 `assert`），不满足就退出，
不会静默产出一个"看起来成功"的坏文件。

---

## 5. ⚠️ 已知缺陷（必须带进高精度素材阶段）

### 5.1 裙摆 / 袖侧布片在抬臂时拉成"三角翼"

- **现象**：`03_arm_up` / `04_arm_cross` 两个极限姿势下，腰侧布片朝手臂方向张开成平板。
- **实测**（`lia_deform_probe.py`，原始自动权重）：7050 个顶点位移 > 12 cm，
  其中 **5457 个离手臂骨链 > 7 cm**；最差顶点位于 `(-0.22, -0.14, 0.61)`（裙摆前缘），
  却由 `hand_r = 0.67` / `lowerarm_r = 0.26` 驱动。
- **根因**：整体一次 QuadriFlow 让**布片与手臂在网格上几何融合**。
  - `d_arm` 中位数 14.7 cm，但布片**外侧**只有 2–5 cm → 落在手臂体积内。
  - 按顶点切 → 半边跟手臂、半边跟躯干 → **撕裂**。
  - **区域分割也失效**：沿凹折痕断开后，**19958 / 20456 个顶点落在同一个区域内**
    （QuadriFlow 表面太平滑，布与手臂之间没有可用折痕）。
  - **测地 Voronoi 也失效**：布片与手臂表面连通，沿表面距离反而更近。
- **尝试过并记录在案的方案**（脚本都还在，可复用）：
  1. 欧氏距离剥离 → 制造硬边界，撕裂更规整
  2. 测地 Voronoi（多组种子）→ 布片判给手臂
  3. 凹折痕区域生长 + 区域级归属 → 无法分割（单区域）
- **结论**：这个问题**不能靠权重解决，只能靠几何**——即先做部件分割再逐件重拓扑
  （原本计划的 `03a 部件分割 → 02b 按部件重拓扑`）。
- **本版处置**：回退到"标准自动权重 + ≤4 影响 + 归一化 + 平滑"，
  布片整体跟手臂走（视觉上像大袖随臂动，**不撕裂**）。
  Lia 是 NPC，待机/行走/说话的手臂动作幅度小，日常表现不受影响。

### 5.2 其他

| # | 问题 | 归属阶段 |
| --- | --- | --- |
| a | 脸被重拓扑抹平、无面部循环边 | 高精度素材（重拓扑） |
| b | 手指并成手套 | 高精度素材（重拓扑） |
| c | 头发糊成大块，无发束分离 | 高精度素材 + 发骨 |
| d | 无 UV 排布优化（仅 Smart UV 占位）、无贴图 | PHASE 04/05 |
| e | 长马尾无独立骨，前屈时会穿过身体 | 发骨阶段 |
| f | 仅 Idle 一个动画；Walk / Talk 未做 | PHASE 09 |

---

## 6. 交付物

| 类型 | 路径 |
| --- | --- |
| 绑定源文件 | `assets_source/characters/lia/03_rig/LIA_v3h_final_idle.blend` |
| 无动画绑定版 | `.../03_rig/LIA_v3g_final.blend` |
| 导出 GLB | `assets_source/characters/lia/06_export/lia_v3.glb`（1.92 MB） |
| Godot 资产 | `godot/assets/characters/lia/lia_v3.glb` |
| Godot 测试场 | `godot/scenes/characters/LiaCharacterTest.tscn` |
| 测试场脚本 | `godot/scripts/characters/lia_character_test.gd` |
| 审核图 | `.../03_rig/LIA_V3_POSE_*.png`（12 姿势 × 3 视角）、`LIA_V3_GODOT_SHEET.png` |

**GLB 内容实测**（非声称）：

```
skins = 1      joints = 23     animations = 1 (Idle)      materials = 1
mesh attributes = JOINTS_0, WEIGHTS_0, POSITION, NORMAL, TEXCOORD_0
```

---

## 7. Godot 接入

项目用 `gl_compatibility`。测试场**不引用 GLB 的 .tscn**，而是运行时
`load("res://assets/characters/lia/lia_v3.glb")` —— 场景文件不会与资产漂移。

```bash
# 导入（新增/更新 GLB 后必须跑一次）
"/g/Godot/Godot_v4.4.1-stable_win64_console.exe" --path F:/SEKAI/godot --headless --import

# 出审核图（窗口模式，脚本自行 quit）
... --path F:/SEKAI/godot --resolution 1000x1100 \
    res://scenes/characters/LiaCharacterTest.tscn -- \
    --capture <out.png> --yaw 0.0 --pitch 0.06 --dist 3.0 [--skeleton]
```

运行时按键：`LMB` 环绕 / 滚轮缩放 / `SPACE` 骨架叠加 / `TAB` 切换动画 / `R` 复位。

**相机朝向**：Blender `-Y` 前方经 glTF Y-up 转换后为 Godot **`+Z`**。
所以 `--yaw 0.0`（相机在 +Z 侧）看到的是**正面**。

---

## 8. 工具（`tools/character/`）

| 脚本 | 作用 | 可逆 |
| --- | --- | --- |
| `lia_rig_build.py` | 生成 23 骨骨架 + 自动权重 + Smart UV + 占位材质 | 写新文件 |
| `lia_pose_test.py` | 12 组极限姿势 × 3 视角变形 QA 渲染 | 只读 |
| `lia_deform_probe.py` | **诊断**：摆姿势后找位移异常顶点及其权重来源 | 只读 |
| `lia_weight_cleanup.py` | 权重剥离 / ≤4 影响 / 归一化 / 平滑（读→改→清空重建） | 写新文件 |
| `lia_weight_region.py` | 凹折痕区域分割 + 测地 Voronoi 版清理（本版未采用，留档） | 写新文件 |
| `lia_anim_idle.py` | authored Idle 呼吸循环（5 s @ 24 fps） | 写新文件 |
| `lia_export_glb.py` | 导出 GLB + 二进制解析自检（断言 skin/joint/normal/材质） | 写新文件 |

---

## 9. 踩坑（下次直接用）

1. **`vertex_groups[i].remove()` 之后 `mesh.vertices[v].groups` 会返回旧缓存**。
   第一版清理脚本因此在 strip 后又把手臂权重原样写了回去，且**不报任何错**。
   正确做法：权重全部读进 Python dict → 处理 → `vertex_groups.clear()` → 重建。
2. **Blender 4.4+ 的 `Action` 没有 `.fcurves`**（slotted actions），
   fcurves 在 `action.layers[0].strips[0].channelbags[0].fcurves`。
   更稳的写法：不要自己 `actions.new()`，让 `keyframe_insert` 自动建 action 再改名。
3. **`use_auto_smooth` 在 Blender 4.1+ 已移除**，`shade_smooth()` 仍可用。
4. **QuadriFlow 默认 `use_mesh_symmetry=True` 必须关**——本角色发型/披风刻意不对称。
5. **QuadriFlow 后表面极度平滑**，凹折痕分割退化成单一区域，不要指望它做部件分割。
6. `d_arm`（到骨骼线段的距离）是做权重诊断最有效的单一指标；
   但**它无法区分"手臂"和"紧贴手臂的衣服"**——这是几何问题不是指标问题。
