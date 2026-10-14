#!/usr/bin/env node
/* ============================================================================
   SEKAI · SVG EMITTER
   ----------------------------------------------------------------------------
   把 svg/library.js 里的组件落成**独立 .svg 文件**，给 ART 线和 Godot 用。

   为什么要这么做（§35 / §M）：
   - 网页里这些几何是 innerHTML 注入的字符串，外面的人拿不到。
   - Godot 能直接 import .svg 当 Texture2D，所以"网页里的图标和 Godot 里的
     图标长得不一样"这件事可以从流程上消除 —— 不是靠约定，是靠同一份源。

   颜色：库里写的是 `var(--sk-x, #fallback)`。
   - 在网页里内联时吃到 tokens.css 的真实值；
   - 落成文件时 CSS 变量不存在，自动退回 fallback（= tokens.css 的同一批值）。
   两边的值都在 tokens.css 里，所以不会漂移。

   用法：
     node emit_svg.mjs                      # 输出到 ..\..\assets_source\ui
     node emit_svg.mjs --out <dir>
     node emit_svg.mjs --check              # 只报告差异，不写文件（CI 用）
   ========================================================================= */

import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  mark,
  markArcOnly,
  ringArc,
  focusLine,
  cornerFrame,
  divider,
  loadingRing,
  abilitySegment,
  locationOrnament,
} from '../svg/library.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');

const argv = process.argv.slice(2);
function arg(name, fallback = null) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}
const OUT = arg('out', path.join(REPO, 'assets_source', 'ui'));
const CHECK = argv.includes('--check');

/* ---------------------------------------------------------------------------
   清单。name / 生成函数 / 用途 / 给谁用 —— 用途写清楚，ART 才知道该替换哪一个。

   PASS 03 §D：每件还要带一个 verdict（state / identity / demote / delete），
   并且 verdict 是 **demote / delete 的不落盘**。
   理由：这些文件是给 ART 和 Godot 的交换格式。只要文件还在 assets_source 里，
   它就会被人捡回去用 —— "删掉"必须体现在磁盘上，不能只体现在注释里。
   函数仍在库里（V1 代码和历史画廊还要跑），但不再是交付资产。
   ------------------------------------------------------------------------ */
const PARTS = [
  {
    name: 'sekai_mark',
    verdict: 'identity',
    note: '品牌标记：开口的环 + 正中一点（信标 / 观察者）。16px 到 150px 都成立。同时是存档图标 / 加载字形。',
    owner: 'ART（可重绘，但缺口角度与点的比例必须保持）',
    svg: () => mark({ size: 128, stroke: 1.6, dot: 5 }),
  },
  {
    name: 'sekai_mark_arc_only',
    verdict: 'identity',
    note: '只有环、没有点。用于"点还没落下来"的过渡帧，或极小的角落水印。',
    owner: 'ART',
    svg: () => markArcOnly({ size: 128, stroke: 1.6 }),
  },
  {
    name: 'ring_arc',
    verdict: 'demote',
    note: '⛔ 不表达任何状态，只是"看起来很 SEKAI"（DE-AI 清单第 3 条）。V2 全线禁用。',
    owner: '（无 —— 已停止导出）',
    export: false,
    svg: () => ringArc({ size: 800, r: 392, from: 87, to: 389, stroke: 1 }),
  },
  {
    name: 'focus_line',
    verdict: 'state',
    note: '菜单焦点线：右端固定、左端推进，读作"这条被划上了"。stroke 用非缩放描边，所以任何宽度都是 1px。',
    owner: 'UI 自用 / Godot 菜单',
    svg: () => focusLine({ width: 400, height: 6 }),
  },
  {
    name: 'corner_frame',
    verdict: 'delete',
    note: '⛔ 装饰角框 —— 装饰边框的第一块砖。不表达状态：内容怎么变，角都不变。',
    owner: '（无 —— 已停止导出）',
    export: false,
    svg: () => cornerFrame({ w: 320, h: 200, arm: 18, stroke: 1 }),
  },
  {
    name: 'divider_key',
    verdict: 'identity',
    note: '64px 金色渐变短线。**只允许出现在 Logo 下，全片一条。**',
    owner: 'UI 自用',
    svg: () => divider({ width: 64, variant: 'key' }),
  },
  {
    name: 'divider_hair',
    verdict: 'state',
    note: '全宽 1px 细线。用于分组（设置行之间），不用于强调。',
    owner: 'UI 自用 / 面板分组',
    svg: () => divider({ width: 400, variant: 'hair' }),
  },
  {
    name: 'loading_ring',
    verdict: 'state',
    note: '环境加载环。不是进度条。注意 V2 主菜单改用 line state（§15），环留给游戏内加载。',
    owner: 'UI 自用 / Godot BootScene',
    svg: () => loadingRing({ size: 96, r: 44, stroke: 1.5 }),
  },
  {
    name: 'ability_segment',
    verdict: 'state',
    note: '能力轮盘扇区的一段扇环（不是实心块）。from/to 是角度，0 = 正右、逆时针为正。',
    owner: 'COMBAT 提供状态，UI 负责表现',
    svg: () => abilitySegment({ r0: 52, r1: 130, from: 0, to: 110, stroke: 1 }),
  },
  {
    name: 'location_ornament',
    verdict: 'state',
    note: '⚠ 只允许作为"地点标题被写出时的下划线"，必须与标题同一个 write 动画。单独/静态出现即为装饰，删。',
    owner: 'UI 自用 / 地点标题',
    svg: () => locationOrnament({ width: 120 }),
  },
];

/* ---------------------------------------------------------------------------
   落盘
   ------------------------------------------------------------------------ */
const HEAD = '<?xml version="1.0" encoding="UTF-8"?>\n';
const COMMENT = (p) =>
  `<!-- SEKAI · ${p.name}\n` +
  `     ${p.note}\n` +
  `     裁決：${p.verdict}${p.export === false ? '（不导出）' : ''}\n` +
  `     归属：${p.owner}\n` +
  `     本文件由 ui_web/tools/emit_svg.mjs 从 ui_web/svg/library.js 生成。\n` +
  `     不要直接改这里 —— 改库，然后重新运行 emitter。\n` +
  `-->\n`;

/**
 * 把 `var(--sk-gold, #C9A65C)` 解析成 `#C9A65C`。
 *
 * 这一步是**必须**的，不是洁癖：
 * 落盘的文件是交换格式，消费者是 Godot（ThorVG）、Blender 的贴图流程、
 * 或者别人的浏览器。CSS 自定义属性在里面**没有定义域** ——
 * 浏览器碰巧能吃（presentation attribute 会被当 CSS 声明代入），
 * ThorVG 不吃，于是同一条线在网页里在、在 Godot 里不在。
 * 交换格式里只允许字面值。
 */
function resolveVars(s) {
  return s.replace(/var\(\s*(--[\w-]+)\s*,\s*([^()]+?)\s*\)/g, '$2');
}

function body(svg) {
  // 独立文件必须有 xmlns（内联注入时可以省，文件里不行）
  let s = resolveVars(svg.trim());
  if (!/xmlns=/.test(s)) s = s.replace('<svg ', '<svg xmlns="http://www.w3.org/2000/svg" ');
  // 独立文件不要 class（没有 CSS 吃它）
  return s.replace(/\sclass="[^"]*"/g, '');
}

async function main() {
  const written = [];
  if (!CHECK) await fsp.mkdir(OUT, { recursive: true });

  for (const p of PARTS) {
    const svg = HEAD + COMMENT(p) + body(p.svg()) + '\n';
    const abs = path.join(OUT, `${p.name}.svg`);

    /* 被裁決掉的件：**不落盘，并且把上一轮留下的文件删掉**。
       只加注释不算删除 —— 文件只要在 assets_source 里，就还会被捡去用。 */
    if (p.export === false) {
      if (fs.existsSync(abs)) {
        if (CHECK) {
          console.log(`LEFT  ${path.relative(REPO, abs)}  (verdict=${p.verdict} —— 应被删除)`);
          process.exitCode = 1;
        } else {
          await fsp.unlink(abs);
          console.log(`  rm   ${path.relative(REPO, abs)}  (verdict=${p.verdict})`);
        }
      } else {
        console.log(`  skip ${p.name}  (verdict=${p.verdict})`);
      }
      written.push({ name: p.name, file: null, verdict: p.verdict, exported: false, note: p.note, owner: p.owner });
      continue;
    }

    if (CHECK) {
      let prev = null;
      try {
        prev = await fsp.readFile(abs, 'utf8');
      } catch (_) {
        /* 不存在 = 视为差异 */
      }
      if (prev !== svg) {
        console.log(`DIFF  ${path.relative(REPO, abs)}`);
        process.exitCode = 1;
      } else {
        console.log(`ok    ${path.relative(REPO, abs)}`);
      }
      continue;
    }
    await fsp.writeFile(abs, svg, 'utf8');
    written.push({ name: p.name, file: `${p.name}.svg`, verdict: p.verdict, exported: true, note: p.note, owner: p.owner });
    console.log(`  ${path.relative(REPO, abs)}  ${(svg.length / 1024).toFixed(1)} KB`);
  }

  if (CHECK) return;

  // 清单：ART / Godot 侧照着这个表替换，不用读代码
  const manifest = {
    generatedBy: 'ui_web/tools/emit_svg.mjs',
    source: 'ui_web/svg/library.js',
    note: '这些文件的颜色用 tokens.css 的 fallback 值。改颜色请改 ui_web/tokens/tokens.css 后重新生成。',
    parts: written,
  };
  await fsp.writeFile(path.join(OUT, 'UI_SVG_MANIFEST.json'), JSON.stringify(manifest, null, 2), 'utf8');
  console.log(`\nOK  ${written.length} parts -> ${path.relative(REPO, OUT)}`);
}

main().catch((err) => {
  console.error('FAILED:', err.message);
  process.exit(1);
});
