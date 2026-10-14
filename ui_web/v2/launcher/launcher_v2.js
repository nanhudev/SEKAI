/* ============================================================================
   SEKAI · LAUNCHER V2 (UI PASS 02 · DE-AI)
   ----------------------------------------------------------------------------
   §6：Launcher 不再是独立品牌网站，它只是 THE DOOR INTO SEKAI。
   §8：理想形态接近一张 splash —— 黑 → 一个很简单的 SEKAI 标记 → 一条门缝 →
        进入。玩家几乎意识不到自己经过了一个 Launcher。

   所以这里**没有**：
     ✗ 载入环 / 进度条 / 状态文案（"真实加载"发生在 Godot 内部，Launcher 不该假装知道）
     ✗ 上下装饰细线与刻度尺
     ✗ 世界漂移背景（那是主菜单的事 —— 把世界揭开放在这里，Launcher 就成了第二个
       标题画面，正是 §6 禁止的）
     ✗ 页脚三行系统信息
     ✗ 中文名与副标题（副标题全片只出现一次，在主菜单）

   留下：标记（写出来的）、一条门缝、「进入」、左下角极小的一行（版本 / 开发模式）。

   退出时它把自己收回到**交接帧**：纯色 + 屏幕正中的标记，除此之外什么都没有。
   那一帧是三个场景共同的合同，定义在 components/handoff.js。
   ========================================================================= */

import { SKMotion } from '../../motion/motion.js';
import { SKTokens } from '../../tokens/tokens.js';
import { SKHost } from '../../host/host.js';
import { mark } from '../../svg/library.js';
import { handoffSizePx } from '../../components/mark_motion.js';
import { setupCursor } from '../../components/cursor.js';
import { uiCue, bindCues } from '../../components/ui_cue.js';
import { createLoading } from '../../components/loading_glyph.js';
import { LAUNCHER, HANDOFF, COPY, KEYART } from '../v2.config.js';

const $ = (id) => document.getElementById(id);
const Q = new URLSearchParams(location.search);
const RENDER = Q.get('render') === '1';
const NO_CURSOR = Q.get('cursor') === 'native';
const SEEN_KEY = 'sekai.v2.launcher.seen';

const S = { els: {}, leaving: false, bootAnims: [], devOpen: false };

let T0 = 0;

function applyMotionPreference() {
  if (Q.get('motion') === 'reduce') SKMotion.setReduced(true);
  document.documentElement.dataset.render = RENDER ? '1' : '0';
}

/**
 * PASS 04 · PART C：Launcher 用与主菜单**同一张** Key Art，
 * 处理成 darker / more cropped / less information —— Launcher → Main Menu
 * 因此自然读成"同一个世界"，而不是从黑屏跳进一张新图。
 *
 * 交接合同不破：launch() 时背景淡到黑 —— 最后一帧仍是 void + 居中标记。
 * 仅当 ?bg= 命中 KEYART 才启用；不传参 Launcher 保持纯黑（原行为不变）。
 */
function buildKeyart() {
  const bgKey = Q.get('bg');
  const src = bgKey ? KEYART[bgKey] : null;
  if (!src) return null;
  const box = $('keyart');
  const img = document.createElement('img');
  img.alt = '';
  img.decoding = 'sync';
  img.src = src;
  box.appendChild(img);
  box.classList.add('is-on');
  S.els.keyart = box;
  return box;
}

/* ---------------------------------------------------------------------------
   组装
   ------------------------------------------------------------------------ */

/** §A1：题签。第一屏三件主要信息里的两件（SEKAI / 副标题）。 */
function buildTitle() {
  const t = $('doorTitle');
  const name = document.createElement('div');
  name.className = 'v2-door__title-name';
  name.textContent = COPY.launcherTitle;
  const sub = document.createElement('div');
  sub.className = 'v2-door__title-sub';
  sub.textContent = COPY.launcherSubtitle;
  t.append(name, sub);
  t.style.opacity = '0';
  S.els.title = t;
}

function buildDoor() {
  const host = $('doorMark');
  host.innerHTML = mark({ size: 128, stroke: 1.6, dot: 5 });
  S.els.arc = host.querySelector('.sk-mark__arc');
  S.els.dot = host.querySelector('.sk-mark__dot');
  S.els.markHost = host;

  const seam = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  seam.setAttribute('class', 'v2-door__seam');
  seam.setAttribute('viewBox', '0 0 100 1');
  seam.setAttribute('preserveAspectRatio', 'none');
  seam.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', 'M0 0.5 H100');
  path.setAttribute('pathLength', '1');
  seam.appendChild(path);
  S.els.seam = seam;
  S.els.seamPath = path;

  const enter = document.createElement('button');
  enter.type = 'button';
  enter.className = 'v2-door__enter';
  enter.dataset.cue = 'confirm';
  enter.textContent = COPY.launcherEnter;
  // §A3：focus line。悬停/聚焦时 CSS 让它 scaleX(0→1)，不需要 JS。
  const enterLine = document.createElement('span');
  enterLine.className = 'v2-door__enter-line';
  enterLine.setAttribute('aria-hidden', 'true');
  enter.appendChild(enterLine);
  S.els.enter = enter;

  $('doorCol').append(seam, enter);

  // 起始不可见
  S.els.enter.style.opacity = '0';
  S.els.seam.style.opacity = '1';
}

function buildMeta() {
  const meta = $('doorMeta');
  const v = document.createElement('span');
  v.textContent = SKHost.version;
  const sep = document.createElement('span');
  sep.className = 'v2-meta__sep';
  sep.textContent = '/';
  const dev = document.createElement('button');
  dev.type = 'button';
  dev.className = 'v2-meta__btn';
  dev.textContent = COPY.devMode;
  dev.addEventListener('click', () => toggleDev());
  meta.append(v, sep, dev);
  S.els.metaEl = meta;
}

/** §7：Developer Mode 另外打开。正式玩家看到的只有「进入」。 */
function buildDev() {
  const box = $('doorDev');
  const targets = SKHost.visibleTargets().filter((t) => t.dev);
  if (!targets.length) {
    box.remove();
    S.els.dev = null;
    return;
  }
  for (const t of targets) {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'v2-meta__btn';
    b.dataset.id = t.id;
    b.textContent = t.label;
    b.addEventListener('click', () => {
      uiCue('confirm', { id: t.id });
      launch(t.id);
    });
    box.appendChild(b);
  }
  box.hidden = true;
  S.els.dev = box;
}

function toggleDev() {
  if (!S.els.dev) return;
  S.devOpen = !S.devOpen;
  S.els.dev.hidden = !S.devOpen;
  uiCue(S.devOpen ? 'confirm' : 'back');
}

/* ---------------------------------------------------------------------------
   进场 —— 标记被写出来，然后一条门缝划开
   ------------------------------------------------------------------------ */
function playIntro(cfg = LAUNCHER) {
  const b = cfg.beats;
  const d = cfg.dur;
  const A = S.bootAnims;

  // 题签：SEKAI + 副标题先落（§A1）
  A.push(
    SKMotion.animate(S.els.title, [{ opacity: 0 }, { opacity: 1 }], {
      duration: d.title,
      delay: b.title,
      ease: SKTokens.ease('--sk-e-out'),
      fill: 'both',
    })
  );
  // 弧：写出来（§C 的 WRITE 语言）
  A.push(
    SKMotion.animate(S.els.arc, [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], {
      duration: d.markArc,
      delay: b.mark,
      ease: SKTokens.ease('--sk-e-write'),
      fill: 'both',
    })
  );
  // 点：弧走到一半时才落上去
  A.push(
    SKMotion.animate(S.els.dot, [{ transform: 'scale(0.2)' }, { transform: 'scale(1)' }], {
      duration: d.markDot,
      delay: b.mark + Math.round(d.markArc * 0.55),
      ease: SKTokens.ease('--sk-e-snap'),
      fill: 'both',
    })
  );
  // 门缝
  A.push(
    SKMotion.animate(S.els.seamPath, [{ strokeDashoffset: 1 }, { strokeDashoffset: 0 }], {
      duration: d.line,
      delay: b.line,
      ease: SKTokens.ease('--sk-e-write'),
      fill: 'both',
    })
  );
  // 「进入」
  A.push(
    SKMotion.animate(S.els.enter, [{ opacity: 0 }, { opacity: 1 }], {
      duration: d.action,
      delay: b.action,
      ease: SKTokens.ease('--sk-e-out'),
      fill: 'both',
    })
  );
  // 左下那一行
  A.push(
    ...SKMotion.animateAll([S.els.metaEl, S.els.dev], [{ opacity: 0 }, { opacity: 1 }], {
      duration: d.meta,
      delay: b.meta,
      ease: SKTokens.ease('--sk-e-out'),
      fill: 'both',
    })
  );
}

/** 跳过启动（§「MUST BE SKIPPABLE」）：全部推到终态。 */
function skipIntro() {
  if (S.skipped) return;
  S.skipped = true;
  for (const a of S.bootAnims) {
    try {
      a.finish();
    } catch (_) {
      /* ignore */
    }
  }
  S.els.title.style.opacity = '1';
  S.els.arc.style.strokeDashoffset = '0';
  S.els.dot.style.transform = 'scale(1)';
  S.els.seamPath.style.strokeDashoffset = '0';
  S.els.enter.style.opacity = '1';
  S.els.metaEl.style.opacity = '1';
}

/* ---------------------------------------------------------------------------
   进入 —— 门在自己身后合上，画面收回交接帧
   ------------------------------------------------------------------------ */

/**
 * 点「进入」之后：
 *   ① 门缝 / 「进入」/ 左下那一行 淡出（§27 的精神：玩家已经决定了，不要表演）
 *   ② 画面回到**交接帧**：纯色 void + 屏幕正中的标记
 *   ③ 停 HANDOFF.holdMs 之后才真的拉起 Godot
 *
 * ③ 的那一拍是 Launcher 唯一存在的理由：它让"玩家按下"和"游戏出现"之间
 * 有一个画面上连续的瞬间，而不是一次硬切。
 */
export function launch(targetId) {
  if (S.leaving) return { ok: false, error: 'already leaving' };
  S.leaving = true;

  const fade = 260;
  // 门合上：题签也一起走 —— 交接帧是"void + 居中标记"，多一个字都是违约。
  SKMotion.animateAll(
    [S.els.title, S.els.seam, S.els.enter, S.els.metaEl, S.els.dev],
    [{ opacity: 1 }, { opacity: 0 }],
    { duration: fade, ease: SKTokens.ease('--sk-e-in'), fill: 'both' }
  );

  // §19（PASS 04）：Key Art 在合门时轻微 zoom + 淡到黑 ——
  // "图片被推进去"代替"黑屏开始加载"，交接帧落点不变。
  if (S.els.keyart) {
    SKMotion.animate(
      S.els.keyart.querySelector('img'),
      [{ transform: 'scale(1.14)' }, { transform: 'scale(1.2)' }],
      { duration: fade + Number(HANDOFF.holdMs), ease: SKTokens.ease('--sk-e-in'), fill: 'both' }
    );
    SKMotion.animate(S.els.keyart, [{ opacity: 1 }, { opacity: 0 }], {
      duration: fade + 120,
      delay: 60,
      ease: SKTokens.ease('--sk-e-in'),
      fill: 'both',
    });
  }

  const total = fade + Number(HANDOFF.holdMs);

  if (!RENDER) {
    window.setTimeout(async () => {
      // PASS 05：等待摆在这里的是 launcher 唯一一次 >3s 的可能 ——
      // 宿主桥要 spawn Godot 并看住头一秒（launcher_host.py 的 1.2s 窗口），
      // 冷机上 Godot 自己加载世界还要更久。超过 3s 才给符号，之前画面保持安静。
      const res = await S.loader.watch(SKHost.launch(targetId || 'main'), {
        label: COPY.loadingWait,
      });
      if (!res.ok) {
        // §44：不无限等待。说清楚，并把「进入」还给玩家。
        S.leaving = false;
        skipIntro();
        showFailure(`${COPY.errorCN}${SKHost.devMode ? ` ${res.error}` : ''}`);
        return;
      }
      if (!SKHost.isNative) {
        window.setTimeout(() => {
          const n = $('doorNote');
          n.textContent = '原型：未真正启动游戏进程（用 host/launcher_host.py 打开才是真链路）';
          n.hidden = false;
        }, 400);
      }
    }, total);
  }
  return { ok: true, total, simulated: !SKHost.isNative };
}

function showFailure(msg) {
  const el = $('failure');
  el.textContent = msg;
  el.hidden = false;
}

/* ---------------------------------------------------------------------------
   输入
   ------------------------------------------------------------------------ */
function bindInput() {
  bindCues(document);
  S.els.enter.addEventListener('click', () => {
    uiCue('confirm', { id: 'enter' });
    launch('main');
  });
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      launch('main');
    } else if (e.key === 'Escape') {
      skipIntro();
    }
  });
  document.addEventListener('pointerdown', (e) => {
    if (e.target.closest('.v2-door__enter') || e.target.closest('.v2-meta__btn')) return;
    skipIntro();
  });
}

/* ---------------------------------------------------------------------------
   main
   ------------------------------------------------------------------------ */
async function main() {
  applyMotionPreference();
  SKMotion.setRenderMode(RENDER);
  await SKHost.init({ hostParam: Q.get('host') === '1' });

  /* §A4（PASS 03）FAST PATH：回头启动不重播完整仪式（1–1.5s 内落定）。
      与主菜单的 §30 同一条规则。URL ?boot=first|again 可强制，便于 A/B 出片。 */
  const forced = Q.get('boot');
  const seen = (() => {
    try {
      return localStorage.getItem(SEEN_KEY) === '1';
    } catch (_) {
      return false;
    }
  })();
  const cfg = forced === 'again' ? LAUNCHER.again : forced === 'first' ? LAUNCHER : seen ? LAUNCHER.again : LAUNCHER;

  buildTitle();
  buildDoor();
  buildMeta();
  buildDev();
  buildKeyart();
  /* PASS 05：加载符号最先挂好 —— 它服务于任何 >3s 的等待，
     而不得不先挂的原因是：等待可能在第一帧之前就开始了（世界图 / 桥调用）。 */
  S.loader = createLoading(document.body, { variant: 'center', label: COPY.loadingWait });
  bindInput();
  if (!NO_CURSOR && !RENDER) setupCursor($('cursor'));

  T0 = performance.now();
  playIntro(cfg);
  // again 路径不调 skipIntro()：1ms 的动画自己瞬间落位，而「进入世界」/meta
  // 保留它们的 240ms 淡入 —— 那一拍是"快速"与"硬跳"之间的分界。

  /* §I20：整段启动**只有一个** signature cue，挂在标记被写出的那一刻。
     这里发一次事件就完了 —— 后面「进入」出现、meta 出现都不再发声。 */
  uiCue('startup', { id: 'launcher', fast: cfg === LAUNCHER.again });

  if (!RENDER) {
    window.setTimeout(() => {
      try {
        localStorage.setItem(SEEN_KEY, '1');
      } catch (_) {
        /* 隐私模式忽略 */
      }
    }, 1600);
  }

  document.documentElement.dataset.ready = '1';
}

/* ---------------------------------------------------------------------------
   给评审 / 出片用
   ------------------------------------------------------------------------ */
window.SKLauncher = {
  launch,
  skip: skipIntro,
  host: SKHost,
  /** PASS 05：加载符号的自测/出片口（见 components/loading_glyph.js 的用法）。 */
  loader: {
    engage: (t) => S.loader.engage(t),
    release: () => S.loader.release(),
    state: () => S.loader.state(),
    watch: (p, o) => S.loader.watch(p, o),
  },
  /** 交接帧的核对数据：标记方框的中心与边长（屏幕像素）。 */
  markBox: () => {
    const r = S.els.markHost.getBoundingClientRect();
    return {
      centre: [Math.round((r.x + r.width / 2) * 100) / 100, Math.round((r.y + r.height / 2) * 100) / 100],
      want: [window.innerWidth / 2, window.innerHeight / 2],
      side: Math.round(r.width * 100) / 100,
      handoffSide: handoffSizePx(),
    };
  },
};

main();
