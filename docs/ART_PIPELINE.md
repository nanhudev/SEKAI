# ART & MODELING PIPELINE

SEKAI 所有正式 3D 美术资产的唯一产线。与 `AGENT_CONSTITUTION.md` 一致，本文件补充资产状态机与目录所有权。

## 固定链路

```
Producer / WorkBuddy（分析缺口 + 写 Asset Brief）
   ↓
ChatGPT Web · GPT-5.6 Sol（Blender bpy Code Generator）
   ↓
Blender Python 脚本（# C2B:CHUNK 分块）
   ↓
Blender MCP · 可见 Blender 执行
   ↓
视觉检查（silhouette / proportion / scale / material / FP readability）
   ↓
不合格 → 把 error + 截图 + 具体缺陷发回 ChatGPT 修
   ↓
导出 GLB
   ↓
Godot 集成
   ↓
第一人称实机验收（唯一过关标准）
```

## 角色边界

| 角色 | 做什么 | 不做什么 |
| --- | --- | --- |
| WorkBuddy | Producer / Integrator / QA；写 brief、执行脚本、导出、接入、验收 | 不自己写复杂 bpy 建模代码 |
| ChatGPT Web | 生成可执行的 Blender 4.x `bpy` | 不管游戏逻辑 |
| Blender MCP | 开 Blender、跑脚本、整理 scene、rename、collection、导出 | 不大规模重写模型；脚本报错交回 ChatGPT |

## 分块规则

复杂资产必须分块，每块独立可运行：

```
# C2B:CHUNK blockout
...
# C2B:END

# C2B:CHUNK details
...
# C2B:END

# C2B:CHUNK export
...
# C2B:END
```

禁止一次生成巨大脚本再整体调试。

## 状态机

```
REQUESTED → SPEC READY → GENERATING → BLENDER RUN
   → VISUAL REVIEW → FIXING → EXPORT READY
   → IN GODOT → IN-GAME VERIFIED
```

`IN GODOT` 不等于完成。只有 `IN-GAME VERIFIED` 才算过关。

## 迭代上限

Combat MVP 每个资产最多 2–3 次 major visual iteration。达到 80% 可用先接 Godot，在实机里看。
Blender 里好看 ≠ 第一人称里好看。Godot 第一人称是唯一验收场。

## 风格

Anime Stylized Fantasy + Stylized Next-Gen + PBR。
禁止 generic low-poly、mobile-game toy style、随机素材包。

性能：60 FPS > 面数炫技。FP Sword 可以近看；Sentinel 适合拆件；Town 以后大量实例化。

## 目录所有权

| 用途 | 路径 |
| --- | --- |
| Blender 源文件（永久保留） | `F:\SEKAI\assets_source\` |
| 生成脚本 | `F:\SEKAI\assets\chat2blender\` |
| 正式导出 GLB | `F:\SEKAI\assets\models\` |
| Godot 使用 | `F:\SEKAI\godot\models\` |
| Brief | `F:\SEKAI\docs\asset_briefs\` |
| 执行日志 | `F:\SEKAI\docs\CHAT2BLENDER_LOG.md` |

不要产生多套重复模型。

## 不归 Blender 管

Magic Circle、Iaido 屏幕裂痕、HUD → Godot Shader / VFX。
Suno / 音频 → AUDIO 对话。
