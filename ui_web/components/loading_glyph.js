/* ============================================================================
   SEKAI · LOADING GLYPH（PASS 05 · 独立加载动画）
   ----------------------------------------------------------------------------
   一个零件，三种等待共用：Launcher 的启动桥调用、Main Menu 的世界图加载、
   Menu → Game 的进入。它不是"页面的一部分"，是**一个可挂到任何页面上的动作**。

   ---------------------------------------------------------------------------
   为什么是现在这个样子
   ---------------------------------------------------------------------------
   1. 不是 Loading Screen。世界（或 Key Art）**一直在后面活着** ——
      黑屏 + 转圈是"程序正在装"，而这里是"世界正在被写出来"。
   2. 不是 spinner，不是进度环，不是百分比。
      SEKAI 不知道 Godot 内部加载到了第几步（旧 §15/WORLD.sync 的理由没变），
      假装知道就是假的。这里是两条被反复书写的细线：世界在被写，写完就走。
   3. 语言统一在已有的两种上：**WRITE（一笔被写出来）+ 已有的 hairline**。
      启动序列里"一条线切开画面"是同一个词，这里的每一笔就是那个词的重复，
      而不是一套新的进度 UI 词汇。
   4. 出现条件是**时间**：等待跨过 LOADING.thresholdMs（默认 3000ms）才现身。
      三秒以内的等待应该安静 —— 加载提示本身也是一种噪声。

   ---------------------------------------------------------------------------
   用法
   ---------------------------------------------------------------------------
     const loader = createLoading(document.body, { variant: 'left' });
     await loader.watch(anyPromise, { label: '正在进入' });
       · 等待 ≤ 3s：什么都不出现，promise 原样透传。
       · 等待 > 3s：3s 那一刻符号淡入循环书写，就绪后至少活 minVisibleMs 再淡出。
   也提供 engage()/release() 手动控制（出片/评审用；接地gate 在 window.SKLoader）。
   ========================================================================= */

import { SKMotion } from '../motion/motion.js';
import { SKTokens } from '../tokens/tokens.js';
import { LOADING } from '../v2/v2.config.js';

/* ---------------------------------------------------------------------------
   构建
   ------------------------------------------------------------------------ */

/**
 * 挂载加载符号（默认隐藏）。
 *
 * @param {HTMLElement} host
 * @param {object} [opts]
 * @param {'left'|'center'} [opts.variant] left = 与菜单同一条栅格对齐线；center = 居中（Launcher）
 * @param {string} [opts.label] 可以有。任何英文（"LOADING"）或系统词都不要。
 * @returns {object} loader
 *
 * 书写期间 host 上会挂 `data-loading="1"` —— 组件只**发布状态**，不替页面决定
 * 谁该让位。为什么需要这个状态：left 变体压在与版本行 `.v2-meta` 同一条栅格线上，
 * 两个元素同时可见时细线会横穿版本号（实测截图里读出一串重影字）。
 * 页面在自己的样式表里写 `[data-loading="1"] .v2-meta { opacity: 0 }` 即可 ——
 * 规距仍是「同一时刻只说一件事」：世界正在被写的时候，角落信息退场。
 */
export function createLoading(host, { variant = 'left', label = '' } = {}) {
  const root = document.createElement('div');
  root.className = `sk-load sk-load--${variant}`;
  root.hidden = true;
  root.setAttribute('role', 'status');
  root.setAttribute('aria-live', 'polite');

  const labelEl = document.createElement('span');
  labelEl.className = 'sk-load__label';
  labelEl.textContent = label;
  // 必须**无条件**挂进 DOM。
  // 曾经的写法是 `if (label) root.appendChild(labelEl)` —— 初始 label 为空
  // （watch/engage 后才给文本的常见路径）时，labelEl 根本不在文档里，
  // engage('正在准备世界') 设了 textContent 却永远不显示。可见性一律由 hidden 管。
  labelEl.hidden = !label;

  const strokes = document.createElement('span');
  strokes.className = 'sk-load__strokes';
  const inks = [];
  for (let i = 0; i < 2; i += 1) {
    const stroke = document.createElement('span');
    stroke.className = 'sk-load__stroke';
    const ink = document.createElement('span');
    ink.className = 'sk-load__ink';
    stroke.appendChild(ink);
    strokes.appendChild(stroke);
    inks.push(ink);
  }

  root.appendChild(labelEl);
  root.appendChild(strokes);
  host.appendChild(root);

  const S = { visible: false, loop: [], engagedAt: 0 };

  /* -------------------------------------------------------------------------
     书写循环 —— WRITE 语言
     ----------------------------------------------------------------------
     一笔：从左边写出（inset 右→0），再从左边被抹掉（inset 左→100%）。
     第二笔延迟 strokeStagger 出现 —— 两笔不同相位，读起来是"一直在被写"，
     而不是"一段来回扫的动画"。clip-path 而不是 scaleX：scaleX 会把整条
     线压缩成一根变短的金线（那是"进度条"的词汇），clip-path 是"笔在工作"。 */
  function startLoop() {
    for (const anim of S.loop) {
      try {
        anim.cancel();
      } catch (_) {
        /* ignore */
      }
    }
    S.loop = inks.map((ink, i) =>
      SKMotion.animate(
        ink,
        [
          { clipPath: 'inset(0 100% 0 0)' },
          { clipPath: 'inset(0 0% 0 0)', offset: 0.42 },
          { clipPath: 'inset(0 0 0 100%)' },
        ],
        {
          duration: LOADING.strokeMs,
          delay: i * LOADING.strokeStagger,
          ease: SKTokens.ease('--sk-e-write'),
          iterations: Infinity,
          fill: 'both',
        }
      )
    );
  }

  function stopLoop() {
    for (const anim of S.loop) {
      try {
        anim.cancel();
      } catch (_) {
        /* ignore */
      }
    }
    S.loop = [];
  }

  /* ------------------------------------------------------------------------- */

  function engage(text) {
    if (S.visible) {
      if (text && text !== labelEl.textContent) labelEl.textContent = text;
      return;
    }
    S.visible = true;
    S.engagedAt = performance.now();
    if (text) labelEl.textContent = text;
    if (text) labelEl.hidden = false;
    else labelEl.hidden = !label;
    root.hidden = false;
    host.dataset.loading = '1'; // 发布状态：页面样式据此让位（见文件头注释）
    startLoop();
    SKMotion.animate(root, [{ opacity: 0 }, { opacity: 1 }], {
      duration: LOADING.engageMs,
      ease: SKTokens.ease('--sk-e-out'),
      fill: 'both',
    });
  }

  function release() {
    if (!S.visible) return;
    S.visible = false;
    const fade = SKMotion.animate(root, [{ opacity: 1 }, { opacity: 0 }], {
      duration: LOADING.releaseMs,
      ease: SKTokens.ease('--sk-e-in'),
      fill: 'both',
    });
    fade.finished
      .then(() => {
        if (S.visible) return; // 退场途中又被唤回来
        root.hidden = true;
        root.style.opacity = '';
        labelEl.textContent = label;
        labelEl.hidden = !label;
        delete host.dataset.loading; // 撤回状态：让位的元素按页面自身状态复位
        stopLoop();
      })
      .catch(() => {
        stopLoop();
      });
  }

  /**
   * 跟着一个 Promise：超时才现身，就绪后兜住最短存活时间再收。
   * **返回值照原样透传** —— watch 不是 await 的替代品，它只是"顺手照顾画面"。
   *
   * @template T
   * @param {Promise<T>} promise
   * @param {object} [opts] thresholdMs / label / onEngage
   * @returns {Promise<T>}
   */
  function watch(promise, { thresholdMs = LOADING.thresholdMs, label: text, onEngage } = {}) {
    let engageTimer = window.setTimeout(() => {
      engage(text || label);
      onEngage?.();
    }, Math.max(0, thresholdMs));

    const finish = async () => {
      window.clearTimeout(engageTimer);
      engageTimer = 0;
      if (!S.visible) return;
      const alive = performance.now() - S.engagedAt;
      const rest = LOADING.minVisibleMs - alive;
      if (rest > 0) await new Promise((r) => window.setTimeout(r, rest));
      release();
    };

    return promise.then(
      async (value) => {
        await finish();
        return value;
      },
      async (err) => {
        await finish();
        throw err;
      }
    );
  }

  return {
    root,
    get visible() {
      return S.visible;
    },
    engage,
    release,
    watch,
    dispose: () => {
      stopLoop();
      delete host.dataset.loading;
      root.remove();
    },
    /** 出片/自测：正在显示时的鼠标做法与时长的核对数据 */
    state: () => ({
      visible: S.visible,
      hidden: root.hidden,
      /** host 上是否挂着让位状态 —— 页面样式（例如 meta 退场）就靠它 */
      hostFlag: host.dataset.loading === '1',
      label: labelEl.textContent,
      opacity: root.style.opacity || getComputedStyle(root).opacity,
      strokes: inks.length,
    }),
  };
}
