# Chat2Blender Production Rule

除非用户明确解除，否则所有新 Blender 资产必须通过网页版 ChatGPT → GPT-5.6 Sol → Blender Python → 可见 Blender → GLB → 游戏的流程制作。适用于建筑、角色、武器、手、家具、植物、遗迹和怪物。

本项目的 Blender 几何资产采用固定生产线。除非用户明确解除此规则，后续所有开发 Agent 必须遵守。

1. 由 SEKAI Agent 分析当前游戏真正缺少的资产，写明用途、尺寸、风格、拓扑、材质、碰撞、动画、拆件、发光、LOD、GLB 导出与性能预算。
2. 在 Agent 工作区内打开 ChatGPT 网页，调用网页端 GPT-5.6 Sol 生成 Blender 4.x `bpy` 脚本。SEKAI Agent 自身不得为节省步骤直接编写复杂 Blender Python 建模代码。
3. 要求脚本程序化生成、正确命名、统一 collection、合理 origin 与 scale、应用 transform、适合实时渲染、避免无意义高面数，并可直接导出 glTF/GLB。
4. 复杂资产按 `# C2B:CHUNK blockout/details/materials/export` 分块。每块都在可见 Blender 中运行并观察；发现问题后把截图或具体缺陷交回网页端 GPT-5.6 Sol 修正。
5. Blender 验收后导出 GLB 到 `F:\SEKAI\assets`，由 SEKAI Agent 接入游戏，并在实际游戏中验收尺度、材质、碰撞和性能。

SEKAI Agent 的职责是 Producer、Integrator、QA；网页端 GPT-5.6 Sol 是 Blender Code Generator；Blender 是 Asset Runtime。每个资产在 `docs/ASSET_LICENSES.md` 记录制作来源和用途。
