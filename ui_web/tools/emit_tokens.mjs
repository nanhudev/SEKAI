#!/usr/bin/env node
/* ============================================================================
   SEKAI · TOKEN / TIMELINE EMITTER
   ----------------------------------------------------------------------------
   生成 `godot/scripts/ui/ui_tokens.gd`。

   解决的问题有**两个**，而且第二个比第一个重要：

   1. 颜色/间距/时长。html 侧的唯一真相源是 tokens.css，Godot 侧没有对应物。
      如果不生成，就只能手抄一份 —— 而手抄的表一定会漂移。

   2. **交接合同与时序。** HANDOFF（Launcher 最后一帧 ≡ BootSplash 第一帧）
      和 BOOT_SEQ（开场时序）、MENU_SEQ（主菜单进场时序）本来就是"两侧必须
      逐项对上"的东西。让 Godot 从 launcher.config.js / main_menu.config.js
      **直接读出来**，比让 Godot 侧照着文档抄一遍强得多：抄错了没人会发现，
      "生成的"不可能抄错。

      这也是为什么 main_menu 的时序被单独拆进 main_menu.config.js ——
      那个文件没有副作用，Node 可以直接 import；main_menu.js 会调 main()，
      import 它等于在 Node 里跑一遍页面。

   所以它 import 真正的 JS 模块，而不是用正则扒文本 —— 值就是值本身。

   用法：
     node emit_tokens.mjs                 # 写到 godot/scripts/ui/ui_tokens.gd
     node emit_tokens.mjs --check         # 只报差异（CI / 提交前）
     node emit_tokens.mjs --out <file>
   ========================================================================= */

import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const UI_ROOT = path.resolve(HERE, '..');
const REPO = path.resolve(UI_ROOT, '..');

const argv = process.argv.slice(2);
function arg(name, fallback = null) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}
const CHECK = argv.includes('--check');
const OUT = path.resolve(
  arg('out', path.join(REPO, 'godot', 'scripts', 'ui', 'ui_tokens.gd'))
);

/* ---------------------------------------------------------------------------
   1. 读 tokens.css
   ------------------------------------------------------------------------ */
const CSS = await fsp.readFile(path.join(UI_ROOT, 'tokens', 'tokens.css'), 'utf8');

/** 只取 `:root { ... }` 里的声明，后面的 @media 覆盖块不算（它们是降级）。 */
function firstRootBlock(css) {
  const start = css.indexOf(':root');
  if (start < 0) return '';
  const open = css.indexOf('{', start);
  let depth = 1;
  let i = open + 1;
  while (i < css.length && depth > 0) {
    if (css[i] === '{') depth += 1;
    if (css[i] === '}') depth -= 1;
    i += 1;
  }
  return css.slice(open + 1, i - 1);
}

const root = firstRootBlock(CSS);
const decls = new Map();
for (const m of root.matchAll(/(--sk-[a-z0-9-]+)\s*:\s*([^;]+);/g)) {
  const name = m[1];
  if (!decls.has(name)) decls.set(name, m[2].trim()); // 同名取第一次（后面的降级块不在 root 里）
}

const hex = (v) => {
  const m = String(v).match(/^#([0-9a-fA-F]{6})$/);
  return m ? m[1].toLowerCase() : null;
};
/** rgba(r, g, b, a) -> Color("rrggbb", a)。line-soft / line-faint / smoke 都是这种，
 *  它们用得很频繁，不能因为"不是纯 hex"就丢掉。 */
const rgba = (v) => {
  const m = String(v).match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$/);
  if (!m) return null;
  const to2 = (n) => Number(n).toString(16).padStart(2, '0');
  return { hex: `${to2(m[1])}${to2(m[2])}${to2(m[3])}`, a: m[4] === undefined ? 1 : Number(m[4]) };
};
const colorOf = (v) => {
  const h = hex(v);
  if (h) return { hex: h, a: 1 };
  return rgba(v);
};
const num = (v) => {
  const m = String(v).match(/^(-?\d+(?:\.\d+)?)px$/);
  return m ? Number(m[1]) : null;
};
const ms = (v) => {
  const m = String(v).match(/^(\d+(?:\.\d+)?)ms$/);
  return m ? Number(m[1]) : null;
};
const bezier = (v) => {
  const m = String(v).match(/^cubic-bezier\(([^)]+)\)$/);
  return m ? m[1].split(',').map((s) => Number(s.trim())) : null;
};

const colors = {};
const spaces = {};
const durs = {};
const eases = {};
const skipped = [];

/* --- 别名解析 ---------------------------------------------------------------
   `--sk-fg: var(--sk-text)` 这类是**语义名**，前面几组颜色解析不出 hex 就是
   因为这个。但 Godot 侧同样需要它们 —— 否则只能把 gold-bright 硬编码进
   GDScript，而那正是漂移的起点。所以顺着 var() 链追到底，按同一个名字发出去。
   -------------------------------------------------------------------------- */
const ALIAS_HOPS_MAX = 8;
function declValue(name) {
  let v = decls.get(name);
  for (let i = 0; i < ALIAS_HOPS_MAX && v; i += 1) {
    const m = String(v).match(/^var\(\s*(--sk-[\w-]+)\s*\)$/);
    if (!m) break;
    v = decls.get(m[1]);
  }
  return v;
}

const groups = {
  colors: [
    'void', 'ink', 'ink-soft', 'ink-raise', 'smoke',
    'line', 'line-soft', 'line-faint',
    'text', 'text-2', 'text-3', 'text-4',
    'gold', 'gold-bright', 'gold-line',
    'hp', 'mp', 'sp', 'alert',
    'fire', 'frost', 'gale',
    'surface-hover', 'surface-focus', 'surface-primary', 'surface-press',
    // 语义别名（值等于上面某个原语，但名字是"用途"，界面代码读这一组）
    'fg', 'fg-dim', 'fg-meta', 'fg-ghost',
    'accent', 'accent-hi', 'surface', 'border', 'border-focus',
  ],
  spaces: ['s1', 's2', 's3', 's4', 's5', 's6', 's7', 's8', 's9', 's10', 'radius', 'chamfer', 'chamfer-lg', 'stroke-hair', 'stroke'],
  // 注意 stagger 在 CSS 里的名字是 --sk-stagger（不带 t-）；用 [css, gd] 对显式写出来，
  // 免得下次又靠命名规律去猜。
  durs: [
    ['instant', '--sk-t-instant'],
    ['fast', '--sk-t-fast'],
    ['base', '--sk-t-base'],
    ['slow', '--sk-t-slow'],
    ['crawl', '--sk-t-crawl'],
    ['write', '--sk-t-write'],
    ['drift', '--sk-t-drift'],
    ['breathe', '--sk-t-breathe'],
    ['stagger', '--sk-stagger'],
  ],
  eases: ['out', 'in', 'io', 'snap', 'write', 'unfold', 'drift'],
};

for (const n of groups.colors) {
  // 用 declValue 而不是 decls.get：别名会被追到原语。非别名（#hex / rgba）
  // 原样返回，走的还是同一条路。
  const raw = declValue(`--sk-${n}`);
  const c = colorOf(raw);
  if (c) colors[n] = c;
  else skipped.push(`color --sk-${n} (${raw ?? 'missing'})`);
}
for (const n of groups.spaces) {
  const v = num(decls.get(`--sk-${n}`));
  if (v !== null) spaces[n] = v;
  else skipped.push(`space --sk-${n} (${decls.get(`--sk-${n}`) ?? 'missing'})`);
}
for (const [key, cssName] of groups.durs) {
  const v = ms(decls.get(cssName));
  if (v !== null) durs[key] = v;
  else skipped.push(`duration ${cssName} (${decls.get(cssName) ?? 'missing'})`);
}
for (const n of groups.eases) {
  const raw = decls.get(`--sk-e-${n}`);
  // --sk-e-drift 是 linear：它没有贝塞尔控制点，保留字面意思。
  if (raw === 'linear') {
    eases[n] = 'linear';
    continue;
  }
  const v = bezier(raw);
  if (v) eases[n] = v;
  else skipped.push(`easing --sk-e-${n} (${raw ?? 'missing'})`);
}

/* ---------------------------------------------------------------------------
   1b. 字号：clamp(minPx, Nvmin, maxPx) -> [min, N, max]
   网页侧用 vmin 表达"以 900px 高为基准的比例"。Godot 没有 vmin 单位，
   所以把三个数原样带过去，由 ui_tokens.gd 的 type_px() 用同一套公式算。
   手抄这一组数字是最容易出错的地方（7.11 / 5.33 / 2.67 …），所以必须生成。
   ------------------------------------------------------------------------ */
const TYPE_TOKENS = ['mega', 'display', 'title', 'head', 'body', 'small', 'micro', 'nano'];
const TRACK_TOKENS = ['mega', 'wide', 'title', 'body', 'figure'];
const type = {};
const track = {};

for (const n of TYPE_TOKENS) {
  const raw = decls.get(`--sk-fs-${n}`);
  const m = String(raw).match(/^clamp\(\s*(-?[\d.]+)px\s*,\s*([\d.]+)vmin\s*,\s*(-?[\d.]+)px\s*\)$/);
  if (m) type[n] = [Number(m[1]), Number(m[2]), Number(m[3])];
  else skipped.push(`type --sk-fs-${n} (${raw ?? 'missing'})`);
}
for (const n of TRACK_TOKENS) {
  const raw = decls.get(`--sk-track-${n}`);
  const m = String(raw).match(/^(-?[\d.]+)em$/);
  if (m) track[n] = Number(m[1]);
  else skipped.push(`track --sk-track-${n} (${raw ?? 'missing'})`);
}

/* --- 版心边距：与字号同一套 clamp(px, Nvmin, px) ---------------------------
   页脚（Launcher）与元信息条（主菜单）都靠它对齐屏幕边距。
   漏掉它，两侧的页脚就会差 20px，而这种差没人会主动去查。 */
const gutterRaw = decls.get('--sk-gutter');
const gutterMatch = String(gutterRaw).match(/^clamp\(\s*(-?[\d.]+)px\s*,\s*([\d.]+)vmin\s*,\s*(-?[\d.]+)px\s*\)$/);
let gutter = null;
if (gutterMatch) gutter = [Number(gutterMatch[1]), Number(gutterMatch[2]), Number(gutterMatch[3])];
else skipped.push(`gutter --sk-gutter (${gutterRaw ?? 'missing'})`);

/* --- 行高（无单位倍数）------------------------------------------------------
   版式里最容易被忽略、又最容易差出十几个像素的一类数值：CSS 里没写
   line-height 的元素**继承 body**（1.62），不是继承最近的标题值。
   Godot 侧推算块高时若按 1.34 算，品牌块就会矮 15px、整体上移 7px。 */
const lines = {};
for (const n of ['tight', 'snug', 'body']) {
  const raw = decls.get(`--sk-lh-${n}`);
  const m = String(raw).match(/^([\d.]+)$/);
  if (m) lines[n] = Number(m[1]);
  else skipped.push(`line-height --sk-lh-${n} (${raw ?? 'missing'})`);
}

/* --- 字重 -------------------------------------------------------------------
   字标是 300，副标题是 500。400 与 300 的差别在宽字距大字上是一眼可见的 ——
   而 Godot 的 SystemFont 默认 400，不显式给就会"看起来就是不太对"。 */
const WEIGHT_TOKENS = ['light', 'regular', 'medium', 'semi'];
const weight = {};
for (const n of WEIGHT_TOKENS) {
  const raw = decls.get(`--sk-fw-${n}`);
  const m = String(raw).match(/^(\d+)$/);
  if (m) weight[n] = Number(m[1]);
  else skipped.push(`weight --sk-fw-${n} (${raw ?? 'missing'})`);
}

/* ---------------------------------------------------------------------------
   2. 读 launcher.config.js —— 交接合同与时序，直接 import 真模块
   ------------------------------------------------------------------------ */
const cfgPath = path.join(UI_ROOT, 'launcher', 'launcher.config.js');
const { SEQUENCE, LOADING, COPY } = await import(pathToFileURL(cfgPath).href);
// HANDOFF 从它自己的模块读 —— 它是三个场景共同的合同，不属于启动器配置。
// （launcher.config.js 只是 re-export，所以两条路都对，这条更直接。）
const handoffPath = path.join(UI_ROOT, 'components', 'handoff.js');
const { HANDOFF } = await import(pathToFileURL(handoffPath).href);

/* ---------------------------------------------------------------------------
   2b. 读 main_menu.config.js —— 主菜单进场时序 + 菜单项
   与上面同理：这是 Launcher→BootSplash→MainMenu 三段演出里唯一还没被生成的
   一段。生成之后，整条启动链路的时间轴在 Godot 侧没有一个是手抄的。
   ------------------------------------------------------------------------ */
const menuCfgPath = path.join(UI_ROOT, 'main_menu', 'main_menu.config.js');
const { MENU_BOOT, ITEMS } = await import(pathToFileURL(menuCfgPath).href);

/* --- 两支时钟的换算 ---------------------------------------------------------
   MENU_BOOT 的 beats 用的是"网页版主菜单自己的 t=0"（交接帧）；
   BOOT_SEQ 用的是 Launcher 的 t=0。它们描述的是**同一场品牌演出**的两套编号，
   下面这张锚点表就是两者的对应关系。

   Godot 侧的品牌段由 BootSplash 播 BOOT_SEQ（那才是"接着 Launcher 往下演"），
   主菜单只播导航/页脚/焦点三拍。这三拍的**可移植事实**是"比副标题晚多少"，
   所以取差、再加回 BOOT_SEQ 的副标题时刻 —— 于是 Godot 只有一支时钟。

   刻意**不含**背景渐变那一拍：MENU 的 scene(260) 是"渐变淡入"，Launcher 的
   bgMove(1500) 是"背景开始移动"，是两个不同的事件，硬凑成一对只会得到一个
   反序的锚点表。不需要它 —— 只要副标题那个锚点是同一件事就够了。
   -------------------------------------------------------------------------- */
const BRAND_ANCHOR = [
  ['runes', 'runes'],
  ['letters', 'wordmark'],
  ['cn', 'wordmarkCN'],
  ['rule', 'rule'],
  ['subtitle', 'subtitle'],
];

const bootBeats = SEQUENCE.full.beats;
const menuBeats = MENU_BOOT.beats;

// 锚点表一旦和实际时序对不上，换算出来的导航时刻就是错的 —— 而且错得很安静。
// 所以这里当场验一遍：两边的值必须同序（都单调递增）。改了时序忘了改锚点，
// 会在这里炸，不会生成一份看着合理的错表。
{
  const order = (get) => BRAND_ANCHOR.map((p) => get(p)).join('|');
  const bootVals = BRAND_ANCHOR.map(([, bk]) => bootBeats[bk]);
  const menuVals = BRAND_ANCHOR.map(([mk]) => menuBeats[mk]);
  const bad = (arr, label) =>
    arr.some((v) => typeof v !== 'number') ||
    arr.some((v, i) => i > 0 && v <= arr[i - 1]);
  if (bad(bootVals, 'BOOT_SEQ') || bad(menuVals, 'MENU_BOOT')) {
    throw new Error(
      `BRAND_ANCHOR 与实到时序不符（必须两边都严格递增）：\n` +
        `  BOOT_SEQ : ${order(([, bk]) => bootBeats[bk])}\n` +
        `  MENU_BOOT: ${order(([mk]) => menuBeats[mk])}\n` +
        `  改过 launcher.config.js 或 main_menu.config.js 的 beat 顺序后，请同步 BRAND_ANCHOR。`
    );
  }
}

/** 把主菜单的"晚段"beat 换算到启动时钟（毫秒，交接帧 = 0，BootSplash 的 _at 基准）。 */
const LATE_BEATS = ['nav', 'meta', 'focus'];
const subtitleLag = menuBeats.subtitle; // 网页侧的副标题时刻，作为公共锚点
const menuSeq = {};
for (const k of LATE_BEATS) {
  menuSeq[k] = bootBeats.subtitle + (menuBeats[k] - subtitleLag);
}

/* --- 消费契约校验 -----------------------------------------------------------
   Godot 侧是**按键名**读这些表的（`beats["wordmark"]`、`durs["bgFade"]`…）。
   JS 这边多一个键、少一个键，没有任何人会吭声 —— 直到运行时 GDScript 抛
   "Invalid access to property or key"。本次就踩了这个坑：我按 MENU 的命名去读
   BOOT 的表（letters / cn / scene 在 BOOT_SEQ / BOOT_DUR 里都不存在），
   解析检查干干净净，一跑演出就断在第二句上。

   所以把"Godot 到底读哪几个键"写成清单。少一个就在生成期炸，不留给运行时。
   -------------------------------------------------------------------------- */
const TABLES = { BOOT_SEQ: bootBeats, BOOT_DUR: SEQUENCE.full.dur, MENU_SEQ: menuSeq, MENU_DUR: MENU_BOOT.dur };
const GD_READS = {
  BOOT_SEQ: ['runes', 'bgMove', 'wordmark', 'wordmarkCN', 'rule', 'subtitle'],
  BOOT_DUR: ['rune', 'bgFade', 'letter', 'letterStagger', 'wordmarkCN', 'rule', 'subtitle'],
  MENU_SEQ: ['nav', 'meta', 'focus'],
  MENU_DUR: ['markHomeDelay', 'markHome', 'navItem', 'navStagger', 'meta'],
};
{
  const missing = [];
  for (const [table, keys] of Object.entries(GD_READS)) {
    for (const k of keys) {
      if (!(k in TABLES[table])) missing.push(`${table}["${k}"]  ← Godot 读它，但表里没有`);
    }
  }
  if (missing.length) {
    throw new Error('消费契约不满足：\n  ' + missing.join('\n  '));
  }
}

/* ---------------------------------------------------------------------------
   3. 生成 GDScript
   ------------------------------------------------------------------------ */
const gdColor = (c) => (c.a === 1 ? `Color("${c.hex}")` : `Color("${c.hex}", ${c.a})`);

function dict(obj, fmt, indent = '\t') {
  // **键一律加引号，不做裸键优化。**
  // 令牌名里有连字符（text-2 / line-soft / surface-hover），
  // 裸键会被 GDScript 当成减法解析；`void` 又是保留字。
  // 省几个引号换来一份语法错误的生成文件，不划算。
  return Object.entries(obj)
    .map(([k, v]) => `${indent}${JSON.stringify(k)}: ${fmt(v)},`)
    .join('\n');
}

const now = new Date().toISOString().slice(0, 10);

const gd = `# ============================================================================
# SEKAI · UI TOKENS  （**本文件由工具生成，不要手改**）
# ----------------------------------------------------------------------------
# 生成器 : ui_web/tools/emit_tokens.mjs
# 来源   : ui_web/tokens/tokens.css             （颜色 / 间距 / 时长 / 缓动）
#          ui_web/launcher/launcher.config.js   （HANDOFF 交接合同 · 启动时序）
#          ui_web/main_menu/main_menu.config.js （主菜单进场时序 · 菜单项）
# 生成于 : ${now}
#
# 为什么要生成而不是手抄：
#   HANDOFF、启动时序、主菜单时序本来就是"网页与 Godot 两侧必须逐项对上"的
#   东西。手抄的表一定会漂移，而且漂了没人会发现。生成的不可能抄错。
#   改数值请改上面三个源文件，然后重新运行 emitter。
#
# 注意：这里**不**生成字号。网页侧字号是 clamp(px, Nvmin, px)，
# 是"以 900px 高为基准的比例"，用 vmin 表达；Godot 侧应当用
# 视口高度换算（见 ui_scale()），而不是钉死一个 px。
# ============================================================================
extends RefCounted

# --- 颜色 -------------------------------------------------------------------
const COLOR := {
${dict(colors, gdColor)}
}

# --- 间距 / 形体 ------------------------------------------------------------
const SPACE := {
${dict(spaces, (v) => String(v))}
}

# --- 字号：[最小px, Nvmin, 最大px] ------------------------------------------
# 与 CSS 的 clamp(minPx, Nvmin, maxPx) 逐字对应。用 type_px() 求值。
const TYPE := {
${dict(type, (v) => `[${v[0]}, ${v[1]}, ${v[2]}]`)}
}

# --- 字距（em）--------------------------------------------------------------
# 宽字距是本设计的主要"呼吸"手段。Godot 的 Label 没有 letter-spacing，
# 所以标题必须自己逐字排版（见 wordmark 的实现在 boot_splash.gd）。
const TRACK := {
${dict(track, (v) => String(v))}
}

# --- 行高（无单位倍数）------------------------------------------------------
# CSS 里没写 line-height 的元素继承 body（body 值），不是继承标题值。
# 推算块高时必须照这个来，否则品牌块会整块偏移。
const LINE := {
${dict(lines, (v) => String(v))}
}

# --- 字重 -------------------------------------------------------------------
# SystemFont 默认 400。字标是 300、元信息是 500 —— 不显式给就等于没对齐。
const WEIGHT := {
${dict(weight, (v) => String(v))}
}

# --- 版心边距：[最小px, Nvmin, 最大px] --------------------------------------
# 与 TYPE 同一套公式，用 gutter_px() 求值。
const GUTTER := [${gutter ? gutter.join(', ') : '32, 5.2, 96'}]

# --- 时长（毫秒）------------------------------------------------------------
const DUR_MS := {
${dict(durs, (v) => String(v))}
}

# --- 缓动（cubic-bezier 控制点）---------------------------------------------
# Godot 的 Tween 只有 TRANS_/EASE_ 预设，没有任意贝塞尔。
# 这里保留原始控制点，是为了让"意图"能被查到，并按下面的对应关系选预设：
#   out      → TRANS_CUBIC + EASE_OUT
#   in       → TRANS_CUBIC + EASE_IN
#   io       → TRANS_SINE  + EASE_IN_OUT
#   snap     → TRANS_BACK  + EASE_OUT（或 QUINT）
#   write    → TRANS_CUBIC + EASE_OUT（慢起快走；入场用 EASE_IN 会更像"落笔"）
#   unfold   → TRANS_QUINT + EASE_OUT
#   drift    → TRANS_LINEAR
const EASE_BEZIER := {
${dict(eases, (v) => (Array.isArray(v) ? `Vector4(${v.join(', ')})` : `"${v}"`))}
}

# --- 品牌标记几何（viewBox 128×128）----------------------------------------
# 实现见 web 侧 ui_web/svg/library.js 的 mark()。
# 「开口的环 + 正中一点」：环 302°，缺口 58° 落在右上；点是信标 / 观察者。
const MARK_VIEWBOX := 128.0
const MARK_ARC_RADIUS := 40.0
const MARK_ARC_SWEEP_DEG := 294.0
const MARK_ARC_GAP_CENTER_DEG := 58.0
const MARK_DOT_RADIUS := ${HANDOFF.dotRadius}.0

# --- HANDOFF：Launcher 最后一帧 ≡ BootSplash 第一帧 ------------------------
# 这是"一个连续启动过程"能被验收的唯一依据。两侧逐项对齐。
# 验收方式：两侧最后一帧采样，四角与侧翼都必须是 bg，
# 最亮像素必须落在屏幕正中的那个点上。
const HANDOFF := {
${dict(
  {
    bg: HANDOFF.bg,
    mark_side_vmin: HANDOFF.markSideVmin,
    mark_side_min_px: HANDOFF.markSideMinPx,
    mark_side_max_px: HANDOFF.markSideMaxPx,
    mark_center_x: HANDOFF.markCenterX,
    mark_center_y: HANDOFF.markCenterY,
    arc_progress: HANDOFF.arcProgress,
    dot_progress: HANDOFF.dotProgress,
    arc_color: HANDOFF.arcColor,
    dot_color: HANDOFF.dotColor,
    arc_stroke_px: HANDOFF.arcStrokePx,
    hold_ms: HANDOFF.holdMs,
    exit_ms: HANDOFF.exitMs,
  },
  (v) => (typeof v === 'string' && v.startsWith('#') ? `Color("${v.slice(1).toLowerCase()}")` : String(v))
)}
}

# --- 启动演出时序（毫秒，从画面出现算起）-----------------------------------
# 与 ui_web/launcher/index.html 同一支舞。Godot 侧跑同一张表。
const BOOT_SEQ := {
${Object.entries(SEQUENCE.full.beats)
  .map(([k, v]) => `\t${JSON.stringify(k)}: ${v},`)
  .join('\n')}
}

const BOOT_DUR := {
${Object.entries(SEQUENCE.full.dur)
  .map(([k, v]) => `\t${JSON.stringify(k)}: ${v},`)
  .join('\n')}
}

const BOOT_SEQ_FAST := {
${Object.entries(SEQUENCE.fast.beats)
  .map(([k, v]) => `\t${JSON.stringify(k)}: ${v},`)
  .join('\n')}
}

# --- 加载表现 ---------------------------------------------------------------
# **禁止假加载**：不显示百分比；真实进度只影响"线写到哪"，不影响数字。
const LOADING := {
	"ambient_line_ms": ${LOADING.ambientLineDuration},
	"ambient_gap_ms": ${LOADING.ambientLineGap},
	"ring_spin_ms": ${LOADING.ringSpinDuration},
	"stalled_after_ms": ${LOADING.stalledAfter},
}

# --- 文案（唯一真相源在 launcher.config.js 的 COPY）-------------------------
const COPY := {
	"wordmark": ${JSON.stringify(COPY.wordmark)},
	"wordmark_cn": ${JSON.stringify(COPY.wordmarkCN)},
	"subtitle": ${JSON.stringify(COPY.subtitle)},
	"skip": ${JSON.stringify(COPY.skip)},
	"skip_en": ${JSON.stringify(COPY.skipEn)},
	"error_cn": ${JSON.stringify(COPY.error.cn)},
	"error_en": ${JSON.stringify(COPY.error.en)},
}

# --- 主菜单进场时序（毫秒，**启动时钟**：交接帧 = 0，与 BOOT_SEQ 同一支表）---
# 品牌段（标记 / 字标 / 中文名 / 金线 / 副标题 / 世界层）由 BootSplash 播，
# 用的是上面的 BOOT_SEQ —— 因为那才是"接着 Launcher 往下演"。
# 这里只有主菜单自己要负责的三拍。
#
# 换算方式：取 MENU_BOOT 里这三拍相对副标题的滞后，加到 BOOT_SEQ 的副标题时刻上。
# 换句话说，可移植的事实是"导航比副标题晚 160ms"，不是"导航在 1420ms"。
const MENU_SEQ := {
${Object.entries(menuSeq)
  .map(([k, v]) => `\t${JSON.stringify(k)}: ${v},`)
  .join('\n')}
}

# --- 主菜单用到的时长（毫秒）------------------------------------------------
# 时长没有原点问题，所以原样生成，不做换算。
#
# 注意：网页版主菜单是**自包含**的（它自己从交接帧演到菜单出现），
# 所以这张表里的 letter / cn / rule / subtitle / scene / runes 属于"品牌段"，
# 在 Godot 里由 BootSplash 用 BOOT_DUR 表达 —— 两边数值不同是**故意的**：
# Launcher 那条链路上多出了 pulse / dot / markArc / loading 几拍。
# Godot 侧的 MainMenu **只消费**：markHome / markHomeDelay / navItem /
# navStagger / meta。
const MENU_DUR := {
${Object.entries(MENU_BOOT.dur)
  .map(([k, v]) => `\t${JSON.stringify(k)}: ${v},`)
  .join('\n')}
}

# --- 主菜单退场（进入世界）--------------------------------------------------
# 终点与 Launcher 首帧 / BootSplash 首帧**完全相同**：纯色 + 屏幕正中的标记。
# 所以"进入世界"这个动作在三个场景里都能用同一句断言验收。
const MENU_EXIT := {
	"mark_delay_ms": ${MENU_BOOT.exit.markHome.delay},
	"mark_dur_ms": ${MENU_BOOT.exit.markHome.duration},
	"hold_ms": ${MENU_BOOT.exit.holdMs},
}

# --- 菜单项 -----------------------------------------------------------------
# 文案（cn/en）属于 NARRATIVE 线，此处是**占位**。Godot 与网页读同一份表，
# 免得两边各写一套菜单然后逐渐说不一样的话。
#   needs_save : 没有存档时该项不可用 —— 灰掉并说明原因，不假装能用
#   note       : 本 PASS 未接入的功能。写清楚比弹个空的模态框诚实
const MENU_ITEMS := [
${ITEMS.map(
  (it) =>
    `\t{"id": ${JSON.stringify(it.id)}, "cn": ${JSON.stringify(it.cn)}, ` +
    `"en": ${JSON.stringify(it.en)}, "needs_save": ${it.needsSave ? 'true' : 'false'}, ` +
    `"note": ${JSON.stringify(it.note ?? '')}},`
).join('\n')}
]

# ---------------------------------------------------------------------------
# 缩放：网页侧的字号是 clamp(px, Nvmin, px)，基准视口高 900px。
# Godot 侧用同一个基准换算，分辨率不同才不会把比例搞乱。
# ---------------------------------------------------------------------------
const REFERENCE_HEIGHT := 900.0

static func ui_scale(viewport_height: float) -> float:
	return viewport_height / REFERENCE_HEIGHT

## 网页侧字号是 clamp(minPx, Nvmin, maxPx)，vmin = min(视口宽, 高)。
## Godot 没有 vmin，所以这里用同一个公式算，而不是钉死一个 px。
static func type_px(name: String, viewport_size: Vector2) -> float:
	var t: Array = TYPE[name]
	var vmin := minf(viewport_size.x, viewport_size.y)
	return clampf(t[1] * vmin / 100.0, t[0], t[2])

## 字距（像素）。tracking 是 em，所以要乘字号。
static func track_px(name: String, font_size_px: float) -> float:
	return float(TRACK[name]) * font_size_px

## 版心边距（像素）。与 type_px() 同一个 clamp 公式。
static func gutter_px(viewport_size: Vector2) -> float:
	var vmin := minf(viewport_size.x, viewport_size.y)
	return clampf(GUTTER[1] * vmin / 100.0, GUTTER[0], GUTTER[2])

## 12 栅的第 column 列（1 起）距离左边的像素偏移。
static func grid_col(viewport_size: Vector2, column: int) -> float:
	return viewport_size.x * float(column - 1) / 12.0

## 8vmin（交接帧的标记方框边长）在当前视口下的像素值。
## **夹取上下限**：网页侧 CSS 的 .sk-brand__mark 是 clamp(44px, 8vmin, 92px)，
## 不夹的话超宽比例下 JS 与 CSS 会算出不同边长，交接帧就差几十像素。
static func handoff_mark_side(viewport_size: Vector2) -> float:
	var vmin := minf(viewport_size.x, viewport_size.y)
	var raw := vmin * HANDOFF["mark_side_vmin"] / 100.0
	return clampf(raw, HANDOFF["mark_side_min_px"], HANDOFF["mark_side_max_px"])

## 启动时钟 → "演出开始后第几秒"。BOOT_SEQ / MENU_SEQ 都是"交接帧 = 0"的表，
## BootSplash 与 MainMenu 都从同一刻开始播，所以换算只应该有这一处。
## 谁要是自己写 hold_ms + ms/1000，两段演出就会错开 320ms —— 而错开看不出来。
static func boot_at(ms: float) -> float:
	return (float(HANDOFF["hold_ms"]) + ms) / 1000.0

## 交接帧的标记中心（像素）。
static func handoff_mark_center(viewport_size: Vector2) -> Vector2:
	return Vector2(viewport_size.x * HANDOFF["mark_center_x"], viewport_size.y * HANDOFF["mark_center_y"])
`;

/* ---------------------------------------------------------------------------
   4. 落盘 / 检查
   ------------------------------------------------------------------------ */
if (skipped.length) {
  console.log('--- 未能生成的令牌 ---');
  for (const s of skipped) console.log('  ' + s);
}

if (CHECK) {
  let prev = null;
  try {
    prev = await fsp.readFile(OUT, 'utf8');
  } catch (_) {
    /* 不存在 = 视为差异 */
  }
  // 生成头带日期，日期不同不算差异
  const strip = (s) => (s ? s.replace(/^# 生成于 ：.*$/m, '').replace(/^# 生成于 : .*$/m, '') : s);
  if (strip(prev) !== strip(gd)) {
    console.log(`DIFF  ${path.relative(REPO, OUT)}`);
    process.exitCode = 1;
  } else {
    console.log(`ok    ${path.relative(REPO, OUT)}`);
  }
} else {
  await fsp.mkdir(path.dirname(OUT), { recursive: true });
  await fsp.writeFile(OUT, gd, 'utf8');
  console.log(`OK  ${path.relative(REPO, OUT)}  (${(gd.length / 1024).toFixed(1)} KB)`);
  console.log(
    `    colors=${Object.keys(colors).length} spaces=${Object.keys(spaces).length} ` +
      `durs=${Object.keys(durs).length} eases=${Object.keys(eases).length}`
  );
}
