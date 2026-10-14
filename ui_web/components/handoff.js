/* ============================================================================
   SEKAI · HANDOFF —— 「交接帧」合同
   ----------------------------------------------------------------------------
   整条启动链路上有**三个**边界，每一个都必须落在同一帧上：

       Launcher 最后一帧  ≡  Godot BootSplash 第一帧
       MainMenu 退场最后一帧  ≡  同样这一帧

   这一帧的定义是：**纯色 void + 屏幕正中、边长为 handoffSize 的品牌标记**
   （环已写完、点已就位，没有渐变、没有雾、没有粒子、没有文字）。

   为什么把它单独放在这里，而不是留在 launcher.config.js 里：
   它不是"启动器的配置"，它是**三个场景共同的合同**。主菜单退场时也要落到
   这一帧，所以主菜单必须能读到它。放在启动器配置里，读法就变成了
   `main_menu → launcher.config`，方向是错的。
   （launcher.config.js 仍然 re-export 它，所以老引用不会断。）

   数值改这里，然后重新跑 tools/emit_tokens.mjs —— Godot 侧的 HANDOFF 是从
   这个文件生成的，不是照文档抄的。
   ========================================================================= */

export const HANDOFF = {
  /** 背景必须是纯色 void，不能有渐变、雾、粒子 */
  bg: '#060A10',

  /** 标记方框边长 = min(视口宽, 高) 的 8%（即 8vmin）。
      夹取上下限与 launcher.css 的 .sk-brand__mark clamp 一致 ——
      否则在超宽/超高比例下 CSS 会夹住而 JS 不夹，交接帧就差几十像素。 */
  markSideVmin: 8,
  markSideMinPx: 44,
  markSideMaxPx: 92,

  /** 标记中心 = 屏幕正中 */
  markCenterX: 0.5,
  markCenterY: 0.5,

  /* ---- 几何（viewBox 空间；方框边长 viewBox 单位）---- */
  viewBox: 128,
  /** 环：半径 40，从 91° 逆时针扫 294° 到 25°，缺口 58° 落在右上 */
  arcPath: 'M 63.30 24.01 A 40 40 0 1 0 100.25 47.09',
  arcRadius: 40,
  arcSweepDeg: 294,
  arcGapCenterDeg: 58,
  arcProgress: 1,
  /** 点：信标 / 观察者 */
  dotRadius: 5,
  dotProgress: 1,

  /* ---- 颜色 ---- */
  arcColor: '#EDE4D3',
  dotColor: '#C9A65C',

  /* ---- 线宽（屏幕像素，non-scaling）---- */
  arcStrokePx: 1.6,
  /** 方便核对：方框 8vmin 在 900px 高基准下 = 72px，缩放比 72/128 = 0.5625
      → 点半径落在屏幕上 ≈ 2.81px */
  dotRadiusPxAt900: 2.81,

  /** 交接画面保持多久再拉起 Godot */
  holdMs: 320,
  /** 退出转场总时长 */
  exitMs: 1200,
};

/**
 * 交接帧上标记的边长（屏幕像素）。
 *
 * **三个边界必须用这一个函数算**。任何一处自己写 `innerHeight * 0.08`
 * 都会在另两处对不上，而对不上是看不见的 —— 只有把两帧叠起来量才会发现。
 */
export function handoffSizePx() {
  const vmin = Math.min(window.innerWidth, window.innerHeight);
  const raw = (vmin * HANDOFF.markSideVmin) / 100;
  return Math.min(HANDOFF.markSideMaxPx, Math.max(HANDOFF.markSideMinPx, raw));
}
