# LAUNCHER SPEC

> UI PASS 01 · 实现 = `ui_web/launcher/` ＋ `ui_web/host/` ＋ `launcher_host.py`。
> 时序真相源 = `ui_web/launcher/launcher.config.js`（`SEQUENCE` / `LOADING` / `COPY` / `HANDOFF`）。
> Godot 侧读本文的同一张表。

---

## 1. 流程

```
黑 → 一记脉动 → 标记（环＋点）被写出来 → 细几何 / 刻度线成形
   → 背景开始动 → 标题逐字写出 → 金色短线 → 副标题字距 settle
   → 加载表现（环境循环）→ 门开 → 幕落 → 交接帧 → Godot BootSplash
```

**随时可 SKIP**，SKIP 跳到 `resolved`。
不是传统 MMO 登录页：没有账号框、没有服务器列表、没有公告轮播。

---

## 2. 时间表（ms，从页面出现算起）

### 首次启动 `full`

| beat | at | 内容 |
| --- | --- | --- |
| `pulse` | 180 | 笔尖落到纸上（560ms，向下坠） |
| `dot` | 300 | 点落下（420ms，`scale .2→1.35→1`，`e-snap`） |
| `markArc` | 460 | 环开始绕着点被写出（1400ms，`e-write`） |
| `runes` | 1250 | 细几何 / 刻度线依次成形（每件 900ms） |
| `bgMove` | 1500 | 背景开始动（1800ms 淡入，之后进入 drift） |
| `wordmark` | 1900 | `SEKAI` 逐字写出（每字 420ms，级联 70ms） |
| `wordmarkCN` | 2480 | `世界之外`（520ms） |
| `rule` | 2640 | 金色渐变短线（620ms，64px） |
| `subtitle` | 2880 | `BEYOND THE WRITTEN FATE`：字距 `0.52em → 0.26em` settle（700ms） |
| `loading` | 3150 | 加载环与加载线浮出（600ms），开始环境循环 |
| **`resolved`** | **3500** | **标题完全成立。演出安全点 —— 门最早在这里开。** |
| `skipHint` | 1150 | SKIP 提示浮出（克制，右下） |

### 后续启动 `fast`

同一支舞，压缩到 ~1.0s，**去掉细几何**。
`pulse 50 · dot 90 · markArc 140 · wordmark 400 · cn 610 · rule 700 · subtitle 780 · loading 860 · resolved 960`。

不是"跳过动画"，是"记得这段舞所以走快板"。判定用 `localStorage['sekai.launcher.seen.v1']`。

---

## 3. 加载表现（§7 的核心）

**禁止假加载。`sleep(5)` 一律不许。**

- **不显示百分比**。任何时刻都不出现 `72%` 这种东西。
- 真实进度可得时，它影响的是**线写到哪 / 环画到哪 / 字形密度**，
  而不是数字。`SKLauncher.setProgress(p)` 直接设 `translateX(-100+p*100)%` 与 `stroke-dasharray p`。
- 进度不可得时，进入**环境循环**：线一笔一笔反复写（1500ms 一笔 + 340ms 停顿），环缓慢自转（24s 一圈）。
- **最小呈现时间**：`resolved` 是"标题成立"的时刻，不是"游戏就绪"的时刻。
  门在 `max(resolved, ready)` 打开。`ready` 更晚时环境层继续循环，**不会卡住**。
- 超过 `beats.loading + 6000ms` 仍未就绪 → 文案换成"世界仍在成形 / STILL FORMING"。
  **仍然不显示假进度。**

---

## 4. HANDOFF —— Launcher 最后一帧 ≡ Godot BootSplash 第一帧

这是"一个连续启动过程"能被验收的**唯一依据**。两侧逐项对齐。

| 项 | 值 |
| --- | --- |
| 背景 | 纯色 `#060A10`（`--sk-void`）。**无渐变、无雾、无粒子、无 vignette** |
| 标记方框边长 | `min(视口宽, 高) × 8%`（= `8vmin`） |
| 标记中心 | 屏幕正中 `(50%, 50%)` |
| 几何（viewBox 空间，方框 128×128） | 环：半径 40，`M 63.30 24.01 A 40 40 0 1 0 100.25 47.09`；从 91° 逆时针扫 294° 到 25°，**缺口 58° 落在右上** |
| 点 | `cx 64 cy 64 r 5`（信标 / 观察者） |
| 交接时进度 | 环 `arcProgress = 1`（已写完）、点 `dotProgress = 1` |
| 颜色 | 环 `#EDE4D3`（暖白）；点 `#C9A65C`（金） |
| 线宽 | 环 **1.6px 屏幕像素**（`non-scaling-stroke`，不随方框缩放） |
| 点半径换算 | 方框 8vmin 于 900px 高 = 72px，缩放比 72/128 = 0.5625 → 点半径 ≈ **2.81px** |
| 保持 | 交接画面停留 `holdMs = 320` |
| 退出转场总时长 | `exitMs = 1200`（标记移向正中：delay 260 + 760ms 位移） |

**验收方式（已实测通过）**：两侧最后一帧采样，四角与左右侧翼必须都是 `(6,10,16)`，
最亮像素必须是 `(201,166,92)` 且落在 `(800,450)`。Launcher 与 Main Menu 两端均已满足。

---

## 5. 宿主接口（`launcher_host.py`）

轻量桌面外壳 = **pywebview + 已装好的 WebView2**。
（已审计：Rust/cargo 未安装 → Tauri 出局；Electron ~300MB；WebView2 153.0.4234.48 已在。）

页面**只**通过 `SKHost` 说话，不直接碰 pywebview：

| 方法 | 语义 |
| --- | --- |
| `preflight()` | Godot 可执行文件与工程目录是否存在。Launcher 唯一需要的 ready 来源 |
| `launch(targetId)` | 启动游戏。**永不抛** —— 失败返回 `{ ok: false, error, detail }` |
| `quit()` | 关闭 Launcher（先关窗再拉起 Godot） |

宿主在启动时生成 `./.host.json`，页面读取它：

```json
{
  "mode": "native",
  "version": "…", "build": "…",
  "devMode": true,
  "godot": "G:\\Godot\\Godot_v4.4.1-stable_win64.exe",
  "project": "F:\\SEKAI\\godot",
  "save": { "exists": true, "location": "雾栖镇", "locationEn": "MISTVALE" },
  "targets": [ { "id": "main", "label": "进入世界", "primary": true }, … ]
}
```

取不到 `.host.json` 就退回内建默认值，**所以纯静态服务器上也能跑原型**。
注意：**只有 native 模式才去取 `.host.json`** —— 浏览器里它根本不存在，
无脑 fetch 会让每次打开原型都在控制台留一条 404，掩盖真正的错误。

### 启动目标

| id | 正式玩家可见 | 说明 |
| --- | --- | --- |
| `main` | ✅ | 唯一的"进入世界 / ENTER WORLD" |
| `training` | ❌ dev | 训练场 |
| `mistvale` | ❌ dev | 雾谷实机检视 |
| `combat` | ❌ dev | 战斗沙盒 |

Dev 入口在 UI 上是**内联文字链接**，不是按钮（不与主 CTA 竞争视觉）。`devMode=false` 时整体不渲染。

---

## 6. 失败处理（§44）

**Launcher 绝不允许死在无限 loading。**

- `preflight()` 失败 → 不进入 loading 循环，直接给克制的失败态：
  `无法进入世界。` / `Unable to enter world.`
- 启动失败 → 同一套失败态 ＋ `重试` / `退出`。
- **错误详情只在 Developer Mode 显示**（`#failDetail`）。正式玩家看到的是干净的两行。
- 文案克制：不出现感叹号、不出现"请联系客服"。

---

## 7. Godot 侧（TASK 6 / 7）

### 7.1 字体（**最高优先级**）

工程内**没有任何字体资产**（无 `.ttf/.otf`、无 `Theme`、无 `default_font` 覆盖），
所以所有中文都是豆腐块。

最省成本且无授权成本的修法：一个 `Theme` + `SystemFont`，`font_names` 依序回退：

```
["Source Han Serif SC", "Noto Serif SC", "Songti SC", "SimSun"]   # 衬线（标题/地点）
["Inter", "Noto Sans SC", "Microsoft YaHei"]                       # 无衬线（正文）
```

### 7.2 BootScene

`run/main_scene` 目前是 `res://scenes/main/Main.tscn`，**没有 BootScene、没有命令行参数解析**。
需要：

1. 新增 `BootScene`：从 `HANDOFF` 那一帧开始（纯 `#060A10` + 正中标记），
   然后按 §2 的时间表放演出，最后切到 MainMenu。
2. `main_flow.gd` 增加 `OS.get_cmdline_user_args()` 解析（**只做加法** ——
   combat 相关脚本归并行会话，不要动）。
   约定参数：`--target=main|training|mistvale|combat`。
3. 保留 `main_flow.gd` 现有信号契约：
   `start_pressed` / `settings_pressed` / `exit_pressed` / `resume_pressed` /
   `title_pressed` / `back_pressed` ＋ 四条滑条。**不要改这些名字。**

### 7.3 落地方式

选 **A：在 Godot 里重建受 SVG 启发的 UI**（不是 WebView 桥）。
理由：本项目 UI 是 12 栅 + 矢量 + 简单变换，用 Godot 的 `Control` + `Line2D` /
`Polygon2D` / `_draw()` 足够；引入 WebView 运行时层会换来一个不稳定的依赖，
而原型好不好看并不是引入它的理由（§M 明说）。

`assets_source/ui/*.svg` 可被 Godot 直接 import 成 `Texture2D`，
所以"网页里的图标和 Godot 里的图标不一样"从流程上被消除了。

---

## 8. 当前状态

| 项 | 状态 |
| --- | --- |
| Launcher HTML 原型（可交互） | ✅ 已跑通、已出片 `ui_web/previews/launcher_preview.mp4` |
| 启动动效 / 加载表现 | ✅ |
| 动态主菜单 HTML | ✅ 已出片 `ui_web/previews/main_menu_preview.mp4` |
| HANDOFF 交接帧 | ✅ 两端实测一致 |
| SVG 组件库 ＋ 落盘 | ✅ 10 件 → `assets_source/ui/` |
| `launcher_host.py` | ⏳ |
| Godot BootScene / 参数解析 | ⏳ |
| Godot 主菜单 V2 / 字体修复 | ⏳ |
| Ability Wheel V2 | ⏳ 仅出 web 原型 ＋ spec（`radial_wheel.gd` 归 COMBAT 线） |
