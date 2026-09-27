"""Capture decrypted Suno clip audio in real time via a WebAudio tap.

The Suno player feeds its <audio> element from a MediaSource-backed blob
(decrypted client-side), so the encrypted CDN stream cannot be decoded
offline. Instead we attach a MediaElementAudioSourceNode + ScriptProcessor
to the player element and record the PCM while the clip plays once.

Page side state lives in window.__tap (installed by install_tap()).
Each clip: reset() -> play clip -> collect() returns WAV base64.

Usage:
    suno_capture.py install              # install the tap in the page
    suno_capture.py grab <out.wav>       # play current clip and capture
"""

import base64
import json
import sys
import time

sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
from cdp import Page  # noqa: E402

TAP_JS = r"""
(() => {
  if (window.__tap) return 'already installed';
  const ctx = new (window.AudioContext || window.webkitAudioContext)();
  const tap = { ctx: ctx, proc: null, src: null, chunks: [], ch: 2,
                recording: false, sampleRate: ctx.sampleRate };
  window.__tap = tap;
  return 'installed rate=' + ctx.sampleRate;
})()
"""

ATTACH_JS = r"""
(async () => {
  const tap = window.__tap;
  if (!tap) return 'ERR no tap';
  await tap.ctx.resume();
  const el = [...document.querySelectorAll('audio')].find(e => (e.src || '').startsWith('blob:'));
  if (!el) return 'ERR no player element';
  if (tap.src && tap.src.__el === el) return 'attached already';
  if (tap.src) return 'ERR element changed - reinstall';
  const proc = tap.ctx.createScriptProcessor(4096, 2, 2);
  const src = tap.ctx.createMediaElementSource(el);
  src.connect(proc);
  proc.connect(tap.ctx.destination);
  proc.onaudioprocess = (e) => {
    if (!tap.recording) return;
    const n = e.inputBuffer.numberOfChannels;
    const c0 = new Float32Array(e.inputBuffer.getChannelData(0));
    const c1 = n > 1 ? new Float32Array(e.inputBuffer.getChannelData(1)) : c0;
    tap.chunks.push([c0, c1]);
  };
  tap.proc = proc;
  tap.src = src;
  tap.src.__el = el;
  return 'attached';
})()
"""

WAV_ENCODE_JS = r"""
(() => {
  const tap = window.__tap;
  if (!tap) return 'ERR no tap';
  const nChunks = tap.chunks.length;
  if (!nChunks) return 'ERR no samples';
  let total = 0;
  for (const [c0] of tap.chunks) total += c0.length;
  const rate = tap.sampleRate, ch = 2;
  const dataBytes = total * ch * 2;
  const buf = new ArrayBuffer(44 + dataBytes);
  const dv = new DataView(buf);
  const wstr = (o, s) => { for (let i = 0; i < s.length; i++) dv.setUint8(o + i, s.charCodeAt(i)); };
  wstr(0, 'RIFF'); dv.setUint32(4, 36 + dataBytes, true); wstr(8, 'WAVE');
  wstr(12, 'fmt '); dv.setUint32(16, 16, true); dv.setUint16(20, 1, true);
  dv.setUint16(22, ch, true); dv.setUint32(24, rate, true);
  dv.setUint32(28, rate * ch * 2, true); dv.setUint16(32, ch * 2, true);
  dv.setUint16(34, 16, true);
  wstr(36, 'data'); dv.setUint32(40, dataBytes, true);
  let off = 44;
  for (const [c0, c1] of tap.chunks) {
    for (let i = 0; i < c0.length; i++) {
      dv.setInt16(off, Math.max(-32768, Math.min(32767, c0[i] * 32767)), true); off += 2;
      dv.setInt16(off, Math.max(-32768, Math.min(32767, c1[i] * 32767)), true); off += 2;
    }
  }
  tap.chunks = [];
  let bin = '';
  const u8 = new Uint8Array(buf);
  const step = 0x8000;
  for (let i = 0; i < u8.length; i += step) {
    bin += String.fromCharCode.apply(null, u8.subarray(i, i + step));
  }
  return JSON.stringify({ b64: btoa(bin), seconds: (total / rate), chunks: nChunks });
})()
"""


def install(page):
    print(page.eval(TAP_JS))
    print(page.eval(ATTACH_JS))


def grab(page, out_path, clip_row=None):
    page.eval(TAP_JS)
    print("tap:", page.eval(ATTACH_JS))
    # find play control for the given row (or whatever is currently first)
    rect = page.eval("""(() => {
        const bs = [...document.querySelectorAll('button,[role=button]')]
            .filter(b => ((b.getAttribute('aria-label') || '').toLowerCase().startsWith('play')));
        const b = bs[%d];
        if (!b) return null;
        b.scrollIntoView({block: 'center'});
        const r = b.getBoundingClientRect();
        return {x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2)};
    })()""" % (clip_row if clip_row is not None else 0))
    if not rect:
        sys.exit("no play button found")
    # start recording right before clicking play
    page.eval("window.__tap.chunks = []; window.__tap.recording = true;")
    page.click_xy(rect["x"], rect["y"])
    # wait until playback ends (element paused) or 30 s cap
    for _ in range(120):
        time.sleep(0.5)
        state = page.eval("""(() => {
            const el = [...document.querySelectorAll('audio')].find(e => (e.src||'').startsWith('blob:'));
            if (!el) return 'no-el';
            return el.paused ? 'paused' : 'playing ' + el.currentTime.toFixed(1);
        })()""")
        if state == "paused":
            break
        if isinstance(state, str) and state.startswith("no-el"):
            break
    time.sleep(0.6)
    page.eval("window.__tap.recording = false;")
    payload = page.eval(WAV_ENCODE_JS)
    info = json.loads(payload)
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(info["b64"]))
    print("saved %s (%.2f s)" % (out_path, info["seconds"]))


def main():
    cmd = sys.argv[1]
    page = Page("suno")
    try:
        if cmd == "install":
            install(page)
        elif cmd == "grab":
            row = int(sys.argv[3]) if len(sys.argv) > 3 else None
            grab(page, sys.argv[2], row)
        else:
            sys.exit("unknown command")
    finally:
        page.close()


if __name__ == "__main__":
    main()
