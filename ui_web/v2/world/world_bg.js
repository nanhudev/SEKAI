/* ============================================================================
   SEKAI · WORLD LAYER
   ----------------------------------------------------------------------------
   把"世界"作为 UI 背景装进页面。见 world_bg.css 顶部的层次说明。

   背景来源（PASS 04 裁决，详见 v2.config.js 的 KEYART 注释与 PRODUCTION_BOARD）：
     · 默认 = 真游戏画面：godot/tools/menu_vista_renderer.gd 从
       scenes/world/MistvaleRegion.tscn 出的图 —— ART 每次交付都会自动升级这一屏。
     · `?bg=a|b|c` = KEY ART（image generation 主菜单封面）—— 当前 Mistvale
       地图仍在 Greybox → Stylized 生产中，允许 Key Art 先 SELL THE DREAM；
       地图达到 VISUAL CANDIDATE 后做 A/B 重裁决，把 WORLD.base 换回去即可。
   （PASS 02 的"禁止幻想插画"旧约束由本裁决显式取代：Key Art 不是 generic
   插画，是带世界身份清单的 SEKAI 主视觉，且真场景仍是默认与长期真相源。）

   运动比例（§23）：
     世界（漂移 + 雾）  ← 这一层，占大头，且**极慢**
     UI 响应            ← 菜单那一侧，100–380ms
     装饰               ← 几乎没有
   ========================================================================= */

import { SKMotion } from '../../motion/motion.js';
import { WORLD, KEYART } from '../v2.config.js';

/* ---------------------------------------------------------------------------
   构建
   ------------------------------------------------------------------------ */

/**
 * 装出世界层。**返回 Promise** —— 图没到位就不算装好，
 * 否则出片会拍到一张空背景，而"空背景"看起来和"背景没生效"一模一样。
 *
 * @param {HTMLElement} host
 * @returns {Promise<object>} parts
 */
export function buildWorld(host) {
  /* PASS 04：`?bg=a|b|c` 选 Key Art 候选做主菜单背景；不传 = 真 Godot 渲染。
     默认不变 —— Key Art 只是展示方案，真相源仍然是 menu_vista_renderer.gd。 */
  const bgKey = new URLSearchParams(location.search).get('bg');
  const keyartSrc = bgKey ? KEYART[bgKey] : null;

  const root = document.createElement('div');
  root.className = keyartSrc ? 'world world--keyart' : 'world';
  root.setAttribute('aria-hidden', 'true');

  const push = document.createElement('div');
  push.className = 'world__push';

  const drift = document.createElement('div');
  drift.className = 'world__drift';

  const base = document.createElement('img');
  base.className = 'world__base';
  base.dataset.loaded = '0';
  base.alt = '';
  base.decoding = 'sync';
  base.src = keyartSrc || WORLD.base;

  drift.appendChild(base);

  /* PASS 04：Key Art 的 2.5D 视差层 —— sky / fg 是同一张图的软 mask 副本
     （见 world_bg.css 的注释）。只在 ?bg= 命中 KEYART 时存在；
     真 Godot 渲染继续是单层，不引入任何假景深。加载完成前不显示，
     否则出片可能拍到"半透明副本叠在 void 上"的一帧。 */
  const layers = {};
  if (keyartSrc) {
    for (const k of ['sky', 'fg']) {
      const el = document.createElement('img');
      el.className = `world__layer world__layer--${k}`;
      el.alt = '';
      el.decoding = 'sync';
      el.src = keyartSrc;
      el.style.opacity = '0';
      drift.appendChild(el);
      layers[k] = el;
    }
  }

  const mists = [];
  /* §16（PASS 04）：Key Art 已经把该有的雾画进图里，独立雾层只留"活气"——
     透明度减半以上，否则灰白雾带盖在亮部上读成"图片上贴了三条白带"。 */
  const mistScale = keyartSrc ? 0.4 : 1;
  for (const m of WORLD.mist) {
    const el = document.createElement('div');
    el.className = 'world__mist';
    el.dataset.k = m.key;
    el.style.top = `${(m.y * 100).toFixed(2)}%`;
    el.style.height = `${(m.h * 100).toFixed(2)}%`;
    el.style.opacity = String(m.opacity * mistScale);
    el.style.filter = `blur(${m.blur}px)`;
    drift.appendChild(el);
    mists.push({ el, cfg: m });
  }

  push.appendChild(drift);

  const scrim = document.createElement('div');
  scrim.className = 'world__scrim';

  const curtainTop = document.createElement('div');
  curtainTop.className = 'world__curtain world__curtain--top';
  const curtainBottom = document.createElement('div');
  curtainBottom.className = 'world__curtain world__curtain--bottom';

  const line = document.createElement('div');
  line.className = 'world__line';
  line.setAttribute('aria-hidden', 'true');

  // §16：接相机切换用的一片雾。平时不在画面上（opacity 0）。
  const wipe = document.createElement('div');
  wipe.className = 'world__wipe';
  wipe.setAttribute('aria-hidden', 'true');

  root.append(push, scrim, curtainTop, curtainBottom, line, wipe);
  host.appendChild(root);

  const parts = {
    root,
    push,
    drift,
    base,
    mists,
    scrim,
    curtainTop,
    curtainBottom,
    line,
    wipe,
    /** 背景是不是 Key Art（PASS 04）。动效与交接层会按此分流。 */
    keyart: Boolean(keyartSrc),
    /** 世界层已经在画面上的时刻（毫秒，页面时钟）。buildWorld 之后才有的动画都以此为准。 */
    ready: false,
  };

  return new Promise((resolve) => {
    const done = () => {
      base.dataset.loaded = '1';
      for (const el of Object.values(layers)) el.style.opacity = '';
      parts.ready = true;
      resolve(parts);
    };
    // 图挂了也要往下走：宁可背景是一片 void，也不能把整个启动流程挂住。
    // （§44 的同一条原则：启动失败要能被说出来，不是无限等待。）
    if (base.complete && base.naturalWidth > 0) {
      done();
      return;
    }
    base.addEventListener('load', done, { once: true });
    base.addEventListener('error', done, { once: true });
  });
}

/* ---------------------------------------------------------------------------
   Key Art 2.5D 视差（PASS 04）
   ------------------------------------------------------------------------ */

/**
 * PART B：指针驱动的轻视差。只服务 Key Art 背景（parts.keyart）。
 *
 * 幅度不在 JS 里 —— CSS 的 .world__layer--sky/--fg 与 .world--keyart .world__base
 * 各自拿 --par-x / --par-y（-1..1）乘自己的系数（2–8px）。这里只负责把指针
 * 位置**缓动**进这两个变量：lerp 0.06/帧，读成"镜头很重"，不是"鼠标跟随"。
 *
 * @returns {{stop: () => void} | null} 非 Key Art / 减少动态时返回 null
 */
export function startWorldParallax(parts) {
  if (SKMotion.reduced || !parts.keyart) return null;
  let tx = 0, ty = 0, cx = 0, cy = 0, raf = 0;

  const tick = () => {
    raf = 0;
    cx += (tx - cx) * 0.06;
    cy += (ty - cy) * 0.06;
    parts.root.style.setProperty('--par-x', cx.toFixed(4));
    parts.root.style.setProperty('--par-y', cy.toFixed(4));
    if (Math.abs(tx - cx) + Math.abs(ty - cy) > 0.002) raf = requestAnimationFrame(tick);
  };
  const onMove = (e) => {
    tx = (e.clientX / window.innerWidth) * 2 - 1;
    ty = (e.clientY / window.innerHeight) * 2 - 1;
    if (!raf) raf = requestAnimationFrame(tick);
  };
  window.addEventListener('mousemove', onMove, { passive: true });
  return {
    stop: () => {
      window.removeEventListener('mousemove', onMove);
      if (raf) cancelAnimationFrame(raf);
    },
  };
}

/* ---------------------------------------------------------------------------
   世界自身的运动 —— 极慢，且不设终点
   ------------------------------------------------------------------------ */

/**
 * 开始世界运动。
 *
 * 时长全部按"读成静止"来定：漂移 90 秒走 3.5%，雾带 64–112 秒走一百多像素。
 * §5 要的是 almost still —— 20 秒会读成"在播放动画"，3 分钟读成静止。
 *
 * 全部用 ping-pong（去 → 回）而不是无限单向：
 * 单向循环在回头的那一帧会出现一个可见的接缝，而接缝是"这是段动画"最明确的证据。
 */
export function startWorldMotion(parts) {
  const out = [];
  if (SKMotion.reduced) return out;

  const d = WORLD.drift;
  out.push(
    SKMotion.animate(
      parts.drift,
      [{ transform: 'scale(1)' }, { transform: `scale(${d.to})` }, { transform: 'scale(1)' }],
      { duration: d.durMs * 2, ease: 'linear', iterations: Infinity, fill: 'both' }
    )
  );

  for (const { el, cfg } of parts.mists) {
    out.push(
      SKMotion.animate(
        el,
        [
          { transform: 'translate3d(0,0,0)' },
          { transform: `translate3d(${cfg.dx}px,0,0)` },
          { transform: 'translate3d(0,0,0)' },
        ],
        { duration: cfg.durMs * 2, ease: 'linear', iterations: Infinity, fill: 'both' }
      )
    );
  }
  return out;
}

/* ---------------------------------------------------------------------------
   启动：一条线把世界切开
   ------------------------------------------------------------------------ */

/**
 * ① 写出那条线。WRITE 语言，L→R。
 *
 * **不是 SVG，是一根 scaleX 的 div。** 早先是 SVG path + `pathLength="1"` +
 * `stroke-dasharray: 1` 的"写线"手法，在这里是坏的：这条线要横跨整屏，
 * 靠 `preserveAspectRatio="none"` 把 viewBox（100×1）横向拉伸 16 倍，
 * 而虚线间距会被那次非等比拉伸一起放大 —— 于是"写出的一条线"实际渲染成
 * **一条虚线**。虚线在主菜单里读起来是"测量/校准"的词汇，正是 §10 禁的那种。
 *
 * scaleX 对这个场景是严格更好的：拉伸不会把线变粗（transform-origin 在左端，
 * 竖向尺寸不受 scaleX 影响），不依赖任何 dash 语义，也不需要在"用户单位 /
 * 屏幕像素 / pathLength 归一化"三者之间做换算。
 *
 * @returns {Animation}
 */
export function worldLine(parts, { delay = 0, duration = 460 } = {}) {
  return SKMotion.animate(
    parts.line,
    [{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }],
    { duration, delay, ease: 'cubic-bezier(0.22, 0.61, 0.24, 1)', fill: 'both' }
  );
}

/**
 * ② 线变成遮罩：两块黑幕从这条线往上下退开，世界露出来。
 *
 * 这是全片最慢的一拍，也是唯一一处"仪式感"该花的地方 ——
 * §9 要的是"世界被揭开"，不是"UI 系统启动完成"。
 *
 * @returns {number} 退场完成所需的总毫秒（相对 delay）
 */
export function worldOpen(parts, { delay = 0, duration = 780, lineFade = 380 } = {}) {
  SKMotion.animate(
    parts.curtainTop,
    [{ height: '50%' }, { height: '0%' }],
    { duration, delay, ease: 'cubic-bezier(0.30, 0.00, 0.22, 1)', fill: 'both' }
  );
  // 下沿慢一档。完全对称会读成"一个机械的虹膜"，错开 40ms 就读成"揭开"。
  SKMotion.animate(
    parts.curtainBottom,
    [{ height: '50%' }, { height: '0%' }],
    { duration: duration * 1.06, delay: delay + 40, ease: 'cubic-bezier(0.30, 0.00, 0.22, 1)', fill: 'both' }
  );
  // 线在打开的同时淡掉 —— 它不是"被擦掉"，而是"变成了打开这件事本身"。
  SKMotion.animate(parts.line, [{ opacity: 1 }, { opacity: 0 }], {
    duration: lineFade,
    delay: delay + Math.max(0, duration - lineFade - 60),
    ease: 'cubic-bezier(0.4, 0, 0.6, 1)',
    fill: 'both',
  });
  return duration * 1.06 + 40;
}

/** 跳过启动时用：直接落到位（世界完全揭开、线已消失）。 */
export function worldSettle(parts) {
  for (const a of [parts.curtainTop, parts.curtainBottom, parts.line]) {
    for (const anim of a.getAnimations?.() ?? []) anim.cancel();
  }
  parts.curtainTop.style.height = '0%';
  parts.curtainBottom.style.height = '0%';
  parts.line.style.opacity = '0';
  parts.line.style.transform = 'scaleX(1)';
}

/** 启动还没开始 / 还没结束时的样子：世界全黑 + 线未写。 */
export function worldHide(parts) {
  parts.curtainTop.style.height = '50%';
  parts.curtainBottom.style.height = '50%';
  parts.line.style.opacity = '1';
  parts.line.style.transform = 'scaleX(0)';
}

/* ---------------------------------------------------------------------------
   压暗 —— 唯一的"功能性叠加层"
   ------------------------------------------------------------------------ */

export function setScrim(parts, to, { duration = 240, delay = 0 } = {}) {
  return SKMotion.animate(parts.scrim, [{ opacity: 1 }, { opacity: to }], {
    duration,
    delay,
    ease: 'cubic-bezier(0.33, 0, 0.67, 1)',
    fill: 'both',
  });
}

/* ---------------------------------------------------------------------------
   进入世界 / 退出世界
   ------------------------------------------------------------------------ */

/**
 * 把世界推到"世界帧"。这是进入世界最后一步，也是与 Godot 交接的那一帧。
 *
 * 注意方向：**相机在往里推**，所以画面放大、内容向下走 ——
 * 玩家感觉自己在向前、向下进入刚才看着的那个地方。
 */
export function worldPush(parts, { from = 1, to = 1.055, panY = -0.012, duration = 900, delay = 0 } = {}) {
  return SKMotion.animate(
    parts.push,
    [
      { transform: `scale(${from}) translate3d(0,0,0)` },
      { transform: `scale(${to}) translate3d(0,${(panY * 100).toFixed(3)}%,0)` },
    ],
    { duration, delay, ease: 'cubic-bezier(0.36, 0.00, 0.24, 1)', fill: 'both' }
  );
}

/** 直接把世界摆到指定帧，不播。出片对帧、以及"从游戏回到标题"时用。 */
export function worldSetFrame(parts, frame) {
  parts.push.style.transform = `scale(${frame.scale}) translate3d(0,${(frame.panY * 100).toFixed(3)}%,0)`;
}

/* ---------------------------------------------------------------------------
   进入世界的两件小事（PASS 03）
   ------------------------------------------------------------------------ */

/**
 * §14 的 "world exposure changes"：菜单光是"看着"的光，进入时光抬一档。
 * 一维 brightness、一拍之内、走完即摘 —— 滤镜留在全屏层上是常驻合成开销，
 * 所以 animation finished 后要把 filter 清掉。
 */
export function worldExpose(parts, { to = 1.04, duration = 700, delay = 0 } = {}) {
  // 注意：brightness 的终态由 fill:'both' 保持，交接到 Godot 的世界帧
  // 那一侧由 MenuCamera 的曝光参数承担 —— 滤镜本身不跨交接存活。
  return SKMotion.animate(
    parts.base,
    [{ filter: 'brightness(1)' }, { filter: `brightness(${to})` }],
    { duration, delay, ease: 'cubic-bezier(0.33, 0, 0.67, 1)', fill: 'both' }
  );
}

/**
 * §16：一片雾横过画面，接相机切换。雾走完时已经是玩家相机。
 * 这不是转场特效 —— 它就是这个世界本来就有的雾，只是此刻从镜头前经过。
 * 挂在 drift **外面**（push 层），所以它不随镜头推进缩放，读作"贴着镜头的空气"。
 */
export function worldWipe(parts, { durMs = 1250, fromX = -0.55, toX = 0.55, peak = 0.82, delay = 0 } = {}) {
  return SKMotion.animate(
    parts.wipe,
    [
      { opacity: 0, transform: `translate3d(${(fromX * 100).toFixed(1)}vw,0,0)` },
      { opacity: peak, offset: 0.45 },
      { opacity: 0, transform: `translate3d(${(toX * 100).toFixed(1)}vw,0,0)` },
    ],
    { duration: durMs, delay, ease: 'linear', fill: 'both' }
  );
}
