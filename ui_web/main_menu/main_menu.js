/* ============================================================================
   SEKAI · MAIN MENU
   ----------------------------------------------------------------------------
   进场（= Godot BootSplash 要复刻的那一段）：

     t=0  纯色 + 屏幕正中的标记      ← 这正是 Launcher 的最后一帧
      ↓  环境浮出（雾 / 环 / 尘 / 规则线）
      ↓  标记回到本位（左上）
     SEKAI 逐字写出 → 世界之外 → 金色短线 → Beyond the Written Fate
      ↓  菜单项从左侧依次展开
      ↓  焦点落到第一项，焦点线被写出来

   交互：
     hover  = 焦点跟着走（鼠标不是"另一个光标"，它就是焦点）
     ↑ ↓    = 移动焦点
     Enter  = 进入
     Esc    = 无操作（本 PASS 不做返回）

   注意：**没有音效**。所有界面事件走 uiCue() 发布事件，由 AUDIO 线决定声音。
   ========================================================================= */

import { SKTokens } from '../tokens/tokens.js';
import { SKMotion } from '../motion/motion.js';
import { mark } from '../svg/library.js';
import {
  buildSceneBackground,
  animateSceneBackground,
  buildRunes,
  animateRunes,
  fadeSceneBackground,
} from '../components/scene_bg.js';
import { markHome, markToCenter } from '../components/mark_motion.js';
import { setupCursor } from '../components/cursor.js';
import { uiCue } from '../components/ui_cue.js';
import { SKHost } from '../host/host.js';
import { MENU_BOOT, ITEMS } from './main_menu.config.js';

// 时序与菜单项的数据住在 main_menu.config.js（无副作用，Node 能直接 import）。
// 这里再导出一遍，是为了不改动已有引用方（emit_tokens.mjs / 评审脚本）。
export { MENU_BOOT, ITEMS };

const $ = (id) => document.getElementById(id);
const Q = new URLSearchParams(location.search);
const RENDER = Q.get('render') === '1';
const NO_CURSOR = Q.get('cursor') === 'native';

const S = {
  items: [],
  focusedId: null,
  entering: false,
  els: {},
};

/* ==========================================================================
   0. 无障碍
   ========================================================================= */
function applyMotionPreference() {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  document.documentElement.setAttribute('data-motion', reduced ? 'reduce' : 'full');
}

/* ==========================================================================
   1. 建立 DOM
   ========================================================================= */
function buildBrand() {
  const host = $('mark');
  host.innerHTML = mark({ size: 128, stroke: 1.6, dot: 5 });
  S.els.mark = host;

  const word = $('word');
  word.setAttribute('aria-label', 'SEKAI');
  word.innerHTML = [...'SEKAI']
    .map((ch) => `<span class="sk-letter" aria-hidden="true">${ch}</span>`)
    .join('');
  S.els.letters = [...word.querySelectorAll('.sk-letter')];
  $('wordCN').textContent = '世界之外';
  $('subtitle').textContent = 'Beyond the Written Fate';
  S.els.word = word;
  S.els.wordCN = $('wordCN');
  S.els.rule = $('rule');
  S.els.subtitle = $('subtitle');
}

function buildNav() {
  const nav = $('nav');
  nav.innerHTML = '';
  S.items = [];

  // "继续"的副标题承担存档摘要：上一次停在哪里。
  // 术语（雾栖镇 / MISTVALE）来自 NARRATIVE 线的命名裁决，不由 UI 线自造。
  const subLabel = (def) => {
    if (def.id !== 'continue') return def.en;
    const save = SKHost.save;
    if (!save.exists) return 'NO SAVE — 尚无存档';
    return [def.en, save.location, save.locationEn].filter(Boolean).join(' · ');
  };

  for (const def of ITEMS) {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'sk-item';
    btn.dataset.id = def.id;
    btn.dataset.cue = def.note ? 'deny' : 'confirm';
    btn.dataset.cueHover = 'hover';
    const enabled = !(def.needsSave && !SKHost.save.exists);
    if (!enabled) {
      btn.classList.add('is-disabled');
      btn.setAttribute('aria-disabled', 'true');
    }
    btn.innerHTML = `
      <svg class="sk-item__line" preserveAspectRatio="none" aria-hidden="true"
           viewBox="0 0 400 6" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <!-- gradientUnits="userSpaceOnUse" 必需：这条线的 bbox 高度为 0，
               默认的 objectBoundingBox 会让渐变退化，规格规定退化渐变 = 整条不画。 -->
          <linearGradient id="skfl-${def.id}" gradientUnits="userSpaceOnUse"
                          x1="0" y1="0" x2="400" y2="0">
            <stop offset="0%" stop-color="#C9A65C" stop-opacity="0"/>
            <stop offset="8%" stop-color="#C9A65C" stop-opacity="0.85"/>
            <stop offset="100%" stop-color="#C9A65C" stop-opacity="0.35"/>
          </linearGradient>
        </defs>
        <path pathLength="1" d="M 0 3 H 400" fill="none" stroke="url(#skfl-${def.id})"
              stroke-width="1" vector-effect="non-scaling-stroke"/>
      </svg>
      <span class="sk-item__tick" aria-hidden="true"></span>
      <span class="sk-item__cn">${def.cn}</span>
      <span class="sk-item__en">${subLabel(def)}</span>
    `;
    nav.appendChild(btn);

    const path = btn.querySelector('.sk-item__line path');
    const line = SKMotion.stateAnim(
      path,
      [
        { strokeDashoffset: '1', opacity: 0 },
        { strokeDashoffset: '0', opacity: 1 },
      ],
      { duration: SKTokens.msec('--sk-t-fast'), ease: SKTokens.ease('--sk-e-write') }
    );

    const item = { ...def, el: btn, line, enabled };
    btn.addEventListener('pointerenter', () => {
      if (!item.enabled) return;
      focusItem(def.id, { cue: 'hover' });
    });
    btn.addEventListener('focus', () => focusItem(def.id, { cue: 'focus' }));
    btn.addEventListener('click', () => activate(def.id));
    S.items.push(item);
  }
}

/* ==========================================================================
   2. 焦点
   ========================================================================= */
/**
 * @param {string} id
 * @param {object} [opts]
 * @param {string|null} [opts.cue] 要广播的音效 cue（null = 不广播）
 * @param {number} [opts.at]       出片模式专用：这次焦点变化属于页面时间轴的第
 *                                 at 毫秒。boot 时焦点落在 beats.focus，
 *                                 必须显式给出 —— 否则冻结出片里焦点线不会出现。
 */
function focusItem(id, { cue = 'focus', at } = {}) {
  const next = S.items.find((i) => i.id === id);
  if (!next || !next.enabled) return;
  if (S.focusedId === id) {
    if (cue) uiCue(cue, { id });
    return;
  }
  const prev = S.items.find((i) => i.id === S.focusedId);
  S.focusedId = id;

  if (prev) {
    prev.el.classList.remove('is-focus');
    prev.line.off(at);
  }
  next.el.classList.add('is-focus');
  next.line.on(at);
  if (cue) uiCue(cue, { id });
}

function moveFocus(delta) {
  const usable = S.items.filter((i) => i.enabled);
  if (!usable.length) return;
  const at = usable.findIndex((i) => i.id === S.focusedId);
  const next = usable[(at + delta + usable.length * 2) % usable.length] || usable[0];
  focusItem(next.id);
}

/* ==========================================================================
   3. 进入 / 说明条
   ========================================================================= */
function showNote(text, ms = 3200) {
  const el = $('note');
  el.textContent = text;
  el.hidden = false;
  const a = SKMotion.animate(el, [{ opacity: 0 }, { opacity: 1 }], {
    duration: 240,
    ease: SKTokens.ease('--sk-e-out'),
    fill: 'both',
  });
  window.clearTimeout(S._noteTimer);
  if (!RENDER) {
    S._noteTimer = window.setTimeout(() => {
      SKMotion.animate(el, [{ opacity: 1 }, { opacity: 0 }], {
        duration: 300,
        ease: SKTokens.ease('--sk-e-in'),
        fill: 'both',
      });
    }, ms);
  }
  return a;
}

function activate(id) {
  const item = S.items.find((i) => i.id === id);
  if (!item || !item.enabled) {
    uiCue('deny', { id });
    if (item) showNote(item.note || '这一项现在不可用。');
    return;
  }
  if (item.note) {
    uiCue('confirm', { id });
    showNote(item.note);
    return;
  }
  enterWorld(id);
}

/* ==========================================================================
   4. 退场 —— 终点与 Launcher 完全相同：纯色 + 正中的标记
   ========================================================================= */
function enterWorld(id) {
  if (S.entering) return;
  S.entering = true;
  uiCue('start', { id });
  const E = {
    out: SKTokens.ease('--sk-e-out'),
    in: SKTokens.ease('--sk-e-in'),
    io: SKTokens.ease('--sk-e-io'),
  };

  // 1. 菜单与品牌退场（DISSOLVE：擦除，不是淡出）
  SKMotion.dissolve(
    S.items.map((i) => i.el),
    { duration: 260, stagger: 46, ease: E.in, dir: 'up', fragment: true }
  );
  SKMotion.dissolve([S.els.word, S.els.wordCN, S.els.rule, S.els.subtitle], {
    duration: 280,
    delay: 80,
    stagger: 46,
    ease: E.in,
    dir: 'right',
    fragment: true,
  });
  SKMotion.dissolve([document.querySelector('.sk-meta-bar'), $('note')].filter(Boolean), {
    duration: 240,
    delay: 60,
    ease: E.in,
    dir: 'right',
  });

  // 2. 世界"合上"：环的缺口转出画面。这是唯一一处允许有仪式感的退场动作。
  SKMotion.animate(
    S.scene.ring,
    [{ rotate: '0deg' }, { rotate: '-58deg' }],
    { duration: 1700, delay: 240, ease: E.io, fill: 'both' }
  );

  // 3. 环境退下 → 只剩纯色
  fadeSceneBackground(S.scene, S.runes, { delay: 480, ease: E.in });

  // 4. 标记移到屏幕正中，**尺寸不变**。这就是 Launcher 的最后一帧，
  //    用的是同一个 components/mark_motion.js —— 两侧不可能对不上。
  markToCenter(S.els.mark, MENU_BOOT.exit.markHome);

  const total =
    MENU_BOOT.exit.markHome.delay + MENU_BOOT.exit.markHome.duration + MENU_BOOT.exit.holdMs;
  if (!RENDER) {
    window.setTimeout(async () => {
      const res = await SKHost.launch(id);
      if (!res.ok) {
        S.entering = false;
        showNote(`无法进入世界。${SKHost.devMode ? ` ${res.error}` : ''}`, 60000);
      }
    }, total - 60);
  }
  return total;
}

/* ==========================================================================
   5. 进场
   ========================================================================= */
function playBoot() {
  const B = MENU_BOOT.beats;
  const D = MENU_BOOT.dur;
  const E = {
    out: SKTokens.ease('--sk-e-out'),
    in: SKTokens.ease('--sk-e-in'),
    write: SKTokens.ease('--sk-e-write'),
    unfold: SKTokens.ease('--sk-e-unfold'),
  };
  uiCue('startup');

  // 起点：标记在屏幕正中（= Launcher 的最后一帧）。
  // 先停一拍再动 —— 这一拍就是"启动过程是连续的"被人眼读到的地方。
  markHome(S.els.mark, { delay: D.markHomeDelay, duration: D.markHome });

  // 环境
  SKMotion.animate(S.scene.grad, [{ opacity: 0 }, { opacity: 1 }], {
    duration: D.scene,
    delay: B.scene,
    ease: E.out,
    fill: 'both',
  });
  animateSceneBackground(S.scene, { delay: B.scene, particles: 22, ringSpin: 240000 });
  animateRunes(S.runes, { delay: B.runes, opacity: 0.1, duration: D.runes });

  // 字标
  SKMotion.animate(S.els.word, [{ opacity: 0 }, { opacity: 1 }], {
    duration: 1,
    delay: B.letters,
    fill: 'both',
  });
  S.els.letters.forEach((el, i) => {
    SKMotion.animate(el, [{ clipPath: 'inset(0 100% 0 0)' }, { clipPath: 'inset(0 0% 0 0)' }], {
      duration: D.letter,
      delay: B.letters + i * D.letterStagger,
      ease: E.write,
      fill: 'both',
    });
  });
  SKMotion.animate(
    S.els.wordCN,
    [
      { opacity: 0, clipPath: 'inset(0 100% 0 0)' },
      { opacity: 1, clipPath: 'inset(0 0% 0 0)' },
    ],
    { duration: D.cn, delay: B.cn, ease: E.write, fill: 'both' }
  );
  SKMotion.animate(
    S.els.rule,
    [
      { opacity: 0, clipPath: 'inset(0 100% 0 0)' },
      { opacity: 1, clipPath: 'inset(0 0% 0 0)' },
    ],
    { duration: D.rule, delay: B.rule, ease: E.write, fill: 'both' }
  );
  const wide = SKTokens.get('--sk-track-wide') || '0.26em';
  SKMotion.animate(
    S.els.subtitle,
    [
      { opacity: 0, letterSpacing: '0.52em' },
      { opacity: 1, letterSpacing: wide },
    ],
    { duration: D.subtitle, delay: B.subtitle, ease: E.out, fill: 'both' }
  );

  // 菜单
  const nav = $('nav');
  SKMotion.animate(nav, [{ opacity: 0 }, { opacity: 1 }], {
    duration: 1,
    delay: B.nav,
    fill: 'both',
  });
  S.items.forEach((item, i) => {
    SKMotion.unfold([item.el], {
      duration: D.navItem,
      delay: B.nav + i * D.navStagger,
      ease: E.unfold,
      axis: 'x',
      origin: 'left',
      radius: '0px',
    });
  });
  const meta = document.querySelector('.sk-meta-bar');
  SKMotion.animate(meta, [{ opacity: 0 }, { opacity: 1 }], {
    duration: D.meta,
    delay: B.meta,
    ease: E.out,
    fill: 'both',
  });

  // 焦点落到第一项（音效由 AUDIO 线决定；这里只是把状态和线准备好）
  const firstId = (S.items.find((i) => i.enabled) || S.items[0]).id;
  if (RENDER) {
    // 出片：不能靠真实定时器（截图/录像不该取决于机器快慢），
    // 把这次状态变化直接挂到时间轴的 beats.focus 上。
    focusItem(firstId, { cue: null, at: B.focus });
  } else {
    window.setTimeout(() => focusItem(firstId, { cue: 'focus' }), B.focus);
  }
}

/* ==========================================================================
   6. 输入
   ========================================================================= */
function setupInput() {
  window.addEventListener('keydown', (e) => {
    if (S.entering) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      moveFocus(e.key === 'ArrowDown' ? 1 : -1);
    } else if (e.key === 'Enter' || e.key === ' ') {
      if (S.focusedId) {
        e.preventDefault();
        activate(S.focusedId);
      }
    } else if (e.key === 'Home') {
      const first = S.items.find((i) => i.enabled);
      if (first) focusItem(first.id);
    }
  });
}

/* ==========================================================================
   7. 主流程
   ========================================================================= */
async function main() {
  applyMotionPreference();
  // 必须在 boot 之前打开 —— boot 期间就会触发一次焦点（状态动画）。
  SKMotion.setRenderMode(RENDER);
  // ?host=1 由桌面宿主自己加上。没有它 = 浏览器 / 出片，绝不发起宿主请求。
  await SKHost.init({ hostParam: Q.get('host') === '1' });
  if (Q.get('dev') === '0') SKHost.config.devMode = false;
  if (Q.get('motion') === 'reduce') document.documentElement.setAttribute('data-motion', 'reduce');

  // 环境与规则线（与 Launcher 同一段代码、同一组 y 位置）
  S.scene = buildSceneBackground($('scene'), { particles: 22 });
  S.runes = buildRunes($('runes'), { upper: 0.1, lower: 0.88 });

  buildBrand();
  buildNav();
  $('verLine').textContent = `SEKAI  ${SKHost.version}  ·  ${SKHost.build}`;
  $('hintLine').textContent = '↑ ↓ 选择   ENTER 进入';
  setupCursor($('cursor'), { disabled: NO_CURSOR || RENDER });
  setupInput();

  playBoot();

  window.SKMenu = {
    state: S,
    ITEMS,
    MENU_BOOT,
    /** 宿主句柄。评审和 harness 需要能问出"现在到底是 native 还是 web"。 */
    host: SKHost,
    focus: (id) => focusItem(id, { cue: null }),
    moveFocus,
    activate,
    enterWorld,
    showNote,
    totalMs: RENDER
      ? MENU_BOOT.beats.focus +
        500 +
        MENU_BOOT.exit.markHome.delay +
        MENU_BOOT.exit.markHome.duration +
        MENU_BOOT.exit.holdMs
      : Infinity,
  };
  document.documentElement.dataset.ready = '1';
}

main();
