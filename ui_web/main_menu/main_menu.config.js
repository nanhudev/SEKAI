/* ============================================================================
   SEKAI · MAIN MENU CONFIG
   ----------------------------------------------------------------------------
   这个文件只放**数据**，不放逻辑，也没有任何副作用 —— 它必须能被 Node 直接
   import。原因和 launcher.config.js 一样：

     `ui_web/tools/emit_tokens.mjs` 要把 MENU_BOOT 生成进
     `godot/scripts/ui/ui_tokens.gd`，这样 Godot 的 MainMenu V2 读的是同一张表。

   主菜单的进场时序（beats/dur）和退场时序（exit）是"网页与 Godot 两侧必须
   逐项对上"的东西。手抄一定会漂移，漂了没人发现。生成的不可能抄错。

   所以：**时序数值改这里**，不要改 main_menu.js。改完重新跑 emitter。
   ========================================================================= */

/* ----------------------------------------------------------------------------
   进场时间表。t=0 是"纯色 + 屏幕正中的标记"这一帧 ——
   它正是 Launcher 的最后一帧（见 launcher.config.js 的 HANDOFF）。

   **两支时钟，别搞混：**
     · 本表的 beats 用的是"网页版主菜单自己的 t=0"，也就是交接帧。
     · Godot 侧的品牌段由 BootSplash 用 launcher 的 BOOT_SEQ 播（那才是"接着
       Launcher 往下演"），主菜单只负责导航/页脚/焦点这三拍。
       所以 emit_tokens.mjs 会把 beats 里的 nav/meta/focus **换算到启动时钟**上
       （办法见 emitter 里的 BRAND_ANCHOR），Godot 因此只需要一支时钟。
     · dur 是时长，没有原点问题 —— 换到哪支时钟上都一样，原样生成。
   ------------------------------------------------------------------------- */
export const MENU_BOOT = {
  beats: {
    scene: 260,
    runes: 460,
    letters: 720,
    cn: 1020,
    rule: 1150,
    subtitle: 1260,
    nav: 1420,
    meta: 1560,
    focus: 1860,
  },
  dur: {
    /** 标记起飞前的静默。这一拍就是"启动是连续的"被人眼读到的地方 ——
     *  它之前画面完全不动，和 Launcher 的最后一帧一模一样。 */
    markHomeDelay: 260,
    markHome: 800,
    scene: 1500,
    runes: 1000,
    letter: 300,
    letterStagger: 46,
    cn: 380,
    rule: 420,
    subtitle: 460,
    navItem: 420,
    navStagger: 88,
    meta: 420,
  },
  /** 退场（进入世界）总时长。Godot 侧从进场结束开始算。 */
  exit: {
    markHome: { delay: 620, duration: 780 },
    holdMs: 320,
  },
};

/* ----------------------------------------------------------------------------
   菜单项。
   cn/en 文案属于 NARRATIVE 线 —— 这里是**占位**，等术语表确认后替换。
   新增一项只需要往这里加一条，不写第二套菜单代码。

   needsSave : 没有存档时该项不可用（灰掉并在副标题说明原因，不撒谎）
   note      : 本 PASS 未接入的功能。按下不弹模态框，只在说明条里写清楚。
   ------------------------------------------------------------------------- */
export const ITEMS = [
  { id: 'continue', cn: '继续', en: 'CONTINUE', needsSave: true },
  { id: 'new', cn: '新的旅程', en: 'NEW JOURNEY' },
  { id: 'settings', cn: '设置', en: 'SETTINGS', note: '设置面板在 UI PASS 02 接入。' },
  {
    id: 'exit',
    cn: '退出',
    en: 'EXIT',
    note: 'Web 原型不关闭进程；桌面版会退出 Launcher 与游戏。',
  },
];
