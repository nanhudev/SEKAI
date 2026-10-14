#!/usr/bin/env node
/* ============================================================================
   SEKAI · PNG PIXEL SAMPLER
   ----------------------------------------------------------------------------
   用途：验收"这一帧到底等于什么颜色"。这不是可有可无的谨慎 ——
   本项目已经**两次**把渲染/量测假象当成代码 bug（一次是渐变线其实没画，
   一次是我自己量错了行），两次都是靠"把像素读出来"才定性的。
   眼睛和缩略图在这类判断上不可靠，数字可靠。

   零依赖：Node 内置 zlib 解压 IDAT，自己反 PNG 滤波器。
   支持 8bit 灰阶/RGB/RGBA、非隔行 —— 也就是 Chrome 截图会产出的那些。

   用法：
     node sample_png.mjs <file.png>
     node sample_png.mjs <file.png> --rows 440,448,456
     node sample_png.mjs <file.png> --json

   输出：
     · 四角 + 四边中点的颜色（"是不是纯色"）
     · 视口内最亮像素的位置与颜色（"那个点在不在该在的地方"）
     · 主色直方图前几名（"画面里到底有几种颜色"）
     · 可选：指定行的游程（"这一行有哪些非底色区段"）
   ========================================================================= */

import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';

const argv = process.argv.slice(2);
const file = argv[0];
if (!file || file.startsWith('--')) {
  console.error('用法: node sample_png.mjs <file.png> [--rows y1,y2] [--json]');
  process.exit(2);
}
const AS_JSON = argv.includes('--json');
const rowsArg = (() => {
  const i = argv.indexOf('--rows');
  return i >= 0 && argv[i + 1] ? argv[i + 1].split(',').map(Number) : [];
})();

/* ---------------------------------------------------------------------------
   1. 解 PNG
   ------------------------------------------------------------------------ */
function decodePng(buf) {
  if (buf.readUInt32BE(0) !== 0x89504e47) throw new Error('不是 PNG');
  let pos = 8;
  let w = 0, h = 0, depth = 0, colorType = 0, interlace = 0;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    const data = buf.subarray(pos + 8, pos + 8 + len);
    if (type === 'IHDR') {
      w = data.readUInt32BE(0);
      h = data.readUInt32BE(4);
      depth = data[8];
      colorType = data[9];
      interlace = data[12];
    } else if (type === 'IDAT') {
      idat.push(data);
    } else if (type === 'IEND') {
      break;
    }
    pos += 12 + len;
  }
  if (depth !== 8) throw new Error(`只支持 8bit，遇到 ${depth}`);
  if (interlace !== 0) throw new Error('不支持隔行扫描');
  const channels = { 0: 1, 2: 3, 4: 2, 6: 4 }[colorType];
  if (!channels) throw new Error(`不支持的 colorType ${colorType}`);

  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * channels;
  const out = Buffer.alloc(stride * h);

  const paeth = (a, b, c) => {
    const p = a + b - c;
    const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
  };

  let rp = 0;
  for (let y = 0; y < h; y += 1) {
    const ft = raw[rp++];
    const rowOff = y * stride;
    const prevOff = rowOff - stride;
    for (let x = 0; x < stride; x += 1) {
      const v = raw[rp++];
      const a = x >= channels ? out[rowOff + x - channels] : 0;
      const b = y > 0 ? out[prevOff + x] : 0;
      const c = y > 0 && x >= channels ? out[prevOff + x - channels] : 0;
      let val;
      switch (ft) {
        case 0: val = v; break;
        case 1: val = v + a; break;
        case 2: val = v + b; break;
        case 3: val = v + ((a + b) >> 1); break;
        case 4: val = v + paeth(a, b, c); break;
        default: throw new Error(`未知滤波器 ${ft} @ row ${y}`);
      }
      out[rowOff + x] = val & 0xff;
    }
  }
  return { w, h, channels, data: out };
}

/* ---------------------------------------------------------------------------
   2. 取样
   ------------------------------------------------------------------------ */
const img = decodePng(fs.readFileSync(path.resolve(file)));
const { w, h, channels, data } = img;
const px = (x, y) => {
  const o = (y * w + x) * channels;
  if (channels === 1) return [data[o], data[o], data[o]];
  if (channels === 2) return [data[o], data[o], data[o]];
  return [data[o], data[o + 1], data[o + 2]];
};
const hex = (c) => '#' + c.map((v) => v.toString(16).padStart(2, '0')).join('');
const sum = (c) => c[0] + c[1] + c[2];

const corners = {
  '左上': px(0, 0),
  '右上': px(w - 1, 0),
  '左下': px(0, h - 1),
  '右下': px(w - 1, h - 1),
};
const flanks = {
  '上中': px(w >> 1, 0),
  '下中': px(w >> 1, h - 1),
  '左中': px(0, h >> 1),
  '右中': px(w - 1, h >> 1),
};

let bright = { c: [0, 0, 0], x: -1, y: 0 };
const hist = new Map();
for (let y = 0; y < h; y += 1) {
  for (let x = 0; x < w; x += 1) {
    const c = px(x, y);
    const s = sum(c);
    if (s > sum(bright.c)) bright = { c, x, y };
    const k = hex(c);
    hist.set(k, (hist.get(k) || 0) + 1);
  }
}

/* 指定行的游程：把这一行里"连续同色"的区段列出来。
   "线画出来了没有"这种问题，看游程比看缩略图可靠得多。 */
const runs = {};
for (const y of rowsArg) {
  if (!(y >= 0 && y < h)) continue;
  const segs = [];
  let start = 0;
  let cur = hex(px(0, y));
  for (let x = 1; x < w; x += 1) {
    const k = hex(px(x, y));
    if (k !== cur) {
      segs.push({ from: start, to: x - 1, n: x - start, color: cur, sum: sum(px(start, y)) });
      start = x;
      cur = k;
    }
  }
  segs.push({ from: start, to: w - 1, n: w - start, color: cur, sum: sum(px(start, y)) });
  // 只留非纯底色的（底色 = 该行出现最多且贴着两端的那个色）
  runs[y] = segs;
}

const top = [...hist.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6);

if (AS_JSON) {
  console.log(
    JSON.stringify(
      {
        file,
        size: `${w}x${h}`,
        channels,
        corners,
        flanks,
        brightest: { ...bright, hex: hex(bright.c) },
        histogram: top.map(([color, n]) => ({ color, n, pct: +((n / (w * h)) * 100).toFixed(3) })),
        runs,
      },
      null,
      2
    )
  );
} else {
  console.log(`${path.basename(file)}   ${w}x${h}  ch=${channels}`);
  console.log('  四角: ' + Object.entries(corners).map(([k, v]) => `${k}=${hex(v)}`).join('  '));
  console.log('  四边: ' + Object.entries(flanks).map(([k, v]) => `${k}=${hex(v)}`).join('  '));
  console.log(`  最亮: ${hex(bright.c)} @ (${bright.x}, ${bright.y})  sum=${sum(bright.c)}`);
  console.log('  主色: ' + top.map(([c, n]) => `${c} ${((n / (w * h)) * 100).toFixed(2)}%`).join('  '));
  for (const y of Object.keys(runs)) {
    console.log(`  第 ${y} 行游程:`);
    for (const s of runs[y]) {
      console.log(`      x ${String(s.from).padStart(4)}..${String(s.to).padStart(4)}  ${s.color}  sum=${s.sum}`);
    }
  }
}
