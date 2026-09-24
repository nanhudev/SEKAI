# SEKAI / 世界之外

雾栖村第一人称 RPG 可运行原型。详见 [状态](docs/STATUS.md)。

Windows 桌面可双击 **试玩SEKAI.cmd**；它调用本项目的 `play-sekai.ps1`，检查或启动本地服务器并打开游戏。项目需保留在 `F:\SEKAI`，电脑需有 Node.js。

```powershell
npm install
npm run dev
```

手动开发时浏览器打开 `http://localhost:5173/`；桌面试玩脚本使用 `http://127.0.0.1:5174/`。受限环境可改用 `npm run build`、`npm run preview`，打开 `http://localhost:4173/`。

主菜单提供继续旅程、新游戏与载入；暂停菜单可自动保存或写入 1–3 号存档位。旧版 `sekai.save.v1` 存档可读入并迁移到新版结构。

WASD 移动，鼠标环视，Shift 冲刺，空格跳跃，Ctrl 蹲下，E 交互，Esc 暂停。找到奥伦获得剑、米拉获得法杖。剑：左键连击/按住重击、右键格挡、Q 风切。法杖：Z/X/C 选择火/冰/风，左键释放。1/2 切换武器。
