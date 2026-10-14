/* ============================================================================
   SEKAI · MOTION KIT
   ----------------------------------------------------------------------------
   四种运动语言的唯一执行层（见 docs/ui/MOTION_LANGUAGE.md）：
     A · WRITE     线条被写出来        write()
     B · CONVERGE  元素向一点聚合      converge()
     C · UNFOLD    几何从中心展开      unfold()
     D · DISSOLVE  退出不是 fade       dissolve()
   外加三种环境循环：drift() / breathe() / particle()

   三条硬规则：
   1. 全部走 Web Animations API。不用 CSS `animation` 声明做一次性演出
      —— 因为 render harness 需要 `pause()` + `currentTime = t` 才能逐帧出片。
   2. 时长与缓动只能来自 tokens.css，本文件不写裸数字。
   3. prefers-reduced-motion 或 [data-motion="reduce"] 时，一次性演出直达终态，
      环境循环不启动。信息不依赖动画可读。
   ========================================================================= */

import { SKTokens, motionTokens } from '../tokens/tokens.js';

const T = motionTokens();

/** 注册表：所有本 kit 创建的动画，供 render harness 统一冻结 / seek */
const registry = new Set();

function track(anim) {
  registry.add(anim);
  anim.addEventListener('finish', () => registry.delete(anim), { once: true });
  anim.addEventListener('cancel', () => registry.delete(anim), { once: true });
  return anim;
}

/* ---------------------------------------------------------------------------
   降级：读取 reduced 状态
   ------------------------------------------------------------------------ */
let _reducedOverride = null;

/**
 * 出片模式开关。
 * 打开后，状态动画不再按真实时钟播放，而是等待被挂到页面时间轴上，
 * 这样逐帧出片才能把它们算进去（否则焦点线在验收视频里永远不出现）。
 * 页面在解析到 ?render=1 时自行打开 —— 必须在 boot 之前，因为 boot 期间
 * 就会触发一次焦点。
 */
let _renderMode = false;

function prefersReduced() {
  if (_reducedOverride !== null) return _reducedOverride;
  const attr = document.documentElement.getAttribute('data-motion');
  if (attr === 'reduce') return true;
  if (attr === 'full') return false;
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}

/* ---------------------------------------------------------------------------
   normalizeStroke —— 让任意 SVG 几何都能用统一的 0..1 进度书写
   pathLength=1 之后，dasharray = 1 就是"整条线"，dashoffset 1 -> 0 就是写出来。
   这是整套 UI 不用为每个路径量长度就获得可控书写的关键。
   ------------------------------------------------------------------------ */
export function normalizeStroke(el) {
  if (!el) return el;
  if (el.hasAttribute('pathLength')) return el;
  const tag = (el.tagName || '').toLowerCase();
  if (['path', 'line', 'polyline', 'polygon', 'circle', 'ellipse', 'rect'].includes(tag)) {
    el.setAttribute('pathLength', '1');
  }
  return el;
}

/** 一个元素或一组元素 -> 数组。同时展平 NodeList / querySelectorAll 结果。 */
function toArray(target) {
  if (!target) return [];
  if (typeof target === 'string') return Array.from(document.querySelectorAll(target));
  if (target instanceof Element) return [target];
  if (target[Symbol.iterator]) return Array.from(target);
  return [];
}

/* ============================================================================
   核心：animate —— 所有运动的唯一出口
   ========================================================================= */
function animate(el, keyframes, opts = {}) {
  // 传数组进来必须**当场喊**，不能顺着往下走。
  // 这个错很难查：异常在 motion.js 里抛出，调用点在页面里；而且它只炸那一次调用，
  // 前面几拍照常播 —— 于是症状是"启动播了一半就停住"，看起来像时间轴写错了。
  // Launcher 的 playIntro 就是这样死的：弧、点、门缝、「进入」都出来了，
  // 到左下那行（唯一一次多元素调用）整条链断掉，页面连 ready 都没发。
  if (Array.isArray(el)) {
    throw new TypeError(
      'SKMotion.animate() 只接受单个元素，收到数组。多元素请用 SKMotion.animateAll()。'
    );
  }

  const {
    duration = T.t.base,
    delay = 0,
    ease = T.e.out,
    fill = 'both',
    iterations = 1,
    composite,
  } = opts;

  if (prefersReduced() && iterations === 1) {
    // 直达终态，不播。
    const last = Array.isArray(keyframes) ? keyframes[keyframes.length - 1] : keyframes;
    applyFinal(el, last);
    return null;
  }

  const a = el.animate(keyframes, { duration, delay, easing: ease, fill, iterations, composite });
  return track(a);
}

/**
 * 多元素版本 —— 把同一个补间施加到一组元素上。
 *
 * 返回 **Animation 数组**（不是单个），所以可以直接 spread 进 bootAnims：
 *     A.push(...SKMotion.animateAll([a, b, c], frames, opts))
 * 这样 skipIntro() 里的 `for (const a of S.bootAnims) a.finish()` 继续有效 ——
 * 它拿到的永远是扁平的一串 Animation，而不是"某一项是数组"。
 */
function animateAll(els, keyframes, opts = {}) {
  return (els || []).filter(Boolean).map((el) => animate(el, keyframes, opts));
}

/** reduced-motion 时把终态直接写进 inline style */
function applyFinal(el, frame) {
  if (!el || !el.style || !frame) return;
  for (const [k, v] of Object.entries(frame)) {
    if (k === 'offset' || k === 'easing' || k === 'composite') continue;
    try {
      el.style[k] = v;
    } catch (_) {
      /* 非标准属性忽略 */
    }
  }
}

/* ============================================================================
   LANGUAGE A · WRITE —— 线条被写出来
   用途：Launcher / 标题 / 地点名 / Lore / 菜单 focus
   ========================================================================= */
function write(target, opts = {}) {
  const {
    duration = T.t.write,
    delay = 0,
    stagger = 0,
    ease = T.e.write,
    reverse = false,
    startAt = 0, // 0..1，从线的哪一段开始写（用于环境线只写一部分）
  } = opts;

  const els = toArray(target);
  const out = [];
  els.forEach((el, i) => {
    normalizeStroke(el);
    // 显式写出 dasharray，避免依赖 CSS 里每个元素都记得设
    if (!el.style.strokeDasharray) el.style.strokeDasharray = '1';
    const from = reverse ? 0 : 1 - startAt;
    const to = reverse ? 1 : 0;
    const a = animate(
      el,
      [
        { strokeDashoffset: String(from), opacity: opts.fadeIn === false ? 1 : 0 },
        { strokeDashoffset: String(to), opacity: 1 },
      ],
      { duration, delay: delay + i * stagger, ease, fill: 'both' }
    );
    // fill:'both' 已经把终态按住，这里只是让静态截图（不播动画时）也正确
    if (a) a.persist = true;
    out.push(a);
  });
  return out;
}

/* ============================================================================
   LANGUAGE B · CONVERGE —— 元素向一点聚合
   用途：选中 / 技能就绪 / Iaido 相关 UI
   元素从外侧略远处 + 略大 / 略小，收拢到本位。
   ========================================================================= */
function converge(target, opts = {}) {
  const {
    duration = T.t.base,
    delay = 0,
    stagger = 0,
    ease = T.e.unfold,
    from = 18, // px，从多远处收拢
    angle = 0, // 收拢来向（弧度）；0 = 从左来
    scaleFrom = 1,
    fade = true,
  } = opts;

  const dx = Math.cos(angle) * from;
  const dy = Math.sin(angle) * from;

  return toArray(target).map((el, i) =>
    animate(
      el,
      [
        {
          transform: `translate(${dx}px, ${dy}px) scale(${scaleFrom})`,
          opacity: fade ? 0 : 1,
        },
        { transform: 'translate(0px, 0px) scale(1)', opacity: 1 },
      ],
      { duration, delay: delay + i * stagger, ease }
    )
  );
}

/** CONVERGE 的反向：向一点收掉（释放选中 / 收起） */
function diverge(target, opts = {}) {
  const {
    duration = T.t.base,
    delay = 0,
    ease = T.e.in,
    to = 14,
    angle = Math.PI,
    fade = true,
  } = opts;
  const dx = Math.cos(angle) * to;
  const dy = Math.sin(angle) * to;
  return toArray(target).map((el, i) =>
    animate(
      el,
      [
        { transform: 'translate(0,0) scale(1)', opacity: 1 },
        { transform: `translate(${dx}px, ${dy}px) scale(0.985)`, opacity: fade ? 0 : 1 },
      ],
      { duration, delay: delay + i * stagger, ease }
    )
  );
}

/* ============================================================================
   LANGUAGE C · UNFOLD —— 几何从中心展开
   用途：Ability Wheel / 子菜单 / 装备
   用 clip-path inset() 展开（不是 scale —— scale 会让描边变粗，一眼假）。
   ========================================================================= */
function unfold(target, opts = {}) {
  const {
    duration = T.t.slow,
    delay = 0,
    stagger = 0,
    ease = T.e.unfold,
    axis = 'both', // 'both' | 'x' | 'y'
    origin = 'center', // 'center' | 'top' | 'bottom' | 'left' | 'right'
    radius = '2px',
  } = opts;

  const closed = insetFor(axis, origin, 'closed', radius);
  const open = insetFor(axis, origin, 'open', radius);

  return toArray(target).map((el, i) =>
    animate(
      el,
      [
        { clipPath: closed, opacity: 0 },
        { clipPath: open, opacity: 1 },
      ],
      { duration, delay: delay + i * stagger, ease }
    )
  );
}

function insetFor(axis, origin, state, radius) {
  if (state === 'open') return `inset(0% round ${radius})`;
  const half = '50%';
  switch (axis) {
    case 'x':
      return origin === 'right' ? `inset(0% 0% 0% 100% round ${radius})` : `inset(0% 100% 0% 0% round ${radius})`;
    case 'y':
      return origin === 'bottom' ? `inset(100% 0% 0% 0% round ${radius})` : `inset(0% 0% 100% 0% round ${radius})`;
    default:
      switch (origin) {
        case 'top':
          return `inset(0% ${half} 100% ${half} round ${radius})`;
        case 'bottom':
          return `inset(100% ${half} 0% ${half} round ${radius})`;
        case 'left':
          return `inset(${half} 100% ${half} 0% round ${radius})`;
        case 'right':
          return `inset(${half} 0% ${half} 100% round ${radius})`;
        default:
          return `inset(${half} ${half} ${half} ${half} round ${radius})`;
      }
  }
}

/** UNFOLD 的反向：从中心收回（Ability Wheel 释放选择后） */
function foldImpl(target, opts = {}) {
  const {
    duration = T.t.slow,
    delay = 0,
    stagger = 0,
    ease = T.e.in,
    axis = 'both',
    origin = 'center',
    radius = '2px',
  } = opts;
  const closed = insetFor(axis, origin, 'closed', radius);
  const open = insetFor(axis, origin, 'open', radius);
  return toArray(target).map((el, i) =>
    animate(el, [{ clipPath: open, opacity: 1 }, { clipPath: closed, opacity: 0 }], {
      duration,
      delay: delay + i * stagger,
      ease,
    })
  );
}

/* ============================================================================
   LANGUAGE D · DISSOLVE —— 退场：线断 / 碎裂 / mask 塌缩
   非常克制。默认是"擦除"（wipe）而不是 fade。
   ========================================================================= */
function dissolve(target, opts = {}) {
  const {
    duration = T.t.base,
    delay = 0,
    stagger = 0,
    ease = T.e.in,
    dir = 'right', // 擦除方向：线往哪边消失
    fragment = false, // 是否叠一层轻微位移，读作"碎裂"
  } = opts;

  return toArray(target).map((el, i) => {
    const wipe = {
      left: 'inset(0% 100% 0% 0%)',
      right: 'inset(0% 0% 0% 100%)',
      up: 'inset(100% 0% 0% 0%)',
      down: 'inset(0% 0% 100% 0%)',
    }[dir] || 'inset(0% 0% 0% 100%)';

    const shift = fragment ? (dir === 'left' || dir === 'up' ? -3 : 3) : 0;
    const frames = [
      { clipPath: 'inset(0% 0% 0% 0%)', opacity: 1, transform: 'translate(0,0)' },
      {
        clipPath: wipe,
        opacity: 0,
        transform: `translate(${dir === 'left' || dir === 'right' ? shift : 0}px, ${
          dir === 'up' || dir === 'down' ? shift : 0
        }px)`,
      },
    ];
    return animate(el, frames, { duration, delay: delay + i * stagger, ease });
  });
}

/** DISSOLVE 用于线条：把线"擦掉"（dashoffset 反向走） */
function unwrite(target, opts = {}) {
  const { duration = T.t.base, delay = 0, stagger = 0, ease = T.e.in, from = 0 } = opts;
  return toArray(target).map((el, i) => {
    normalizeStroke(el);
    if (!el.style.strokeDasharray) el.style.strokeDasharray = '1';
    return animate(
      el,
      [
        { strokeDashoffset: from, opacity: 1 },
        { strokeDashoffset: 1, opacity: 0 },
      ],
      { duration, delay: delay + i * stagger, ease }
    );
  });
}

/* ============================================================================
   文本揭示：mask 从左到右拉开（wordmark 用）
   不是打字机。是一个 mask 被"写"过去。
   ========================================================================= */
function revealMask(target, opts = {}) {
  const {
    duration = T.t.crawl,
    delay = 0,
    stagger = 0,
    ease = T.e.write,
    dir = 'right',
    fade = false,
  } = opts;
  const hidden = {
    right: 'inset(0% 100% 0% 0%)',
    left: 'inset(0% 0% 0% 100%)',
    up: 'inset(100% 0% 0% 0%)',
    down: 'inset(0% 0% 100% 0%)',
  }[dir];
  return toArray(target).map((el, i) =>
    animate(
      el,
      [
        { clipPath: hidden, opacity: fade ? 0 : 1 },
        { clipPath: 'inset(0% 0% 0% 0%)', opacity: 1 },
      ],
      { duration, delay: delay + i * stagger, ease }
    )
  );
}

/* ============================================================================
   STATE ANIM —— 持久状态的双向动画
   ----------------------------------------------------------------------------
   hover / focus / 选中这类**状态**必须可被随时打断并反向（BRIEF §30：
   漂亮动画不能让 UI 变慢）。用 play/reverse 控制一条一次性建好的动画，
   比每次事件都新建/取消更可靠，也不会留下回弹。

   两条路径，取决于是否在出片（RENDER）：
   - 真实交互：on()/off() 直接改 playbackRate 播放。立刻响应、可打断、可反向。
   - 逐帧出片：不能按真实时钟走（那就不是确定性的了）。改为把这次状态变化
     挂到**页面时间轴**的某一毫秒上（`at`），或标脏等 adoptAt() 认领，
     之后由 seekAll() 求值。

   为什么必须这样：如果状态动画完全不参与 seek，那么"焦点线被写出来"这件事
   在验收视频里永远不会出现 —— 而它正是四种运动语言里最常出现的一种。
   ========================================================================= */
function stateAnim(el, keyframes, opts = {}) {
  // 状态动画不使用 delay：它的语义是"从现在这个值走到那个值"，
  // 一个空转的 delay 会让 currentTime 与进度不再线性对应。
  const a = animate(el, keyframes, { ...opts, delay: 0, fill: 'both' });

  if (!a) {
    // reduced-motion：没有动画对象，on/off 直接写终态
    return {
      anim: null,
      on: () => applyFinal(el, keyframes[keyframes.length - 1]),
      off: () => applyFinal(el, keyframes[0]),
      jump: (on) => applyFinal(el, on ? keyframes[keyframes.length - 1] : keyframes[0]),
      current: 0,
    };
  }

  a._skState = true;
  a._skDur = Number(a.effect.getTiming().duration) || 0;
  a._skWant = 0; // 目标：0 = off，1 = on
  a._skDirty = false; // 自上次 adoptAt 以来目标是否变过
  a.pause();
  a.currentTime = 0;

  /** 把这次变化挂到页面时间轴的 at 毫秒上，并从"此刻的值"开始走 */
  function snap(at) {
    a._skDirty = false;
    a._skOrigin = at;
    a._skFrom = Number(a.currentTime) || 0;
    a._skTo = a._skWant ? a._skDur : 0;
    a.pause();
  }

  /**
   * @param {boolean} v    目标状态
   * @param {number} [at]  页面时间轴毫秒位置。给定时这次变化属于演出的第 at 毫秒；
   *                       不给时（真实交互 / 脚本化事件）在 RENDER 下先标脏，
   *                       等 harness 的 adoptAt() 认领到它实际发生的时刻。
   */
  function setWant(v, at) {
    const want = v ? 1 : 0;
    if (want === a._skWant) return;
    a._skWant = want;

    if (_renderMode) {
      if (typeof at === 'number') snap(at);
      else a._skDirty = true;
      return;
    }

    // 真实交互：立刻按方向播。可打断、可反向，不回弹（§30）
    a.playbackRate = want ? 1 : -1;
    if (want && Number(a.currentTime) >= a._skDur) a.currentTime = 0;
    if (!want && Number(a.currentTime) <= 0) a.currentTime = a._skDur;
    a.play();
  }

  return {
    anim: a,
    get current() {
      return Number(a.currentTime) || 0;
    },
    /** @param {number} [at] 见 setWant */
    on(at) {
      setWant(1, at);
    },
    off(at) {
      setWant(0, at);
    },
    /** 不播，直接到位 */
    jump(on) {
      a.pause();
      a.playbackRate = 1;
      a.currentTime = on ? a._skDur : 0;
      a._skWant = on ? 1 : 0;
      a._skDirty = false;
      a._skOrigin = undefined;
    },
  };
}

/* ============================================================================
   状态反馈（§30：UI 永远优先响应）
   按下 / hover 必须立刻到达，即使完整转场还没结束。
   ========================================================================= */
function press(el, opts = {}) {
  const { depth = 1 } = opts;
  return animate(
    el,
    [{ transform: 'translateY(0)' }, { transform: `translateY(${depth}px)` }, { transform: 'translateY(0)' }],
    { duration: T.t.instant * 2, ease: T.e.snap, fill: 'none' }
  );
}

/** 一次极短的"脉动"—— Launcher 开场那一下，或技能就绪 */
function pulse(target, opts = {}) {
  const {
    duration = T.t.slow,
    delay = 0,
    ease = T.e.out,
    property = 'opacity',
    peak = 1,
    rest = 0,
  } = opts;
  return toArray(target).map((el, i) =>
    animate(
      el,
      [{ [property]: rest }, { [property]: peak, offset: 0.18 }, { [property]: rest }],
      { duration, delay: delay + i * 0, ease, fill: 'both' }
    )
  );
}

/* ============================================================================
   AMBIENT —— 环境循环。一定慢。不允许出现在"会分散注意力"的地方。
   ========================================================================= */

/** 漂移：雾 / 环 / 云。绕一圈回到原位，用线性以免有接缝感。 */
function drift(target, opts = {}) {
  const {
    dx = 0,
    dy = 0,
    scale = 1,
    rotate = 0,
    duration = T.t.drift,
    delay = 0,
    ease = T.e.drift,
  } = opts;
  return toArray(target).map((el) =>
    animate(
      el,
      [
        { transform: 'translate(0px,0px) scale(1) rotate(0deg)' },
        { transform: `translate(${dx}px,${dy}px) scale(${scale}) rotate(${rotate}deg)` },
        { transform: 'translate(0px,0px) scale(1) rotate(0deg)' },
      ],
      { duration, delay, ease, iterations: Infinity, fill: 'none' }
    )
  );
}

/** 呼吸：标题微浮。幅度必须小到"看久了才发现"。 */
function breathe(target, opts = {}) {
  const { amp = 3, duration = T.t.breathe, delay = 0, rotate = 0 } = opts;
  return toArray(target).map((el) =>
    animate(
      el,
      [
        { transform: 'translateY(0px)' },
        { transform: `translateY(-${amp}px)` },
        { transform: 'translateY(0px)' },
      ],
      { duration, delay, ease: 'cubic-bezier(0.42,0,0.58,1)', iterations: Infinity, fill: 'none' }
    )
  );
}

/** 粒子：缓慢上浮的极小点。density 由页面决定，行为在这里。 */
function particles(container, opts = {}) {
  const {
    count = 18,
    size = [1, 2.2],
    rise = [180, 420],
    duration = [26000, 52000],
    delayMax = 0,
    opacity = [0.06, 0.2],
    color = 'var(--sk-text-2)',
  } = opts;

  const nodes = [];
  for (let i = 0; i < count; i++) {
    const dot = document.createElement('i');
    dot.className = 'sk-particle';
    const s = rnd(size);
    const x = Math.random() * 100;
    const y = 100 + Math.random() * 40;
    dot.style.cssText = [
      `width:${s}px`,
      `height:${s}px`,
      `left:${x}%`,
      `top:${y}%`,
      `background:${color}`,
      `opacity:0`,
    ].join(';');
    container.appendChild(dot);
    nodes.push(dot);

    const dur = rnd(duration);
    const travel = rnd(rise);
    const a = rnd(opacity);
    animate(
      dot,
      [
        { transform: 'translate(0,0)', opacity: 0 },
        { opacity: a, offset: 0.15 },
        { opacity: a * 0.5, offset: 0.7 },
        { transform: `translate(${(Math.random() - 0.5) * 40}px, -${travel}px)`, opacity: 0 },
      ],
      {
        duration: dur,
        delay: Math.random() * (delayMax || dur * 0.8),
        ease: 'linear',
        iterations: Infinity,
        fill: 'none',
      }
    );
  }
  return nodes;
}

function rnd(v) {
  if (Array.isArray(v)) return v[0] + Math.random() * (v[1] - v[0]);
  return v;
}

/* ============================================================================
   STAGGER —— 级联
   ========================================================================= */
function stagger(target, factory, opts = {}) {
  const { step = T.stagger, delay = 0 } = opts;
  return toArray(target).map((el, i) => factory(el, i, delay + i * step));
}

/* ============================================================================
   RENDER HARNESS 接口
   ----------------------------------------------------------------------------
   动效不能只截图验收。逐帧出片的做法：
     1. SKMotion.freezeAll()   把所有动画归零到同一时间原点并暂停
     2. SKMotion.seekAll(t)    把整页推到 t 毫秒
     3. puppeteer 截一帧       -> frame_%05d.png
     4. ffmpeg 编码            -> *.mp4
   这样出片是完全确定性的，与真实帧率无关。

   为什么需要 _skOrigin：
   退出转场是在"玩家按下 ENTER WORLD 的那一刻"才创建的动画，它的 delay 是相对
   那一刻的。如果直接 startTime = 0，它就会被错误地按"页面开始"计量。
   所以每个动画记一个 _skOrigin（它属于页面时间轴的哪一刻），最后统一换算。
   ========================================================================= */
function collect() {
  const doc = typeof document.getAnimations === 'function' ? document.getAnimations() : [];
  return new Set([...doc, ...registry]);
}

/** 只遍历**演出**动画（状态动画单独处理，见 adoptAt / seekAll） */
function eachAnimation(fn) {
  const set = collect();
  for (const a of set) {
    if (a._skState) continue;
    fn(a);
  }
  return set.size;
}

/** 把所有**当前已存在**的动画钉在 t=0 原点并暂停 */
function freezeAll() {
  let n = 0;
  eachAnimation((a) => {
    if (a._skOrigin === undefined) a._skOrigin = 0;
    try {
      a.pause();
      a.startTime = 0;
    } catch (_) {
      /* 某些动画不可设 startTime，忽略 */
    }
    n += 1;
  });
  return n;
}

/**
 * 把"之后新建的 / 目标变过的"动画认领到页面时间轴的 origin 毫秒处。
 * 按下 ENTER WORLD 之后立刻调用一次，传入按下那一刻的 t。
 *
 * 状态动画只认领 `_skDirty`（目标变过）的那些，并把起点定在它**当时的值**上 ——
 * 这样视频里能看到它被写出来，而不是硬切。
 */
function adoptAt(origin) {
  let n = 0;
  for (const a of collect()) {
    if (a._skState) {
      if (!a._skDirty) continue;
      a._skDirty = false;
      a._skOrigin = origin;
      a._skFrom = Number(a.currentTime) || 0;
      a._skTo = a._skWant ? a._skDur : 0;
      a.pause();
      n += 1;
      continue;
    }
    if (a._skOrigin !== undefined) continue;
    a._skOrigin = origin;
    try {
      a.pause();
      a.startTime = 0;
    } catch (_) {
      /* ignore */
    }
    n += 1;
  }
  return n;
}

/** 把整页推到 ms 毫秒 */
function seekAll(ms) {
  for (const a of collect()) {
    if (a._skState) {
      // 从未被触发过 -> 保持初态，不参与时间轴
      if (a._skOrigin === undefined) continue;
      const from = Number(a._skFrom) || 0;
      const to = a._skTo === undefined ? from : Number(a._skTo);
      const span = Math.abs(to - from);
      const local = span === 0 ? 0 : Math.min(span, Math.max(0, ms - a._skOrigin));
      try {
        a.currentTime = to >= from ? from + local : from - local;
      } catch (_) {
        /* ignore */
      }
      continue;
    }
    if (a._skOrigin === undefined) a._skOrigin = 0;
    try {
      a.startTime = 0;
      a.pause();
      a.currentTime = Math.max(0, ms - a._skOrigin);
    } catch (_) {
      /* ignore */
    }
  }
  return ms;
}

function releaseAll() {
  eachAnimation((a) => {
    try {
      a.play();
    } catch (_) {
      /* ignore */
    }
  });
}

function setRenderMode(on) {
  _renderMode = !!on;
}

function animationCount() {
  const doc = typeof document.getAnimations === 'function' ? document.getAnimations() : [];
  return new Set([...doc, ...registry]).size;
}

function listAnimations() {
  const doc = typeof document.getAnimations === 'function' ? document.getAnimations() : [];
  return Array.from(new Set([...doc, ...registry])).filter((a) => !a._skState);
}

function setReduced(flag) {
  _reducedOverride = flag === null ? null : !!flag;
}

/* ============================================================================
   导出
   ========================================================================= */
export const SKMotion = {
  // 语言
  write,
  converge,
  diverge,
  unfold,
  fold: foldImpl,
  dissolve,
  unwrite,
  revealMask,
  // 状态
  stateAnim,
  press,
  pulse,
  // 环境
  drift,
  breathe,
  particles,
  // 工具
  animate,
  animateAll,
  stagger,
  normalizeStroke,
  // 无障碍
  get reduced() {
    return prefersReduced();
  },
  setReduced,
  // render harness
  setRenderMode,
  get renderMode() {
    return _renderMode;
  },
  freezeAll,
  adoptAt,
  seekAll,
  releaseAll,
  allAnimations: listAnimations,
  count: animationCount,
};

if (typeof window !== 'undefined') {
  window.SKMotion = SKMotion;
  window.SKT = T;
}
