/* ============================================================================
   SEKAI · TOKENS (JS bridge)
   ----------------------------------------------------------------------------
   不复制一份颜色表。所有值都从 tokens.css 的 computed style 里读，
   因此 tokens.css 是唯一真相源，JS 与 CSS 不可能漂移。

   用法：
     SKSpace.get('--sk-gold')        -> " #C9A65C"
     SKSpace.msec('--sk-t-write')    -> 1400
     SKSpace.css('--sk-e-out')       -> "cubic-bezier(...)"

   在 Node / render harness 里可以传入自定义的 root 元素。
   ========================================================================= */

export const SKTokens = (() => {
  const cache = new Map();
  let root = null;

  function el() {
    if (root && root.isConnected) return root;
    root = document.documentElement;
    return root;
  }

  /** 读取一个 CSS 变量的原始字符串（已 trim） */
  function get(name) {
    const key = name.startsWith('--') ? name : `--${name}`;
    const c = el();
    if (cache.has(key) && cache.get(key)._rev === rev) return cache.get(key)._v;
    const v = getComputedStyle(c).getPropertyValue(key).trim();
    cache.set(key, { _v: v, _rev: rev });
    return v;
  }

  let rev = 0;

  /** tokens.css 是静态的；主题切换时调用 invalidate() */
  function invalidate() {
    rev += 1;
  }

  /** 时长 token -> 毫秒数。"140ms" -> 140, "1.4s" -> 1400 */
  function msec(name) {
    const v = get(name);
    if (v.endsWith('ms')) return parseFloat(v);
    if (v.endsWith('s')) return parseFloat(v) * 1000;
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : 0;
  }

  function px(name) {
    return parseFloat(get(name)) || 0;
  }

  /** 数字 token -> number（用于 flex/grid 计算） */
  function num(name) {
    return parseFloat(get(name));
  }

  /**
   * 把 tokens.css 的静态色值解析成 [r,g,b,a] 0..1，供 canvas / SVG filter 用。
   * 支持 #rgb / #rrggbb / #rrggbbaa / rgb() / rgba()。
   */
  function rgba(name) {
    const v = get(name);
    if (!v) return [0, 0, 0, 0];
    if (v.startsWith('#')) return hexToRgba(v);
    const m = v.match(/rgba?\(([^)]+)\)/);
    if (m) {
      const parts = m[1].split(/[\s,/]+/).filter(Boolean).map(Number);
      return [parts[0] / 255, parts[1] / 255, parts[2] / 255, parts.length > 3 ? parts[3] : 1];
    }
    return [0, 0, 0, 0];
  }

  function hexToRgba(hex) {
    let h = hex.slice(1);
    if (h.length === 3) h = h.split('').map((c) => c + c).join('');
    if (h.length === 6) h += 'ff';
    return [
      parseInt(h.slice(0, 2), 16) / 255,
      parseInt(h.slice(2, 4), 16) / 255,
      parseInt(h.slice(4, 6), 16) / 255,
      parseInt(h.slice(6, 8), 16) / 255,
    ];
  }

  /** 供 <input type=color> 之类需要 hex 的地方使用 */
  function hex(name) {
    const [r, g, b] = rgba(name);
    const to = (n) => Math.round(Math.max(0, Math.min(1, n)) * 255).toString(16).padStart(2, '0');
    return `#${to(r)}${to(g)}${to(b)}`;
  }

  /** 把 token 名转成可直接喂给 WAAPI 的 easing 字符串 */
  function ease(name) {
    return get(name.startsWith('--') ? name : `--${name}`);
  }

  return { get, msec, px, num, rgba, hex, ease, invalidate, setRoot(n) { root = n; invalidate(); } };
})();

/* 全局便捷别名 —— 原型页面里直接 SK.g('--sk-gold') */
export const SK = SKTokens;

/* ============================================================================
   语义化运动常量。页面写 `SKMotion` 序列时引用这些，不写裸数字。
   ========================================================================= */
export function motionTokens() {
  return {
    t: {
      instant: SKTokens.msec('--sk-t-instant'),
      fast: SKTokens.msec('--sk-t-fast'),
      base: SKTokens.msec('--sk-t-base'),
      slow: SKTokens.msec('--sk-t-slow'),
      crawl: SKTokens.msec('--sk-t-crawl'),
      write: SKTokens.msec('--sk-t-write'),
      drift: SKTokens.msec('--sk-t-drift'),
      breathe: SKTokens.msec('--sk-t-breathe'),
    },
    e: {
      out: SKTokens.ease('--sk-e-out'),
      in: SKTokens.ease('--sk-e-in'),
      io: SKTokens.ease('--sk-e-io'),
      snap: SKTokens.ease('--sk-e-snap'),
      write: SKTokens.ease('--sk-e-write'),
      unfold: SKTokens.ease('--sk-e-unfold'),
      drift: SKTokens.ease('--sk-e-drift'),
    },
    stagger: SKTokens.msec('--sk-stagger'),
  };
}
