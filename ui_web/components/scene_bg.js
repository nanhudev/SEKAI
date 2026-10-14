/* ============================================================================
   SEKAI · SHARED SCENE BACKGROUND
   ----------------------------------------------------------------------------
   Launcher 和 Main Menu 必须看起来是"同一个世界的两层界面"。
   最省力也最有效的做法：**背景是同一段代码、同一个几何、同一个速度**。

   构成（全部极慢）：
     grad      底：右上方的暖光 + 向下的暗
     ring      环的轮廓：与标记同源的弧，放大到屏幕外。缺口永远在右上
     smoke     三团模糊的雾，各自漂移（周期 76–128 秒）
     particles 浮尘（周期 30–62 秒）
     vignette  暗角

   所有位移量都很小。主菜单不是动态壁纸网站（BRIEF §23）。
   ========================================================================= */

import { SKMotion } from '../motion/motion.js';
import { SKTokens } from '../tokens/tokens.js';
import { ringArc } from '../svg/library.js';

/**
 * 建立背景 DOM。返回各层句柄，交给 animateSceneBackground 播。
 * @param {HTMLElement} host 会被清空的容器
 */
export function buildSceneBackground(host, opts = {}) {
  const {
    ring = {},
    smoke = true,
    particles = 22,
    vignette = true,
  } = opts;

  const ringCfg = {
    left: '74%',
    top: '42%',
    size: '96vmin',
    color: 'rgba(116,138,158,0.34)',
    ...ring,
  };

  host.innerHTML = `
    <div class="sk-bg__grad"></div>
    <div class="sk-bg__ring"></div>
    ${smoke ? '<div class="sk-bg__smoke"><span></span><span></span><span></span></div>' : ''}
    <div class="sk-bg__particles"></div>
    ${vignette ? '<div class="sk-bg__vignette"></div>' : ''}
  `;

  const ringEl = host.querySelector('.sk-bg__ring');
  ringEl.style.left = ringCfg.left;
  ringEl.style.top = ringCfg.top;
  ringEl.style.width = ringCfg.size;
  ringEl.style.height = ringCfg.size;
  ringEl.innerHTML = ringArc({ size: 400, r: 196, from: 87, to: 389, stroke: 1, color: ringCfg.color });

  return {
    root: host,
    grad: host.querySelector('.sk-bg__grad'),
    ring: ringEl,
    smoke: host.querySelector('.sk-bg__smoke'),
    particles: host.querySelector('.sk-bg__particles'),
    vignette: host.querySelector('.sk-bg__vignette'),
  };
}

/**
 * 让背景开始呼吸。所有动画都是可 seek 的 WAAPI —— 出片时才控得住。
 * @param {object} parts buildSceneBackground 的返回值
 * @param {object} opts delay（演出起点）/ particles / ringSpin
 */
export function animateSceneBackground(parts, opts = {}) {
  const { delay = 0, particles = 22, ringSpin = 240000, particleDelayMax = 12000 } = opts;
  const ease = SKTokens.ease('--sk-e-out');

  if (parts.smoke) {
    const spans = [...parts.smoke.querySelectorAll('span')];
    spans.forEach((el, i) => {
      SKMotion.animate(el, [{ opacity: 0 }, { opacity: 1 }], {
        duration: 2200,
        delay: delay + i * 260,
        ease,
        fill: 'both',
      });
    });
    SKMotion.drift(spans[0], { dx: 34, dy: -16, scale: 1.06, duration: 92000 });
    SKMotion.drift(spans[1], { dx: -46, dy: 22, scale: 0.96, duration: 128000 });
    SKMotion.drift(spans[2], { dx: 24, dy: -30, scale: 1.04, duration: 76000 });
  }

  SKMotion.animate(parts.ring, [{ opacity: 0 }, { opacity: 1 }], {
    duration: 2600,
    delay,
    ease,
    fill: 'both',
  });
  // 极慢自转：缺口在动，但一分钟也看不出动过。
  SKMotion.drift(parts.ring, { rotate: 360, duration: ringSpin });

  if (parts.particles && particles > 0) {
    SKMotion.particles(parts.particles, {
      count: particles,
      size: [1, 2.2],
      rise: [200, 460],
      duration: [30000, 62000],
      delayMax: particleDelayMax,
      opacity: [0.05, 0.17],
      color: 'var(--sk-text-2)',
    });
  }
}

/**
 * 画面级的"书写规则线"：两条长横线 + 左端一小段金字 + 一条刻度尺。
 * 两个页面用**同一组 y 位置**（0.10 / 0.88）—— 这是"同一个游戏"最廉价的证据。
 */
export function buildRunes(host, opts = {}) {
  const { upper = 0.1, lower = 0.88, markLeft = 'calc(100% / 12 * 2)' } = opts;
  host.innerHTML = `
    <i class="sk-hair" data-y="upper"></i>
    <i class="sk-hair" data-y="lower"></i>
    <i class="sk-hair-mark" data-y="upper"></i>
    <span class="sk-tick-line" data-y="lower"></span>
  `;
  const [hairA, hairB] = [...host.querySelectorAll('.sk-hair')];
  const mark = host.querySelector('.sk-hair-mark');
  const ticks = host.querySelector('.sk-tick-line');
  hairA.style.top = `${upper * 100}%`;
  hairB.style.top = `${lower * 100}%`;
  mark.style.top = `${upper * 100}%`;
  ticks.style.top = `${lower * 100}%`;
  mark.style.left = markLeft;
  return { hairs: [hairA, hairB], mark, ticks };
}

/** 规则线的书写演出 */
export function animateRunes(parts, opts = {}) {
  const { delay = 0, opacity = 0.1, tickOpacity = 0.32, duration = 1400 } = opts;
  const ease = SKTokens.ease('--sk-e-write');
  parts.hairs.forEach((el, i) => {
    SKMotion.animate(
      el,
      [
        { opacity: 0, clipPath: 'inset(0 100% 0 0)' },
        { opacity, clipPath: 'inset(0 0% 0 0)' },
      ],
      { duration, delay: delay + i * 220, ease, fill: 'both' }
    );
  });
  SKMotion.animate(
    parts.mark,
    [
      { opacity: 0, clipPath: 'inset(0 100% 0 0)' },
      { opacity: 0.5, clipPath: 'inset(0 0% 0 0)' },
    ],
    { duration: 700, delay: delay + 380, ease, fill: 'both' }
  );
  SKMotion.animate(
    parts.ticks,
    [
      { opacity: 0, clipPath: 'inset(0 100% 0 0)' },
      { opacity: tickOpacity, clipPath: 'inset(0 0% 0 0)' },
    ],
    { duration: 1600, delay: delay + 520, ease, fill: 'both' }
  );
}

/** 退场：环境整体退下，最终只剩纯色（= Launcher 的 HANDOFF 帧） */
export function fadeSceneBackground(parts, runes, opts = {}) {
  const { delay = 0, ease = SKTokens.ease('--sk-e-in') } = opts;
  const fade = (el, duration, extraDelay = 0) =>
    el &&
    SKMotion.animate(el, [{ opacity: 1 }, { opacity: 0 }], {
      duration,
      delay: delay + extraDelay,
      ease,
      fill: 'both',
    });

  fade(parts.smoke, 720, 140);
  fade(parts.particles, 620, 160);
  fade(parts.ring, 700, 160);
  fade(parts.grad, 760, 200);
  fade(parts.vignette, 760, 200);
  if (runes) {
    fade(runes.hairs[0]?.parentElement, 620, 120);
  }
}
