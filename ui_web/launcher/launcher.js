/* ============================================================================
   SEKAI · LAUNCHER
   ----------------------------------------------------------------------------
   编排顺序（对应 BRIEF §5）：

     Black
      ↓  笔尖触纸（一记短脉动）
     mark 的弧被写出来
      ↓  笔画接上，从缺口飞出
     细几何 / 规则线成形，背景开始移动
      ↓
     SEKAI 逐字写出 → 世界之外 → 金色短线 → Beyond the Written Fate
      ↓
     加载表现（线在写 / 环在画）—— 真实就绪前一直环境循环
      ↓
     ENTER WORLD 展开
      ↓  按下
     幕落：信息层消散 → 字标擦除 → 环境退下 → 标记移到正中央
      ↓  HANDOFF（纯色 + 标记）＝ Godot BootSplash 的第一帧
     Godot

   不做事：不 sleep、不假装进度、不因为启动失败而死循环。
   ========================================================================= */

import { SKTokens } from '../tokens/tokens.js';
import { SKMotion } from '../motion/motion.js';
import { mark, loadingRing } from '../svg/library.js';
import {
  buildSceneBackground,
  animateSceneBackground,
  buildRunes,
  animateRunes,
  fadeSceneBackground,
} from '../components/scene_bg.js';
import { markToCenter } from '../components/mark_motion.js';
import { setupCursor } from '../components/cursor.js';
import { uiCue } from '../components/ui_cue.js';
import { SKHost } from '../host/host.js';
import { SEQUENCE, LOADING, COPY, SEEN_KEY, HANDOFF } from './launcher.config.js';

/* --------------------------------------------------------------------------
   环境 / 调试开关
   ----------------------------------------------------------------------- */
const Q = new URLSearchParams(location.search);
const RENDER = Q.get('render') === '1'; // 逐帧出片模式：不真的启动进程
const FORCE_MODE = Q.get('mode'); // 'full' | 'fast'
const FORCE_READY = Q.get('ready'); // 毫秒；给一个很大的值可复现"卡在环境循环"
const NO_CURSOR = Q.get('cursor') === 'native';

const $ = (id) => document.getElementById(id);
const T = () => ({
  instant: SKTokens.msec('--sk-t-instant'),
  fast: SKTokens.msec('--sk-t-fast'),
  base: SKTokens.msec('--sk-t-base'),
  slow: SKTokens.msec('--sk-t-slow'),
  crawl: SKTokens.msec('--sk-t-crawl'),
});
const EASE = () => ({
  out: SKTokens.ease('--sk-e-out'),
  in: SKTokens.ease('--sk-e-in'),
  io: SKTokens.ease('--sk-e-io'),
  snap: SKTokens.ease('--sk-e-snap'),
  write: SKTokens.ease('--sk-e-write'),
  unfold: SKTokens.ease('--sk-e-unfold'),
  drift: SKTokens.ease('--sk-e-drift'),
});

const S = {
  mode: 'full',
  seq: null,
  ready: false,
  readyAt: Infinity,
  resolvedAt: 0,
  t0: 0,
  skipped: false,
  launching: false,
  exited: false,
  progress: null, // 0..1 真实进度；null = 不可得
  stalledTimer: 0,
  els: {},
};

/* ==========================================================================
   0. 无障碍：把系统偏好落成页面属性
   ========================================================================= */
function applyMotionPreference() {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.documentElement.setAttribute('data-motion', reduced ? 'reduce' : 'full');
  return reduced;
}

/* ==========================================================================
   1. 建立 DOM
   ========================================================================= */
function buildMark() {
  const host = $('mark');
  // 脉动节点必须保留在标记内部 —— 它要跟标记同心，这一点靠结构而不是靠计算。
  host.insertAdjacentHTML('afterbegin', mark({ size: 128, stroke: 1.6, dot: 5 }));
  S.els.mark = host;
  S.els.arc = host.querySelector('.sk-mark__arc');
  S.els.dot = host.querySelector('.sk-mark__dot');
  S.els.pulse = $('pulse');
}

function buildWordmark() {
  const word = $('word');
  word.setAttribute('aria-label', COPY.wordmark);
  word.innerHTML = [...COPY.wordmark]
    .map((ch) => `<span class="sk-letter" aria-hidden="true">${ch}</span>`)
    .join('');
  S.els.letters = [...word.querySelectorAll('.sk-letter')];
  $('wordCN').textContent = COPY.wordmarkCN;
  $('subtitle').textContent = COPY.subtitle;
}

function buildRing() {
  $('ring').innerHTML = loadingRing({ size: 96, r: 42, stroke: 1.5 });
  S.els.ring = $('ring').querySelector('.sk-ring');
  S.els.ringProgress = $('ring').querySelector('.sk-ring__progress');
}

function buildBackgroundRing() {
  // 环境层与规则线都由 components/scene_bg.js 建立 —— Launcher 与主菜单共用。
  S.scene = buildSceneBackground($('scene'), { particles: 22 });
  S.runes = buildRunes($('runes'), { upper: 0.1, lower: 0.88 });
}

function buildActions() {
  const box = $('actions');
  const targets = SKHost.visibleTargets();
  const primary = targets.find((t) => t.primary) || targets[0];
  const dev = targets.filter((t) => t !== primary);

  box.innerHTML = '';

  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'sk-btn sk-btn--primary sk-cut';
  btn.dataset.target = primary.id;
  btn.innerHTML = `<span class="sk-btn__main">${primary.label}</span><span class="sk-btn__sub">${primary.en}</span>`;
  box.appendChild(btn);

  if (dev.length) {
    const row = document.createElement('div');
    row.className = 'sk-actions__dev';
    for (const t of dev) {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'sk-dev-link';
      b.dataset.target = t.id;
      b.innerHTML = `<span>${t.label}</span><span class="sk-meta">${t.en}</span>`;
      row.appendChild(b);
    }
    box.appendChild(row);
  }

  box.querySelectorAll('[data-target]').forEach((el) => {
    el.addEventListener('click', () => launch(el.dataset.target));
  });
  S.els.actions = box;
}

function buildFooter() {
  $('verLine').textContent = `${COPY.version}  ${SKHost.version}  ·  ${SKHost.build}`;
  $('skipCN').textContent = COPY.skip;
  $('skipEN').textContent = COPY.skipEn;
  $('failCN').textContent = COPY.error.cn;
  $('failEN').textContent = COPY.error.en;
  if (SKHost.devMode) $('devBadge').hidden = false;
  $('btnSkip').addEventListener('click', (e) => {
    e.stopPropagation();
    skip();
  });
  $('btnQuit').addEventListener('click', () => SKHost.quit());
  $('btnQuit2').addEventListener('click', () => SKHost.quit());
  $('btnRetry').addEventListener('click', () => {
    $('failure').hidden = true;
    launch(lastTarget);
  });
}

/* ==========================================================================
   2. 环境层
   --------------------------------------------------------------------------
   实现在 components/scene_bg.js，与主菜单共用。这里只提供时间表。
   ========================================================================= */
function buildAmbient(delay) {
  animateSceneBackground(S.scene, { delay, particles: 22, ringSpin: 240000 });
  animateRunes(S.runes, S.seq.runes ? { delay: S.seq.beats.runes, opacity: 0.1 } : { delay: 0, duration: 160, opacity: 0.1 });
}

/* ==========================================================================
   3. 演出
   ========================================================================= */
function buildSequence() {
  const seq = S.seq;
  const b = seq.beats;
  const d = seq.dur;
  const E = EASE();
  const els = S.els;

  /* --- 3.1 笔尖落纸 --------------------------------------------------- */
  if (els.pulse) {
    SKMotion.animate(
      els.pulse,
      [
        { height: '0px', opacity: 0 },
        { height: '26px', opacity: 0.9, offset: 0.3 },
        { height: '26px', opacity: 0.4, offset: 0.62 },
        { height: '0px', opacity: 0 },
      ],
      { duration: d.pulse, delay: b.pulse, ease: E.write, fill: 'both' }
    );
  }

  /* --- 3.2 标记：点落下，然后环绕着它被写出来 --------------------------- */
  // 点的落下不是淡入，是"从无到有地收拢" —— 读作一滴墨落定。
  SKMotion.animate(
    els.dot,
    [
      { transform: 'scale(0.2)', opacity: 0 },
      { transform: 'scale(1.35)', opacity: 1, offset: 0.55 },
      { transform: 'scale(1)', opacity: 1 },
    ],
    { duration: d.dot, delay: b.dot, ease: E.snap, fill: 'both' }
  );
  SKMotion.write(els.arc, { duration: d.markArc, delay: b.markArc, ease: E.write });

  /* --- 3.3 细几何由 animateRunes() 处理（buildAmbient 里） ------------- */

  /* --- 3.4 字标 ------------------------------------------------------- */
  els.letters.forEach((el, i) => {
    SKMotion.animate(el, [{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0% 0 0)' }], {
      duration: d.letter,
      delay: b.wordmark + i * d.letterStagger,
      ease: E.write,
      fill: 'both',
    });
  });

  // 中文名：整块 mask 拉开
  SKMotion.animate($('wordCN'), [{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0% 0 0)' }], {
    duration: d.wordmarkCN,
    delay: b.wordmarkCN,
    ease: E.write,
    fill: 'both',
  });

  // 金色短线：这一整套 UI 唯一允许的纯装饰
  SKMotion.animate($('rule'), [{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0% 0 0)' }], {
    duration: d.rule,
    delay: b.rule,
    ease: E.write,
    fill: 'both',
  });

  // 副标题：字距从很宽收到正常，读作"落定"
  const wide = SKTokens.get('--sk-track-wide') || '0.26em';
  SKMotion.animate(
    $('subtitle'),
    [
      { opacity: 0, letterSpacing: '0.52em' },
      { opacity: 1, letterSpacing: wide },
    ],
    { duration: d.subtitle, delay: b.subtitle, ease: E.out, fill: 'both' }
  );

  // 标题完成后极小的呼吸。幅度 2px —— 看久了才发现。
  SKMotion.breathe($('word'), { amp: 2, duration: SKTokens.msec('--sk-t-breathe') });
}

/* ==========================================================================
   4. 加载表现
   ========================================================================= */
function startLoading() {
  const seq = S.seq;
  const E = EASE();
  const els = S.els;
  const labels = LOADING.labels;

  $('loadCN').textContent = labels.writing.cn;
  $('loadEN').textContent = labels.writing.en;

  SKMotion.animate($('status'), [{ opacity: 0 }, { opacity: 1 }], {
    duration: seq.dur.loadingIn,
    delay: seq.beats.loading,
    ease: E.out,
    fill: 'both',
  });

  // 环：缓慢自转，永远在动（不表示进度，只表示"还在"）
  SKMotion.drift(els.ring, { rotate: 360, duration: LOADING.ringSpinDuration });

  if (S.progress !== null) {
    setProgress(S.progress);
  } else {
    ambientLine();
    ambientRingBreath();
  }

  // 长时间未就绪：换文案，仍然不显示假数字。
  // 出片模式下不挂真实定时器 —— 否则它会污染逐帧结果。
  if (!RENDER) {
    S.stalledTimer = window.setTimeout(() => {
      if (!S.ready && !S.exited) {
        $('loadCN').textContent = labels.still.cn;
        $('loadEN').textContent = labels.still.en;
      }
    }, seq.beats.loading + LOADING.stalledAfter);
  }
}

/** 环境循环：一笔，一停，再一笔。 */
function ambientLine() {
  const el = $('loadLine');
  const total = LOADING.ambientLineDuration + LOADING.ambientLineGap;
  const holdAt = LOADING.ambientLineDuration / total;
  S.els.lineAnim = SKMotion.animate(
    el,
    [
      { transform: 'translateX(-100%)' },
      { transform: 'translateX(0%)', offset: holdAt },
      { transform: 'translateX(0%)' },
    ],
    {
      duration: total,
      iterations: Infinity,
      ease: 'linear',
      fill: 'none',
      delay: S.seq.beats.loading + 200,
    }
  );
}

/** 没有真实进度时，环上的弧自己慢慢地涨落。 */
function ambientRingBreath() {
  S.els.ringAnim = SKMotion.animate(
    S.els.ringProgress,
    [
      { strokeDasharray: '0.04 1' },
      { strokeDasharray: '0.2 1' },
      { strokeDasharray: '0.04 1' },
    ],
    {
      duration: 9000,
      iterations: Infinity,
      ease: 'cubic-bezier(0.42,0,0.58,1)',
      fill: 'none',
    }
  );
}

/**
 * 真实进度（0..1）。它影响的是"线写到哪、环画到哪"，不是显示一个百分数。
 * 宿主拿不到进度时这个方法永远不会被调用 —— 那就是环境循环。
 */
function setProgress(p) {
  S.progress = Math.max(0, Math.min(1, p));
  const els = S.els;

  if (els.lineAnim) {
    els.lineAnim.cancel();
    els.lineAnim = null;
  }
  if (els.ringAnim) {
    els.ringAnim.cancel();
    els.ringAnim = null;
  }

  // translateX(-100%) 是空，translateX(0) 是写满。直接按住，不补间 ——
  // 进度本来就是离散上报的，再补一层缓动只会让它看起来更假。
  els.lineAnim = SKMotion.animate($('loadLine'), [{ transform: `translateX(${-100 + S.progress * 100}%)` }], {
    duration: 1,
    fill: 'both',
  });
  els.ringProgress.setAttribute('stroke-dasharray', `${Math.max(0.02, S.progress)} 1`);

  if (S.progress >= 1) {
    $('loadCN').textContent = LOADING.labels.ready.cn;
    $('loadEN').textContent = LOADING.labels.ready.en;
  }
}

/* ==========================================================================
   5. 就绪与行动
   ========================================================================= */
/**
 * 门打开。
 * 关键：行动区的出现**必须**是一组带 delay 的 WAAPI 动画，不能用 setTimeout。
 * 否则逐帧出片时会因为"真实时间早就过去了"而提前出现在第一帧。
 */
function revealActions(delay = 0) {
  if (S.els.actionsRevealed || S.exited) return;
  S.els.actionsRevealed = true;
  const E = EASE();

  const primary = S.els.actions.querySelector('.sk-btn--primary');
  const dev = [...S.els.actions.querySelectorAll('.sk-dev-link')];
  const box = S.els.actions.querySelector('.sk-actions__dev');

  // UNFOLD：从左侧展开。不是淡入，不是放大。
  SKMotion.unfold([primary], {
    duration: 480,
    delay,
    ease: E.unfold,
    axis: 'x',
    origin: 'left',
    radius: '2px',
  });

  if (box) {
    SKMotion.converge([box], { duration: 420, delay: delay + 180, from: 12, angle: 0, ease: E.out });
  }
  dev.forEach((el, i) => {
    SKMotion.converge([el], { duration: 300, delay: delay + 260 + i * 70, from: 8, angle: 0, ease: E.out });
  });

  // 焦点提示退场（用动画而不是 hidden，出片时才是可 seek 的）
  const skipEl = $('btnSkip');
  const fade = SKMotion.animate(skipEl, [{ opacity: 1 }, { opacity: 0 }], {
    duration: 320,
    delay: delay + 200,
    ease: E.in,
    fill: 'both',
  });
  skipEl.style.pointerEvents = 'none';
  if (fade && !RENDER) fade.addEventListener('finish', () => (skipEl.hidden = true), { once: true });
  else if (!fade) skipEl.hidden = true;

  if (!RENDER && primary) {
    window.setTimeout(() => primary.focus({ preventScroll: true }), delay + 60);
  }
}

function becomeReady() {
  if (S.ready) return;
  S.ready = true;
  S.readyAt = performance.now() - S.t0;
  uiCue('ready');
  window.clearTimeout(S.stalledTimer);
  // 已经过安全点 → 立刻开门；否则等演出走到安全点。两者取晚者。
  const wait = Math.max(0, S.seq.beats.resolved - S.readyAt);
  window.setTimeout(() => revealActions(0), wait);
}

function showSkipHint() {
  const el = $('btnSkip');
  el.hidden = false;
  SKMotion.animate(el, [{ opacity: 0 }, { opacity: 1 }], {
    duration: T().slow,
    delay: S.seq.beats.skipHint,
    ease: EASE().out,
    fill: 'both',
  });
}

/* ==========================================================================
   6. SKIP
   ========================================================================= */
function skip() {
  if (S.skipped || S.exited) return;
  S.skipped = true;
  S.t0 = performance.now();

  // 把所有一次性演出按到终态。无限循环（环境层）不动。
  for (const a of SKMotion.allAnimations()) {
    try {
      if (a.effect.getTiming().iterations === Infinity) continue;
      a.finish();
    } catch (_) {
      /* 某些动画不可 finish，忽略 */
    }
  }
  // 环境层的最低可见度也要补上，否则 skip 后画面是空的
  S.runes.hairs.forEach((el) => (el.style.opacity = '0.1'));
  S.runes.mark.style.opacity = '0.5';
  S.runes.ticks.style.opacity = '0.32';
  S.scene.ring.style.opacity = '1';

  if (S.ready) revealActions();
  else $('loadCN').textContent = LOADING.labels.still.cn;
}

/* ==========================================================================
   7. 幕落 —— 退出转场。终点是 HANDOFF 那一帧。
   ========================================================================= */
function scheduleExit(startAt) {
  const E = EASE();
  const els = S.els;
  S.exited = true;

  const infos = [
    $('wordCN'),
    $('subtitle'),
    $('rule'),
    $('word'),
    $('status'),
    els.actions,
    document.querySelector('.sk-footer'),
  ].filter(Boolean);

  // 1. 信息层：擦除，不是淡出
  SKMotion.dissolve(infos, { duration: 300, delay: startAt, stagger: 55, ease: E.in, fragment: true });

  // 2. 字标逐字被擦掉（从右往左）
  SKMotion.dissolve([...els.letters].reverse(), {
    duration: 240,
    delay: startAt + 60,
    stagger: 30,
    ease: E.in,
    dir: 'up',
  });

  // 3. 环境退下。最终只剩纯色 —— 这就是 HANDOFF.bg
  fadeSceneBackground(S.scene, S.runes, { delay: startAt });

  // 4. 标记归位：移到**屏幕正中**，尺寸不变。
  //    尺寸不变是有意的 —— Godot 只要按同一个比例画同一个标记就能接上。
  markToCenter(els.mark, { delay: startAt + 260, duration: 760 });

  return startAt + 260 + 760 + HANDOFF.holdMs;
}

/* ==========================================================================
   8. 启动
   ========================================================================= */
let lastTarget = 'main';

async function launch(targetId) {
  if (S.launching || !S.ready) return;
  S.launching = true;
  lastTarget = targetId || 'main';
  uiCue('start', { id: lastTarget });

  const startAt = 0; // 相对当前时刻
  const doneAt = scheduleExit(startAt);

  if (RENDER) {
    // 出片模式：只播转场，不拉起任何进程。
    // 不修改页脚 —— 预览视频里出现的每一件东西都应该是真实游戏里会出现的东西。
    return;
  }

  window.setTimeout(async () => {
    const res = await SKHost.launch(lastTarget);
    if (!res.ok) {
      S.launching = false;
      S.exited = false;
      showFailure(res.error, res.detail, lastTarget);
    }
    // ok 的话宿主会关掉这个窗口并拉起 Godot —— 这里不需要再做任何事。
  }, doneAt - 80);
}

function showFailure(error, detail, target) {
  const box = $('failure');
  box.hidden = false;
  const dev = SKHost.devMode;
  $('failDetail').hidden = !dev;
  $('failDetail').textContent = dev
    ? `target: ${target}\nhost: ${SKHost.mode}\ngodot: ${SKHost.config.godot || '—'}\nproject: ${SKHost.config.project || '—'}\n\n${error || 'unknown'}${detail ? `\n${detail}` : ''}`
    : '';
  SKMotion.animate(box, [{ opacity: 0 }, { opacity: 1 }], { duration: 240, ease: EASE().out, fill: 'both' });
}

/* ==========================================================================
   10. 输入
   ========================================================================= */
function setupInput() {
  const anything = (e) => {
    if (S.exited) return;
    if (e.type === 'keydown' && e.key === 'Tab') return; // 让 Tab 去走焦点
    if (S.els.actionsRevealed && (e.target.closest?.('.sk-btn, .sk-quiet, .sk-dev-link'))) return;
    skip();
  };

  window.addEventListener('keydown', anything);
  window.addEventListener('mousedown', anything, { capture: true });
}

/* ==========================================================================
   11. 主流程
   ========================================================================= */
async function main() {
  applyMotionPreference();
  // 出片模式：状态动画改为挂页面时间轴，而不是按真实时钟播放。
  SKMotion.setRenderMode(RENDER);
  // ?host=1 由桌面宿主自己加上。没有它 = 浏览器 / 出片，绝不发起宿主请求。
  await SKHost.init({ hostParam: Q.get('host') === '1' });

  // 查询串覆盖：出片 / 评审时能强制看到"正式玩家视角"或"完整演出"
  if (Q.get('dev') === '0') SKHost.config.devMode = false;
  if (Q.get('dev') === '1') SKHost.config.devMode = true;
  if (Q.get('motion') === 'reduce') document.documentElement.setAttribute('data-motion', 'reduce');
  if (Q.get('motion') === 'full') document.documentElement.setAttribute('data-motion', 'full');

  // 首次启动 → 完整演出；之后 → 快板。SKIP 过也算"看过"。
  let seen = false;
  try {
    seen = localStorage.getItem(SEEN_KEY) === '1';
  } catch (_) {
    seen = false;
  }
  S.mode = FORCE_MODE === 'fast' || (!FORCE_MODE && seen) ? 'fast' : 'full';
  S.seq = SEQUENCE[S.mode];

  buildMark();
  buildWordmark();
  buildRing();
  buildBackgroundRing();
  buildActions();
  buildFooter();
  setupCursor($('cursor'), { disabled: NO_CURSOR || RENDER });

  const readyAt = FORCE_READY !== null ? Number(FORCE_READY) : RENDER ? 0 : null;
  if (readyAt !== null) {
    // 出片 / 强制就绪：门开的时间点也要是**动画的 delay**，不能是定时器。
    S.ready = true;
    S.readyAt = readyAt;
    revealActions(Math.max(0, S.seq.beats.resolved - readyAt));
  }

  S.t0 = performance.now();
  uiCue('startup', { mode: S.mode });
  buildAmbient(S.seq.beats.bgMove);
  buildSequence();
  startLoading();
  showSkipHint();
  setupInput();

  // 预检：Godot 是否真的在。失败也不进死循环 —— 直接给克制的错误。
  if (readyAt === null) {
    const pre = await SKHost.preflight();
    if (pre && pre.ok) {
      becomeReady();
    } else {
      showFailure(pre.error || 'preflight failed', pre.detail, 'main');
    }
  }

  if (S.mode === 'fast') {
    try {
      localStorage.setItem(SEEN_KEY, '1');
    } catch (_) {
      /* 隐私模式忽略 */
    }
  }

  /* 出片接口：把整页推到任意毫秒。 */
  window.SKLauncher = {
    state: S,
    seq: S.seq,
    skip,
    launch,
    setProgress,
    revealActions,
    /** 出片模式专用：在指定时间点开始幕落，返回整段结束时刻 */
    scheduleExit,
    HANDOFF,
    /** 宿主句柄。评审和 harness 需要能问出"现在到底是 native 还是 web" ——
        这个问题的答案决定了"点进去会不会真的拉起 Godot"。 */
    host: SKHost,
    /** 供 harness 判断总长度 */
    totalMs: RENDER ? S.seq.beats.resolved + 2400 : Infinity,
  };
  document.documentElement.dataset.ready = '1';
}

main();
