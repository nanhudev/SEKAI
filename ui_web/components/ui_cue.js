/* ============================================================================
   SEKAI · UI CUE CONTRACT
   ----------------------------------------------------------------------------
   UI 线**不生产音效**（BRIEF §45：SFX 归 AUDIO 线）。这里只把"界面发生了什么"
   发布成事件，由 AUDIO 线决定用什么声音、什么时候响。

   事件：window 上的 CustomEvent("sekai:ui")，detail = { cue, id, source }

   PASS 03（§I）把**资产**收敛成六个：UI_FOCUS / UI_CONFIRM / UI_BACK /
   UI_OPEN / UI_CLOSE / UI_BOOT。事件比资产细 —— 细分留给 AUDIO 做混音决策：

     事件    → 资产       含义
     -------  ----------  --------------------------------------------------
     hover    → UI_FOCUS  指针进入一个可交互项（比键盘 focus 更轻，可同为素材）
     focus    → UI_FOCUS  焦点真的落到某项上（键盘/W/S/方向键）
     confirm  → UI_CONFIRM 按下确认
     back     → UI_BACK   返回 / 关闭
     deny     → UI_BACK   不可用的项被触发（同一素材、更闷的滤波；V2 里极少响）
     open     → UI_OPEN   子界面打开（设置）
     close    → UI_CLOSE  子界面关闭
     startup  → UI_BOOT   启动演出开始（Launcher 首帧）
     ready    → (silent)  世界揭开/菜单落位 —— §I20：这段保持安静
     start    → (silent)  玩家进入世界 —— 世界环境音接管，UI 不再发声

   **Boot 只允许一个 signature cue（UI_BOOT）**：建议挂在标记/揭开的瞬间，
   一个非常轻的 "world-writing" 声。不要一串预告片音效。

   为什么用事件而不是直接调 Audio：Godot 侧、Web 原型、以后的 WebView bridge
   都能监听同一个事件名，声音不会因为界面实现方式改变而丢。
   ========================================================================= */

export const UI_CUES = [
  'hover',
  'focus',
  'confirm',
  'back',
  'deny',
  'open',
  'close',
  'startup',
  'ready',
  'start',
];

/**
 * @param {string} cue 上面的 cue 之一
 * @param {object} [meta] 额外信息，会放进 detail
 */
export function uiCue(cue, meta = {}) {
  try {
    window.dispatchEvent(new CustomEvent('sekai:ui', { detail: { cue, ...meta } }));
  } catch (_) {
    /* 老环境忽略 */
  }
}

/**
 * 把 DOM 上的 data-cue 自动挂上。
 * 用法：<button data-cue="confirm">…</button>
 *   data-cue-hover="hover" 可选，默认 hover
 */
export function bindCues(root) {
  root.addEventListener('pointerenter', (e) => {
    const el = e.target.closest?.('[data-cue-hover]');
    if (el) uiCue(el.dataset.cueHover);
  }, true);

  root.addEventListener('click', (e) => {
    const el = e.target.closest?.('[data-cue]');
    if (!el) return;
    if (el.disabled || el.classList.contains('is-disabled')) uiCue('deny', { id: el.dataset.id });
    else uiCue(el.dataset.cue, { id: el.dataset.id });
  });
}
