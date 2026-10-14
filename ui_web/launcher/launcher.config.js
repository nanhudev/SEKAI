/* ============================================================================
   SEKAI · LAUNCHER SEQUENCE
   ----------------------------------------------------------------------------
   启动演出的**唯一时间表**。所有时间以毫秒计，从页面出现算起。

   设计原则（对应 BRIEF §5 / §6 / §7）：
   1. 不做假等待。`resolved` 只是"标题完全成立"的时刻，不是"可以进游戏"的时刻。
      真正的门是 host 报 ready。两者取晚者。
   2. 演出有最小长度（resolved），所以不会出现"闪一下就进去了"；
      但 ready 更晚时，环境层继续循环，不会出现"卡住"。
   3. 随时可 SKIP：跳到 resolved，不跳过错过的信息（信息在静态终态里都在）。
   ========================================================================= */

export const SEQUENCE = {
  /* ---------------------------------------------------------------------
     首次启动：完整演出 ~3.5s
     --------------------------------------------------------------------- */
  full: {
    runes: true,
    beats: {
      pulse: 180, // 一记极短的脉动：笔尖落到纸上的第一个痕迹
      dot: 300, // 点的落下（信标 / 观察者就位）
      markArc: 460, // 环开始绕着点被写出来
      runes: 1250, // 细几何 / 刻度线依次成形
      bgMove: 1500, // 背景开始移动（雾、环、尘）
      wordmark: 1900, // SEKAI 逐字写出
      wordmarkCN: 2480, // 世界之外
      rule: 2640, // 金色渐变短线写出来
      subtitle: 2880, // Beyond the Written Fate 字距settle + 浮出
      loading: 3150, // 加载环与加载线浮出，并开始环境循环
      resolved: 3500, // 安全点：标题完全成立，可在此结束演出
      skipHint: 1150, // SKIP 提示浮出（克制，右下）
    },
    dur: {
      pulse: 560,
      dot: 420,
      markArc: 1400,
      rune: 900,
      bgFade: 1800,
      letter: 420,
      letterStagger: 70,
      wordmarkCN: 520,
      rule: 620,
      subtitle: 700,
      loadingIn: 600,
    },
  },

  /* ---------------------------------------------------------------------
     后续启动：同一支舞，压缩到 ~1.0s。去掉细几何，标题更快写出来。
     不是"跳过动画"，是"记得这段舞所以走快板"。
     --------------------------------------------------------------------- */
  fast: {
    runes: false,
    beats: {
      pulse: 50,
      dot: 90,
      markArc: 140,
      runes: 0,
      bgMove: 60,
      wordmark: 400,
      wordmarkCN: 610,
      rule: 700,
      subtitle: 780,
      loading: 860,
      resolved: 960,
      skipHint: 400,
    },
    dur: {
      pulse: 200,
      dot: 200,
      markArc: 560,
      rune: 340,
      bgFade: 700,
      letter: 200,
      letterStagger: 34,
      wordmarkCN: 240,
      rule: 300,
      subtitle: 300,
      loadingIn: 300,
    },
  },
};

/* ---------------------------------------------------------------------------
   加载表现（§7）
   真实进度可得时，它影响"线写到哪"和"环画到哪"，而不是显示 72%。
   不可得时，线进入环境循环：一笔一笔反复写，环缓慢自转。
   ------------------------------------------------------------------------- */
export const LOADING = {
  ambientLineDuration: 1500, // 环境循环里一笔的长度
  ambientLineGap: 340, // 两笔之间的停顿
  ringSpinDuration: 24000, // 环自转一圈
  stalledAfter: 6000, // 超过这么久还没 ready，换文案（仍然不显示假进度）
  labels: {
    writing: { cn: '正在书写', en: 'WRITING' },
    still: { cn: '世界仍在成形', en: 'STILL FORMING' },
    ready: { cn: '已就绪', en: 'READY' },
  },
};

/* ---------------------------------------------------------------------------
   文案
   ------------------------------------------------------------------------- */
export const COPY = {
  wordmark: 'SEKAI',
  wordmarkCN: '世界之外',
  subtitle: 'Beyond the Written Fate',
  version: 'SEKAI',
  skip: '跳过',
  skipEn: 'SKIP',
  error: {
    cn: '无法进入世界。',
    en: 'Unable to enter world.',
  },
  webNote: 'Web 原型 · 未真正启动 Godot',
};

/** 首次启动判定用的 localStorage key。命名带版本，换演出时不会误用旧标记。 */
export const SEEN_KEY = 'sekai.launcher.seen.v1';

/* ---------------------------------------------------------------------------
   HANDOFF 现在住在 components/handoff.js
   ---------------------------------------------------------------------------
   它不再是"启动器的配置"，而是 Launcher / BootSplash / MainMenu **三个边界
   共同的合同** —— 主菜单退场也要落到同一帧，所以主菜单需要读它。
   放在这里会让依赖方向变成 main_menu → launcher，那是错的。

   这里 re-export，老引用（含 tools/emit_tokens.mjs）不会断。
   ------------------------------------------------------------------------- */
export { HANDOFF } from '../components/handoff.js';
