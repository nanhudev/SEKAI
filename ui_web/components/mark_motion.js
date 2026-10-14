/* ============================================================================
   SEKAI · MARK MOTION (the hand-off move)
   ----------------------------------------------------------------------------
   整条启动链路靠这一段把三个边界缝成一个连续过程：

     Launcher 退场        → 移到正中、缩放到 handoff 尺寸
     BootSplash 第一帧     ← 从正中、handoff 尺寸开始（reset_to_handoff）
     MainMenu 退场        → 移到正中、缩放到 handoff 尺寸

   **尺寸必须一起动。** 早先这里只动位置、注释写着"尺寸不变"—— 那是错的：
   Launcher 的品牌标记是 8vmin，主菜单的品牌标记是 4.4vmin，只动位置的话
   两边退场会停在两个不同大小的标记上，而 HANDOFF 只承认一个。
   这种错看不出来（两帧都"是纯色 + 正中一个标记"），只有把两帧叠起来量才会发现。

   两个页面共用本文件 —— 任何一边改动，另一边自动跟上。
   ========================================================================= */

import { SKMotion } from '../motion/motion.js';
import { SKTokens } from '../tokens/tokens.js';
import { HANDOFF, handoffSizePx } from './handoff.js';

/**
 * 标记当前布局中心 距 屏幕正中 的偏移。
 *
 * 两个坑，都踩过：
 *
 * 1. 要按**目标尺寸**算。元素改宽高时左上角不动、中心会跟着移
 *    (target - current)/2，所以偏移量里必须把这一半扣掉。
 *
 * 2. 更隐蔽的一个：标记是**文档流里的块**。它一改尺寸，父块 `.sk-brand`
 *    的高度就跟着变，而父块在栅格里是 align-self:center —— 高度一变它就
 *    重新居中，于是标记**自己的静态位置**也移了 (target-from)/2。
 *    主菜单的品牌标记是 4.4vmin（900px 视口下 40px），交接尺寸是 8vmin（72px），
 *    差值 32px，正好让落点偏 16px。Launcher 之所以没这个毛病，只是因为它的
 *    品牌标记本来就已经是 8vmin，差值恰好为 0 —— 也就是说这个 bug 一直
 *    躲在一个"另一侧碰巧对了"的巧合后面。
 *
 *    解法不是把那 16px 硬扣掉（那等于把父块的布局方式抄进这里，谁改
 *    align-self 谁就得知道这儿也有一份），而是**让浏览器自己算这次重排**：
 *    临时套上目标尺寸、量一次、再还原。这样无论父块怎么排版，量到的都是
 *    元素变成目标尺寸之后的真实静态位置。
 */
export function offsetToCenter(el, targetSize = null) {
  const r0 = el.getBoundingClientRect();
  const target = targetSize == null ? r0.width : targetSize;

  // 量之前必须把元素**按**回目标尺寸，而且必须带 !important。
  // 元素身上通常还挂着 fill:both 的 WAAPI 动画（markHome / markToCenter 都会留下），
  // 动画属于层叠里的"动画"来源，会盖掉普通内联样式 —— 直接写 el.style.width
  // 是**没有效果**的，量到的仍是动画当前的样子。层叠顺序里唯一能压住动画的
  // 是作者 !important。踩过一次，量出来跟没改一样。
  const PROPS = ['width', 'height', 'transform'];
  const saved = PROPS.map((p) => [p, el.style.getPropertyValue(p), el.style.getPropertyPriority(p)]);
  el.style.setProperty('transform', 'none', 'important');
  el.style.setProperty('width', `${target}px`, 'important');
  el.style.setProperty('height', `${target}px`, 'important');
  const r = el.getBoundingClientRect();
  for (const [p, v, prio] of saved) {
    if (v) el.style.setProperty(p, v, prio);
    else el.style.removeProperty(p);
  }

  return {
    dx: window.innerWidth / 2 - r.left - target / 2,
    dy: window.innerHeight / 2 - r.top - target / 2,
  };
}

/** 把标记从本位移到屏幕正中，并缩放到交接尺寸（Launcher 退场 / 菜单退场） */
export function markToCenter(el, { delay = 0, duration = 760, toHandoffSize = true } = {}) {
  const r = el.getBoundingClientRect();
  const from = r.width;
  const target = toHandoffSize ? handoffSizePx() : from;
  const { dx, dy } = offsetToCenter(el, target);
  el.style.transformOrigin = 'center center';
  return {
    offset: { dx, dy },
    size: target,
    anim: SKMotion.animate(
      el,
      [
        { transform: 'translate(0px, 0px)', width: `${from}px`, height: `${from}px` },
        { transform: `translate(${dx}px, ${dy}px)`, width: `${target}px`, height: `${target}px` },
      ],
      { duration, delay, ease: SKTokens.ease('--sk-e-io'), fill: 'both' }
    ),
  };
}

/** 把标记从屏幕正中（交接尺寸）移回本位（菜单进场） */
export function markHome(el, { delay = 0, duration = 780, offset = null } = {}) {
  const r = el.getBoundingClientRect();
  const natural = r.width;
  const hand = handoffSizePx();
  const off = offset || offsetToCenter(el, hand);
  el.style.transformOrigin = 'center center';
  // 先钉在正中（交接尺寸），避免首帧露出本位
  el.style.transform = `translate(${off.dx}px, ${off.dy}px)`;
  el.style.width = `${hand}px`;
  el.style.height = `${hand}px`;
  const anim = SKMotion.animate(
    el,
    [
      {
        transform: `translate(${off.dx}px, ${off.dy}px)`,
        width: `${hand}px`,
        height: `${hand}px`,
      },
      { transform: 'translate(0px, 0px)', width: `${natural}px`, height: `${natural}px` },
    ],
    { duration, delay, ease: SKTokens.ease('--sk-e-out'), fill: 'both' }
  );
  // 播完之后把内联尺寸摘掉，交还给 CSS —— 否则窗口缩放时标记不再跟着 vmin 变。
  // 出片模式（暂停 + seek）永远播不完，也就永远不会摘，正好。
  anim.finished
    .then(() => {
      el.style.width = '';
      el.style.height = '';
    })
    .catch(() => {});
  return anim;
}

/** 交接帧的标记方框边长（屏幕像素）。验收脚本用它核对两侧。 */
export { handoffSizePx };
export const HANDOFF_FRAME = HANDOFF;
