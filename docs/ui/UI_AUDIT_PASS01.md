# UI PASS 01 — 现状审计

日期：2026-09-27 · 分支 `godot-combat-mvp` · Godot 4.4.1
审计范围：MainMenu / PauseMenu / SettingsMenu / CombatHUD / Ability Wheel / UI Kit V1 / 启动链路 / 字体与主题

---

## 0. 一句话结论

**目前不存在任何"视觉层"。** 所有菜单是脚本里 `new()` 出来的 Godot 默认控件；已有的 UI Kit V1 五件 SVG 躺在 `godot/ui/kit_v1/` 且**零消费者**；没有任何字体资产；没有任何 Launcher 或启动演出。玩家双击游戏 → 立刻看到 Godot 默认 Button 组成的深色页面。

---

## 1. 菜单三件套 —— 纯功能占位

| 文件 | 行数 | 真实状态 |
| --- | --- | --- |
| `godot/scenes/ui/MainMenu.tscn` | 12 | 只有 root `Control` + 脚本，**无任何子节点** |
| `godot/scripts/systems/main_menu.gd` | 35 | `ColorRect` `#0b1b20` + `VBoxContainer` @ `(80,160)` + 3 个裸 `Button` |
| `godot/scenes/ui/PauseMenu.tscn` | 12 | 同上 |
| `godot/scripts/systems/pause_menu.gd` | 33 | `ColorRect` alpha 0.82 + 4 个裸 `Button` |
| `godot/scenes/ui/SettingsMenu.tscn` | 12 | 同上 |
| `godot/scripts/systems/settings_menu.gd` | 58 | 4 个裸 `HSlider`，默认值**硬编码在 `_ready()`**，无持久化 |

**证据**：三个 `.tscn` 均只有一行 `[node name=... type="Control"]`。全部视觉在 `_ready()` 里用代码 `new()` 出来，所以**没有任何可在编辑器里调整的视觉参数**。

### 具体缺失

- 无 Panel Frame、无 8px 斜切、无描边、无渐变底 —— 与 `UI_STYLE_BOARD.md` §4.1 完全不符
- 排版是 Godot 默认主题：默认字体、默认字号、默认按钮贴图风格
- 主菜单副标题写的是 **"COMBAT SANDBOX"** —— 开发占位文案直接暴露给玩家
- 按钮文案 "进入战斗沙盒" —— 同上
- 无背景视觉、无动效、无 focus 语言、无 hover 反馈设计
- **无 Reduced Motion 开关**（`UI_DIRECTION.md` §动效 已要求"减少动态效果设置"，但 Settings 只有 FOV/灵敏度/镜头运动/镜头震动）

---

## 2. CombatHUD —— 数值可读，视觉为零

`godot/scripts/combat/combat_hud.gd`（198 行）

| 项 | 现状 | 与 Style Board 的差距 |
| --- | --- | --- |
| 血条色 | `Color(0.75,0.27,0.25)` 硬编码 | 应为 Vermilion `#C0563F` |
| 蓝条色 | `Color(0.42,0.7,0.78)` | 应为 Jade `#6FAE9C` |
| 体力色 | `Color(0.7,0.73,0.45)` | 应为 Gamboge `#D8B45A` |
| 控件 | 3 × `ProgressBar` 默认外观 | 应为 SVG 轨道 + 斜切填充 + 延迟残影条 |
| 位置 | `VBoxContainer` @ bottom-left `(24,-120)` | 未定义安全区 / 未定义静止淡化与战斗强调规则（逻辑部分已在 `_process` 实现 `quiet` 淡化，可复用） |
| 状态文本 | `Label` 纯文字，无 panel | 未做信息层级 |

**可复用资产**：`quiet` 淡化逻辑、`iaido_presence` 衰减、`banner` 顶栏提示、`chain.message` 接入 —— 这些是**行为**，值得在 V2 保留，只换皮。

---

## 3. Ability Wheel —— 完全脱离色板

`godot/scripts/combat/radial_wheel.gd`（129 行）· 纯 `_draw()` 画布 280×280

| 项 | 现状 | 差距 |
| --- | --- | --- |
| 环 | `Color(0.8,0.9,0.95,0.75)` 白 2px | 应为 Ink Line `#2C3A44` **1px** |
| 中心盘 | `Color(0.03,0.07,0.09,0.96)` | 应为 Ink `#0E1418` + Gold 1px 环 |
| 扇区 | 元素色 alpha .30/.52/.85 纯色块 | 应为 Ink Soft 底 + 选中叠 Gold 0.18 |
| 刻度 | **无** | Style Board §4.3 要求分界处 12px 短刻度 |
| 指针 | 白 3px 线 + 白 6px 圆 | 应为 Gold 2px + Gold Bright 6px 圆 |
| 字体 | `get_theme_default_font()` | CJK 无字体资产 → **中文标签渲染为豆腐块** |
| 动效 | **零**。`visible = true/false` 硬切 | 需 UNFOLD 展开 / CONVERGE 收束 / DISSOLVE 退出 |

**结论**：Style Board 里唯一被写成完整规范的组件（§4.3），恰好是**实现得最不遵守规范**的一个 —— 现有代码早于 Style Board 写成。逻辑层（`entries` / `sector_angle` / `sector_of` / `set_direction`）设计良好且已被 6 个法术喂满，**保留逻辑，只重写 `_draw()` + 加动效**。

---

## 4. UI Kit V1 —— 文件在，接线不在

`godot/ui/kit_v1/` 5 件 SVG：`panel_frame` / `status_bars` / `ability_wheel` / `location_card` / `button_states`，均已导入为 `Texture2D`。

**但全仓库 grep `kit_v1` 的命中只在 docs 里。**
`docs/ASSET_MANIFEST.md` 自己写的是 `IN GODOT (files placed; scene integration pending)` —— 即**未接入**。

另外这 5 件是 **SVG 静态样式板（style board sheet）**，不是可复用组件：每件把多个状态画在一张画布上（如 `button_states.svg` 是 4 个状态并排、`ability_wheel.svg` 是整只轮盘），**无法直接当九宫格 / 九宫切片使用**。这是"画了一本规范书"而不是"造了一套零件"。

→ V2 需要的是**可切片、可改色、可换状态**的零件（见 `UI_DESIGN_SYSTEM.md` §7）。

---

## 5. 启动链路 —— 不存在

| 项 | 现状 |
| --- | --- |
| `project.godot` `run/main_scene` | `res://scenes/main/Main.tscn` |
| Main.tscn 结构 | `Main`(Node) → MainMenu / PauseMenu / SettingsMenu |
| BootScene / Splash | **不存在** |
| Launcher | **不存在** |
| 启动参数解析 | **不存在**（无 `OS.get_cmdline_user_args()` 调用） |
| `play-sekai.ps1` | 旧的 **Web/Three.js 原型**启动脚本（build vite + preview），与 Godot 无关 |

**玩家体验**：双击 → 直接看到菜单。零启动演出，零世界感。

---

## 6. 字体与主题 —— 最大的单点问题

- `find godot -iname "*.ttf" -o -iname "*.otf"` → **0 个命中**
- 无 `Theme` 资源（`*.tres` 里没有 theme）
- 无 `default_font` 覆盖
- 代码里出现的中文（"进入战斗沙盒" / "旅途暂歇" / "视野角度" / 法术名"寒流"）**全部走 Godot 默认字体**

Godot 4 默认字体不含 CJK 字形 → **这些字现在渲染为方框/空白**。

这是"为什么像原型"的最大原因，且**一条 `SystemFont` 就能修**（`font_names = ["Source Han Serif SC","Noto Serif SC","SimSun"]`，Windows 上免资产、免授权）。

---

## 7. 环境审计结论（供 Launcher 技术选型）

| 候选 | 本机状态 | 判定 |
| --- | --- | --- |
| Rust / Tauri | `cargo` / `rustc` **未安装** | ✗ 需装 ~1.5GB 工具链，违背"最轻" |
| Electron | 未安装，`npm i electron` ≈ 300MB 运行时 | ✗ 为一个启动器引入整个 Chromium |
| WebView2 运行时 | **已装** `153.0.4234.48` | ✓ 可直接复用系统 WebView |
| Edge / Chrome | 均已安装 | ✓ 作为 WebView2 / app-mode 后备 |
| Python | **3.13.14 已装** | ✓ |
| Node | **22.22.2 + npm 10.9.7** | ✓ |
| ffmpeg | **不在 PATH**（散落在剪映/格式工厂目录） | ⚠ 需显式指定路径或另装 |
| Godot | `G:\Godot\Godot_v4.4.1-stable_win64.exe` | ✓ 已有 |

**选型**：**Python + pywebview（内部走 WebView2）** —— 唯一"已全部就位"的组合，wrapper 约 200 行，无 300MB 运行时。启动器前端是纯 HTML/CSS/JS，符合 §26 的"轻量 Desktop Wrapper"要求。

---

## 8. 并行会话警告（执行本 PASS 时必须遵守）

审计时刻 `git status` 有 **40+ 个已修改文件**，且 `assets_source/review/` 在 150 秒内仍有新写入 —— **ART / AUDIO / COMBAT 会话正在活跃**。

本 PASS 的纪律：

1. **绝不 `git add -A`**。只提交本 PASS 新增 / 明确归属 UI 的文件。
2. **不碰** `radial_wheel.gd` + `combat_hud.gd` 的重写（COMBAT 会话正在改这两个），Ability Wheel V2 只出 **Web 原型 + 设计方案**，落到 Godot 等 COMBAT 线确认空闲。
3. **不碰** `IaidoTuning.tres` / `audio/` / `assets/` / 战斗脚本。
4. `main_flow.gd` 只做**追加式**改动（新增 boot 参数读取），不改既有信号契约。
5. 新增 `class_name` 后需跑一次 `--editor --quit` 注册，**跑之前先确认无人正在 import**。

---

## 9. PASS 01 的范围裁决

| 项 | 本 PASS 做 | 理由 |
| --- | --- | --- |
| Launcher（Web + 桌面 wrapper） | ✅ 完整可运行 | P0，全项目缺失 |
| Startup Motion | ✅ | P0 |
| Loading Presentation | ✅ | P0 |
| Dynamic Main Menu（Web） | ✅ 完整交互 | P0 |
| UI Design Tokens | ✅ | 是后面所有东西的地基 |
| Motion Kit（4 语言） | ✅ | 是 SVG 动效的执行层 |
| Godot Main Menu V2 + BootSplash | ✅ | 让 Godot 侧不再"像原型" |
| Godot 字体修复 | ✅（`SystemFont`） | 单点收益最大 |
| Ability Wheel Motion V2 | ⚠️ 只出 Web 原型 + 规范 | COMBAT 线正占用该文件 |
| HUD 重做 | ⏸ 不做 | §J：先立语言，HUD 复用 |
| Pause / Settings 重做 | ⏸ 不做（继承 tokens） | 本轮 P0 是 Launcher + Menu |
