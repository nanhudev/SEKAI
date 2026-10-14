# SEKAI CHARACTER LINE — 角色美术 / 技术角色线

> 独立工作线。权威规格。与 COMBAT / AUDIO / ART(道具·环境) / UI / NARRATIVE **并列**，互不越界。
> 当前角色：**LIA / 莉娅**（渡工）。阶段状态见 `docs/characters/LIA_V0_AUDIT.md` 与 `PRODUCTION_BOARD.md`。

## 0. 角色

| 角色 | 做什么 |
| --- | --- |
| CHARACTER ARTIST | 造型、比例、面部、发型、服装设计取舍 |
| TECHNICAL ARTIST | 拓扑、法线、UV、材质、导出规范 |
| RIGGER | 骨架、辅骨、控制骨 vs 变形骨 |
| SKINNING ARTIST | 权重、极限姿势验证 |
| ANIMATOR | Idle / Walk / Run / Talk / Gesture |
| GODOT INTEGRATOR | GLB 导入、贴图、测试场景、实机验收 |

## 1. 目标

`Lia` 必须真正具备：高质量二次元次世代外观 · 合理拓扑 · 干净法线 · 正确部件拆分 · 可维护 UV · PBR 材质 · 完整骨骼 · 可靠蒙皮 · 干净权重 · 面部基础控制 · 头发/服装辅骨 · 可播放动作 · Godot 4.4.1 正确导入 · 可移动/对话/表演。

**不是一张漂亮静态模型。**

## 2. 美术方向（锁定）

`ANIME STYLIZED NEXT-GEN`。不是 photoreal，不是纯低模，不是手游立绘堆装饰。
Lia：清爽 · 年轻 · 旅行者/渡工 · 有辨识度 · 实用服装 · 克制幻想感。

用户已明确要求 **面部简化 / 头发简化**，为的是方便建模、法线、绑骨、刷权重。

**禁止继续增加**：碎发丝 · 复杂层叠衣摆 · 大量挂件 · 微小饰品 · 超细带子。
**目标**：`SIMPLE ENOUGH TO RIG, GOOD ENOUGH TO BE A HERO CHARACTER`。

## 3. 目录所有权

```
assets_source/characters/lia/
  00_reference/    审计数据 + 审核渲染（证据）
  01_v0_original/  LIA_v0_original.fbx  ← 只读，永不覆盖
  02_working/      重拓扑 / 清理中的工作文件
  03_rig/          骨架 / 蒙皮 / 变形测试
  04_animation/    动作
  05_texture/      UV / 贴图 / 材质
  06_export/       lia_master.blend · lia_game.glb · 交付副本
```

- **V0 只读**。所有优化基于副本。
- Source of truth：`06_export/lia_master.blend` + `lia_game.glb` + `05_texture/` + `04_animation/`。
- **禁止**散落 `lia_final_final2.blend`。
- 工具：`tools/character/*.py`（只属于本线）。文档：`docs/characters/`。

## 4. Scale 规范（硬性）

- Blender 米制，导出 `scale = 1`，Godot `1 unit = 1 m`。
- **锁定身高（颅顶）= 1.580 m**，缩放 ×1.5076，已于 PHASE 01b 应用于 `02_working/LIA_v1_base.blend`。
  缩放后包围盒 size `0.942 × 0.516 × 1.692`（1.692 = 马尾尖）。
- **锁定后整体 Scale 不再改**。要改必须先回退到重拓扑之前。
- `Anime Stylized Human Proportion`——V0 实测 7.7 头身，保持，不 Q 版不写实化。

## 5. 命名

部件：`LIA_HEAD` `LIA_BODY` `LIA_EYES` `LIA_HAIR_MAIN` `LIA_HAIR_SIDE_L/R` `LIA_TOP` `LIA_BOTTOM` `LIA_CAPE` `LIA_BELT` `LIA_BOOTS` `LIA_ACCESSORY`。
骨骼：`root` `pelvis` `spine_01..03` `neck` `head` `clavicle_l/r` `upperarm_l/r` `lowerarm_l/r` `hand_l/r` `thigh_l/r` `calf_l/r` `foot_l/r` `toe_l/r` + 五指 `thumb/index/middle/ring/pinky` 各 2–3 节 + `hair_*` / `cape_*` 辅骨。
**禁止 `Bone.001`**。坐标后缀 `_l` / `_r` 是**角色自身左右**（角色面朝 −Y 时 `_l` = +X）。

## 6. 姿势规范

正式 rest pose = **A-POSE**（非 T-Pose）：左右对称 · 手臂自然向下 35–45° · 手掌自然 · 手指轻分开 · 双腿自然站立 · 脚尖正向或极轻外展 · 脊柱中立 · 头看正前。
**这不是摆拍姿势，是 rig rest pose。**

## 7. 每阶段强制自审（不可跳过）

```
MODEL PASS     看 6 角度剪影 + 形体
RIG PASS       看极限姿势
WEIGHT PASS    看极限姿势 before/after
MATERIAL PASS  看 Godot 里
ANIMATION PASS 看视频
```
**第一次技术通过 ≠ 可以交用户。**

## 8. 错误分类（先定性，再动手）

`MODEL` `NORMAL` `UV` `MATERIAL` `RIG` `WEIGHT` `ANIMATION` `GODOT`

看到"手臂变形烂"不许同时乱改模型 / 动画 / 骨骼三个地方——先定因。

## 9. 交付审核表（CONTACT SHEET）

每个重要版本生成：Front A-Pose · Side · Back · 3/4 · Face Close-up · Shoulder 90° · Elbow 120° · Crouch · Walk Frame · Godot In-game。
工具：`tools/character/make_contact_sheet.py`。

## 10. 版本语义

```
Lia_V0 = 用户提供 FBX（SOURCE / BASE MESH，只读）
Lia_V1 = 归零 + 缩放的基底（clean base）
Lia_V2 = 重拓扑完成的干净模型
Lia_V3 = RIG CANDIDATE（第一个真 Milestone）
Lia_V4 = GAME-READY CANDIDATE
```
**禁止版本含义混乱。**

## 11. 工具与依赖

允许：Blender · Rigify · Geometry/Python helpers · 成熟 GitHub 开源工具 · 本地自动绑骨/权重辅助。
**所有自动工具最后必须经过 HUMAN-LEVEL VISUAL QA。**
**NEVER CONFUSE AUTOMATION SUCCESS WITH CHARACTER QUALITY.**

开源工具引入必须记录：`repo` / `commit 或 tag` / `license` / `reused` / `modified` → 写入 `docs/ASSET_LICENSES.md`。
**禁止**把角色源资产上传到来源不明的在线服务。优先本地可复现管线。

Rigify 可用于提高效率，但导出 Godot **只导干净变形骨架**，控制骨不带入。
变形骨与控制骨必须区分。

## 12. 权重 / 变形硬性

- 自动权重只是起点，**必须手工清理**：肩 · 腋 · 肘 · 腕 · 胯 · 裆 · 膝 · 踝 · 颈。
- 最终 **≤4 influences / vertex**；清除微小权重、对侧权重、漂移影响；Normalize。
- 极限姿势验证必做：肩（前抬/上举/抱胸）· 肘（0/45/90/130°）· 腿（高抬/蹲/大跨）· 脊柱（前屈/扭转/侧弯）· 颈（左右/上下看）。
- A-Pose 100 分但动画肩膀烂 = **FAIL**。角色是 MOVING ASSET。

## 13. 头发 / 披风

- 头发按 **大块发团**（main back / side L/R / bangs / 1–2 条签名发束）建，禁止大量细碎独立 mesh。
- 辅骨走**简单骨链**（`hair_back_01..03` 等），**不是每撮一套骨**。目标：可控次级运动，不依赖实时毛发模拟。
- 披风/发优先 **AUTHORED 简单骨骼动画**，不上一开始就复杂 Cloth。原则：`STABLE > REALISTIC`。

## 14. 面部 / 表情

- 简化但必须**真 3D**，不做纯平面贴图假脸。需要干净颊面 · 简单下颌 · 干净鼻 · 清晰眼窝 · 可控嘴唇。
- 不写实：不做毛孔 / 深法令纹 / 复杂眼睑褶皱。
- 重拓扑即预留 **eye / mouth / jaw / brow** 的 animation-friendly loop，避免"嘴一动整个脸崩"。
- 形态键第一批：`Blink_L` `Blink_R` `Mouth_A/I/U/E/O` `Smile` `Frown`。不做 50 个。
- 表情集最低：`blink` `neutral` `soft_smile` `concern` `annoyed/tense`。默认不要一直大笑。
- Lip sync 非 P0，但 rig/mesh 必须 **FUTURE READY**——不许把嘴做死。

## 15. Godot 接入

- 导出优先 **GLB / glTF 2.0**。检查 skeleton / skin / materials / animations / shape keys / scale / root。
- 专用测试场 `LiaCharacterTest.tscn`：切动画 · 转相机 · 近距检查 · 开关骨架显示 · 试表情。
  **不要每次进完整 Mistvale 测模型。**
- Gameplay 碰撞用 **capsule / interaction area**，不用真实 mesh。衣服头发不参与 gameplay collision。
- Lia 是 Hero NPC，允许比路人高质量，但仍需 game ready；不锁死极低 poly budget，也要规划 `LOD0/1/2`（短期只做 LOD0 时必须在文档写明后续）。
- 实机（MISTVALE）验收：站河边 · 走 · 转身 · 对话 · 后续坐船姿势。

## 16. 并行安全

- **只动自己的文件**。禁止 `git add -A`。
- 不修改 combat / level art / audio / ui / narrative —— 除非角色接入绝对需要，且必须先写 REQ 文档。
- 共享工作树，动别人文件前先看 mtime。

## 17. 连续工作原则

做完 PHASE 02 自动进 PHASE 03；rig 有问题自己修；自动权重失败就分析原因改手工权重。
**只有真正需要 Art Direction 决策时才停下来问。**
