/* ============================================================================
   SEKAI · SVG COMPONENT LIBRARY
   ----------------------------------------------------------------------------
   单一真相源。这里的字符串被两处消费：
     1. 页面直接 innerHTML 注入（可以直接吃到 CSS 变量，能被 SKMotion 书写）
     2. tools/emit_svg.mjs 把它落成独立 .svg 文件给 ART / Godot 用
   因此不存在"网页里的图标和 Godot 里的图标不一样"这种漂移。

   所有颜色写成 `var(--sk-x, #fallback)`：
   - 内联进 HTML 时吃到 tokens.css
   - 独立看 .svg 文件时用 fallback 仍然正确

   约定：
   - 每件都带 pathLength="1"，所以 SKMotion.write() 不用量长度
   - 需要被"书写"的几何带 class="sk-line" 或显式 stroke
   - 绝不使用实心填充（除极少数指示点）

   ============================================================================
   PASS 03 · §D 审计 —— 每件必须回答「WHAT STATE DOES THIS COMMUNICATE?」
   ----------------------------------------------------------------------------
   答案是"它看起来很 SEKAI"的，删或降级。目标比例 80% 功能 / 20% 身份。

     组件               裁决        理由
     -----------------  ----------  -------------------------------------------
     mark               KEEP        身份 20% 的那一半。同时是存档图标/加载字形。
     markArcOnly        KEEP        mark 的过渡帧变体，不单独引入语言。
     ringArc            DEMOTE      ❌ 装饰圆环。V2 全线禁用；只有 V1 scene_bg 用。
     focusLine          KEEP        焦点态。它就是"这一项被选中"这件事本身。
     cornerFrame        DELETE      ❌ 装饰角框 = 三四层装饰边框的入口（PART K #7）。
     divider 'hair'     KEEP        分隔 = 信息分组（设置行之间）。
     divider 'key'      KEEP        品牌金线，**只允许出现在 Logo 下**，全片一条。
     loadingRing        KEEP        加载态。注意 V2 主菜单改用 line state（§15），
                                    环留给游戏内加载。
     abilitySegment     KEEP        技能轮扇区 —— 下一阶段 UI 的核心，不是装饰。
     locationOrnament   DEMOTE      ⚠ 只允许作为"地点标题被写出时的下划线"，
                                    跟着标题一起写。**禁止单独出现**。
     cursor             KEEP        光标态（精确 / 悬停 / 按下）。

   **删掉的东西不许被重新捡回来。** 上面标 ❌ 的两个是 PASS 02 已经清掉的
   "AI 味"具体来源：一个巨大的、缓慢旋转的、不表达任何状态的圆环，
   和一组不知道在框住什么的角括号。
   ========================================================================= */

const C = {
  line: 'var(--sk-line, #2C3A44)',
  gold: 'var(--sk-gold, #C9A65C)',
  goldHi: 'var(--sk-gold-bright, #E8CE8C)',
  text: 'var(--sk-text, #EDE4D3)',
  text2: 'var(--sk-text-2, #B8AE9C)',
  text3: 'var(--sk-text-3, #7E8B95)',
  fire: 'var(--sk-fire, #D4763F)',
  frost: 'var(--sk-frost, #7FA8C9)',
  gale: 'var(--sk-gale, #8FBFA6)',
};

const ATTR = 'fill="none" stroke-linecap="round" stroke-linejoin="round" vector-effect="non-scaling-stroke"';

/* ============================================================================
   1. SEKAI MARK
   ----------------------------------------------------------------------------
   「开口的环 + 正中一点」

   - 环：302° 的弧，缺口 58° 落在右上。世界是圆的，但没有合上。
   - 点：正中心的鎏金点。它是**信标 / 观察者**，也是书写的第一滴墨。

   两段独立几何 → 两段独立动画。Launcher 开场正是"笔尖落下（点）→ 环被写出来"。
   为什么不是"环 + 斜线"：那会读成 ∅（禁止符）。为什么不是一笔画完的圆：
   24px 以下会糊成一个实心圆。这个组合从 16px 到 150px 都成立。

   viewBox 128，中心 (64,64)，环半径 40，缺口 25°–91°。
   ========================================================================= */
export function mark({ size = 128, stroke = 1.6, dot = 5 } = {}) {
  return `
<svg class="sk-mark" width="${size}" height="${size}" viewBox="0 0 128 128"
     xmlns="http://www.w3.org/2000/svg" aria-hidden="true" ${ATTR} stroke-width="${stroke}">
  <!-- 环：从 91° 逆时针 294° 到 25°。缺口在右上，58° 正中。 -->
  <path class="sk-mark__arc" pathLength="1"
        d="M 63.30 24.01 A 40 40 0 1 0 100.25 47.09"
        stroke="${C.text}" stroke-width="${stroke}"/>
  <!-- 点：信标 / 观察者 -->
  <circle class="sk-mark__dot" cx="64" cy="64" r="${dot}" fill="${C.gold}" stroke="none"/>
</svg>`.trim();
}

/** 只有环，没有点。用于"点还没落下来"的过渡帧，或者极小的角落水印。 */
export function markArcOnly({ size = 128, stroke = 1.6 } = {}) {
  return `<svg width="${size}" height="${size}" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg"
    aria-hidden="true" ${ATTR} stroke-width="${stroke}">
  <path pathLength="1" d="M 63.30 24.01 A 40 40 0 1 0 100.25 47.09" stroke="${C.text}"/>
</svg>`;
}

/* ============================================================================
   1b. RING ARC —— 只有一段弧
   Launcher / Main Menu 背景里那个"世界的环"。与 mark 的弧同源（缺口都在右上），
   只是被放大到屏幕外。两个页面共用同一个缺口角度 = 同一个世界。

   ⛔ PASS 03 裁决：DEMOTE。它不表达任何状态 —— 放在背景里只是"看起来很
   SEKAI"，正是 DE-AI 清单第 3 条（为了高级而出现的细环）。
   V2 全线禁用；这里保留只为 V1 scene_bg 仍能跑，以及 gallery 的历史对照。
   新代码一律不许调用。
   ========================================================================= */
export function ringArc({ size = 400, r = 196, from = 87, to = 389, stroke = 1, color = C.line } = {}) {
  const c = size / 2;
  const p = (radius, deg) => {
    const a = (deg * Math.PI) / 180;
    return [c + radius * Math.cos(a), c - radius * Math.sin(a)];
  };
  const [x0, y0] = p(r, from);
  const [x1, y1] = p(r, to);
  const large = Math.abs(to - from) > 180 ? 1 : 0;
  return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"
    xmlns="http://www.w3.org/2000/svg" aria-hidden="true" fill="none"
    stroke-linecap="round" vector-effect="non-scaling-stroke">
  <path pathLength="1" d="M ${x0.toFixed(2)} ${y0.toFixed(2)} A ${r} ${r} 0 ${large} 0 ${x1.toFixed(2)} ${y1.toFixed(2)}"
        stroke="${color}" stroke-width="${stroke}"/>
</svg>`;
}

/* ============================================================================
   2. FOCUS LINE —— 菜单焦点线
   一条 1px 线，从右往左被写出来（右端固定，左端推进），读作"这条被划上了"。
   两端各留一点透明，避免生硬的端头。
   ========================================================================= */
export function focusLine({ width = 240, height = 6 } = {}) {
  const y = height / 2;
  return `<svg class="sk-focus-line" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"
    xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none" aria-hidden="true" ${ATTR}>
  <defs>
    <!-- gradientUnits="userSpaceOnUse" 是必需的，不是风格选择：
         这条线的 bbox 高度为 0，默认的 objectBoundingBox 会让渐变退化，
         而规格规定退化渐变 = **整条不画**（不报错、不警告，就是看不见）。 -->
    <linearGradient id="skf-${width}" gradientUnits="userSpaceOnUse"
                    x1="0" y1="0" x2="${width}" y2="0">
      <stop offset="0%" stop-color="${C.gold}" stop-opacity="0"/>
      <stop offset="8%" stop-color="${C.gold}" stop-opacity="0.85"/>
      <stop offset="100%" stop-color="${C.gold}" stop-opacity="0.35"/>
    </linearGradient>
  </defs>
  <path pathLength="1" d="M 0 ${y} H ${width}" stroke="url(#skf-${width})" stroke-width="1"/>
</svg>`;
}

/* ============================================================================
   3. CORNER FRAME —— 四角括号
   不是闭合边框。只有角。它"框住"内容但不围住 —— 保持通透。

   ⛔ PASS 03 裁决：DELETE。"四角括号"是装饰边框的第一块砖 —— 一旦有角，
   下一步就是"四边都补上"，再下一步就是"外面再套一层"（PART K #7）。
   而且它不表达状态：框住的内容无论怎么变，角都不变。
   保留函数只为 gallery 的历史对照；任何界面代码不许调用。
   ========================================================================= */
export function cornerFrame({ w = 320, h = 200, arm = 18, stroke = 1, color = C.gold } = {}) {
  const a = arm;
  const d = [
    `M 0 ${a} L 0 0 L ${a} 0`,
    `M ${w - a} 0 L ${w} 0 L ${w} ${a}`,
    `M ${w} ${h - a} L ${w} ${h} L ${w - a} ${h}`,
    `M ${a} ${h} L 0 ${h} L 0 ${h - a}`,
  ].join(' ');
  return `<svg class="sk-corner-frame" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"
    xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none" aria-hidden="true" ${ATTR}>
  <path pathLength="1" d="${d}" stroke="${color}" stroke-width="${stroke}" opacity="0.55"/>
</svg>`;
}

/* ============================================================================
   4. DIVIDER —— 分隔线
   variant: 'hair' 全宽 1px / 'key' 64px 金色渐变（唯一允许的纯装饰）
   ========================================================================= */
export function divider({ width = 240, variant = 'key' } = {}) {
  if (variant === 'hair') {
    return `<svg class="sk-divider" width="${width}" height="1" viewBox="0 0 ${width} 1"
      xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none" aria-hidden="true">
    <path pathLength="1" d="M 0 0.5 H ${width}" stroke="${C.line}" stroke-width="1" opacity="0.5"/>
  </svg>`;
  }
  const w = Math.min(64, width);
  return `<svg class="sk-divider sk-divider--key" width="${w}" height="1" viewBox="0 0 ${w} 1"
    xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none" aria-hidden="true">
  <defs>
    <!-- 同上：bbox 高为 0，必须 userSpaceOnUse，否则整条不画 -->
    <linearGradient id="skdv" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${w}" y2="0">
      <stop offset="0%" stop-color="${C.gold}" stop-opacity="0"/>
      <stop offset="50%" stop-color="${C.gold}" stop-opacity="0.9"/>
      <stop offset="100%" stop-color="${C.gold}" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <path pathLength="1" d="M 0 0.5 H ${w}" stroke="url(#skdv)" stroke-width="1"/>
</svg>`;
}

/* ============================================================================
   5. LOADING RING —— 环境加载环
   不是进度条。是"环正在被画完"：
     - 外圈 1px 静态 Ink Line（结构）
     - 内圈 Gold 弧，其 sweep = 真实进度（没有真实进度时走环境呼吸）
     - 4 个 8px 刻度（方位感）
   ========================================================================= */
export function loadingRing({ size = 96, r = 44, stroke = 1.5 } = {}) {
  const c = size / 2;
  return `<svg class="sk-ring" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"
    xmlns="http://www.w3.org/2000/svg" aria-hidden="true" ${ATTR} stroke-width="${stroke}">
  <circle cx="${c}" cy="${c}" r="${r}" stroke="${C.line}" stroke-width="1" opacity="0.55"/>
  <!-- 进度弧：pathLength=1，所以 stroke-dasharray 直接就是进度比例 -->
  <path class="sk-ring__progress" pathLength="1"
        d="M ${c} ${c - r} A ${r} ${r} 0 1 1 ${c - 0.01} ${c - r}"
        stroke="${C.gold}" stroke-width="${stroke}"
        stroke-dasharray="0.02 1" stroke-dashoffset="0"/>
  <path pathLength="1" d="M ${c + r + 3} ${c} h 6" stroke="${C.line}" stroke-width="1"/>
  <path pathLength="1" d="M ${c - r - 9} ${c} h 6" stroke="${C.line}" stroke-width="1"/>
  <path pathLength="1" d="M ${c} ${c + r + 3} v 6" stroke="${C.line}" stroke-width="1"/>
  <path pathLength="1" d="M ${c} ${c - r - 9} v 6" stroke="${C.line}" stroke-width="1"/>
</svg>`;
}

/* ============================================================================
   6. ABILITY SEGMENT —— 轮盘扇区
   一段扇环（不是实心块）。from/to 是角度（度，0 = 正右，逆时针为正）。
   ========================================================================= */
export function abilitySegment({ r0 = 52, r1 = 130, from = 0, to = 110, color = C.gold, stroke = 1 } = {}) {
  const box = r1 * 2 + 8;
  const c = box / 2;
  const p = (radius, deg) => {
    const a = (deg * Math.PI) / 180;
    return [c + radius * Math.cos(a), c - radius * Math.sin(a)];
  };
  const [x0, y0] = p(r1, from);
  const [x1, y1] = p(r1, to);
  const [x2, y2] = p(r0, to);
  const [x3, y3] = p(r0, from);
  const large = Math.abs(to - from) > 180 ? 1 : 0;
  const d =
    `M ${x0.toFixed(2)} ${y0.toFixed(2)} ` +
    `A ${r1} ${r1} 0 ${large} 0 ${x1.toFixed(2)} ${y1.toFixed(2)} ` +
    `L ${x2.toFixed(2)} ${y2.toFixed(2)} ` +
    `A ${r0} ${r0} 0 ${large} 1 ${x3.toFixed(2)} ${y3.toFixed(2)} Z`;
  return `<svg class="sk-segment" width="${box}" height="${box}" viewBox="0 0 ${box} ${box}"
    xmlns="http://www.w3.org/2000/svg" aria-hidden="true" ${ATTR} stroke-width="${stroke}">
  <path pathLength="1" d="${d}" stroke="${color}"/>
</svg>`;
}

/* ============================================================================
   7. LOCATION ORNAMENT —— 地点名下的线

   ⚠ PASS 03 裁决：DEMOTE，且**只允许在一种用法下存活**：作为地点标题被写出时
   的下划线，必须与标题同一个 write 动画、同一条时间线。
   那时它是状态（"这个地名正在被写下"），不是装饰。
   单独放在任何地方、静态存在、或者放在不是地点名的地方 —— 都是装饰，删。
   ========================================================================= */
export function locationOrnament({ width = 120 } = {}) {
  return `<svg class="sk-location-ornament" width="${width}" height="5" viewBox="0 0 ${width} 5"
    xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="none" aria-hidden="true">
  <defs>
    <!-- 同上：bbox 高为 0，必须 userSpaceOnUse -->
    <linearGradient id="sklo" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="${width}" y2="0">
      <stop offset="0%" stop-color="${C.gold}" stop-opacity="0"/>
      <stop offset="50%" stop-color="${C.gold}" stop-opacity="1"/>
      <stop offset="100%" stop-color="${C.gold}" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <path pathLength="1" d="M 0 2.5 H ${width}" stroke="url(#sklo)" stroke-width="1"/>
</svg>`;
}

/* ============================================================================
   8. CURSOR —— 精确十字
   细十字 + 中心点。方向上是"标尺"不是"箭头"。
   ========================================================================= */
export function cursor({ arm = 14 } = {}) {
  return `<div class="sk-cursor__x"></div><div class="sk-cursor__y"></div><div class="sk-cursor__dot"></div>`;
}

export const COLORS = C;
export const SVG_ATTR = ATTR;
