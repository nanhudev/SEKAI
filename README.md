# SEKAI / 世界之外 · 云端最新快照

跨设备开发分支：`codex/cloud-latest`。新设备安装 Git 和 Git LFS 后：

```sh
git lfs install
git clone --single-branch --branch codex/cloud-latest https://github.com/nanhudev/SEKAI.git
cd SEKAI
git lfs pull
python tools/check_portable.py
```

后续运行 `git pull --ff-only` 和 `git lfs pull`。新进度需提交并推送后才可跨设备获取。
Godot 4.4.1 打开 `godot/project.godot`，游戏内村庄 v078。
Blender 5.1.2 打开 `environment_production/Terrain/v093/SEKAI_Valley_Terrain_v093.blend`。
UE 5.8.3 打开 `ue5_lab/SEKAI_StarterVillage/SEKAI_StarterVillage.uproject`，默认地图 v093。
Web 原型：Node.js 22，`npm ci`、`npm run dev`。

Codespaces 支持代码开发；UE/Blender 图形编辑需要本机或 GPU 云电脑。
项目不要求原盘符；美术 Python 自动定位项目，缓存 `.local/`。可覆盖 SEKAI_ROOT、SEKAI_RUNTIME_DIR、BLENDER_BIN、FFMPEG_BIN、PYTHON_BIN。
Windows UE 脚本需设置 UE_ENGINE_DIR 为引擎安装目录，打开已保存工程不需重新导入。
只保留最新母版及当前工程依赖；旧编号资源是最新场景必要共享依赖。v093 未同步到 Godot，视觉与路线验收未完成，见 `docs/CLOUD_HANDOFF.md`。
历史脚本依赖的旧母版已排除，继续建模从 v093 起步。更新资产后更新 CLOUD_ASSETS.json 哈希。

以下为原 Web 原型操作说明，其中固定盘符和端口描述已由上方接手方式取代。

雾栖村第一人称 RPG 可运行原型。详见 [状态](docs/STATUS.md)。

Windows 桌面可双击 **试玩SEKAI.cmd**；它调用本项目的 `play-sekai.ps1`，检查或启动本地服务器并打开游戏。项目需保留在 `F:\SEKAI`，电脑需有 Node.js。

```powershell
npm install
npm run dev
```

手动开发时浏览器打开 `http://localhost:5173/`；桌面试玩脚本使用 `http://127.0.0.1:5174/`。受限环境可改用 `npm run build`、`npm run preview`，打开 `http://localhost:4173/`。

主菜单提供继续旅程、新游戏与载入；暂停菜单可自动保存或写入 1–3 号存档位。旧版 `sekai.save.v1` 存档可读入并迁移到新版结构。

WASD 移动，鼠标环视，Shift 冲刺，空格跳跃，Ctrl 蹲下，E 交互，Esc 暂停。找到奥伦获得剑、米拉获得法杖。剑：左键连击/按住重击、右键格挡、Q 风切。法杖：Z/X/C 选择火/冰/风，左键释放。1/2 切换武器。
