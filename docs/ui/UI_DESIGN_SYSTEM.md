# UI DESIGN SYSTEM

> UI PASS 01 · 单一真相源 = `ui_web/tokens/tokens.css`。
> 这份文档是**索引**，不是复制品。数值以 tokens.css 为准；这里解释**为什么**。

---

## 1. 一句话

**"世界正在被书写。"**
UI 是浮在世界之上的一层字迹 —— 它存在，但从不遮住世界。
（呼应 `UI_DIRECTION.md` / `UI_STYLE_BOARD.md`，两文仍是权威视觉意图。）

风格坐标：Fantasy Clean UI ＋ 东方手稿的留白 ＋ 现代信息设计。
关键词：**安静 · 优雅 · 精确 · 古旧 · 通透 · 未完成**

---

## 2. 颜色

深色底、暖白字、去饱和灰蓝次级、**克制的浅金重音**。

| 组 | 令牌 | 值 | 用途 |
| --- | --- | --- | --- |
| 墨 | `--sk-void` | `#060A10` | 世界底色。也是 Launcher↔Godot 交接帧的**唯一**颜色 |
| | `--sk-ink` / `--sk-ink-soft` / `--sk-ink-raise` | `#0E1418` / `#16202A` / `#1D2933` | 面板层级 |
| 线 | `--sk-line` | `#2C3A44` | Ink Line，1px，结构与分组 |
| | `--sk-line-soft` / `--sk-line-faint` | | 更弱的层级 |
| 字 | `--sk-text` | `#EDE4D3` | 暖白，主文字 |
| | `--sk-text-2` / `3` / `4` | `#B8AE9C` / `#7E8B95` / `#4A555E` | 次级 / 元信息 / 幽灵 |
| 金 | `--sk-gold` | `#C9A65C` | **重音，只做小面积** |
| | `--sk-gold-bright` | `#E8CE8C` | 焦点态文字 |
| 生命 | `--sk-hp` `#C0563F` · `--sk-mp` `#6FAE9C` · `--sk-sp` `#D8B45A` | | 参考 `combat_hud` 现行色的**语义名**，非当前实现 |
| 元素 | `--sk-fire` `#D4763F` · `--sk-frost` `#7FA8C9` · `--sk-gale` `#8FBFA6` | | 元素图标语法 |

### 金色预算（硬性）

**金 ≤ 单个屏幕面积的 8%，且永远不做大面积填充。**

一个选中菜单行已经有 3 处金：中文名、左侧刻度、焦点线。**副行不再给金。**
（这条是实测出来的：四金同行会让整行读成"刷了金漆"。）

---

## 3. 字体

| 角色 | 令牌 | 栈 |
| --- | --- | --- |
| 衬线（标题/品牌/地点） | `--sk-font-serif` | Source Han Serif SC → Noto Serif SC → Songti SC → SimSun → serif |
| 无衬线（正文/按钮） | `--sk-font-sans` | Inter → Noto Sans SC → … → system-ui |
| 数字/英文元信息 | `--sk-font-num` | Inter → Roboto → ui-monospace（**必须 tabular**） |

字号全部 `clamp(px, Nvmin, px)`，**以 900px 高为基准**。这是分辨率无关的写法，
不是响应式的补丁 —— 1440p 和 1080p 下标题与留白的比例必须一致。

字距令牌：`--sk-track-mega 0.42em` → `--sk-track-wide 0.26em` → `--sk-track-title 0.10em` → `--sk-track-body 0.015em`。
宽字距是本设计的主要"呼吸"手段，**不要用加大字号来代替它**。

> ⚠️ **Godot 侧目前没有任何字体资产** —— 所有中文都会渲染成豆腐块。
> 修法见 `LAUNCHER_SPEC.md` §Godot 字体。这是 UI PASS 01 里优先级最高的一条。

---

## 4. 形体

- **单一倒角母题**：`--sk-chamfer: 8px`，`clip-path: polygon(...)` 切四角（`--sk-chamfer-lg: 14px` 用于大面板）。全 UI 只用这一种切角。
- 圆角半径 `--sk-radius: 2px` —— 近乎直角。**不做大圆角卡片。**
- 描边：`--sk-stroke-hair: 1px`。所有 SVG 几何带 `vector-effect="non-scaling-stroke"`。
- 间距阶：`--sk-s1 4px` … `--sk-s10 144px`。版心 `--sk-gutter: clamp(32px, 5.2vmin, 96px)`。
- **12 栅**是 Launcher 与 Main Menu 的共用骨架。品牌落 3–8 / 3–9 列，菜单落 3–5 列。**左对齐，不居中堆叠。**

---

## 5. 四条验收问题

出自 `UI_STYLE_BOARD.md`，此处保留 —— **D 拥有否决权**：

| | 问题 | 不通过的样子 |
| --- | --- | --- |
| A | 它像 SEKAI，还是像某个通用 RPG 模板？ | 换个 logo 就能当别的游戏 |
| B | 它读起来是"世界之外"，还是"又一个暗色 UI"？ | 只有深灰和金色 |
| C | 它是安静的，还是需要用户去注意它？ | 光晕、跳动、发光边框 |
| D | **它挡不挡战斗阅读？** | **HUD/特效打架 —— 一票否决** |

---

## 6. 明令禁止

写作 UI 时**不得**出现：

- 大圆角卡片 · 全站 glassmorphism · 巨大 CTA 按钮 · SaaS 渐变 · landing page 分区
- 通用 `hover: scale(1.0 → 1.1)`
- 手游感：一排按钮 · 红点 · 多货币条 · 夸张奖励特效
- 金色外框的"经典 RPG"框 · 卷轴 UI · 科幻 HUD

详见 BRIEF §46–47。**用 HTML/CSS/JS 做，也必须读起来是游戏 UI，不是作品集网站。**

---

## 7. 代码结构

```
ui_web/
  tokens/        tokens.css（唯一真相源） · tokens.js（读 computed style，禁止复制色表）
  motion/        motion.js（四种运动语言的唯一执行层） · motion.css
  components/    components.css（按钮/菜单行/光标/面板） · scene.css+scene_bg.js（世界层）
                 mark_motion.js · cursor.js · ui_cue.js
  svg/           library.js（10 个矢量组件，被页面内联 + 被 emitter 落盘）
  launcher/ main_menu/ ability_wheel/
  previews/      *_preview.mp4（动效验收物，§L）
  tools/         render.mjs（确定性出片） · emit_svg.mjs · gallery.html · mark_study*.html
assets_source/ui/  由 emit_svg.mjs 生成，给 ART 和 Godot 用
```

**JS 绝不复制颜色/时长表** —— 一律 `SKTokens.get('--sk-x')` 读 computed style。
两边分头维护的话一定会漂移。

音效不归 UI 线产（§45）。UI 只广播契约事件，AUDIO 线来接：

```js
window.dispatchEvent(new CustomEvent('sekai:ui', { detail: { cue, id, source } }))
// cue ∈ hover | focus | confirm | back | deny | startup | ready | start
```
