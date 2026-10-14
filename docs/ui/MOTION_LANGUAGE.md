# MOTION LANGUAGE

> UI PASS 01 · 实现层 = `ui_web/motion/motion.js`（唯一执行层）。
> 时长与缓动只来自 `tokens.css`，`motion.js` 里不写裸数字。

---

## 1. 只有四种语言

任何 UI 动效必须能归到这四类之一。归不进去的，就是没想清楚。

| | 名字 | 读作 | 实现 | 用在哪 |
| --- | --- | --- | --- | --- |
| **A** | **WRITE** | 线被**写**出来 | `stroke-dashoffset 1 → 0` | 品牌标记、标题字标、地点名、菜单焦点线、加载线 |
| **B** | **CONVERGE** | 元素向一点**聚合**（反向 `diverge`） | `translate + opacity` | 开发者入口、子项出现、技能就绪、选中项回收 |
| **C** | **UNFOLD** | 几何从中心/边缘**展开**（反向 `fold`） | `clip-path: inset()` | 按钮出现、能力轮盘展开、子菜单 |
| **D** | **DISSOLVE** | 退场是**擦除**，不是淡出 | `clip-path` 单向 wipe（＋可选 3px 位移） | 主菜单进游戏、Launcher 幕落 |

外加三种**环境循环**，只在背景层用，永远极慢：
`drift()`（雾/环/云，92s–128s 一圈）· `breathe()`（标题微浮，6.4s，幅度 2–3px）· `particles()`（上浮微尘，26–52s）。

### 为什么 UNFOLD 不用 scale

`scale` 会把描边一起放大 —— 1px 线变 2px，一眼假。
`clip-path: inset()` 是"窗口在开"，描边宽度恒定，读起来像纸在展开。

### 为什么 DISSOLVE 不用 fade

淡出是"消失"，擦除是"被抹掉"。后者才符合"世界正在被书写"。

---

## 2. 令牌

```
时长   --sk-t-instant 90ms   --sk-t-fast 140ms   --sk-t-base 240ms
       --sk-t-slow 480ms     --sk-t-crawl 800ms  --sk-t-write 1400ms
       --sk-t-drift 48000ms  --sk-t-breathe 6400ms
级联   --sk-stagger 62ms
缓动   --sk-e-out    cubic-bezier(.22,.61,.36,1)     通用出场
       --sk-e-in                                       通用入场
       --sk-e-io   cubic-bezier(.42,0,.58,1)           对称
       --sk-e-snap cubic-bezier(.16,.84,.24,1)         瞬时反馈（落在点上）
       --sk-e-write cubic-bezier(.33,0,.15,1)          书写：慢起 → 快走 → 收
       --sk-e-unfold cubic-bezier(.12,.72,.10,1)       展开：快起 → 缓停
       --sk-e-drift linear                             环境循环（避免接缝）
```

**区间是硬的**：`fast 100–160` / `normal 180–280` / `slow 400–800`（§29）。
超出区间的值必须说明理由。

---

## 3. 两条硬规则

### 3.1 UI 永远先响应（§30）

漂亮动画**不得**让 UI 变慢。点击/按键必须在 `--sk-t-instant` 内给出可见反馈，
即使完整转场还没结束。实现手段：

- 状态反馈（hover / focus / 按下）走 `stateAnim()` + CSS `transition`，**可打断、可反向**。
- 一次性演出（四语言）走 WAAPI，**不阻塞**输入。
- SKIP 立即跳到终态 —— 跳过的只是"过程"，信息在静态终态里全都在。

### 3.2 状态 ≠ 演出

| | 演出 | 状态 |
| --- | --- | --- |
| 例子 | 标记被写出来、菜单幕落 | 焦点线、hover 高亮、选中刻度 |
| 能否打断 | 不必 | **必须** |
| 实现 | `animate / write / converge / unfold / dissolve` | `stateAnim()` |
| 出片时 | 由 `_skOrigin` 决定属于时间轴哪一刻 | 由 `on()/off()` 触发，`seekAll` 按段求值 |

`stateAnim` 用一条建好的动画 + `playbackRate = ±1` 双向走，所以反向不会回弹。

---

## 4. 无障碍

`@media (prefers-reduced-motion: reduce)` 与 `:root[data-motion="reduce"]` 同时生效：
一次性演出**直达终态**（`applyFinal`，不是"播得很快"），环境循环不启动，
`--sk-stagger` 归零，粒子隐藏。

**信息不依赖动画可读** —— 这是架构级的，不是补丁。出片和截图会显式强制
`prefers-reduced-motion: no-preference`，以免评审看到降级版。

---

## 5. 出片契约（为什么必须走 WAAPI）

§37 要求"每个重要 UI 必须先录视频"。所以动效必须能**被逐帧推进**：

```
SKMotion.freezeAll()   所有动画归零到同一时间原点并暂停
SKMotion.seekAll(t)    把整页推到 t 毫秒
page.screenshot()      → frame_%05d.png
ffmpeg                 → *_preview.mp4
```

因此有两条代码纪律：

1. **不用 CSS `animation` 声明做一次性演出**，一律 WAAPI —— 只有 WAAPI 能
   可靠地 `pause()` + 设 `currentTime`。
2. **不用 `setTimeout` 排演出** —— 真实定时器对 `seekAll` 不可见，
   会让它在第一帧就"已经发生"。要用 `delay`。
   （`if (!RENDER)` 之外的 `setTimeout` 只允许用于 a11y 焦点这类不影响画面的东西。）

### `_skOrigin` / `adoptAt`

退出转场是在"玩家按下 ENTER WORLD 的那一刻"才创建的动画，它的 delay 是相对那一刻的。
若直接 `startTime = 0`，它会被错误地按"页面开始"计时。所以每个动画记一个
`_skOrigin`（它属于页面时间轴的第几毫秒），`seekAll(ms)` 时再换算成 `ms - _skOrigin`。
`adoptAt(origin)` 由 harness 在每次脚本化交互后调用。

### 出片模式开关

页面解析到 `?render=1` 时**必须在 boot 之前**调用 `SKMotion.setRenderMode(true)`。
否则 boot 期间触发的状态动画（例如"焦点落到第一项"）不会被挂到时间轴上 ——
**焦点线在验收视频里永远不会出现**，而那正是 WRITE 最常见的一处。

---

## 6. 已知坑（都踩过了）

| 坑 | 症状 | 处理 |
| --- | --- | --- |
| WAAPI `transform` 会**整体覆盖** CSS `transform` | 用 `transform: translate(-50%,-50%)` 定位的元素被动画甩到别处 | 用独立的 CSS `translate:` 属性定位 |
| 作者 CSS 的 `display` 覆盖 UA 的 `[hidden]` | 失败浮层 / DEV 徽标在 t=0 就出现 | reset 里加 `[hidden] { display: none !important }` |
| 用 alpha 令牌做**按钮内层底色** | 叠在金色描边上糊成实心金 = 手游 CTA | 用不透明的 `--sk-surface-*` |
| 水平线的渐变用默认 `objectBoundingBox` | bbox 高为 0 → 渐变退化 → **整条不画**（不报错） | 一律 `gradientUnits="userSpaceOnUse"` |
| `var()` 写进落盘的 .svg | 浏览器能吃（碰巧），`<img>`/ThorVG 不吃 → Godot 里没有这条线 | emitter 解析成字面值 |
| 1px 元素在缩图上"看不见" | 评审说"没有这条线"，其实有 | 验收一律用像素采样，不靠肉眼 |

---

## 7. 资产状态

`REQUESTED → SPEC READY → GENERATING → BLENDER RUN → VISUAL REVIEW → FIXING → EXPORT READY → IN GODOT → IN-GAME VERIFIED`

UI 线的 DONE 定义：**HTML 原型可交互 ＋ 已出片 ＋ Godot 侧可见且时序对齐**。
`IN GODOT` ≠ 完成。
