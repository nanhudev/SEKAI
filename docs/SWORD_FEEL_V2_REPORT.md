# SWORD FEEL V2 REPORT

## Current-state audit (before this pass)

| Area | Verified implementation | Feel problem | Planned change |
|---|---|---|---|
| Sword / attach | Sword_FP.tscn under TempSwordVisual; real v9 blade and saya; registry anchors | Tall vertical idle silhouette, apparent forward-mounted weapon | Lower, inward-loaded idle; preserve original mesh/axes and curved seating |
| Hand / body | SwordHandPresentation gloves and camera-space sleeve segments | Hand follows blade; elbow contribution is one generic pulse | Separate shoulder anticipation, elbow acceleration and recovery; small wrist/grip movement at rest |
| Idle animation | AnimationPlayer library; seek uses progress=0 when no move | Idle clip never advances | Breathing clock, minute wrist/finger adjustments; stop breathing during Iaido |
| Basic chain | A1 right draw-cut, A2 return/wave, A3 triple spatial sequence, A4 270-degree arc | A3 is not the requested body-led uppercut; follow-through feels generic | Genuine single rising A3; distinct preparation/acceleration/settle for all four |
| Iaido | 2.75s combat resource + preserved 9.9s Demo, real bore draw, 0.933-turn recovery | Appearance relies on cyan/void and existing long sound cues | Cold steel at draw, restrained world seam, ordered single turn/bore closure and new dedicated audio |
| VFX | Historical ribbon, wave, scars, sector arc, contact sparks | Broad translucent blade sweep and cyan emphasis | Short outer-blade wake, subtle pressure, controlled impact and seam residual |
| Audio | Layered atom registry; previous pass retimed existing Suno/SA3 assets | Four physical swing identities absent; some groups still pending | Offline Stable Audio 3 SFX regeneration, source/seed manifest, material separation and local installation |
| Camera | Positional recoil, FOV, hitstop, trauma cap | Camera can compensate for absent body movement | Keep small camera gain; source motion in shoulder/wrist instead |
| Materials | Imported steel/cutting face/spine slots | Smooth materials have little age or moving surface detail | Subtle directional polish/wear shader on existing blade surfaces; no mesh replacement or rune glow blanket |

Audio source verified on this machine: `F:/SEKAI-AUDIO/venv`, `F:/SEKAI-AUDIO/stable-audio-3`, local weights `F:/SEKAI-AUDIO/models`, provider adapter `F:/SEKAI-WT/audio-dev/audio_source/tools/sfx_provider.py`. Voicebox is a speech route and will not be used to fake sword SFX. New raw/processed outputs are staged on E: because F: has little free space.

Implementation follows existing controller/pose/audio owners. No new scene, skill tree, weapon mesh or combat framework.

## Animation Changes

- 第一人称待机从 `(0.52,-0.50,-0.94)` 改为 `(0.40,-0.36,-0.76)`，内收、抬高握柄，让握力、手腕与前臂在画面中可见。原剑、Saya 和安装坐标继续使用。
- 修复 Idle AnimationPlayer 被反复定位到第零帧的问题。加入 4.6 秒呼吸、7.7 秒微调周期，位置仅毫米级、角度不足一度；握力变化约 0.6%。只有正常待机且刀完全离鞘时叠加，居合屏息期间停止。
- 编辑原生 `SwordPresentation.tres` 的十段动作。四刀分别有肩部准备、肘部加速、惯性延续与回收；新增左上臂段，左右臂在同一身体坐标下反向配合。
- A1 保持短促右向拔切；A2 保持左回斩及已有压力波；A3 **从三次远程空间斩替换为单次身体上挑**，0.16 秒准备、0.14 秒加速、0.12 秒延续、0.26 秒恢复，近身命中向上推动；A4 保持 270 度优弧及合理收势。
- 现有训练区的远处/偏轴靶随 A3 改动转为负对照，避免零距离靶和“上挑还能隔空打人”。
- 居合沿用已有 2.75 秒战斗流程：物理收刀、蓄势、沿鞘轴拔刀、斩击、约 0.933 圈整理、贴鞘口滑入。保留独立 9.9 秒演示档及退出恢复路径。

## VFX Changes

- 普通刀迹仅使用刀身外侧 45%，降低透明度，改成近白空气切割，避免宽蓝色塑料带。
- A2 压力波变薄、降低不透明度与箭尖外扩；A4 继续使用连续优弧扇段。接触火花继续限制数量，既有材质命中定位保持正常。
- 战斗居合降低全屏冷光闪烁，将裂缝边缘及内层改成克制的钢灰色。保留切线、空间裂缝和结束前的残留线；没有新增满屏粒子系统。
- 原有剑面使用新的 PBR 钢材 shader，包含很弱的纵向打磨纹和不规则磨损、分面的粗糙度变化。运行时确认四个剑面使用该材质。**GLB 形状与骨架没有替换。**

## Audio Changes

本机现有 Stable Audio 3 small-sfx 模型实际生成 **14 个新声音**：draw、swing_a1–a4、hit_metal/body/stone/wood、iaido_cut/pressure、sheath_slide/click、parry。

- 每项独立提示词/种子，先生成 2 秒原始音频，再保留动作起音、去直流、裁切及短尾淡出；没有合成临时 sine/swish 占位音替代模型输出。
- 使用现有 SoundAtomRegistry 与 LayeredSFX，四刀拥有不同声音身份。命中仍在目标位置空间化；挥剑仍属于玩家手部。
- 战斗居合改为八个克制声点：收刀摩擦、首次贴合、拔刀金属、瞬间切割、低频压力、轻微整理、沿鞘摩擦、最终闭合。蓄势留白，既有世界声音压低仍有效；长演示保留其原声轨。
- 原始 take 全部没有检测到削波；安装文件峰值约 -12.30 至 -6.02 dBFS。完整电影原生混音峰值 **-3.07 dBFS，削波比例 0**。
- CPU 加载曾出现 native access violation。生成脚本使用逐 tensor 读取既有 checkpoint、BF16 构建后 FP32 CPU 推理解决；首个 draw 是 BF16 推理，其余为 FP32，来源清单明确记录。未下载新模型、未修改外部模型工程、未使用在线生成服务。
- 波形、文件可加载性、声音调用及电影混音已验证；**尚未由真人盲听验收“真实金属”和四刀可辨性**，不把模型输出或指标当作音色验收。

原始/处理音频与完整来源：`E:/SEKAI-SwordFeelV2-20261012/audio/`。工程内来源副本：`F:/SEKAI/audio_source/generated/sword_feel_v2_manifest.json`。

## Camera Changes

- A2 FOV kick 从 +1.6 改为 -0.75，A3 为 -0.65，A4 从 +2.2 改为 -1.1，避免大幅扩张镜头抢走动作主体。
- A3 使用轻微向上响应与 45 ms 命中停顿；四刀 hitstop 分别 32/38/45/80 ms，保留重攻击 90 ms。
- 保留之前已接通的 6/10 mm 接触后坐、平滑衰减与有限震动；肩腕曲线负责主体动作。
- 居合继续使用既有减速、停顿、FOV 拉伸及恢复。结束、取消、死亡后均恢复世界/摄像机所有权。

## Verification and Demo

在 Godot 4.4.1 Compatibility / RX 6650 XT 实际渲染下检查，以下检查返回成功：

| 检查 | 结果 |
|---|---|
| sword_core_regression | A3 单次伤害 46 / 姿态 26，A2 本体/波刃去重及延迟归属 |
| sword_basic_v2 | 全链 A1–A4、近处上挑、远处不命中、四个优弧靶、组合重置与切武器 |
| sword_polish_regression | 扇段连续、恢复采样、历史刀迹与 30/144 FPS 消失时间 |
| sword_feel_v2 | Idle/握力实际推进、四个钢材面、远距 A3 无伤害、14 个音频可加载、八点居合音轨 |
| combat_audio_language | 170 atoms / 82 groups / 30 cues；空间定位、响度、格挡层次及声音触发 |
| sword_upgrade_integration | 战斗居合完整阶段、结束/取消/死亡恢复、保留长演示档、招架事件 |
| probe_blade_clearance | 鞘口最差偏轴约 2.7 mm；刀尖没有穿出鞘壁 |

验收影片：**`E:/SEKAI-SwordFeelV2-20261012/Sword Polish Demo.mp4`**。41.283 秒、1152×648、60 FPS、H.264 + 原生声音 AAC。使用现有 TrainingGround 和真实输入处理路径，明确标注靶子重置；没有新建场景。

包含 Idle、收刀后拔剑、四连击、身体/金属/石头命中、完整居合、第一人称近观、最终收刀。回执确认 A1–A4 顺序、7 次命中与 Prepare/Draw/Strike/Sheath/End 全部阶段。

证据：`E:/SEKAI-SwordFeelV2-20261012/Sword_Feel_V2_acceptance.json`、`Sword_Final_Test_receipt.json`、`Sword_Feel_V2_sheet.jpg` 和各检查日志。影片是脚本输入回放，**不是真人操作手感验收**。

## Files Modified

本轮实际涉及的工程文件（根目录 `F:/SEKAI`）：

- `godot/scripts/combat/sword_basic.gd` — 四刀动作、真正 A3 上挑、FOV 与左手支撑。
- `godot/scripts/combat/combat_controller.gd` — A3 向上命中方向与 rising_cut。
- `godot/scripts/combat/moveset_library.gd` — 待机握姿和微震幅度。
- `godot/scripts/player/temp_sword_visual.gd` — 待机呼吸、腕部微调、外侧刀迹与灰白色。
- `godot/scripts/weapons/sword_hand_presentation.gd` — 可推进的 Idle、独立十段曲线、肩肘手臂几何。
- `godot/scripts/weapons/sword_fp_rig.gd` — 在原剑面安装钢材 shader。
- `godot/scripts/weapons/sword_config.gd` — 上挑 45 ms hitstop。
- `godot/resources/animations/SwordPresentation.tres` — 原生可编辑动作库。
- `godot/resources/shaders/sword_steel_life.gdshader` — 钢材打磨纹与磨损。
- `godot/resources/tuning/IaidoCombatTuning.tres` — 居合光色与闪光控制。
- `godot/scripts/combat/sword_combat_vfx.gd` — 受控空气轨迹/压力波。
- `godot/scripts/audio/sound_atom_registry.gd` — 接入带测量值的新声音清单。
- `godot/scripts/audio/sword_basic_cues.gd` — 挥剑、命中、收刀、招架新身份。
- `godot/scripts/combat/iaido_audio_timeline.gd` — 八点战斗音轨及切档时实际换 stream。
- `godot/audio/sfx/weapons/sword/feel_v2/` — 14 WAV、Godot import sidecars 与安装清单。
- `godot/scripts/training/sword_combo_zone.gd` — 远靶负对照位置及零方向保护。
- `godot/tools/bake_sword_feel_animation.gd` / `sword_feel_v2_demo.gd` — 编辑动作库和现有训练场验收录像。
- `godot/tests/sword_core_regression.gd` / `sword_basic_v2.gd` / `sword_polish_regression.gd` / `sword_upgrade_integration.gd` / `combat_audio_language.gd` / `sword_feel_v2.gd` — 当前动作规格与实测回归。
- `audio_source/tools/sword_feel_v2_audio.py` / `audio_source/generated/sword_feel_v2_manifest.json` — 离线可继续生成/安装工具与来源。
- `ue5_lab/sword_vfx/docs/sword_vfx_event_contract.json` — 由既有工具重生成当前动作事件。
- `docs/SWORD_FEEL_V2_REPORT.md` — 本报告。

已有工作区包含大量其他修改；本轮没有提交、推送或覆盖其他工程，也没有更换 Sword GLB、创建第三人称动作或改输入绑定。

## Remaining Problems

1. 手套/前臂仍是运行时原型几何。截图能看到握剑连接，但尚未达到最终手部拓扑、真实肌肉变形和指节质量。
2. 训练场灯光较平，材质有打磨/磨损层和分面反射，但“真实武器”的视觉标准仍需更好的既有场景光照下近观评价。
3. 自动回放证明流程、伤害、时间、声音存在与恢复正常；不能证明真人操作的重量、舒适度、四刀听觉辨识或居合高级感。
4. 现有场景仍有 `The target vector can't be zero / looking_at` 运行时错误日志，回归过程与录制均退出成功，但不称整个场景完全无错误；该日志在此前基线也存在。
5. 全局旧音频库仍报告 glass_high_tick/glass_tinkle/wood_sheath_tick 等可选缺口；本轮物理剑及战斗居合已使用新银行，未借此重做其它武器/长演示音库。

交付状态：**实现、运行回归、画面抽查及带声音的训练场回放完成；真人听觉与手感验收待确认。**
