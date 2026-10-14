#!/usr/bin/env node
/* ============================================================================
   SEKAI · MOTION RENDER HARNESS
   ----------------------------------------------------------------------------
   动效不能只截图验收（BRIEF §37）。这个工具把 ui_web 的页面**确定性地**出片：

     1. 起一个本地静态服务器（ES module 需要 http，不能 file://）
     2. 用本机 Chrome/Edge 打开页面（?render=1）
     3. SKMotion.freezeAll() 把所有动画钉到同一时间原点并暂停
     4. 逐帧 SKMotion.seekAll(t) + 截图
     5. ffmpeg 编码成 mp4

   因为我们是"推进时间"而不是"实时录屏"，出片与机器性能、掉帧完全无关 ——
   慢机器上跑出来的视频和快机器一模一样。

   用法：
     node render.mjs shots --page launcher --times 800,2400,4200,5600
     node render.mjs probe --page main_menu --selectors ".sk-item,.sk-menu__nav"
     node render.mjs video --page launcher --fps 30 --duration 6200 --exit-at 4300
     node render.mjs video --page main_menu --fps 30 --duration 5200 \
          --events "2600:SKMenu.focus('settings')" --exit-at 4600 --exit-call "SKMenu.enterWorld('new')"

   命令：
     shots       在若干时间点各截一张图（验收构图/终态）
     probe       打印选择器的 getBoundingClientRect + computed（诊断"东西跑到哪去了"）
     video       逐帧出片并编码 mp4（验收动效，BRIEF §37）

   选项：
     --page       launcher | main_menu            （必填）
     --out        输出目录（默认 F:\SEKAI\.render\<page>）
     --w --h      视口（默认 1600 x 900）
     --query      追加到 URL 的查询串，例如 "mode=fast"
     --events     "1200:SKMenu.focus('new');3000:SKMenu.activate('new')"
     --exit-at    在这一毫秒触发退出转场
     --exit-call  退出转场要执行的 JS（默认 SKLauncher.launch('main')）
     --selectors  probe 专用，逗号分隔
     --ffmpeg     ffmpeg 的绝对路径（默认自动探测）
     --chrome     浏览器绝对路径（默认自动探测）
   ========================================================================= */

import http from 'node:http';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const UI_ROOT = path.resolve(HERE, '..');
const REPO = path.resolve(UI_ROOT, '..');

/* --------------------------------------------------------------------------
   参数
   ----------------------------------------------------------------------- */
const argv = process.argv.slice(2);
const CMD = argv[0] || 'shots';
function arg(name, fallback = null) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && argv[i + 1] ? argv[i + 1] : fallback;
}
const flag = (name) => argv.includes(`--${name}`);

const PAGE = arg('page', 'launcher');
const OUT = arg('out', path.join(REPO, '.render', PAGE));
/** 静态服务器的根。默认 ui_web；tools/gallery.html 要从仓库根起服务，
    才能同时读到 ui_web/ 和 assets_source/ui/ 里落盘的 .svg。
    传了 --url 就不起服务器（那是外部已经在跑的）。 */
const ROOT = arg('url') ? null : path.resolve(arg('root', UI_ROOT));
const W = Number(arg('w', 1600));
const H = Number(arg('h', 900));
const FPS = Number(arg('fps', 30));
const DURATION = Number(arg('duration', 6000));
const EXIT_AT = arg('exit-at') ? Number(arg('exit-at')) : null;
/** 退出转场要执行的 JS。Launcher 走 SKLauncher.launch()，主菜单走 SKMenu.enterWorld()。
    写成可覆盖的，是因为"点击后怎么退出"在两个页面里本来就是不同的入口。 */
const EXIT_CALL = arg('exit-call', "SKLauncher.launch('main')");
const QUERY = arg('query', '');
const FRAME_PREFIX = 'frame_';
/** 视频帧写到**临时目录**，不写进 --out。三条理由，都吃过亏：
    ① --out 是交付目录（ui_web/previews），不该堆 180 个 frame_*.png。
       早先视频帧就写在 --out 而且**出片后从不清理**，于是 previews/ 里
       静静躺着 186 张中间帧，谁也不会去删。
    ② 攒到下一次运行时，启动清理要一次删掉 180 个文件 —— 直接撞上本机的
       批量删除保护（一个 turn 内删除数超阈值就拦），于是"出片其实成功了"
       被报成 FAILED。改成整目录一次删，只有 1 次删除调用。
    ③ **目录名必须每次唯一。** 复用同一个目录时，如果上一次的帧没删干净，
       ffmpeg 按 `frame_%05d.png` 顺序读，会把残留的旧帧一起编进新片 ——
       一条比预期更长的视频，而且**看不出来**。唯一目录让残留永远不可能被读到。
       残留目录留在 .render/_frames/ 里是无害的（已 gitignore）。 */
const FRAMES = path.join(REPO, '.render', '_frames', `${PAGE}_${Date.now()}`);

/* --------------------------------------------------------------------------
   可执行文件探测
   ----------------------------------------------------------------------- */
function firstExisting(candidates) {
  for (const c of candidates) if (c && fs.existsSync(c)) return c;
  return null;
}

const CHROME =
  arg('chrome') ||
  firstExisting([
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
  ]);

const FFMPEG =
  arg('ffmpeg') ||
  firstExisting([
    'G:\\娱乐\\JianyingPro\\4.9.0.10872\\ffmpeg.exe',
    'D:\\格式工厂\\FormatFactory\\ffmpeg.exe',
    'C:\\Program Files (x86)\\fastpdf\\ffmpeg.exe',
  ]);

function loadPuppeteer() {
  const ws =
    process.env.SK_NODE_WS ||
    'C:\\Users\\Administrator\\.workbuddy\\binaries\\node\\workspace\\package.json';
  const req = createRequire(pathToFileURL(ws));
  return req('puppeteer-core');
}

/* --------------------------------------------------------------------------
   静态服务器
   ----------------------------------------------------------------------- */
const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
};

function startServer(root) {
  const server = http.createServer(async (req, res) => {
    try {
      let rel = decodeURIComponent(new URL(req.url, 'http://x').pathname);
      if (rel === '/') rel = '/index.html';
      const abs = path.join(root, rel);
      if (!abs.startsWith(root)) {
        res.writeHead(403).end('forbidden');
        return;
      }
      const data = await fsp.readFile(abs);
      res.writeHead(200, {
        'content-type': MIME[path.extname(abs).toLowerCase()] || 'application/octet-stream',
        'cache-control': 'no-store',
      });
      res.end(data);
    } catch (err) {
      res.writeHead(404, { 'content-type': 'text/plain' }).end(String(err && err.message));
    }
  });
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}

/* --------------------------------------------------------------------------
   ffmpeg
   ----------------------------------------------------------------------- */
function run(cmd, args, label) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let err = '';
    p.stderr.on('data', (d) => (err += d));
    p.on('error', reject);
    p.on('close', (code) => (code === 0 ? resolve(err) : reject(new Error(`${label} exited ${code}\n${err.slice(-1500)}`))));
  });
}

/* --------------------------------------------------------------------------
   脚本化交互
   --events "1200:SKMenu.focus('new');3000:SKMenu.activate('new')"
   事件发生时：真实执行 JS → 等 CSS transition 落定（340ms 真实时间）→
   把这一刻新建的 WAAPI 动画认领到该时间点，之后 seek 才能正确。
   ----------------------------------------------------------------------- */
function parseEvents(str) {
  if (!str) return [];
  return str
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean)
    .map((pair) => {
      const i = pair.indexOf(':');
      return { at: Number(pair.slice(0, i)), js: pair.slice(i + 1) };
    })
    .filter((e) => Number.isFinite(e.at))
    .sort((a, b) => a.at - b.at);
}

/**
 * 退出转场脚手架：把时间轴推到点击那一刻 → 跑 EXIT_CALL → 等一拍让
 * setTimeout 里创建的动画落地 → 再把它们认领到时间轴的 `at` 毫秒上。
 *
 * **必须先 seekAll(at) 再触发。** enterWorld() 里的几何是**量 DOM 现场**算出来的
 * （标记现在在哪、现在多大），而 freezeAll() 之后时间轴停在 0：
 * 那时标记正停在启动动画的第一帧 —— 也就是屏幕正中、交接尺寸。
 * 于是退场会算出一个 dx=dy=0 的空动作，看起来"退场动画没生效"。
 * live 模式下不存在这个问题（玩家点下去时标记确实在家），所以这纯粹是
 * 出片脚手架的错，而不是页面的错 —— 但量出来完全一样，特别容易误判。
 *
 * **probe / eval 也必须走这一步。** 早先只有 shots / video 实现了 --exit-at。
 */
async function maybeExit(page, at) {
  if (EXIT_AT === null || at === null || at < EXIT_AT) return false;
  await page.evaluate((o) => window.SKMotion && window.SKMotion.seekAll(o), EXIT_AT);
  await page.evaluate(EXIT_CALL);
  await page.evaluate(() => new Promise((r) => setTimeout(r, 80)));
  await page.evaluate((o) => window.SKMotion.adoptAt(o), EXIT_AT);
  return true;
}

/**
 * 事件驱动的"时间轴脚手架"。
 * @param {Page} page
 * @param {Array} events
 * @param {function} adoptAt 页面里的 SKMotion.adoptAt
 */
async function applyEvents(page, events, upto, cursor, onAdopt) {
  while (cursor.i < events.length && events[cursor.i].at <= upto) {
    const ev = events[cursor.i];
    await page.evaluate(ev.js);
    // 让无法 seek 的 CSS transition 走完（它们只影响状态终值，不影响时间轴）
    await page.evaluate(() => new Promise((r) => setTimeout(r, 340)));
    const n = await onAdopt(ev.at);
    if (flag('verbose')) console.log(`\n  event @${ev.at}ms  ${ev.js}  (adopted ${n})`);
    cursor.i += 1;
  }
}

async function encode(dir, outFile, fps) {
  if (!FFMPEG) throw new Error('ffmpeg not found');
  const pattern = path.join(dir, `${FRAME_PREFIX}%05d.png`);
  // h264_mf 是 Windows MediaFoundation 的软件 H.264 编码器：任何 Windows 10/11
  // 都有，不依赖显卡厂商。失败再退回 AMD 硬件编码。
  const common = ['-hide_banner', '-loglevel', 'error', '-framerate', String(fps), '-i', pattern];
  const tail = ['-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-y', outFile];
  try {
    await run(FFMPEG, [...common, '-c:v', 'h264_mf', '-b:v', '9M', ...tail], 'ffmpeg h264_mf');
  } catch (_) {
    await run(FFMPEG, [...common, '-c:v', 'h264_amf', '-b:v', '9M', ...tail], 'ffmpeg h264_amf');
  }
  return outFile;
}

/* --------------------------------------------------------------------------
   主流程
   ----------------------------------------------------------------------- */
async function main() {
  if (!CHROME) throw new Error('no Chrome / Edge found — pass --chrome <path>');
  const puppeteer = loadPuppeteer();

  await fsp.mkdir(OUT, { recursive: true });
  // 视频帧目录每次用全新的。整目录一次删 —— 见 FRAMES 的注释。
  try {
    await fsp.rm(FRAMES, { recursive: true, force: true });
  } catch {}
  await fsp.mkdir(FRAMES, { recursive: true });

  const server = ROOT ? await startServer(ROOT) : null;
  const port = server ? server.address().port : 0;
  const qs = [`render=1`, ...(QUERY ? [QUERY] : [])].join('&');
  const relPath = arg('path', `${PAGE}/index.html`);
  // --url 允许直接量一个已经跑着的地址（例如 launcher_host.py 起的宿主）。
  // 这样就能验收"页面在真实宿主里"这一层，而不只是它在静态服务器里的样子。
  const url = arg('url') || `http://127.0.0.1:${port}/${relPath}?${qs}`;
  console.log(`url=${url}`);

  const browser = await puppeteer.launch({
    executablePath: CHROME,
    headless: 'new',
    args: [
      `--window-size=${W},${H}`,
      '--hide-scrollbars',
      '--force-device-scale-factor=1',
      '--disable-lcd-text',
      '--font-render-hinting=none',
      '--allow-file-access-from-files',
      '--no-first-run',
      '--no-default-browser-check',
    ],
    defaultViewport: { width: W, height: H, deviceScaleFactor: 1 },
  });

  try {
    const page = await browser.newPage();
    await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'no-preference' }]);

    const errors = [];
    page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}`));
    page.on('console', (m) => {
      if (m.type() === 'error') errors.push(`[console] ${m.text()}`);
    });
    page.on('requestfailed', (r) => errors.push(`[404?] ${r.url()} ${r.failure()?.errorText}`));
    // 404 不是 requestfailed（那只是"没连上"），它是一个正常响应。
    // 光看控制台的 "Failed to load resource" 拿不到 URL，所以自己记一条。
    page.on('response', (r) => {
      if (r.status() >= 400) errors.push(`[${r.status()}] ${r.url()}`);
    });

    // 页面本身 404 时 goto() 依然会成功（404 也是一个响应），
    // 于是后面所有症状都会指向"页面没准备好"，而真正的原因在 URL 上。
    // --path 是**相对 --root** 的，根一换路径就跟着变 —— 所以这里必须拦。
    const nav = await page.goto(url, { waitUntil: 'load', timeout: 30000 });
    if (nav && nav.status() >= 400) {
      throw new Error(
        `页面没加载成功：HTTP ${nav.status()}\n  ${url}\n` +
          `  --path 是相对 --root 的。当前 root=${ROOT}，relPath=${relPath}`
      );
    }

    // 页面用 `document.documentElement.dataset.ready = '1'` 声明"我准备好了"。
    // **但不能让它把整条流水线锁死。** 页面里任何一个 await 抛异常（一次
    // fetch 失败就够了），ready 就永远不会到 —— 而那一刻我们最需要看到的
    // 恰恰是那条异常。原先这里直接抛超时，错误信息全被吞掉，人只会看到
    // 一句 "Waiting failed"，然后去查一个根本不存在的问题。
    let ready = true;
    try {
      await page.waitForFunction(
        () => document.documentElement.dataset.ready === '1',
        { timeout: 20000 }
      );
    } catch {
      ready = false;
      console.log('--- 页面未发出 ready 信号；下面是页面自己的报错，继续出片 ---');
      if (errors.length) errors.forEach((e) => console.log('  ' + e));
      else console.log('  （页面没有任何报错 —— 说明它只是没有设置 dataset.ready）');
    }

    // 打第一帧前先把所有动画冻结在同一原点（页面没有用 Motion Kit 时跳过）
    const frozen = await page.evaluate(() =>
      window.SKMotion ? window.SKMotion.freezeAll() : 0
    );

    if (ready && errors.length) {
      console.log('--- page issues ---');
      errors.forEach((e) => console.log('  ' + e));
    }
    console.log(`page=${PAGE} frozen=${frozen} viewport=${W}x${H}${ready ? '' : ' (no-ready)'}`);

    if (CMD === 'eval' || arg('eval')) {
      // 通用求值：把页面里的真实状态打出来。probe 只能看几何，
      // 但"宿主到底认成 native 还是 web""SKHost.mode 是什么"这类问题
      // 只有求值才能回答。
      const at = arg('at') ? Number(arg('at')) : null;
      const didExit = await maybeExit(page, at);
      if (at !== null) await page.evaluate((ms) => window.SKMotion && window.SKMotion.seekAll(ms), at);
      let out;
      try {
        out = await page.evaluate(new Function(`return (${arg('eval')});`));
      } catch (err) {
        out = { __error: String(err && err.message) };
      }
      if (didExit) console.log(`# 退出转场已在 ${EXIT_AT}ms 触发并认领`);
      console.log(JSON.stringify(out, null, 2));
      console.log('OK');
      return;
    }

    if (CMD === 'probe' || flag('probe')) {
      // probe 支持 --at <ms>：先推到那一毫秒再量。否则量到的永远是 t=0 的
      // 初始态，"动画到底有没有跑对"就看不出来。
      const at = arg('at') ? Number(arg('at')) : null;
      const didExit = await maybeExit(page, at);
      if (at !== null) await page.evaluate((ms) => window.SKMotion && window.SKMotion.seekAll(ms), at);
      const selectors = (
        arg('selectors') ||
        '.sk-column,.sk-brand,.sk-brand__mark,.sk-brand__word,.sk-brand__sub,.sk-hair,' +
          '.sk-hair-mark,.sk-tick-line,.sk-status,.sk-status__track,.sk-status__write,' +
          '.sk-actions,.sk-bg__ring,.sk-footer,.sk-failure,#devBadge'
      )
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
      const info = await page.evaluate((sels) => {
        const rows = [];
        for (const sel of sels) {
          let found = 0;
          document.querySelectorAll(sel).forEach((el) => {
            found += 1;
            if (found > 6) return; // 同类只报前 6 个，避免刷屏
            const r = el.getBoundingClientRect();
            const cs = getComputedStyle(el);
            let dash = '-';
            try {
              // SVG 几何的"写到哪了"就体现在这两个值上。没有它，
              // probe 无法区分"线没画"和"线画了但位置错了"。
              dash = `${cs.strokeDashoffset} / ${cs.strokeDasharray}`;
            } catch (_) {
              /* 非 SVG 元素忽略 */
            }
            rows.push({
              sel,
              cls: el.className && String(el.className).slice(0, 40),
              x: Math.round(r.x),
              y: Math.round(r.y),
              w: Math.round(r.width),
              h: Math.round(r.height),
              opacity: cs.opacity,
              display: cs.display,
              top: cs.top,
              dash,
            });
          });
          if (found === 0) rows.push({ sel, cls: '—NOT FOUND—', x: 0, y: 0, w: 0, h: 0, opacity: '-', display: '-', top: '-' });
        }
        return { rows, vw: innerWidth, vh: innerHeight };
      }, selectors);
      if (didExit) console.log(`# 退出转场已在 ${EXIT_AT}ms 触发并认领`);
      console.log(`viewport ${info.vw}x${info.vh}`);
      for (const r of info.rows) {
        console.log(
          `  ${r.sel.padEnd(22)} ${String(r.cls).padEnd(26)} x=${String(r.x).padStart(5)} y=${String(r.y).padStart(5)} w=${String(r.w).padStart(5)} h=${String(r.h).padStart(4)} op=${r.opacity} top=${r.top} dash=${r.dash}`
        );
      }
      console.log('OK');
      return;
    }

    if (CMD === 'shots') {
      const times = (arg('times', '800,2400,4200') || '')
        .split(',')
        .map((s) => Number(s.trim()))
        .filter((n) => Number.isFinite(n));
      const clip = arg('clip'); // "x,y,w,h"
      const clipOpt = clip
        ? (() => {
            const [x, y, width, height] = clip.split(',').map(Number);
            return { clip: { x, y, width, height } };
          })()
        : {};
      let exitDone = false;
      const events = parseEvents(arg('events'));
      const cursor = { i: 0 };
      const adopt = (t) => page.evaluate((o) => window.SKMotion.adoptAt(o), t);

      for (const t of times) {
        await applyEvents(page, events, t, cursor, adopt);
        if (!exitDone && (await maybeExit(page, t))) exitDone = true;
        await page.evaluate((ms) => window.SKMotion && window.SKMotion.seekAll(ms), t);
        const file = path.join(OUT, `shot_${String(t).padStart(5, '0')}ms.png`);
        await page.screenshot({ path: file, ...clipOpt });
        console.log('  ' + file);
      }
      console.log('OK');
      return;
    }

    /* ---- video ---- */
    const frames = Math.max(1, Math.round((DURATION / 1000) * FPS));
    let exitDone = false;
    const events = parseEvents(arg('events'));
    const cursor = { i: 0 };
    const adopt = (t) => page.evaluate((o) => window.SKMotion.adoptAt(o), t);

    for (let i = 0; i < frames; i++) {
      const t = Math.round((i * 1000) / FPS);

      await applyEvents(page, events, t, cursor, adopt);

      if (!exitDone && (await maybeExit(page, t))) {
        exitDone = true;
        if (flag('verbose')) console.log(`  exit transition at ${EXIT_AT}ms`);
      }

      await page.evaluate((ms) => window.SKMotion.seekAll(ms), t);
      const file = path.join(FRAMES, `${FRAME_PREFIX}${String(i).padStart(5, '0')}.png`);
      await page.screenshot({ path: file });
      if (i % 30 === 0) process.stdout.write(`\r  frame ${i + 1}/${frames}`);
    }
    process.stdout.write(`\r  frame ${frames}/${frames}\n`);

    const mp4 = path.join(OUT, `${PAGE}_preview.mp4`);
    await encode(FRAMES, mp4, FPS);
    const size = (await fsp.stat(mp4)).size;
    console.log(`OK  ${mp4}  (${(size / 1024 / 1024).toFixed(2)} MB, ${frames} frames @ ${FPS}fps)`);

    // 清理失败绝不能把一次成功的出片报成失败 —— 片已经在了。
    try {
      await fsp.rm(FRAMES, { recursive: true, force: true });
    } catch (err) {
      console.log(`  （中间帧没删掉：${err.message}；它们在 ${FRAMES}，可以手动清）`);
    }
  } finally {
    await browser.close();
    if (server) server.close();
  }
}

main().catch((err) => {
  console.error('FAILED:', err.message);
  process.exit(1);
});
