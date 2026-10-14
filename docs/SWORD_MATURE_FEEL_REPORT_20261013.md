# SWORD MATURE FEEL REPORT — 2026-10-13

本轮回应“上一版感觉没什么变化”，重做实际持剑与攻击运动。交付状态：实现、运行检查、实际画面抽查、训练场输入录像完成；是否达到成熟游戏的手感仍等待真人操作评价。

## Animation Changes

- 待机改为双手握柄的斜向准备姿态，握柄接近身体并抬高。双手分别在柄上 -75 / -190 mm，不再让左手永远抱着剑鞘、右手悬挂一把竖剑。
- 四刀全部重新作者：短右横切、回身左切、低处加载后的上挑、肩部盘紧后的终结优弧。每刀都有准备、加速、延续、收势；下一刀从当前动作的结束位置进入。
- 普通 A1 取消每次回鞘/拔刀的动作。独立拔刀、收刀和居合继续使用原有物理鞘轴与插入曲线。
- 动作总原始长度从 0.400 / 0.415 / 0.680 / 0.660 秒改为 0.570 / 0.680 / 0.810 / 1.030 秒。允许衔接的时间早于完整恢复；不用等整段播放完。
- 重新作者双臂肩肘曲线，并加入重斩原生动画：低强度点击完成短加载、按住形成稳定举刀，松开进入下斩。修复旧版“伤害已经开始，画面却重新播放准备”的时钟错位。
- 左手快速挥剑时准确跟随握柄，惯性放在肘和肩；拔/收刀期间左手在刀鞘与握柄之间过渡。
- 普通全拔出姿态不再被“离鞘口较近”错误钳制，待机呼吸与命中反馈可实际生效；真正插鞘时继续约束。

## Combat / Input Changes

- 出刀后的一次下一刀输入可暂存，到既有衔接窗口执行。仍限制一次排队，准备期不会积压整套四连击。
- 本体伤害在加速段约 38% 后开启，A2 现有波刃在约 50% 时释放，降低刀还没真正挥到就先扣血的感觉。
- 保留原四刀伤害、A2 波刃、A4 270 度范围、技能和现有框架。原近/中/远负对照、重置与切武器检查继续通过。

## VFX Changes

- 普通刀迹只覆盖外侧 18%，终结刀外侧 28%，避免宽透明扇片遮住实际武器。
- 延长短暂空气残影，使快速出刀可读；重心在动作和接触，没有新增粒子系统。
- 原剑 GLB 与钢材打磨 shader 保持；新的持剑角度更容易在训练场现有灯光下显示刀刃反光。

## Contact / Camera Changes

- 命中产生刀身短暂咬住、反向偏转与手腕回弹。肉体/金属/石头的额外咬住时间实测为 32.4 / 54.0 / 65.25 ms；重斩更长。
- 远处的波刃命中不会把玩家手中的刀拉歪，旧波刃也不会干扰已进入的下一刀。
- 四刀命中停顿为 45 / 55 / 75 / 105 ms。重斩 95 ms，碎裂保留 105 ms；不同动作与材质有不同阻力。
- 镜头保持轻微方向反馈与 FOV kick，主体运动由刀、双手和肩肘承担。

## Audio Changes

继续使用上一轮已经由本机模型生成、接入并核对来源的 14 个钢材/挥剑/命中/收刀音效。本轮没有重新生成一套声音来掩盖动作问题。实际电影录音峰值 -1.90 dBFS、削波比例 0；真人音色验收仍未完成。

## Verification

Godot 4.4.1 Compatibility / RX 6650 XT 的七项运行检查返回成功：

1. sword_core_regression：A3 单次真实伤害、A2 本体/波刃去重与晚到归属。
2. sword_basic_v2：四刀实命中、远靶存活、四个优弧目标、组合重置和切武器。
3. sword_polish_regression：连续优弧、历史刀迹与采样、30/144 FPS 消失时间。
4. sword_feel_v2：待机/握力推进、钢材面、远距上挑无伤害、14 声音及八点居合音轨。
5. sword_feel_channels：挥空/接触轨迹区别、真实出刀声音时刻、不同命中停顿、停顿后输入窗口。
6. sword_mature_regression：排队衔接约 0.35 秒，双手握柄最差误差约 0.003 mm，材质阻力递增，远波不反作用刀身，举刀释放位置跳变 0。
7. sword_upgrade_integration：十一段必需动画、前景手部、完整居合、退出/死亡恢复和长演示档恢复。

接触探针实测：刀手弹簧在命中时偏离约 49 mm、挥空为 0；连续两个接触堆叠约 96 mm。修正了旧探针允许实际碰撞先发生、再手动注入同一帧导致停顿误报为 0 的问题，并让碎裂检查真实通过受伤节点产生结果。

鞘检查共 365 个插入样本：最差偏轴约 2.7 mm，没有刀尖穿出鞘壁。此次普通四刀不再假装插在鞘中。

## Demo / Play

- 直接启动现有训练场：`E:/SEKAI-SwordMature-20261013/Play Sword Mature.cmd`。
- 新录像：`E:/SEKAI-SwordMature-20261013/Sword Mature Demo.mp4`，41.283 秒，1152×648 / 60 FPS，原生声音。
- 内容：双手待机、独立拔刀、四连击、挥空、举刀/重斩、肉体/金属/石头命中、完整居合、近观、收刀。
- 回执确认四刀顺序、一次重斩、7 次真实命中及居合全部五个阶段。
- 对比图：`Sword_Before_After.jpg`；动作抽查：`Sword_Mature_sheet.jpg`；机器回执：`Sword_Mature_acceptance.json`。
- 录像使用真实输入路径，标注靶子重置，并关闭录制期间的真实鼠标转向以稳定镜头；不当作真人试玩证据。

试玩当前既有绑定：左键平A、右键防御/招架、X 重斩、E 居合、U 近观、1 选择剑。以工程 InputContract 为准。

## Files Modified

工程根目录：`F:/SEKAI`。

- godot/scripts/combat/sword_basic.gd
- godot/scripts/combat/combat_controller.gd
- godot/scripts/combat/moveset_library.gd
- godot/scripts/player/temp_sword_visual.gd
- godot/scripts/weapons/sword_hand_presentation.gd
- godot/scripts/weapons/sword_config.gd
- godot/scripts/weapons/sword_presentation_config.gd
- godot/resources/animations/SwordPresentation.tres
- godot/tools/sword_mature_demo.gd
- godot/tests/sword_mature_regression.gd
- godot/tests/sword_feel_channels.gd
- godot/tests/sword_polish_regression.gd
- godot/tests/sword_upgrade_integration.gd
- ue5_lab/sword_vfx/docs/sword_vfx_event_contract.json（由既有生成器重生成）
- docs/SWORD_MATURE_FEEL_REPORT_20261013.md

修改前主要动作文件存于 `E:/SEKAI-SwordMature-20261013/before/`。没有提交或推送，也没有改输入键位、替换剑模型、增加技能树或新训练场。

## Remaining Problems

- 手套和前臂仍为原型几何，不能把程序动作通过与“已达到最终美术品质”混同。
- 真实重量、输入舒适度和音色必须由操作体验判断。本轮技术和画面证据证明变化存在，不能代替主观验收。
- 既有场景仍输出 looking_at 零向量日志；旧探针退出有资源泄漏日志，单独动画烘焙器保存成功后还可能出现引擎退出崩溃。游戏录像和上述七项运行检查退出成功，新动画已在实际场景中加载验证。
