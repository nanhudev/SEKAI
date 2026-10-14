# Chat2Blender · 2026-09-24

第一批资产：Mistvale Modular Building Kit。

1. 网页端 ChatGPT 新会话选择 GPT-5.6 Sol。提交模块清单、米制尺寸、观察距离、碰撞、动画、材质、LOD、GLB 与预算要求。
2. GPT 输出 `assets/chat2blender/mistvale_kit_blockout.py`。在可见 Blender 5.2.2 LTS 运行，12 个独立对象、600 tris；截图检查发现形体过平且灰色材质显示不足。
3. 将截图观察描述送回同一 GPT 会话。它输出 `assets/chat2blender/mistvale_kit_details.py`。再次在 Blender 运行，12 个对象、1,946 tris，木框、窗棂与屋面层次可见。
4. GPT 输出 `assets/chat2blender/mistvale_kit_export.py`。在 Blender 中导出 12 个独立 GLB 到 `assets/models/mistvale/`，保留 Blender 工作视图中模块的摆放位置。
5. `src/buildingKit.ts` 用全部 12 种模块组合村庄入口附近一栋民居。浏览器内第一人称可见验收通过：门窗、屋顶、木构和围栏比例可读，构建通过。原民居的程序化盒体已替换，仍保留简化碰撞。

剩余工作：将这套模块逐步应用到其他建筑，并制作训练场、铁匠铺、药屋等独立道具组。不可直接由开发 Agent 编写复杂 `bpy` 建模代码；规则见 `docs/AGENT_CONSTITUTION.md`。

## Chat2Blender · 2026-09-27 · Producer 接管

Producer / Integration 角色建立后，Chat2Blender 产线从"单个资产尝试"升级为持续生产管线。

本轮产出（未执行 Blender，仅完成请求侧准备）：

1. C2B-01 First Person Sword — brief 此前已完成，本次补 `docs/asset_briefs/C2B-01-CHATGPT-PROMPT.md`，内含可直接粘贴的角色设定首句与完整 Asset Brief。
2. C2B-02 FP Hand / Forearm — 新 brief。四姿态变体（Sword / Block / Cast / Iaido）作为同一文件内的独立对象，绕开 Rig 阻塞。
3. C2B-03 Lesser Ruin Sentinel — 新 brief。明确无 Rig，拆件 Node 动画；三种攻击的 telegraph 姿态要求。
4. C2B-04 Magic Catalyst — 新 brief。明确禁止传统大法杖，不得遮挡 MagicCircle3D。

执行顺序与状态以 `docs/PRODUCTION_BOARD.md` 为准。

本轮未执行原因：Blender MCP 未连接本会话，ChatGPT Web 需用户登录态。产线规则不变：SEKAI Agent 不编写 Blender 建模代码，只写 brief、执行脚本、导出、接入、验收。

## Chat2Blender · 2026-09-27 · C2B-01 FP Sword 首轮实跑

产线首次完整跑通，人工只做了一次 ChatGPT 登录。

1. 环境打通：Blender MCP 走 9876 裸 socket 直连（`assets/chat2blender/blender_mcp_client.py`）；ChatGPT Web 走 CDP + playwright-core（`F:\tools\chatgpt_bridge.js`）。模型 GPT-5.6 Sol，思考强度「高」。
2. 在 ChatGPT 新会话（"Blender Code Generation"）依次发送：角色设定 → C2B-01 brief → blockout 运行报告。
3. **blockout**：392 行，一次跑通。Blade 152 tris / Guard 188 / Grip 188 / Pommel 188，四个 attachment 空物体齐全，origin 在 grip center，blade 沿 +Y。几何一次到位。
4. **发现缺陷并回传 ChatGPT 修复**：`nodes.get("Principled BSDF")` 在中文界面 Blender 下返回 None（节点实名「原理化 BSDF」），`if bsdf:` 静默跳过，导致四个材质全部渲染为纯白。修复版改为按 `node.type == 'BSDF_PRINCIPLED'` 查找，并对输入插槽做 identifier + 本地化名双匹配。
5. **details**：757 行，一次跑通。Blade 重做为带中脊的网格（124 tris），Guard 增加前掠并新增 `Guard_Motif` 纹样对象（72 tris），其余对象名、empty 名与父子层级全部保持不变。
6. 导出：`.blend` 126 KB → `assets_source/weapons/fp_sword.blend`；GLB 51 KB → `assets/models/weapons/fp_sword.glb`，并复制到 `godot/models/weapons/`。

总计 832 tris，远低于 12k 预算。两次 ChatGPT 往返，零次人工改脚本。

### 工程经验（后续资产直接复用）

- ChatGPT 代码块**不能靠 DOM 抓取**：该版本 ChatGPT 用虚拟滚动 + Codex 语法高亮 span（无 `<pre>`），长代码块只渲染视口内片段，任何单次读取都是残缺的。可靠做法是点击代码块自带的「复制」按钮，再用系统剪贴板取值。
- 判定生成完成不能用「思考摘要消失」，必须要求正文长度连续两次轮询不变。
- MCP 的 `get_viewport_screenshot` 会返回缓存帧，视口改变后截图不更新；验收图改用真实渲染（`assets/chat2blender/render_review.py`）。
- 所有 `127.0.0.1` 请求会被代理拦成 502，Python 需 `ProxyHandler({})`，Node 需 `NO_PROXY`。

---

## ENV-01 Mistvale Ground / Stair / Terrace Kit（12 件）

**产物**：`assets_source/environment/mistvale/env01_ground_kit.blend`（145 KB）· `assets/models/environment/mistvale/ENV01_*.glb` × 12 · 12 件共 **5,986 tris**（预算 30k，最重的 `RetainingWall_Corner` 2,068）

| 件 | 尺寸 (m) | tris |
| --- | --- | ---: |
| Terrace_8x8 | 8.00 × 8.00 × 0.30 | 396 |
| Terrace_4x4 | 4.00 × 4.00 × 0.30 | 352 |
| Terrace_StepEdge_4 | 4.00 × 0.60 × 0.30 | 132 |
| Stair_Straight_4 | 4.00 × 2.00 × 1.44 | 572 |
| Stair_Landing_2x2 | 2.00 × 2.00 × 0.30 | 132 |
| Ramp_4x2 | 4.00 × 2.00 × 0.90 | 90 |
| RetainingWall_4x1p5 | 4.00 × 0.45 × 1.50 | 1,012 |
| RetainingWall_Corner | 4.00 × 4.00 × 1.50 | 2,068 |
| Curb_4 | 4.00 × 0.30 × 0.16 | 44 |
| CliffEdge_4 | 4.00 × 1.00 × 1.19 | 264 |
| BridgeDeck_4 | 4.00 × 2.00 × 0.35 | 528 |
| BridgeRail_4 | 4.00 × 0.15 × 1.05 | 396 |

全部 loc=(0,0,0) / rot=0 / scale=1，每件 4 个材质槽（`MV_Stone_Base` / `MV_Stone_Pale` / `MV_Timber_Dark` / `MV_Moss_Accent`）。12 件尺寸与 brief 逐项吻合，无偏差。

**分块执行**：`kit_common`（集合 + 4 材质 + 共享 helper）→ `terraces`(5) → `stairs_ramps`(2) → `walls_edges`(3) → `bridge`(2)。脚本在 `assets/chat2blender/env01_ground_kit/final/`。

**ChatGPT 往返 3 次**：
1. 首次发角色 + brief（5911 字符，5.6 Sol，强度高，199 秒）→ 5 个 chunk 全出，但**抽取失败**。
2. 要求「每 chunk 整体套一个 fenced code block」重发 → 拿到 4 个完整 chunk；`kit_common` 因「代码没变」被省略。
3. 单独索要 `kit_common` → 301 行完整拿到。

**本轮新增的硬经验（比 C2B-01 更关键）**：

- **`# C2B:CHUNK` 标记绝不能裸露在 fence 外面**。裸写会被 ChatGPT 当 markdown 标题渲染成 `<h1>`，下面的代码随即被**打散成 25 个互不相连的片段**，且每个函数的**定义行全部丢失**，无法拼接。原句已写进 `templates/C2B-ROLE.txt`：一个 chunk = 一个 fence，标记放 fence 内首尾。
- **三种抽取渠道，只有一种可信**：
  - `innerText` → 吃掉缩进（Python 致命）
  - 全选 + Ctrl+C 剪贴板 → **同样吃掉缩进**
  - ✅ `<code class="whitespace-pre! ... CodeContent-*">` 的 **`textContent`** → 缩进完整。工具：`blender_mcp_client` 之外新增 `chatgpt_bridge.js save-code-blocks <dir>`。
- 新版 ChatGPT 的 assistant 消息**没有 `data-message-author-role` 属性**，也没有 `<pre>`，只能靠 `code[class*="CodeContent"]` 定位。
- 生成完成判定：必须同时满足「无 正在回应/正在思考/停止生成」且正文长度连续 3 次不变（`wait-gen`）。旧的 `wait-done` 会在**回答还没开始流式输出时**就误判完成。
- 模型会按「每 chunk 自包含」处理：即便要求了分块，每块仍自带 MAT_SPECS 与私有 helper（`_env01_mat` / `_sr_mat` / `_we_box` / `_br_mat`），只依赖 `kit_common` 提供集合与材质。抽查确认材质查找是 `n.type == 'BSDF_PRINCIPLED'` —— **C2B-01 那个本地化坑的修复被跨轮继承下来了**。

**验收状态**：`assets_source/review/env01_kit_grid.png`（12 件轮廓）+ `env01_kit_assembly.png`（拼接演示）。拼接演示含 8×8 广场 + 4×4 台基 + 2×2 平台 + 路缘 + 坐凳边条 + **旋转 90° 的挡土墙** + 桥面栏杆，全部齐平对接 —— 「能不能拼」这条 LAW 通过。

**已知待改（V2，不阻塞）**：`CliffEdge_4` 在网格图里只读出 3 个团块，brief 要的是 5–7 个碎块形成的「破碎崖沿」；当前更像散石堆。进 Godot 后可再修一次。

**Producer 侧新增工具**：`scene_reset.py`（清场）、`export_kit.py`（每件一个 GLB + 清 review 对象 + 归位原点）、`render_kit.py`（网格 + 拼接两视图，渲完自动归位原点）。
