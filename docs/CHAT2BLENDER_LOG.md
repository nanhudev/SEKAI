# Chat2Blender · 2026-09-24

第一批资产：Mistvale Modular Building Kit。

1. 网页端 ChatGPT 新会话选择 GPT-5.6 Sol。提交模块清单、米制尺寸、观察距离、碰撞、动画、材质、LOD、GLB 与预算要求。
2. GPT 输出 `assets/chat2blender/mistvale_kit_blockout.py`。在可见 Blender 5.2.2 LTS 运行，12 个独立对象、600 tris；截图检查发现形体过平且灰色材质显示不足。
3. 将截图观察描述送回同一 GPT 会话。它输出 `assets/chat2blender/mistvale_kit_details.py`。再次在 Blender 运行，12 个对象、1,946 tris，木框、窗棂与屋面层次可见。
4. GPT 输出 `assets/chat2blender/mistvale_kit_export.py`。在 Blender 中导出 12 个独立 GLB 到 `assets/models/mistvale/`，保留 Blender 工作视图中模块的摆放位置。
5. `src/buildingKit.ts` 用全部 12 种模块组合村庄入口附近一栋民居。浏览器内第一人称可见验收通过：门窗、屋顶、木构和围栏比例可读，构建通过。原民居的程序化盒体已替换，仍保留简化碰撞。

剩余工作：将这套模块逐步应用到其他建筑，并制作训练场、铁匠铺、药屋等独立道具组。不可直接由开发 Agent 编写复杂 `bpy` 建模代码；规则见 `docs/AGENT_CONSTITUTION.md`。
