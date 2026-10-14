/* ============================================================================
   SEKAI · MAIN MENU V2 (UI PASS 02 · DE-AI / GAME-FIRST)
   ----------------------------------------------------------------------------
   与 V1（ui_web/main_menu/）并列存在，方便 A/B。V1 一行没动。

   这一版和 V1 的差别不是"调了一下"，是换了构图：
     · 背景 = 真场景渲染（Mistvale），不是渐变 + 圆环 + 粒子
     · 版面 = 不对称，UI 全部压左三分之一，右边整个留给世界
     · Logo = 左上角，不是屏幕正中的巨型装置
     · 菜单 = 纯文字，没有卡片/边框/圆角；选中只动 6px + 一条侧线 + 亮度
     · 启动 = 一条线把世界切开，不是"UI 系统启动完成"
     · 进入世界 = 不切黑，直接推进到刚才一直看着的地方

   保留不变的是**唯一真相源**：所有数值来自 ../v2.config.js，
   动画只经过 motion/motion.js 的四种语言，交接帧只认 components/handoff.js。
   ========================================================================= */

import { SKMotion } from '../../motion/motion.js';
import { SKTokens } from '../../tokens/tokens.js';
import { SKHost } from '../../host/host.js';
import { mark } from '../../svg/library.js';
import { markHome, handoffSizePx } from '../../components/mark_motion.js';
import { setupCursor } from '../../components/cursor.js';
import { uiCue, bindCues } from '../../components/ui_cue.js';
import {
  buildWorld,
  startWorldMotion,
  worldLine,
  worldOpen,
  worldSettle,
  worldHide,
  worldPush,
  worldSetFrame,
  worldExpose,
  worldWipe,
  startWorldParallax,
} from '../world/world_bg.js';
import { createLoading } from '../../components/loading_glyph.js';
import { MENU_BOOT, MENU_ITEMS, ENTER, EXIT, SETTINGS, COPY, LOADING } from '../v2.config.js';

const SEEN_KEY = 'sekai.v2.menu.seen';

const $ = (id) => document.getElementById(id);
const Q = new URLSearchParams(location.search);
const RENDER = Q.get('render') === '1';
const NO_CURSOR = Q.get('cursor') === 'native';

const S = {
  world: null,
  els: {},
  items: [],
  focused: null,
  entering: false,
  /** 启动演出是否已让位给"就位的菜单"。就位之后 Esc/点空白不再跳过。 */
  booted: false,
  bootAnims: [],
  /** 页面时钟原点（毫秒）。所有 beats 都相对它。 */
  t0: 0,
};

let T0 = 0;
const now = () => performance.now() - T0;

/* ---------------------------------------------------------------------------
   0. 起手
   ------------------------------------------------------------------------ */
function applyMotionPreference() {
  const q = Q.get('motion');
  if (q === 'reduce') SKMotion.setReduced(true);
  document.documentElement.dataset.render = RENDER ? '1' : '0';
}

/* ---------------------------------------------------------------------------
   1. 组装
   ------------------------------------------------------------------------ */

/** 标记。弧与点分开拿，启动时它们各自被"写出来"。 */
function buildMark(host, sizePx) {
  host.innerHTML = mark({ size: sizePx, stroke: 1.6, dot: 5 });
  const svg = host.querySelector('svg');
  return {
    host,
    svg,
    arc: host.querySelector('.sk-mark__arc'),
    dot: host.querySelector('.sk-mark__dot'),
  };
}

/** SEKAI 逐字排出。每个字母一个 inline-block，各自被 clip 揭开。 */
function buildWordmark(host, text) {
  host.textContent = '';
  const out = [];
  for (const ch of text) {
    const s = document.createElement('span');
    s.className = 'v2-brand__letter';
    s.textContent = ch;
    host.appendChild(s);
    out.push(s);
  }
  return out;
}

function buildBrand() {
  // 标记的**显示**尺寸交给 CSS（ui_v2.css 里的 vmin clamp），这里只画 viewBox。
  //
  // 早先想用 SKTokens.px('--sk-fs-display') 去算标记大小 —— 那是错的：
  // 字号 token 的值是 `clamp(28px, 5.33vmin, 92px)`，parseFloat 读出来是 NaN，
  // px() 会安静地返回 0，于是标记变成 0 尺寸，而画面上只是"没看到标记"。
  // 排版尺寸一律由 CSS 决定；JS 只在需要"量"的时候用 getBoundingClientRect()。
  S.els.mark = buildMark($('mark'), 128);
  S.els.letters = buildWordmark($('word'), COPY.wordmark);
  /* 字标的**宿主**要单独登记。字母各自有一个 clip 动画，退场时逐个淡太啰嗦，
     而且真正需要"跟着 UI 一起消失"的是整块字标 —— 早先只登记了 letters，
     于是 SEKAI 在这一屏的退场里**完全不淡**，转场结束后它还挂在世界的左上角。 */
  S.els.word = $('word');
  S.els.wordCN = $('wordCN');
  S.els.rule = $('rule');
  S.els.wordCN.textContent = COPY.wordmarkCN;
  // 起始：字还没写、线还没画
  for (const l of S.els.letters) l.style.clipPath = 'inset(0% 100% 0% 0%)';
  S.els.wordCN.style.opacity = '0';
  S.els.rule.style.transform = 'scaleX(0)';
}

/**
 * 一个菜单项。**纯文字**：没有卡片、没有边框、没有圆角、没有底色。
 * 选中 = 文字右移 6px + 左侧一条线竖着长出来 + 亮度变化。全部 140ms。
 */
function buildItem(def, save) {
  const el = document.createElement('button');
  el.type = 'button';
  el.className = 'v2-item';
  el.dataset.id = def.id;
  el.dataset.cue = 'confirm';

  const side = document.createElement('span');
  side.className = 'v2-item__side';

  const text = document.createElement('span');
  text.className = 'v2-item__text';

  const cn = document.createElement('span');
  cn.className = 'v2-item__cn';
  cn.textContent = def.cn;
  text.appendChild(cn);

  // 只有「继续旅程」有第二行：存档摘要。它是信息，不是装饰（§18）。
  // §6：没有存档时这项根本不进列表（buildNav 过滤），所以走到这里 save.exists 必为真。
  if (def.id === 'continue') {
    const sub = document.createElement('span');
    sub.className = 'v2-item__sub';
    const loc = document.createElement('span');
    loc.className = 'v2-item__loc';
    loc.textContent = save.location || '';
    const sep = document.createElement('span');
    sep.className = 'v2-item__sep';
    sep.textContent = '·';
    const tm = document.createElement('span');
    tm.className = 'v2-item__time';
    tm.textContent = save.playtime || '';
    sub.append(loc, sep, tm);
    text.appendChild(sub);
    el._sub = sub;
  }

  el.append(side, text);

  return {
    def,
    el,
    side,
    text,
    enabled: true,
    // 状态动画：off = 未选中，on = 选中
    sideAnim: SKMotion.stateAnim(
      side,
      [{ transform: 'scaleY(0)' }, { transform: 'scaleY(1)' }],
      { duration: 140, ease: SKTokens.ease('--sk-e-unfold') }
    ),
    textAnim: SKMotion.stateAnim(
      text,
      [{ transform: 'translateX(0px)' }, { transform: 'translateX(6px)' }],
      { duration: 140, ease: SKTokens.ease('--sk-e-out') }
    ),
  };
}

function buildNav() {
  const nav = $('nav');
  const save = SKHost.save;
  /* §6（PASS 03）：没有存档，「继续旅程」**整个不出现** ——
     不做"灰掉但仍占第一位"。灰项是 UI demo 的做法；真游戏里没有的选项就不在。 */
  const defs = MENU_ITEMS.filter((d) => !d.needsSave || save.exists);
  for (const def of defs) {
    const it = buildItem(def, save);
    nav.appendChild(it.el);
    S.items.push(it);
  }
  // 起始不可见；进场时逐项淡入
  for (const it of S.items) it.el.style.opacity = '0';
  S.els.nav = nav;
}

function buildMeta() {
  const meta = $('meta');
  const v = document.createElement('span');
  v.textContent = SKHost.version;
  meta.appendChild(v);
  S.els.meta = meta;
}

/* ---------------------------------------------------------------------------
   2. 启动
   ------------------------------------------------------------------------ */

/**
 * §9 的那条线：黑 → 只有标记 → 一条细线划过 → 线变成 world reveal mask，
 * 世界从线附近露出来 → Logo 降权、菜单出现。
 *
 * 标记**不重画**：它从交接帧就一直在屏幕正中，这里只是让它飞回左上角。
 */
function playBoot(cfg) {
  const b = cfg.beats;
  const d = cfg.dur;
  const first = cfg === MENU_BOOT.first;
  const A = S.bootAnims;

  // ① 标记从正中（交接尺寸）飞回本位 —— 先停一拍，那一拍就是"连续"被读到的地方
  A.push(markHome(S.els.mark.host, { delay: b.markHome, duration: d.markHome }));

  // ② 世界：写线 → 线变成遮罩
  if (first) {
    A.push(worldLine(S.world, { delay: b.line, duration: d.line }));
  }
  worldOpen(S.world, { delay: b.reveal, duration: d.reveal });

  // ③ Logo 成形：金线先画、字逐字写出、中文名与副标题跟上
  A.push(
    SKMotion.animate(S.els.rule, [{ transform: 'scaleX(0)' }, { transform: 'scaleX(1)' }], {
      duration: d.cn,
      delay: b.wordmark,
      ease: SKTokens.ease('--sk-e-write'),
      fill: 'both',
    })
  );
  S.els.letters.forEach((l, i) => {
    A.push(
      SKMotion.animate(
        l,
        [{ clipPath: 'inset(0% 100% 0% 0%)' }, { clipPath: 'inset(0% 0% 0% 0%)' }],
        {
          duration: d.letter,
          delay: b.wordmark + i * d.letterStagger,
          ease: SKTokens.ease('--sk-e-write'),
          fill: 'both',
        }
      )
    );
  });
  A.push(
    SKMotion.animate(S.els.wordCN, [{ opacity: 0 }, { opacity: 1 }], {
      duration: d.cn,
      delay: b.cn,
      ease: SKTokens.ease('--sk-e-out'),
      fill: 'both',
    })
  );
  // 副标题不再属于这一屏（§22/PASS 03：它是 Launcher 门上的题签）。

  // ④ 菜单：世界刚好揭完的那一刻开始逐项出现
  S.items.forEach((it, i) => {
    A.push(
      SKMotion.animate(
        it.el,
        [
          { opacity: 0, transform: 'translateX(-10px)' },
          { opacity: 1, transform: 'translateX(0px)' },
        ],
        {
          duration: d.navItem,
          delay: b.nav + i * d.navStagger,
          ease: SKTokens.ease('--sk-e-out'),
          fill: 'both',
        }
      )
    );
  });

  // ⑤ 焦点落到第一个可用项
  const firstEnabled = S.items.find((i) => i.enabled) || S.items[0];
  if (RENDER) {
    // 出片不能靠真实定时器 —— 直接挂到时间轴上
    focusItem(firstEnabled.def.id, { cue: null, at: b.focus });
  } else {
    window.setTimeout(() => focusItem(firstEnabled.def.id, { cue: 'focus' }), b.focus);
  }
}

/** 跳过（§「MUST BE SKIPPABLE」）：把所有进场动画直接推到终态。 */
function skipBoot() {
  if (S.skipped) return;
  S.skipped = true;
  S.booted = true;
  worldSettle(S.world);
  for (const a of S.bootAnims) {
    try {
      a.finish();
    } catch (_) {
      /* 某些动画不可 finish，忽略 */
    }
  }
  for (const l of S.els.letters) l.style.clipPath = 'inset(0% 0% 0% 0%)';
  S.els.rule.style.transform = 'scaleX(1)';
  S.els.wordCN.style.opacity = '1';
  S.els.mark.host.style.transform = 'none';
  for (const it of S.items) it.el.style.opacity = '1';
  const firstEnabled = S.items.find((i) => i.enabled) || S.items[0];
  focusItem(firstEnabled.def.id, { cue: null });
}

/** 进场结束后记下"看过一次"，下次就走 §30 的回头启动。 */
function markSeen() {
  try {
    localStorage.setItem(SEEN_KEY, '1');
  } catch (_) {
    /* 隐私模式下写不了，忽略 */
  }
}

/* ---------------------------------------------------------------------------
   3. 焦点 —— 菜单就是"响应"
   ------------------------------------------------------------------------ */

/**
 * §17：玩家按 W/S、方向键、鼠标、手柄，菜单必须**立刻**响应。
 * 动画只是跟着响应走，绝不让玩家等动画完成。所以这里全部 140ms。
 *
 * `at` 只有出片模式才传：那一毫秒是"状态改变"发生的时刻，
 * 由时间轴决定，而不是由真实定时器决定。
 */
function focusItem(id, { cue = 'focus', at } = {}) {
  if (S.focused === id) return;
  const next = S.items.find((i) => i.def.id === id);
  if (!next || !next.enabled) return;

  const prev = S.items.find((i) => i.def.id === S.focused);
  if (prev) {
    prev.el.classList.remove('is-focus');
    prev.sideAnim.off(at);
    prev.textAnim.off(at);
  }
  next.el.classList.add('is-focus');
  next.sideAnim.on(at);
  next.textAnim.on(at);
  S.focused = id;
  if (cue) uiCue(cue, { id });
}

function moveFocus(dir) {
  const usable = S.items.filter((i) => i.enabled);
  if (!usable.length) return;
  const cur = usable.findIndex((i) => i.def.id === S.focused);
  const nextIdx = cur < 0 ? 0 : (cur + dir + usable.length) % usable.length;
  focusItem(usable[nextIdx].def.id);
}

/* ---------------------------------------------------------------------------
   4. 进入世界 / 退出世界
   ------------------------------------------------------------------------ */

/**
 * §25：不要黑屏 fade。§14（PASS 03）定死了顺序：
 *   ① 确认的第一帧：选中项当场 resolve —— 玩家先知道"点到了"（§13）
 *   ② 未选项快速退（100ms）
 *   ③ 选中项 resolve 完才退（160ms 后）
 *   ④ Logo 淡掉
 *   ⑤ 压暗退掉 + 光抬一档（exposure）→ 推进
 *   ⑥ 一片雾从镜头前经过（§16），雾走完时已经是玩家相机
 *
 * `worldFrame` 的三个数（scale / panY / scrim）就是全部合同内容。
 */
export function enterWorld(id) {
  if (S.entering) return { ok: false, error: 'already entering' };
  S.entering = true;
  const cue = SKTokens.ease('--sk-e-in');
  const sel = S.items.find((i) => i.def.id === S.focused);

  // ① §13：反馈在第一帧。class 状态 + CSS transition（出片模式下是瞬变，
  //    恰好让第 0 帧就能拍到"已响应"）。动画绝不让玩家等。
  if (sel) sel.el.classList.add('is-resolve');

  // ② 未选项快速退 —— 全部同一拍，不搞逐项 stagger：玩家已经决定了。
  for (const it of S.items) {
    if (it === sel) continue;
    SKMotion.animate(it.el, [{ opacity: 1 }, { opacity: 0 }], {
      duration: ENTER.ui.itemsFadeMs,
      ease: cue,
      fill: 'both',
    });
  }

  // ③ 选中项：resolve 之后才退。它的消失是"被使用"，不是"被清除"。
  if (sel) {
    SKMotion.animate(sel.el, [{ opacity: 1 }, { opacity: 0 }], {
      duration: ENTER.ui.selectedFadeMs,
      delay: ENTER.ui.selectedResolveMs,
      ease: cue,
      fill: 'both',
    });
  }

  // ④ Logo 淡掉 + 那条唯一的金线收回。§25 的"logo 淡出"必须包括**字标本体**
  //    （S.els.word），否则转场结束时 SEKAI 还留在世界帧上 —— 那是要交给 Godot 的。
  SKMotion.animateAll(
    [S.els.mark.host, S.els.word, S.els.wordCN, S.els.meta],
    [{ opacity: 1 }, { opacity: 0 }],
    { duration: ENTER.ui.brandFadeMs, delay: 40, ease: cue, fill: 'both' }
  );
  SKMotion.animate(S.els.rule, [{ transform: 'scaleX(1)' }, { transform: 'scaleX(0)' }], {
    duration: ENTER.ui.brandFadeMs,
    delay: 40,
    ease: SKTokens.ease('--sk-e-in'),
    fill: 'both',
  });

  // ⑤ 压暗退掉（世界帧里没有 UI，也就没有为 UI 存在的压暗）+ 光抬一档
  SKMotion.animate(S.world.scrim, [{ opacity: 1 }, { opacity: 0 }], {
    duration: ENTER.ui.scrimFadeMs,
    delay: 60,
    ease: cue,
    fill: 'both',
  });
  worldExpose(S.world, {
    to: ENTER.exposure.to,
    duration: ENTER.exposure.durMs,
    delay: ENTER.ui.itemsFadeMs,
  });

  // ⑥ 雾带擦过（§16）+ 世界推进。雾从镜头前横过，接住相机切换。
  worldWipe(S.world, {
    durMs: ENTER.wipe.durMs,
    fromX: ENTER.wipe.fromX,
    toX: ENTER.wipe.toX,
    peak: ENTER.wipe.peak,
    delay: ENTER.wipe.delayMs,
  });
  worldPush(S.world, {
    from: ENTER.push.from,
    to: ENTER.push.to,
    panY: ENTER.push.panY,
    duration: ENTER.push.durMs,
    delay: ENTER.ui.itemsFadeMs,
  });

  // ⑦ §15：真实加载没完成时不切 Loading 屏 —— 世界保持活着，
  //    左下只有一条会走完的细线。
  //    PASS 05：这条线就是独立加载符号（components/loading_glyph.js）本身。
  //    之前 v2-load 那条线是同一语言的手写特例，两个元素同位叠放会互相压字，
  //    所以旧元素已删除 —— 一个等待只允许存在一个书写者。
  S.loader.engage(ENTER.loading.label);

  const total = ENTER.ui.itemsFadeMs + ENTER.push.durMs + ENTER.holdMs;

  // 真宿主上这一步才真的拉起 Godot。Web 原型不假装成功。
  if (!RENDER) {
    window.setTimeout(async () => {
      // PASS 05：launch 可能被 Godot 侧的世界加载拖到 3s 以上 ——
      // watch 负责"就绪后收干净"（超时那条分支已经被上面的 engage 先满足了，
      // 所以这里不需要 onEngage 再做交接）。
      const res = await S.loader.watch(SKHost.launch(id || 'main'), {
        label: COPY.enterNote,
      });
      if (!res.ok) {
        S.entering = false;
        S.loader.release();
        showFailure(`${COPY.errorCN}${SKHost.devMode ? ` ${res.error}` : ''}`);
        return;
      }
      // §21（PASS 04）：launch 成功 = Ready。loading 必须在真正进入
      // Gameplay 前结束 —— 上一版只有失败路径调 endLoading()，交接帧
      // 左下一直挂着"正在进入"。成功路径现在同样收掉。
      S.loader.release();
      if (!SKHost.isNative) {
        // 几百毫秒之后才说这句 —— 让转场的帧是干净的（§L 要的是产品画面，不是开发提示）
        window.setTimeout(() => {
          const n = $('enterNote');
          n.textContent = '原型：未真正启动游戏进程（用 host/launcher_host.py 打开才是真链路）';
          n.hidden = false;
        }, 600);
      }
    }, total);
  } else {
    // 出片 / 评审模式没有真宿主回调：线走完就收。交接帧必须干净，
    // 这是上一轮 ui_latest_09 抓到的残留（见 capture 记录）。
    window.setTimeout(() => S.loader.release(), Math.max(total, ENTER.loading.lineMs));
  }
  return { ok: true, simulated: !SKHost.isNative, total };
}

/* ---------------------------------------------------------------------------
   §15：loading 语言统一（PASS 05）
   ------------------------------------------------------------------------
   没有 Loading Screen。世界继续活着，左下角书写 = 尚未就绪。
   旧的 `beginLoading()/endLoading()` 与 `#load` 元素已删除：
   那个特例与新加载符号在**同一位置**，两个元素同时出现时细线会压在
   标签文字上（实测截图里标签上多出一串重影字）。现在只有 components/
   loading_glyph.js 一个书写者，进/退都走 S.loader。
   ------------------------------------------------------------------------ */

/** §27：退出不表演 Logo 收拢。世界再多活一秒，UI 先走，然后黑。 */
export function exitWorld() {
  SKMotion.animateAll(S.items.map((i) => i.el), [{ opacity: 1 }, { opacity: 0 }], {
    duration: EXIT.itemsFadeMs,
    ease: 'ease-in',
    fill: 'both',
  });
  SKMotion.animateAll(
    [S.els.mark.host, S.els.word, S.els.wordCN, S.els.rule, S.els.meta],
    [{ opacity: 1 }, { opacity: 0 }],
    { duration: EXIT.brandFadeMs, ease: 'ease-in', fill: 'both' }
  );
  if (!RENDER) window.setTimeout(() => SKHost.quit(), EXIT.worldHoldMs + EXIT.fadeMs);
  return { ok: true };
}

function showFailure(msg) {
  const el = $('failure');
  el.textContent = msg;
  el.hidden = false;
}

/* ---------------------------------------------------------------------------
   4.5 设置（§H，PASS 03）
   ------------------------------------------------------------------------
   不是另一套 Web 页面：覆盖左区，世界继续在后面动。
   无卡片、无玻璃板 —— 排版行 + hair 分隔线，与主菜单同一条对齐线。

   **值是真的**：写 localStorage，亮度真实作用于世界层。
   ↑↓ 移动、←→ 调整、Esc 返回。返回后焦点回到原来的菜单项（§18）。
   ------------------------------------------------------------------------ */
const Set = {
  open: false,
  values: {},
  row: 0,
  els: [], // { root, bar, num, def }
};

function settingsLoad() {
  let saved = {};
  try {
    saved = JSON.parse(localStorage.getItem(SETTINGS.storageKey) || '{}');
  } catch (_) {
    /* 坏档就当没存过 */
  }
  for (const r of SETTINGS.rows) Set.values[r.id] = Number.isFinite(saved[r.id]) ? saved[r.id] : r.def;
}

function settingsPersist() {
  try {
    localStorage.setItem(SETTINGS.storageKey, JSON.stringify(Set.values));
  } catch (_) {
    /* 隐私模式忽略 */
  }
}

/** 亮度是唯一"当场可见"的一行 —— 改的就是世界层本身。 */
function settingsApply(row) {
  const def = SETTINGS.rows[row];
  if (!def || !def.world || !S.world) return;
  // 100 = 不动滤镜；>100 提亮 <100 压暗。0.75–1.25 的范围足够"调"出差别又不毁画面。
  const v = Set.values[def.id];
  if (v === 100) {
    S.world.base.style.filter = '';
  } else {
    S.world.base.style.filter = `brightness(${(0.75 + (v / 100) * 0.5).toFixed(3)})`;
  }
}

function settingsPaint(row) {
  const e = Set.els[row];
  if (!e) return;
  const v = Set.values[e.def.id];
  e.num.textContent = `${v}`;
  e.bar.style.transform = `scaleX(${(v / 100).toFixed(3)})`;
  for (let i = 0; i < Set.els.length; i++) Set.els[i].root.classList.toggle('is-focus', i === row);
}

function buildSettings() {
  $('settingsTitle').textContent = COPY.settingsTitle;
  $('settingsHint').textContent = COPY.settingsHint;
  const host = $('settingsRows');
  for (const def of SETTINGS.rows) {
    const row = document.createElement('div');
    row.className = 'v2-setrow';

    const cn = document.createElement('span');
    cn.className = 'v2-setrow__cn';
    cn.textContent = def.cn;

    const val = document.createElement('span');
    val.className = 'v2-setrow__val';

    const bar = document.createElement('span');
    bar.className = 'v2-setrow__bar';
    const barFill = document.createElement('span');
    barFill.className = 'v2-setrow__barfill';
    bar.appendChild(barFill);

    const num = document.createElement('span');
    num.className = 'v2-setrow__num';

    val.append(bar, num);
    row.append(cn, val);
    host.appendChild(row);
    Set.els.push({ root: row, bar: barFill, num, def });
  }
  settingsLoad();
  for (let i = 0; i < Set.els.length; i++) settingsApply(i);
  settingsPaint(0);
}

function openSettings() {
  if (Set.open || S.entering) return;
  Set.open = true;
  $('settings').hidden = false;
  uiCue('open', { id: 'settings' });
  // 菜单让位：不是消失，是退到更暗一层 —— 设置关掉它们就回来（§18 的另一半）
  for (const it of S.items) it.el.classList.add('is-dimmed');
}

function closeSettings() {
  if (!Set.open) return;
  Set.open = false;
  settingsPersist();
  $('settings').hidden = true;
  uiCue('close', { id: 'settings' });
  for (const it of S.items) it.el.classList.remove('is-dimmed');
  // §18：回到设置前的那个选择，不跳回第一项
  if (S.focused) {
    const cur = S.items.find((i) => i.def.id === S.focused);
    if (cur) focusItem(S.focused, { cue: null });
  }
}

function settingsAdjust(dir) {
  const def = SETTINGS.rows[Set.row];
  if (!def) return;
  const v = Math.max(0, Math.min(100, Set.values[def.id] + dir * SETTINGS.step));
  if (v === Set.values[def.id]) return;
  Set.values[def.id] = v;
  settingsPaint(Set.row);
  settingsApply(Set.row);
  settingsPersist();
  uiCue('focus', { id: def.id });
}

function settingsMove(dir) {
  const n = SETTINGS.rows.length;
  Set.row = (Set.row + dir + n) % n;
  settingsPaint(Set.row);
  uiCue('focus', { id: SETTINGS.rows[Set.row].id });
}

/* ---------------------------------------------------------------------------
   5. 输入
   ------------------------------------------------------------------------ */
function bindInput() {
  bindCues(document);

  window.addEventListener('keydown', (e) => {
    // 设置打开时，输入整个归设置（§G17 的 Back = Esc 关设置）
    if (Set.open) {
      if (e.key === 'ArrowDown' || e.key === 's' || e.key === 'S') {
        e.preventDefault();
        settingsMove(1);
      } else if (e.key === 'ArrowUp' || e.key === 'w' || e.key === 'W') {
        e.preventDefault();
        settingsMove(-1);
      } else if (e.key === 'ArrowLeft' || e.key === 'a' || e.key === 'A') {
        e.preventDefault();
        settingsAdjust(-1);
      } else if (e.key === 'ArrowRight' || e.key === 'd' || e.key === 'D') {
        e.preventDefault();
        settingsAdjust(1);
      } else if (e.key === 'Escape' || e.key === 'Backspace') {
        e.preventDefault();
        closeSettings();
      }
      return;
    }
    if (e.key === 'ArrowDown' || e.key === 's' || e.key === 'S') {
      e.preventDefault();
      moveFocus(1);
    } else if (e.key === 'ArrowUp' || e.key === 'w' || e.key === 'W') {
      e.preventDefault();
      moveFocus(-1);
    } else if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      const it = S.items.find((i) => i.def.id === S.focused);
      if (it) activate(it);
    } else if (e.key === 'Escape') {
      // Back 键语义：启动没结束时它是"跳过"；菜单已就位后它什么都不做 ——
      // 顶级菜单按 Back 退不出游戏（§G17 的 Back 不等于退出）。
      if (!S.booted) skipBoot();
    }
  });

  // 鼠标与键盘共用同一个焦点（§17：任何一种输入都必须立刻响应）
  S.els.nav.addEventListener('pointerover', (e) => {
    const el = e.target.closest?.('.v2-item');
    if (el && !el.disabled) focusItem(el.dataset.id);
  });

  for (const it of S.items) {
    it.el.addEventListener('click', () => activate(it));
  }
  // 点空白处跳过启动（菜单就位之后，点空白不再有副作用）
  document.addEventListener('pointerdown', (e) => {
    if (S.booted) return;
    if (e.target.closest('.v2-item')) return;
    skipBoot();
  });
}

function activate(it) {
  if (!it.enabled) {
    uiCue('deny', { id: it.def.id });
    return;
  }
  uiCue('confirm', { id: it.def.id });
  if (it.def.id === 'exit') {
    exitWorld();
    return;
  }
  if (it.def.id === 'settings') {
    openSettings();
    return;
  }
  enterWorld(it.def.id);
}

/* ---------------------------------------------------------------------------
   6. main
   ------------------------------------------------------------------------ */
async function main() {
  applyMotionPreference();
  // 必须在任何 animate 之前设好：状态动画在 render 模式下走"直接吸附"而不是播放
  SKMotion.setRenderMode(RENDER);
  await SKHost.init({ hostParam: Q.get('host') === '1' });

  // 评审开关：?nosave=1 强制"没有存档"（§6）。桌面宿主用 .host.json 给真值，
  // 这里只是让"无存档构图"可以在浏览器/出片里被看到，不碰运行时链路。
  if (Q.get('nosave') === '1') SKHost.config.save = { exists: false };

  // 初次 / 回头启动（§30）。URL 可以强制，便于出片与评审对照。
  const forced = Q.get('boot');
  const seen = (() => {
    try {
      return localStorage.getItem(SEEN_KEY) === '1';
    } catch (_) {
      return false;
    }
  })();
  const cfg = forced === 'again' ? MENU_BOOT.again : forced === 'first' ? MENU_BOOT.first : seen ? MENU_BOOT.again : MENU_BOOT.first;

  buildBrand();
  buildNav();
  buildMeta();
  buildSettings();

  // PASS 05：加载符号挂在这里，三个等待点共用（世界图、进入、以及将来
  // 任何超过 3s 的等待）。阴影/流式弄口 `window.SKLoader` 出片与自测用。
  S.loader = createLoading(document.body, { variant: 'left' });

  // 世界层要等图到位才算装好 —— 否则会拍到一张空背景，
  // 而"空背景"看起来和"背景没生效"一模一样。
  // 这一段 wait > 3s（冷磁盘 / 慢磁盘上的 2–3MB 世界图）时才会有加载符号：
  // 平时它完全不存在，页面不会因为图还没到就先摆出一个 loading 状态。
  S.world = await S.loader.watch(buildWorld(document.body), { label: COPY.loadingWait });
  worldHide(S.world);
  startWorldMotion(S.world);
  startWorldParallax(S.world);

  bindInput();
  if (!NO_CURSOR && !RENDER) setupCursor($('cursor'));

  T0 = performance.now();
  playBoot(cfg);
  // 菜单就位之后 Esc/点空白不再有"跳过"的副作用
  window.setTimeout(() => {
    S.booted = true;
  }, cfg.beats.focus + 500);

  if (!RENDER) window.setTimeout(markSeen, 2600);

  // 出片脚手架靠这个等页面稳定
  document.documentElement.dataset.ready = '1';
}

/* ---------------------------------------------------------------------------
   7. 给评审 / 出片用
   ------------------------------------------------------------------------ */
window.SKMenu = {
  focus: (id) => focusItem(id, { cue: null }),
  enterWorld,
  exitWorld,
  skip: skipBoot,
  openSettings,
  closeSettings,
  host: SKHost,
  /** PASS 05：加载符号的自测/出片口（见 components/loading_glyph.js 的用法）。 */
  loader: {
    engage: (t) => S.loader.engage(t),
    release: () => S.loader.release(),
    state: () => S.loader.state(),
    watch: (p, o) => S.loader.watch(p, o),
  },
  get world() {
    return S.world;
  },
  get state() {
    return {
      focused: S.focused,
      entering: S.entering,
      booted: !!S.booted,
      settings: Set.open,
      items: S.items.map((i) => ({ id: i.def.id, enabled: i.enabled })),
    };
  },
};

main();
