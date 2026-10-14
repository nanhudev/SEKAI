/* ============================================================================
   SEKAI · CURSOR
   ----------------------------------------------------------------------------
   精确十字 + 中心点。方向上是"标尺"，不是箭头。
   与 components.css 的 .sk-cursor* 配套。

   安全网：指针离开窗口时把系统光标还回去 —— 绝不能出现"没有光标"的状态。
   传 disabled 或 ?cursor=native 可整体关闭。
   ========================================================================= */

import { cursor as cursorMarkup } from '../svg/library.js';

export function setupCursor(el, { disabled = false } = {}) {
  if (disabled || !el) return null;
  const root = document.documentElement;

  el.hidden = false;
  el.innerHTML = cursorMarkup();
  root.setAttribute('data-cursor-on', '1');

  let raf = 0;
  let px = window.innerWidth / 2;
  let py = window.innerHeight / 2;

  const flush = () => {
    raf = 0;
    el.style.transform = `translate(${px}px, ${py}px)`;
  };

  window.addEventListener(
    'mousemove',
    (e) => {
      px = e.clientX;
      py = e.clientY;
      if (!raf) raf = requestAnimationFrame(flush);
    },
    { passive: true }
  );

  window.addEventListener('mouseover', (e) => {
    const interactive = e.target.closest?.('button, a, input, select, [data-target], [data-cue]');
    root.classList.toggle('sk-hovering', !!interactive);
  });

  window.addEventListener('mousedown', () => root.classList.add('sk-pressing'));
  window.addEventListener('mouseup', () => root.classList.remove('sk-pressing'));

  document.addEventListener('mouseout', (e) => {
    if (!e.relatedTarget) root.removeAttribute('data-cursor-on');
  });
  document.addEventListener('mouseover', () => root.setAttribute('data-cursor-on', '1'));

  return { el };
}
