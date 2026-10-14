# third_party — 外部素材登记处

本目录存放**从外部获取、非本仓原创**的素材。规则：

1. **只读**。任何时候都不要就地修改这些文件——要改就复制到
   `assets_source/characters/` / `assets_source/` 下面改。
2. **每加入一个包，必须在下面的登记表里加一行**，并在包目录里保留作者原始的
   `License.txt` / `How To Use.txt`。
3. 不允许放入来源不明或许可不明的素材。拿不准就不放。
4. `git add -A` 永远不要用（多会话共享工作树）。本目录文件较大，提交前确认是有意为之。

---

## 登记表

### 1. Quaternius · Universal Animation Library（Standard）

| | |
| --- | --- |
| 路径 | `quaternius/universal_animation_library/` |
| 许可 | **CC0 1.0 Universal**（公有领域奉献，可商用、可改、无需署名） |
| 作者 | Quaternius · <https://quaternius.com/packs/universalanimationlibrary.html> |
| 获取 | 2026-09-28 · Godot Asset Store <https://store.godotengine.org/asset/quaternius/universal-animation-library/>（实体落在 DigitalOcean Spaces `assets/64/Universal_Animation_LibraryStandard.zip`） |
| 原始文件 | `Animation Library[Standard]/License.txt`（未改动） |
| 取了什么 | 整包（14.5 MB zip）：Godot GLB、Unity FBX、Unreal FBX |
| 关键用途 | `Godot/AnimationLibrary_Godot_Standard.glb` —— **46 个动画 / 53 骨骼**，Rigify `DEF-*` 命名 |

内容：`AnimationLibrary_Godot_Standard.glb`（6.4 MB）。这是本仓动画的唯一外部来源。

### 2. Quaternius · Ultimate Modular Women

| | |
| --- | --- |
| 路径 | `quaternius/ultimate_modular_women/` |
| 许可 | **CC0 1.0 Universal** |
| 作者 | Quaternius · <https://quaternius.com/packs/ultimatemodularwomen.html> |
| 获取 | 2026-09-28 · 作者公开 Drive 文件夹（页面 "Just give me the Download"）<br>`https://drive.google.com/drive/folders/1720N9IGyQHXYvtvZJzazhxtTTlz-y2Vf` |
| 原始文件 | `License.txt` · `How To Use.txt`（未改动） |
| 取了什么 | `Humanoid Rigs/**/FBX/*`（11 个）+ 许可 + 说明 + 预览图 |
| **没取** | `Humanoid Rigs/**/Blends/`、`Separate Skeletal Meshes and Animations/`（需要时用 `tools/fetch_gdrive.py` 再拉） |

角色（**Humanoid Rig 版 = 干净骨架、无动画、供重定向**）：
Adventurer · Casual · Formal · Medieval · Punk · SciFi · Soldier · Suit · Witch · Worker

> 作者 `License.txt` 里写的是 "Ultimate Modular Males"——**是作者的复制粘贴笔误**，
> 正文许可仍是 CC0 1.0。以正文为准。

### 3. Quaternius · Ultimate Modular Characters

| | |
| --- | --- |
| 路径 | `quaternius/ultimate_modular_characters/` |
| 许可 | **CC0 1.0 Universal** |
| 作者 | Quaternius · <https://quaternius.com/packs/ultimatemodularcharacters.html> |
| 获取 | 2026-09-28 · <br>`https://drive.google.com/drive/folders/1USAAquX2JJWuA2m6zol0KUkFe3UkZ8zX` |
| 取了什么 | `Humanoid Rig/Individual Characters/FBX/*`（11 个）+ 许可 + 说明 + 预览图 |

角色：Adventurer · Beach · Casual · Casual2 · Farmer · King · Punk · Spacesuit · Suit · Swat · Worker

> ⚠️ 这一包的手指命名与女性包**不同**（`Index2/3/4.L` + `_end` 叶骨，共 62 骨）；
> 女性包是 `Index1/2/3.L`，51 骨。重定向脚本按归一化名字 + 链序位配对，两者都能吃。

### 4. Khronos · glTF Sample Assets — CesiumMan

| | |
| --- | --- |
| 路径 | `khronos/CesiumMan/` |
| 许可 | **CC-BY 4.0**（署名 Cesium，2017）——⚠️ **需要署名**，与上面 CC0 不同 |
| 来源 | <https://github.com/KhronosGroup/glTF-Sample-Assets> · 经 jsDelivr CDN 取<br>`Models/CesiumMan/glTF-Binary/CesiumMan.glb` |
| 用途 | 真人比例的 rigged humanoid 参照物，用于对照检查重定向结果 |
| 许可依据 | `Models/CesiumMan/metadata.json` → `"spdx": "CC-BY-4.0"` |

若将来要发行，署名写在 credits 里：`CesiumMan by Cesium, CC-BY 4.0`。

---

## 怎么再拉一次 / 拉别的包

Quaternius 的站点每个包页都挂了一个公开 Drive 文件夹。用本仓工具递归抓：

```bash
# 先列出（确认有什么、别盲拉）
C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe \
  tools/fetch_gdrive.py --url "<drive folder url>" --list

# 只拉需要的那部分
... --url "<url>" --out "F:/SEKAI/third_party/quaternius/<name>" \
    --filter "(?i)(^License|^How To Use|^Preview|Humanoid Rigs?/.*/FBX/)"
```

**注意**：`googleapis.com` 与 `drive.google.com` 在本机只能走 SOCKS5
（脚本默认 `--proxy socks5h://127.0.0.1:10808`，即 v2RayN）。
`drive.google.com/drive/folders/<id>` 是 JS 页面，抓不到东西；
脚本用的是仍然返回纯 HTML 的 `embeddedfolderview` 端点。

## 拿到素材之后怎么用

见 `docs/characters/THIRD_PARTY_CHARACTER_ASSETS.md`。
