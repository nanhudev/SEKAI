# SEKAI ART KIT PLAN

美术线权威规划。范围：模块化地编 Kit、道具家族（Asset Family）、UI 视觉体系。
根：`F:\SEKAI` · 分支：`godot-combat-mvp` · Godot 4.4.

职责边界：本文档只管**可复用美术资产与视觉语言**。不碰战斗逻辑、不碰音频、不写主线文案。

---

## ⚠️ 0. 优先级变更 —— MAP FIRST（ART PASS 02）

**先设计地方，再让资产服务地图。** 不得再「一个 brief → 一个模型 → 下一个」循环。

| 文档 | 角色 |
| --- | --- |
| `docs/LD-01-MISTVALE-REGION-MASTERPLAN.md` | **地方与坐标的权威**。资产 brief 必须引用它的 Zone / Landmark / Narrative ID |
| 本文档 | 资产命名、尺寸规范、Kit 家族、风格语言 |

当前顺序：

```text
LD-01 Masterplan (DESIGN LOCKED)
  ↓
GATE 1 灰盒 → 几何判据已机器实测 ✅ ／ 人工走查 ⬜
  ↓
GATE 2 Landmark → HERO-01 Guild V2 / HERO-02 Bell Tower
  ↓
GATE 3 Architecture → KIT-02 Town V2 / KIT-02a Stair
  ↓
GATE 4 Props + Narrative → PROP-01 / NAR-01~07
  ↓
GATE 5 Atmosphere
```

**ENV-01 降级**为 STRUCTURAL BASE KIT —— 它证明了「能拼」，但不代表最终品质。
**ENV-02 精模暂停（HOLD）**，等 GATE 1 通过后按 Masterplan §19 重写 brief。

本轮的素材配比：**80% 环境／关卡，15% 道具，5% UI 维护**。UI 不再扩张。

---

## 0. 五条 LAW

1. 优先模块化，不做一次性模型
2. 优先地编套件（Kit），不整张地图一次性雕
3. 优先道具家族（Asset Family），不做孤立单品
4. 优先游戏内可读性，不追求 Blender 单图好看
5. **Godot 里的效果才是最终验收**

判定阈值（做之前先问）：

- A 它是不是一个 Kit Piece？
- B 它能不能变成一个 Asset Family？
- C 它能不能实例化 5 次以上？

三个都否 → 慎做。

---

## 1. 尺寸标准（全项目统一，不得各写一套）

| 项 | 数值 |
| --- | --- |
| 基础网格 | **2.00 m** |
| 层高（story） | 3.20 m |
| 墙厚 | 0.30 m |
| 门洞 | 1.20 × 2.20 m |
| 窗洞 | 1.00 × 1.20 m |
| 台阶单级 | 踏面 0.50 m / 踢面 0.18 m |
| 栏杆高 | 1.05 m |
| 台基 / 露台高 | 0.30 m |
| 路缘石 | 0.16 m 高 × 0.30 m 宽 |
| 剑 / 手持物尺度 | C2B-01 已定，握把原点在 grip center |

原点规则：地编件原点在**地面投影中心**；台阶/坡道原点在**坡底、宽度中线**。所有件旋转 0、缩放 1，可按 90° 步进旋转拼接。

---

## 2. 命名规范

| 类别 | 规则 | 例 |
| --- | --- | --- |
| 地编件 | `ENV<NN>_<Piece>` | `ENV01_Terrace_4x4` |
| 道具 | `PROP<NN>_<Family>_<Variant>` | `PROP01_Crate_Medium` |
| 建筑 | `BLD_<Set>_<Part>` | `BLD_Guild_Facade_A` |
| 材质 | 区域前缀 | 雾谷 `MV_*`、通用道具 `PR_*` |
| Blender collection | `SEKAI_<ID>_KIT` | `SEKAI_ENV01_KIT` |

**导出策略：每件一个 GLB。** 理由：Godot 里每件落成单个 Mesh 资源，kitbash 时拖拽即用，实例化开销最低。

路径：

```text
assets_source/environment/mistvale/     # .blend + 生成脚本
assets_source/props/common/
assets_source/ui/
assets/models/environment/mistvale/     # 每件一个 GLB
godot/models/environment/mistvale/      # Godot 消费
```

---

## 3. 环境 Kit 名册

### ENV-01 · Mistvale Ground / Stair / Terrace Kit —— P0 · 12 件

当前状态：**SPEC READY**（brief 见 `docs/asset_briefs/ENV-01-MISTVALE-GROUND-KIT.md`）

台基 / 台阶 / 坡道 / 挡土墙 / 路缘 / 崖沿 / 桥面栏杆。2 m 网格，4 材质（`MV_Stone_Base` / `MV_Stone_Pale` / `MV_Timber_Dark` / `MV_Moss_Accent`）。

**这是整条地编线的地基**，也是 `arena_dressing.gd` 占位柱墙的正式替代物 —— 该脚本头部注释即声明「meant to be replaced wholesale by the ART line」。

### ENV-02 · Adventurer Guild Exterior Set —— P0 · 8 件

立面墙段 / 门庭 / 外梯 / 入口平台 / 屋檐 / 招牌位 / 窗 / 栏杆。只求「能拼出一个有气质的公会」，不追全套。

### ENV-03 · Town House Kit A —— P1 · 9 件

`wall_plain` / `wall_window` / `wall_door` / `beam` / `roof_slope` / `chimney` / `foundation` / `fence` / `sign`。

复用提示：`assets/models/mistvale/` 已有一版 12 件基础 Kit（2026-09-27 生成，**从未接入 Godot**）。ENV-03 应与它**合并而非重造**：先做一次一致性审计（尺寸、命名、材质、原点），能用的直接升级进管线，不能用的重做。

### ENV-04 · Town Market / Stall Kit —— P1 · 7 件

摊位台面 / 顶篷骨架 / 布幔挂点 / 货架 / 秤台 / 招牌 / 地面垫板。

### ENV-05 · Town Prop Set A —— P0 · 12 件

见 §4，本体是道具而非地编，独立成组便于在地编之外单独铺。

### 后续（Combat MVP 之后）

World Beacon、Mistvale 神殿/钟楼候选、镇口牌坊、周边自然过渡带。

---

## 4. 道具家族（Asset Family）

**不按单品开发，按家族开发。** 一个家族先出 3–5 个变体，靠变体覆盖场景，不靠数量。

| 家族 | 变体 | 优先级 |
| --- | --- | --- |
| Crate | small / medium / reinforced / open / stackable | P0 |
| Barrel | sealed / open / metal-banded / water | P0 |
| Furniture | stool / chair / table / shelf / bedside cabinet | P0 |
| Lighting | 灯柱 / 挂灯 / 提灯 | P0 |
| Boundary | 围栏 / 木栅 / 石栏 | P0 |
| Signage | 告示板 / 路牌 / 店铺招牌 | P0 |
| Market | 摊位架 / 货架 / 秤台 | P1 |
| Storage | 麻袋 / 书堆 / 武器架 | P1 |
| Greenery | 花盆 / 花箱 / 藤架 | P1 |
| Soft | 布幔 / 地毯 / 旗帜 | P2 |

实例化要求：每个高频道具必须支持**镜像、90° 旋转、±10% 尺寸变化、配色变体、堆叠、开合状态**。少量资产撑起场景，靠的是变体不是数量。

反例（明确不做）：细节复杂但几乎没人看的精致小件。优先级永远让给每天都能看见的高频物体。

---

## 5. Mistvale 地编结构

不允许「平地上摆房子」。必须建立高低差与视线引导：

```text
入口（低）
  ↓ 坡道 / 台阶
街道
  ↓
中央空间（广场平台）
  ↓ 石阶
公会高台（+3.2 m）
  ↓
住宅层（退回 +1.6 m）
  ↓
更高的地标（钟楼 / 神殿）
  ↓
通往野外 / 遗迹的出口
```

每个节点至少一处**上下结构**：桥、台阶、坡道、高台、挡墙、露台、观景点、高处建筑、低处巷道。

视觉气质：石基 + 木梁 + 浅色抹灰墙 + 深色木构 + 略深青灰屋面 + 少量暖色点缀。不随机配色。

生活痕迹：箱子不成排摆；摊位有开口方向；公会入口有供人停留的平台。

---

## 6. 材质与配色（雾谷区域）

| 材质 | Base Color | Metallic | Roughness | 用途 |
| --- | --- | --- | --- | --- |
| `MV_Stone_Base` | 0.42, 0.44, 0.47 | 0.0 | 0.85 | 台基 / 台阶 / 墙 / 路缘 |
| `MV_Stone_Pale` | 0.68, 0.64, 0.55 | 0.0 | 0.80 | 压顶 / 边条 / 铺装 |
| `MV_Timber_Dark` | 0.20, 0.15, 0.12 | 0.0 | 0.70 | 木构 / 桥面 / 栏杆 |
| `MV_Moss_Accent` | 0.32, 0.38, 0.30 | 0.0 | 0.90 | 少量石块变体 / 崖沿 |

风格：Stylized Next-Gen Fantasy。硬边平面着色，靠轮廓和体块读设计，不靠贴图噪点。**禁止** generic low-poly、mobile-toy、随机素材包拼盘。

---

## 7. Chat2Blender 执行规范

产线固定：

```text
WorkBuddy（写 brief）
  ↓
用户已登录的 ChatGPT 网页（GPT-5.6 Sol / 高强度推理）
  ↓  产出 # C2B:CHUNK ... # C2B:END 分块 bpy
Blender MCP（端口 9876，可见 Blender 5.1.2）
  ↓  执行 → 检查 → 修正
GLB 导出（每件一个）
  ↓
Godot 集成
  ↓
第一人称 / 场景内实机验收
```

工具：

| 工具 | 作用 |
| --- | --- |
| `assets/chat2blender/blender_mcp_client.py` | 直连 9876，执行代码 / 取场景信息 / 截图 |
| `assets/chat2blender/review_scene.py` | QA：逐对象报三角形 / 材质槽 / 尺寸 / 变换 |
| `assets/chat2blender/render_review.py` | 真实渲染检视图（不依赖视口，避开缓存帧） |
| `docs/asset_briefs/templates/C2B-ROLE.txt` | 可复用角色提示词 |
| `docs/asset_briefs/prompts/*.txt` | 实际发送的请求包 |

**已固化的三个硬约束（写进角色提示词，违反即静默失败）**：

1. 禁止按英文名查找着色器节点 —— 本机 Blender 界面是中文，Principled BSDF 实际名为「原理化 BSDF」，必须按 `node.type == 'BSDF_PRINCIPLED'` 查找（C2B-01 首轮四个材质全白就是踩了这个）
2. 禁止用裸 `if x:` 静默吞掉失败
3. 复杂资产必须分 chunk，每块独立可运行

迭代纪律：每件最多 2–3 次 major iteration。到 80% 可用先接 Godot，进游戏里看。脚本报错优先发回 ChatGPT 修（Fix Chunk），不自己大规模重写 bpy。

---

## 8. UI 视觉体系

独立文档：`docs/UI_STYLE_BOARD.md`。

要点：UI 不必都从 Blender 烘图。3D 走 Blender，2D UI 走矢量 / 程序绘制 / 图标。目标是建成 **UI Kit**（面板框、状态条、图标集、分隔线、轮盘环、牌匾），不是一屏一屏硬画死。

---

## 9. 状态表

| ID | 名称 | 优先级 | 状态 |
| --- | --- | --- | --- |
| ENV-01 | Mistvale Ground / Stair / Terrace Kit | P0 | IN GODOT（12 件 / 5,986 tris / 拼接验证通过） |
| ENV-02 | Adventurer Guild Exterior Set | P0 | REQUESTED |
| ENV-03 | Town House Kit A | P1 | REQUESTED（需与既有 mistvale kit 合并审计） |
| ENV-04 | Town Market / Stall Kit | P1 | REQUESTED |
| ENV-05 | Town Prop Set A | P0 | REQUESTED |
| UI-01 | UI Style Board + UI Kit V1 | P0 | DONE（5 件 SVG 已入 `godot/ui/kit_v1/`，场景接入待 MAIN） |
| UI-02 | 主菜单 V1 | P0 | REQUESTED |
| UI-03 | Ability Wheel V1 | P0 | REQUESTED |
| UI-04 | HUD Frame V1 + 状态条 | P0 | REQUESTED |

状态值：`REQUESTED` `SPEC READY` `GENERATING` `BLENDER RUN` `VISUAL REVIEW` `FIXING` `EXPORT READY` `IN GODOT` `IN-GAME VERIFIED`

---

## 10. 生产纪律

- 每轮只推进**一个** Kit Family 或**一个** UI 子系统。不混做。
- 大件完成立刻进 Godot，不长期停在 Blender。
- 不因「资源没全」而停 —— 先 Kit V1 / Prop V1 / UI V1 接进去，之后再 V2、V3。
- 冲突优先级：当前用户指令 > MAIN PROJECT > ART 实现细节。
