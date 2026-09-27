# C2B-01 · ChatGPT Web 提交包（可直接复制粘贴）

ART 对话用。Blender MCP 未连接时，人工打开 ChatGPT Web 粘贴即可。

---

## 第 1 条消息 · 角色设定

```
You are the Blender modeling code author for SEKAI, a first-person stylized next-gen fantasy RPG.

I will provide one asset brief at a time.

You must generate executable Blender 4.x Python using bpy. For complex assets, output incremental standalone chunks using:

# C2B:CHUNK <name>
...
# C2B:END

The asset will be executed in a visible Blender instance, reviewed, exported as GLB, and integrated into Godot 4.4.1.

Prioritize:
- correct metric scale
- strong silhouette
- first-person readability where relevant
- stylized next-gen fantasy design
- clean object names
- low/mid-poly real-time geometry
- PBR materials without external plugin dependencies
- sensible origins and transforms
- GLB compatibility

Do not explain the code unless asked. Generate executable Blender Python.
```

---

## 第 2 条消息 · C2B-01 Asset Brief

```
ASSET REQUEST
ID: C2B-01
Name: First Person Sword
Priority: P0
Purpose: Combat MVP — replaces the temporary three-box primitive currently in Godot
Status: SPEC READY

GAME PURPOSE
First-person sword for SEKAI Combat MVP. Must read clearly during: fast diagonal
cut, reverse cut, forward finishing thrust, block, and a 7.2-second iaido draw
ceremony. The blade is the player's constant companion in first-person view, so
it carries the entire weapon fantasy.

VISUAL STYLE
Stylized next-generation fantasy. Anime-stylized proportion with PBR materials.
Clean and sharp, original silhouette, restrained ornament.
NOT generic low-poly. NOT mobile-game toy style. NOT a random asset pack.
No oversized fantasy proportions, no large jewels, no broad glowing strips, no
decorative shapes that obscure the blade direction.
Small ancient-civilization motifs may sit at the guard and fuller only.

DIMENSIONS (metric, real world scale)
- Total length: 1.05 m
- Blade: 0.78 m
- Grip: 0.22 m
- Compact guard, no basket, no oversized crossguard

VIEWING DISTANCE
0.3 m to 1.2 m from camera. The blade must survive extreme close-up during the
iaido hold, where it sits nearly still for 0.65 s at screen center-right.

FIRST-PERSON / THIRD-PERSON
First-person only. The sword lives in its own foreground viewport in Godot.
Never needs to look good from behind or from a distance.

POLY BUDGET
Under 12,000 triangles for the sword alone. Bevel and edge definition should be
readable at 0.3 m; do not spend triangles on hidden faces.

MATERIALS
Maximum 4 material slots:
1. Steel blade — readable cutting edge and spine in close view
2. Dark wrapped grip
3. Muted warm-metal fittings
4. Optional subtle emissive inlay (guard motif only, must not glow like a torch)
PBR, no external plugin dependencies, no image textures — procedural only.

ANIMATION NEEDS
No rig, no armature. The sword is a rigid Node3D in Godot; all motion is code-driven
transform. Separate named objects so Godot can address parts individually.

MODULARITY — REQUIRED OBJECTS
- Blade
- Guard
- Grip
- Pommel
- Sheath is NOT part of this asset (separate later request)

COLLISION NEEDS
None in Blender. Godot uses Area3D active frames. Do not author gameplay collision.
Do provide named empties for: blade_tip, blade_mid, hilt, cutting_edge_center.

TRANSFORMS AND ORIGIN — CRITICAL
- Origin at grip center
- Blade extends along local +Y
- Cutting edge faces local -X
- Apply all transforms before export
- Consistent normals, no inverted faces, UV present

GODOT USAGE
Godot 4.4.1, imported as GLB scene, parented under WeaponRoot beneath the camera rig.
Existing reference pose offsets (Godot metres):
- idle position  (0.55, -0.52, -0.95)
- sheath position (-0.52, -0.43, -0.80)
- drawn position (0.36, -0.24, -0.82)
The sword pivot must sit where the hand grips it, because the hand asset (C2B-02)
will be aligned to this same origin later.

EXPORT
- GLB to: F:\SEKAI\assets\models\weapons\fp_sword.glb
- Blender source to: F:\SEKAI\assets_source\weapons\fp_sword.blend
- Script to: F:\SEKAI\assets\chat2blender\fp_sword_<chunk>.py

OUTPUT FORMAT
Three standalone chunks, each independently runnable:
# C2B:CHUNK blockout
# C2B:CHUNK details
# C2B:CHUNK export
```

---

## 提交后 · Producer 动作

1. 复制返回的 Python 到 `assets/chat2blender/fp_sword_<chunk>.py`
2. 可见 Blender 逐块执行，每块后截图
3. 视觉检查 6 项：Silhouette / Proportion / Scale / Material / First-person readability / Godot compatibility
4. 不合格 → 把 error + 截图 + 具体缺陷描述发回同一会话，要求 Fix Chunk
5. 最多 2–3 次 major iteration，80% 可用即导出接 Godot
6. 在 Godot 第一人称验收，标 `IN-GAME VERIFIED` 才算过关
