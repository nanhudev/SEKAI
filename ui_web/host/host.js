/* ============================================================================
   SEKAI · HOST BRIDGE
   ----------------------------------------------------------------------------
   页面永远不直接碰宿主能力。所有"宿主能力"（预检、启动游戏、读版本、读存档、
   退出）只经过这里。

   两种运行形态：

   ┌─ mode: 'web'   （浏览器 / 逐帧出片）
   │    没有宿主。启动动效完整播放，但不真的拉起进程，并在角落说明真实原因。
   │    **不发起任何 fetch**。
   │
   └─ mode: 'native'（桌面宿主 ui_web/host/launcher_host.py）
        GET  /.host.json · GET /api/preflight · POST /api/launch · POST /api/quit

   为什么桥是"本地 HTTP"而不是 pywebview：
   pywebview 在 Windows 上要靠 pythonnet（.NET 互操作）才有 WebView2 后端，
   是一层又重又要挑 Python 版本的依赖。而这个宿主本来就是**自己起一个
   localhost 服务**（页面必须走 http 才能用 ES module），
   再多加四个路由就有完整的双向桥了 —— 零第三方依赖，且用已装好的 WebView2。
   窗口用 `msedge --app=`，本身就是无标签页的应用窗口。
   §M 明说：不要因为"原型好看"就引入不稳定的运行时层。

   为什么用 `?host=1` 而不是去探测宿主：
   探测（fetch 一个可能不存在的地址）在"没有宿主"的正常情况下会留下 404，
   而 404 是控制台里最容易被误当成 bug 的东西，还会掩盖真正的错误。
   显式参数让两种情况都干净。桌面宿主打开页面时自己带上 ?host=1。
   ========================================================================= */

const DEFAULT_CONFIG = {
  mode: 'web',
  version: '0.3.0-ui01',
  build: '2026-09-27',
  devMode: true,
  godot: 'G:\\Godot\\Godot_v4.4.1-stable_win64.exe',
  project: 'F:\\SEKAI\\godot',
  /**
   * 存档摘要。真实值由宿主读取 Godot 的存档后写进 .host.json。
   * 这里的 exists:true 是**设计评审用的占位**，好让「继续旅程」在原型里是可用态；
   * 桌面宿主会用真实存档覆盖它。playtime 的假值只服务评审构图
   * （继续旅程 / 雾栖镇 · 1:42），不是运行时数据。
   * PASS 04 §15：01:42 → 1:42 —— 去零填充，读作游戏存档而不是信息设计。
   */
  save: { exists: true, location: '雾栖镇', locationEn: 'MISTVALE', playtime: '1:42' },
  targets: [
    { id: 'main', label: '进入世界', en: 'ENTER WORLD', primary: true },
    { id: 'training', label: '训练场', en: 'TRAINING GROUND', dev: true },
    { id: 'mistvale', label: '雾谷实机检视', en: 'MISTVALE REVIEW', dev: true },
    { id: 'combat', label: '战斗沙盒', en: 'COMBAT SANDBOX', dev: true },
  ],
};

class Host {
  constructor() {
    this.mode = 'web';
    this.config = { ...DEFAULT_CONFIG };
    this._progressCbs = [];
    this._ready = false;
    this._launching = false;
  }

  get isNative() {
    return this.mode === 'native';
  }

  get devMode() {
    return !!this.config.devMode;
  }

  get version() {
    return this.config.version || '—';
  }

  get build() {
    return this.config.build || '—';
  }

  get save() {
    return this.config.save || { exists: false };
  }

  /** 可见的启动目标（正式玩家只看到 primary 那个） */
  visibleTargets() {
    const all = this.config.targets || DEFAULT_CONFIG.targets;
    return this.devMode ? all : all.filter((t) => t.primary || !t.dev);
  }

  /**
   * 决定运行形态。
   * @param {object} [opts]
   * @param {boolean} [opts.hostParam] 页面 URL 是否带 ?host=1（宿主自己加的）
   */
  async init({ hostParam = false } = {}) {
    if (!hostParam) {
      // 浏览器 / 逐帧出片：不取任何东西，零 404。
      this.mode = 'web';
      this.config = { ...DEFAULT_CONFIG, mode: 'web' };
      this._ready = true;
      return this.config;
    }

    const cfg = await this._loadConfig();
    this.config = { ...DEFAULT_CONFIG, ...cfg };
    this.mode = 'native';
    this.config.mode = 'native';
    this._ready = true;
    return this.config;
  }

  /* ---------------------------------------------------------------- 配置 */
  async _loadConfig() {
    // 宿主写文件与窗口起来之间有个空隙，且有文件系统慢的可能 ——
    // 加超时，绝不因为一个配置文件把启动流程挂住。
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), 800);
    try {
      const r = await fetch('/.host.json', { cache: 'no-store', signal: ac.signal });
      if (!r.ok) throw new Error(String(r.status));
      return await r.json();
    } catch (_) {
      // 声明了 host=1 却拿不到配置：仍然按 native 走，让 preflight 去报错。
      return {};
    } finally {
      clearTimeout(timer);
    }
  }

  /* ------------------------------------------------------------- 桥调用 */
  /** 统一的桥调用。**永不抛** —— 上层不需要 try/catch。 */
  async _call(op, payload) {
    if (!this.isNative) return { ok: false, error: 'no bridge' };
    try {
      const opts =
        payload === undefined
          ? { method: 'GET' }
          : {
              method: 'POST',
              headers: { 'content-type': 'application/json' },
              body: JSON.stringify(payload),
            };
      const r = await fetch(`/api/${op}`, opts);
      const body = await r.json().catch(() => ({}));
      if (!r.ok) return { ok: false, error: body.error || `HTTP ${r.status}`, detail: body.detail || '' };
      return body && typeof body === 'object' ? body : { ok: true };
    } catch (err) {
      return { ok: false, error: String(err?.message || err) };
    }
  }

  /* --------------------------------------------------------------- API */
  onProgress(cb) {
    this._progressCbs.push(cb);
  }

  _emitProgress(v) {
    for (const cb of this._progressCbs) cb(v);
  }

  /**
   * 预检：Godot 可执行文件与工程目录是否存在。
   * 这是 Launcher 唯一需要的"ready"来源 —— 真正的场景加载发生在 Godot 内部，
   * 由 Godot 自己的 BootSplash 负责。Launcher 不该假装知道那边的进度。
   */
  async preflight() {
    if (!this.isNative) return { ok: true, simulated: true, detail: 'web prototype' };
    return this._call('preflight');
  }

  /**
   * 启动游戏。返回 { ok, error, detail }。**永不抛** ——
   * Launcher 不能因为启动失败就死在 loading（§44）。
   */
  async launch(targetId) {
    if (this._launching) return { ok: false, error: 'already launching' };

    if (!this.isNative) {
      // Web 原型：把真实原因告诉评审者，而不是假装成功。
      return {
        ok: true,
        simulated: true,
        error: '',
        note: 'Web prototype — Godot process not spawned. Run via host/launcher_host.py for the real link.',
      };
    }

    this._launching = true;
    const res = await this._call('launch', { target: String(targetId || 'main') });
    this._launching = false;
    return res;
  }

  /** 关闭 Launcher。native 下宿主会先关窗再拉起 Godot。 */
  async quit() {
    if (!this.isNative) {
      document.body.innerHTML =
        '<p style="font:14px var(--sk-font-sans, sans-serif);color:#B8AE9C;padding:40px">' +
        'Launcher closed. (web prototype)</p>';
      return { ok: true };
    }
    return this._call('quit');
  }
}

export const SKHost = new Host();
export const HOST_DEFAULTS = DEFAULT_CONFIG;
