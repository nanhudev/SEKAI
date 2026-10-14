# SEKAI PRODUCTION BOARD

三线共享状态。任何对话改了状态必须写回本文件，不能依赖聊天记忆。
路径根：`F:\SEKAI` · 分支：`godot-combat-mvp` · Godot 4.4.1

状态值：`TODO` `DOING` `BLOCKED` `REVIEW` `DONE`
资产状态值：`REQUESTED` `SPEC READY` `GENERATING` `BLENDER RUN` `VISUAL REVIEW` `FIXING` `EXPORT READY` `IN GODOT` `IN-GAME VERIFIED`

DONE 定义（不满足不能标 DONE）：
- MAIN：technically verified + gameplay verified
- AUDIO：integrated + auditioned in game
- ART：GLB integrated + visible in Godot

---

## A · MAIN PROJECT

Godot / Gameplay / Combat / Camera / UI / VFX / Save / Git / Testing

| 任务 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- |
| Boot / Menu / Pause gate | P0 | REVIEW | TECH VERIFIED；桌面可见交互未验收 |
| **战斗沙盒门改挂新训练场（REQ-1 关闭）** | P0 | **TECH VERIFIED（待用户进游戏看）** | 第三扇门 `combat_scene` = `TrainingGround.tscn`；标签改「进入战斗沙盒（训练场）」。`tools/shot_combat_door.gd` 12/12 断言绿 · ENV-01 实摆 55 件 · `ArenaDressing` 已不在 · 捕获帧确为玩家自己的眼。回归 `menu_flow_integration` + `training_ground_boot` 均 PASS。出片 `assets_source/review/door/`。**未迁入**：风墙 `WindProps` 与 `ExecutionLab` 只在旧沙盒里 ⇒ 开发面板那两页在新门是哑的 |
| Movement（WASD/sprint/jump/dodge） | P0 | REVIEW | TECH VERIFIED；手感未验收 |
| Running camera feedback | P0 | REVIEW | 三档预设 + F8 面板；可读性未验收 |
| Sword combo / heavy / block | P0 | REVIEW | TECH VERIFIED；视觉已换真剑（10,378 tris · `Sword_FP.tscn`），不再是三方块 |
| Perfect Guard | P0 | REVIEW | 窗口 0.12s（原 0.18s 已收紧）；音效未接入 |
| Universal single-sword language | P0 | REVIEW | **18/18 集成测试绿**；手感未验收 · 见 `COMBAT_DESIGN.md` |
| Guard → Perfect Guard → Riposte 闭环 | P0 | REVIEW | 窗口/后坐/微光奖励已实现；音效未接入 |
| 藏锋流 Hidden Edge 原型 | P0 | DONE | 纳刀/拔刀红利 + 8 招 + 三技能。本轮 P2 只做 **loop polish**（截锋 → 立刻归鞘），**未加新招** |
| 回风式 Flowing Wind 原型 | P1 | **DONE** | 四段链 + 势(Flow) + 流云/折柳/惊鸿 + 长风三段（玩家定向）。`flowing_wind_integration` 绿 |
| **白蔷庭剑术 White Rose Prototype** | P1 | **REVIEW** | Measure（无资源条）+ 三段短链 + 穿庭 + 缠剑三岔 + 假章/白蔷刺。`white_rose_integration` 绿；手感未验收 |
| **元素数据层（ElementDefinition / State / Field / Library）** | P0 | **DONE** | 敌人里已无 `if element == ...`；改 definition 行为即变（`element_magic_integration` 断言）。三系实例为共享单例 |
| **魔法层（SpellDefinition / MagicSchool / MagicLibrary）** | P0 | **DONE** | 火/冰/风各 2 法术，数字与原 `.tres` 对齐；能力轮盘不再 segfault |
| **剑 × 魔法 5 种交互** | P1 | **DONE** | Shatter（参考组）/ 撞墙 / 风扩火场 / Frosted+断水 / 风步喂势 |
| **风的环境（墙 + 轻物）** | P1 | **PLACEHOLDER** | `WindProps` 程序化：一面墙 + 2 个可推 RigidBody。ART 可换网格，物理角色必须保留 |
| 聚合斩重分类为 SIGNATURE | P0 | DONE | 移出 Ultimate 槽，独立冷却；演出未改动 |
| 无明一刻 Ultimate 原型 | P0 | REVIEW | 独立资产，不共用聚合斩；动画钩子待 ART |
| Combat Lab 开发面板 | P0 | **DONE** | 现在是 **style × magic × enemy state × environment 矩阵**；预设走真实 `_on_hit` 路径（`combat_lab_integration` 绿） |
| Magic / Ability Wheel | P0 | REVIEW | 火冰风已验证；轮盘是技术占位 |
| Shatter | P0 | REVIEW | Area3D + shard + 85ms hitstop；音画未验收 |
| **第四剑术 坠星式** | P3 | **DESIGN ONLY** | `COMBAT_DESIGN.md` §10。**不实现** —— 藏锋若已覆盖"重"，它就是第四种换皮 |
| Iaido 7.2s 张力序列 | P0 | SUPERSEDED | 已被 V6 取代；14 phase 全实现，音频仍为占位合成 |
| Enemy telegraph / AI | P1 | TODO | 现为 technical_dummy，非 Lesser Ruin Sentinel |
| Iaido 5–8s Cinematic Tension Pass | P0 | SUPERSEDED | 时间轴已按用户要求改为 V6 **9.90s**，正式离开 5–8s 目标区间；由用户指令覆盖，勿再以旧区间判红 |
| **聚合斩演出 V6（逻辑重排 + 四条修正）** | P0 | **VISUALLY VERIFIED（录制）／待用户手感验收** | 灰化从鞘口扩散 → 时间暂停 → 收刀等 1s → 斩击与流式玻璃化同步、顺斩向逐片碎裂并漂浮旋转 → 收刀后吞噬（含手/剑/玻璃层）→ 回复。**暂停窗口像素变化 0.00% / 0.00%，控制组 27.40%；末帧亮度 184 vs 开场 178**。影片 `iaido_signature_ceremony.mp4`（330 帧 / 11.00s / 15 cue 取自时间轴） |
| Git：提交本轮未落地改动 | P0 | DONE | 已由 MAIN 提交并推送：`c485aeb` + `8c71561`（7.2s Iaido 全序列）。远端 `godot-combat-mvp` = `8c71561` |
| **聚合斩 V7 · 处决系统 + 收刀/裂缝打磨（EXECUTION FINAL PASS）** | P0 | **REVIEW（headless 全绿 · 待用户看片）** | 一刀一个 Cut Plane 同时驱动世界切裂与敌人断面。致命斩 = **伤害在斩的一刻结算，视觉延迟到归鞘 CLICK 才分开**：hold → 1–3cm 蠕动 → 8.40s 释放 → 非对称下落 → 从伤口向外 dissolve；敌人侧契约 `IaidoExecutionProfile`（ART 见 `ART_INTEGRATION_REQUESTS.md` REQ-7）。**用户追加**：收刀不单独成段 → 融进蓄力、**匀速线性**、`time_stop_start` 收满（`park_insertion` 0.94 → `sheath_depth` 1.0）；`separation_px` 20→26、`gap_ratio` 0.60→0.62、裂纹前缘 300→360、`refract_px` 11→14；**玻璃按切口裂开**（pane 被切口裁成两半，切面法线从 tuning 派生而非硬编码）。测试 `iaido_execution_integration` 全绿 + `iaido_integration` 全绿，**10 条变异全部被打红** |
| **聚合斩 · 三个被找到的静默 bug** | P0 | **DONE** | ① `iaido_cleave.gdshader` 第 103 行写了 GDScript 的 `:=`（GLSL 没有）→ 整个断面材质编译失败、断面/内部/下落全部无声失效，而 `--check-only` **看不见 shader**；已加 `_verify_shaders_are_glsl()` 守卫（M5 变异打红）。② 导演在演出中被销毁时 `CombatController.State.IAIDO` 无人清除 → **玩家此后永远不能出招**；已补 `_exit_tree()` 释放（M10）。③ 玩家死亡检测走 `_process`，而 headless 下 `await physics_frame` 不服务 idle 帧 → 测试曾"通过"一个没发现玩家已死的导演 |
| `NAR-MAIN-01` 可复用 `Readable` 阅读物 | P1 | REQUESTED | 看向纸/书/登记簿 → Interact → 可阅读 → 关闭。第一版不做书籍系统；ECHO-01、货单、告示、信件、日记共用 |
| `NAR-MAIN-02` 雾的可视距离 + 南岸"回不去"暗示 | P2 | REQUESTED | 让"晚上不出门"成为体感；用塌方/水涨代替不可见墙 |
| **缚星链 STAR-BIND CHAIN Prototype（Phase 0–1）** | P0 | **REVIEW** | 第二把武器，第二套剑语言。SWEEP / MOMENTUM / TENSION / HOOK 四件事已实现（极性头部状态机，**无 RigidBody 链节**）。`chain_integration` 绿；**手感未验收** · 见 `COMBAT_DESIGN.md` §19 |
| **CHAIN SYSTEM DESIGN V2** | P0 | **DONE** | `docs/CHAIN_DESIGN.md`。三形态（实链/游链/律链）**不是强度阶梯而是三种"链是什么"的答案**，各自长期可独立存在；两正交轴（形态 × 强化重量）；元素附魔层；机会标签 + 武器链接（**明确不是 QTE**）；学/忆/悟 与 无间 草案；§52 判据 |
| **实链 §43 手感通道：冲击 / 回收 / 绷紧** | P0 | **DONE（headless 已断言 · 手感待验收）** | 落点代价按**目标重量 × 头部速度**扣势能 + 弧线偏折 + hitstop(0.55–1.35×) + 相机。实测 轻 势=0.282 偏=-106.4° / 重 势=0.215 偏=-102.4°。回收有外漂 +0.13m、过冲 10.8°。绷紧=线抖动（紧 0.0059m vs 松 0.7820m）+ 相机 1.80° 挤压。**三项断言全部做过变异测试**（归零后 2 项转红） |
| **抛出方向跟着准心（§13）** | P0 | **DONE** | `aim_pitch_scale` 为 opt-in，仅 `ch_hook`=1.0。没有它，世界里所有高的东西（横杆/废墟环/树杈）都钩不到，**游链以后就没有锚点** |
| **CHAIN LAB 高阶锚点（§45）** | P0 | **DONE** | 双柱龙门 + 可钩横杆（y=2.30m，臂 3.42m），锚体**挂在臂下方**（扫掠射线先测实体世界）。断言：横杆不动、玩家被拉 >0.25m。变异验证过（去掉跟准心即抓不到） |
| **§46 开发者读数闸门** | P1 | **DONE** | `R=`/`M=`/`T=` 只在开发者模式出现；Clean 只剩形态名（非空，HUD 不会空行）。变异验证过（拆闸门 → 4 项转红，精确复现修复前失败态） |
| **链事件接口 `tug` / `wall_impact`（§49）** | P1 | **DONE** | 链只**广播**它知道的时刻，AUDIO 订阅。`tug(step,total,amount)` 每记递减一次；`wall_impact(strength)` 撞实体世界。**记数有断言守着**（变异后 `announced 0 yank(s)` 转红）· 见 `COMBAT_SFX_BRIEF.md` G2/G3 |
| **链的拉扯「顿挫」** | P1 | **DONE** | 一次拉扯拆成 5 记递减（0.28→0.12，求和 1.0），间隔 0.24s，每记 hitstop + 抖动 + 方向冲量。**share 决定距离，gap 只决定节奏**。链「松脱」不取消已拉出的几记 |
| **`PlayerMovement.pull()` 距离口径** | P0 | **DONE** | 曾把推力每帧留在 `velocity` 里被反复花掉，`pull(0.25)` 实际推 3.75m（**假 15 倍**）。改成瞬态扣回后比值 1.00，重量表与声称值差 1% 内。回归：`_check_a_pull_moves_the_distance_it_states()`（已做变异测试） |
| **CHAIN LAB 舞台** | P0 | **DONE** | 长甲板 + 桥 + 尽头石墙 + 固定锚 + 三重量目标；`ArenaDressing` 有 8 件占位物落在甲板/桥里（含门洞一根 4m 柱），已按**网格包围盒**隐藏并有断言守着 |
| 链的 SFX / 手部动画 | P1 | REQUESTED | `COMBAT_SFX_BRIEF.md` **Priority G**（19 条 + 本轮 **G2 事件接口 / G3 落点重量**）；手/前臂资产未到位，现为程序化锚点 |
| 回写 `COMBAT_DESIGN.md`（DOCUMENTATION DEBT） | P2 | **DONE** | 已补 §5 回风 / §6 白蔷庭 / §7 元素三系 / §8 五种交互 / §9 战斗矩阵 / §10 坠星式；旧 §7–15 顺延为 §11–19 |
| **FIRST PLAYABLE SEQUENCE · 首个可玩切片（§1–§28）** | P0 | **REVIEW（32 项验收全绿 · 待用户手感验收）** | 主菜单 `开始游戏` → 淡黑 → 出生**雾栖镇集市广场中心** → 米拉（唯一 NPC，非说教型）唯一一条世界事实「你不是这里的人」+ 石碑一次极短异变 → `[E]` 对话 → 从武器架 `[E] 拿起旧剑` 得到【**无铭长剑**】（鞘内到达，非凭空）→ `[R]` 拔刀（SHEATHED/DRAWING/DRAWN/SHEATHING 四态）→ `[LMB]` 打练习桩 → `[Q]` 中距离剑气 → 远处异响，**灰烬猎犬撞翻木箱**入场 → 完整一战（120 HP，实测 **6.0 s / 4 次攻击输入**，限 15–35 s 内达标）→ 倒地停留后才消失 → 米拉走近 + 石碑二次异变 + 0.3 s 静音 → **QUEST UPDATED【前往冒险者公会】**，之后**仍可自由移动**。进度由真实玩家行为推进（`StoryDirector` 十态机，无 `if time > 15`）。存档 `user://sekai_flags.json`（§22 三 flag），回访不再重播教学。验收：`tools/first_playable_run.gd` 在**可见窗口从主菜单**跑完 §29 全清单 **32/32**；`tools/plaza_smoke.gd` **79/79**。资产接口按 §23 分离（Mira 的 `VisualRoot`/`Interaction`/`DialogueAnchor`、武器的 `WeaponVisual`/`VFXRoot`/`SwordHitbox`） |
| **广场铺装「整轮不可见」+ HUD 卡片永挂（两处静默 bug）** | P0 | **DONE** | ① 石板铺装**每帧都在画，却整整一轮没人看得见**：它按 `MistvaleHeights.height_at + 0.14` 建，而 `MistvaleLand` 的集市铺装在同一场上又铺一层 `height_at + 0.258`（半透明棕 `Color(0.45,0.38,0.30,0.43)`，正是画面里那片"泥地"）⇒ 铺装被压在下面 12 cm。**当时 71 项测试全绿**：测试量的对象是高度场而不是城镇自己的铺装面。已加 `MistvaleLand.paving_height()`（铺装 lift 由 superellipse 反解，非手抄）为唯一权威，广场改问它。新断言已做变异：改回旧式即 **247/247 顶点被埋 -0.0931 m** 转红。② HUD 的 hold 与淡出写成**同一个嵌套判断** ⇒ 倒数归零那帧进入淡出分支，下一帧 `left` 已是 0、外层判断转假 ⇒ **淡出只跑一帧、alpha 冻在 0.995、卡片永挂**：§6 的「无铭长剑/已装备」在 §19 画面里仍在，与任务卡文字叠成一团。三张卡（subtitle/toast/quest）同一结构同一 bug，已拆成独立判断。断言同样经 A/B 验证（修前 `alpha 0.995 visible true`，修后 `0.007 / false`） |
| `tools/plaza_smoke.gd` 自身的两个不可重复性 | P1 | **DONE** | ① 它读 §22 存档却**不隔离**存档 ⇒ 磁盘上留一个 `first_playable_complete: true` 就让整场被当成回访玩家、跳过开场，6 项断言失败全部写着"故事从结尾开始"，**真回归与上一轮的残留无法区分**。现在开局把存档移开、**每条退出路径都放回**（是玩家进度，不是测试的丢弃物）。② 它按**帧数**推进时间去代表开场的 20.7 s，而 `StoryDirector` 走 `create_timer`（真实秒）；headless 每秒出数百帧 ⇒ "1242 帧"实际只推进约 2 s，开场判定必然失败。`--fixed-fps 60` 是另一种让两者一致的办法，**但本环境该组合段错误（rc=139）**，故改真实秒 |

### 战斗线验收现状（COMBAT 会话 · 2026-09-27）

- **缚星链 · CHAIN V4 / A1 垂直切片（2026-09-29）**：用户对 V3 的判决是**抽象层失败**（`摄像机前挂了一条 spline，末端沿路径运动`），本轮按 PART A–N **重建表现层**（保留 ~10m 长链 / 柄+链+三叉头 / A1 A2 A3 / Hitbox·Target·Damage / 换武器 / 训练场），**只交 A1**。出片 `.render/chain_v4_A1_vertical_slice.mp4`（510 帧 @28.2fps = 18.09s：待机 2s → A1 空挥 → A1 命中 → A1 撞墙咬住绷紧 → 回收）+ 四张 still + 两张 V3/V4 before-after。逐段自报：A/B `hits 0 walls 0` · C `hits +2` · D `walls +1`。**层级 = TECHNICALLY VERIFIED**（`chain_v4_slice` §0/§9/§11/§12/§18 五条 · `chain_physicality` · `chain_integration` 三套全绿 exit 0）· **手感未验收（只属于用户）**。本轮 PASS C/D 修掉三处几何真相：链环 `rings` 6→12 且 `LINK_TUBE_RATIO` 0.52（六边形 + 细管 = "白铁丝"，与材质无关）· 链束半径 0.105→0.147 并与绳的 `coil_radius` 解耦（旧值每圈只放得下 2.6 环 → 退化成三角形；环不能比做它的棍子还小）· 三叉侧齿抬出平面（五齿共面 → 侧影塌成一根针）。**§D 音频**：`chain_audio_director.gd` 两处 `String(<int>)` 运行期抛错并**中断函数**，命中/扬拽的 `_play` 从未执行 → 已改 `str()`，cue 时间线由 `capture_chain_audio.gd` 取回。**§11 的断言上一版是装饰**（突变 `BUNDLE_SHED_SHARE=0` 仍绿），现改为有区分度的 `lowest < lowest_loops`，已做突变红检。冻结在 A1 之后：A2/A3/A4/A5、E/Q/F、链大招（PART L）。
  - **两个真 bug 都在链头，且都被所有 ≥3m 的镜头放过**：① `_blade()` **收了 `material` 参数却从不使用**，五根叉一直用 Godot 默认材质画 → 永远是「白色纸片」，`HEAD_TINT` 0.84→0.68 画面**毫无变化**；② `_blade()` 把节点原点放在 `at + dir*(length*0.5)`，而局部几何底在 Y=0 → **每根叉的底被推到安装点前半个叉长，中央叉与肩部之间 25cm 空隙** —— 这才是「五片散落碎片」的真因，任何粗细/张角/材质都修不好。
  - **链盘：嵌套螺旋在几何上不可能不像圆盘**（共轴 + 半径只差一点 → 任何角度都叠成一个面，第一版出来是**蜂窝板**）→ 改成**圈平面绕自身进动的轴旋转**（36°/圈，旧值 5.7°）的 TUMBLE，交叉出现才读成「一把链」。
  - **`ForegroundWeaponLayer` 的 `own_world_3d` 没有 Environment 也没有灯** → metallic 材质放上去就是它自己的剪影（同一 `LINK_TINT` 绳上浅、盘上炭 = 「两种钢」）。新增显式 opt-out `WORLD_DRAWN`，柄+盘整棵子树回世界层和绳共用一盏灯。
  - **§11 / §19 都是「两个拍子其实是同一个拍子」**：§11 盘链退场必须 **RIG 驱动**（左甩只放 3/10m，reach 的任何单调函数都救不了）；§19 的 `load` 曾是 `_bite_phase` 的纯函数 → **wall_bite 与 tension 两张 still 出自同一帧**，加 `TENSION_BUILD_TIME` 给 load 自己的钟才分开。
  - **§18 的可见性缺口**：`chain_v4_slice` 证明锚点零漂移，但镜头里读不出「咬住了」。`WALL_HEIGHT 3.4 → 2.05`（立场被左甩 3.48m 触及距离定死，唯一自由量是墙高）+ 一条涂装命中带。**咬合时链头读成一团是 §18 规范如此**（中央刃沿法线咬进去 → 正对镜头），不是 bug。
  - **测速纪律**：1280x720 实时捕获只有 **~17.5fps**（关 vsync 无效，与分辨率相关）→ §9 的 80–160ms 蓄力只有 1–3 帧，**正片按 960x540（28fps）拍、still 按 1280x720 拍**。`--fixed-fps` **不可用**（事件表走墙钟）。新工具 `tools/sample_frame.gd`（帧→亮度字符图）· `tools/probe_wall_frame.gd`；渲染器现在在 still 行打印链头世界坐标。

- **缚星链 · 待机收纳（CHAIN V4·B 浮链）· 2026-09-29**：用户判决「余链不能只是堆在手边 → 会变成一坨金属毛线」，选 **B 受控浮链**（魔法感压到最低）、待机 = **4 层开放弧**（非闭合圆 / 最外层最大 / 偏扁螺旋扇面）、**屏幕中心 35–40% 禁入**、回收**不要在一帧里突然生成完整盘链**。**本轮只做「待机 + 那 4 层弧」这一件事**，A1/A2/A3/命中墙体/回收仍是设计级。
  - **结（跨层交叠 20 → 0）的四个真因**：① `ARC_TILT` 让每层各有平面 → 没有任何方向能分开它们（改成全体共享一个平面，只有 `ARC_SPIN` 随绕线转）；② `_link_basis` 的 `ref` 传世界 UP → 链环 6.24cm 宽度沿堆叠法线，**整个层距被吃掉**（加第三参，浮链传 `_stow_normal()`）；③ **`Basis.scaled()` 缩放的是 ROW**，之前把每个环沿「链根 X 轴」压扁而不是「横跨绳索」（改**缩列**，半边长 0.0461/0.0109/0.0356 → 0.0312/0.0114/0.0473）；④ **`ARC_LEAD`（每层 12° 额外进角）把绕线撕开** —— 200° 扫掠 + 12° → 每层边界 **−188° 跳变**，重采样在那里铺一根 16cm 长环横切扇面（**这才是那「一坨」的成因**）。已删。
  - **最后一对交叠（引链 × 第 1 层）的解法是 `ARC_START`，不是 `ARC_DEPTH`**：坏的那一对里**引链环根本不在平面内**（`n·t̂` = −0.245），所以把层距提到 0.056 仍读 1，还把第 3 层推到 NDC −1.08。把绕线起点从 1.75 移到 **−1.15 rad**（引链落在扇面靠拳的最近点，**不再横穿外圈**）后归零。`ARC_LEAN ≤ 0.78` 的整片邻域都是 0 —— **选点要选在零区中间**（`STOW_ANCHOR` 挪 0.12m 就能让 0 变 3）。
  - **一条被量出来的错误算术**（好推、值得记）：`ARC_DEPTH` 的下限**不是** 4.26cm。绕线**沿法线前进**，每环切向都带 ≈0.108 的法线分量（引链环更多）→ 判据只能是测出来的：`stow_interpenetration()` **0 over 23 boxes**，最小跨层间隙 **1.77cm**。
  - **取景是 NDC 预算**：`ARC_LEAN` 决定法线 (0,−sin L, cos L)；0.95 → 0.88 向下、第 3 层 y −0.94（离下边 3%）。改 **0.78** 后全部入画（最宽层 x −0.89、最低层 y −0.92）。`ARC_R_GROW` 0.06→0.045、`ARC_SQUASH` 0.60→0.48、`ARC_WIDE` 1.30→1.22 同理。**这些数不单调**（压扁会改每层弧长 → 移动所有 seam 与层切点）→ **扫，不要推**。
  - **尺子立起来了**：`tools/stow_diag.gd` 由临时脚本**转正**（逐层 NDC 框 / 逐对间隙 / 环半边长 / **逐 seam `n·t̂`** —— 回答「这一环属于引链还是绕线」，至今每个浮链故障都问这个）；`tests/chain_v4_slice.gd` 新增 **§STOW 组**。**三条新断言全部做过变异红检**（层距归零 → 23 overlaps；`STOW_ANCHOR.x` → −0.20 → breach 0.0188；**收链循环反转 → 红**）。出片 `.render/stow_idle_ab.png`。**（判据随后由箱子换成圆环 · `stow_diag` 增 `RINGS/STRAIGHT/BEND` 三段 · 见上「裁决①已执行」）**
  - **变异测试当场抓出一条装饰断言**：收链顺序第一版**静止时取样**，而静止 4 层全可见 → `visible == (i < 4)` 对**任何**顺序都成立，**把循环反转它照样绿**。必须**在抛出中、有层已消失的那一帧**取样。
  - **裁决①已执行：采纳细节距啮合（2026-09-29 晚）**——`link_spacing 0.11→0.052`、`links 96→200`、**`LINK_FILL 0.86→1.82`**，链节尺寸**不变**（`0.052×1.82 = 0.11×0.86 = 0.0946 m`，半边长实测仍是 0.0312/0.0114/0.0473），节距/链节长 = 0.55（真实链 0.5–0.6）。观感从「一串甜甜圈」变成真链。
    - **但啮合不是密度问题：它给链节和路径各加了一条硬律，两条都是量出来的。**
    - **尺子必须换代：箱子 → 圆环。** OBB 在「节距 > 链节长」时忠实；`LINK_FILL > 1` 之后**共面邻居 (i,i+2) 是两块实心板**，弯路径把它们的角旋进彼此 → 16 个"重叠"**全是啮合本身**。新增 `stow_ring_readings()`（走 TorusMesh **环中线**，用**段—段**距离；点采样不行——环半径 3.6cm 时 12 边形采样 1.9cm，**比要分辨的间隙还大**），按族分开：`neighbour`(i,i+1，**属链节**) / `layered`(i,j≥i+2，**属浮链**)。§STOW 判据同步从箱子换成圆环。
    - **硬律 1（链节自己）**：`legal = 2·inner − pitch = pitch·(LINK_FILL·LINK_TUBE_RATIO − 1)` → **尺度不变，等比缩小链节毫无用处**。现状 `1.82×0.52 = 0.946 < 1` ⇒ 新增的 `chain_straight_clearance()` **直线对照 −0.0054 m：链节穿不过自己**（这是链节的锅，不是浮链的）。完整约束 `p ≤ L·R_t` 且 `2p ≥ L` ⇒ **`R_t ≥ 0.5`**；R_t=0.52 时合法带只有 `[0.0473,0.0492]`（1.9mm 宽）。
    - **硬律 2（路径）**：弧是压扁椭圆，最紧处在**长轴端** `ρ = b²/a = (R·ARC_SQUASH)²/(R·ARC_WIDE)` = **2.46cm**（路径实测最紧 0.0396m）；而链节最小弯曲半径 **0.185 m**（R_t 0.65）/ **0.111 m**（R_t 0.70）⇒ **紧 5–8 倍**。**降节距完全无用**（实测 p 0.052/0.044/0.038/0.034 下读数纹丝不动：每步转角 ∝ 节距，**但链节不缩**）⇒ **这根链物理上做不出「小·扁·贴髋」的四层扇面**（圆的弧要 R ≥ 0.11–0.19m，四层叠起来出画；正对看又变成「圆盘贴镜头边」，用户明令禁止）。**`ARC_SQUASH` 是罪魁**——它把 3D 路径压扁，而屏幕上的「偏扁」本可由**斜视投影免费获得**（同一平面已经用 `ARC_LEAN` 斜了）。
    - **已落地**：`ARC_LEAD_BACK 0.8→0.0`（旧 `ARC_START` 1.75 时代的 39° 出平面进入角；入口移到 −1.15 后它只剩成本，**39° 角突变 = 折**，啮合后比擦挂更糟。实测 layered −0.0030→−0.0009、margin +0.0502→**+0.0759**）。§STOW 新增三条断言：浮链 `layered ≥ 0`、`chain_straight_clearance` 的 flat/skip1 ≥ 0、`path bend ≥ chain bend`。**变异检验通过**：链节改成合法（`p 0.054 / LINK_FILL 1.752 / R_t 0.65`）后三条**全绿**、只剩 bend 一条红 ⇒ 断言真能分辨。
    - ~~**当前红（3 条，均已具名）**：`layered −0.0007`、`link(flat) −0.0054`、`bend 0.040 vs −1.000`。~~ **（已被下一条「裁决③④已执行」取代：全部转绿）** `chain_integration` PASS。
    - **待裁决 · 两条新的**（**已裁决并执行，见下面「裁决③④已执行」：① 取 `LINK_TUBE_RATIO 0.70`、② 取「圆弧 + 斜视投影」**）：① **链节金属厚度**——做合法需 `LINK_TUBE_RATIO ≥ 0.5`（建议 0.65），金属占链节长 0.24→0.175，**与 §5「比真实更厚」冲突**，是全武器观感改动。② **扇面形态**——要让弧合法就得放弃 3D 压扁（`ARC_SQUASH 0.48→1.0`、`ARC_WIDE 1.22→1.0`），改由**斜视 + 层偏移**得到「偏扁」；或缩短每层扫掠到避开椭圆长轴端的 ~88° 窗口；或**接受**弧端几个像素的互穿（现行视角约 12px，读作「咬得很紧」而非错误——这正是用户批准 B 图的原因）。**是否缩小链节**是第三条路：弯曲极限 ∝ 链节长，2cm 链节即可保住现行扇面，但链节尺寸用户此前要求不变。
  - **裁决②③④已执行 + §STOW 取景收口（2026-09-29 晚）** —— 两条硬律的解锁都是用户裁决的：**③ 链节厚度 `LINK_TUBE_RATIO 0.52→0.70`**（合法带从 1.9mm 放宽到可用）、**④ 扇面改「圆弧 + 斜视投影」`ARC_SQUASH 0.48→1.0` / `ARC_WIDE 1.22→1.0`**（压扁的 3D 路径才是非法弯曲的来源；「偏扁」交给已有的 `ARC_LEAN` 斜视免费获得）。**此后物理全绿**：`nb +0.0036 / ly +0.0134 / flat +0.0079 / legal +0.0122 / bend 0.1315 ≥ 0.1110`，knot 21（箱子模型，仅供对照）。
  - **但画面还是错的，而且缺口在尺子上。** 渲染 `chainidle` 看到：① 余链是**一坨金属毛线**，② 扇面一半**在画面外**。**`stow_breach()` 只回答"有没有进画面中间"，没有任何人回答"有没有出画面"** —— 两者同一病因、相反表现：锚点在髋部、安全带只把它推开中心，所以**太大的浮链不会 breach，它会从左边缘走出去**，`breach` 一路读 0.0000。实测：`breach 0.0000` 而第 3 层坐在 **NDC x −1.382 / y −1.147**（出画一到四成）。⇒ 新增 **`stow_frame_reach()`**（任一已画链节的 `|max(nx,ny)|` 上界，**必须 < 1.0**）+ `stow_diag` 的 **`FRAME` 段（含逐层 |max| 与 OFF-SCREEN 标记）** + §STOW 的 **`reach < 1.0` 断言**（**变异检验通过**：锚点换回旧值 → 立刻红）。
  - **取景主因 = `ARC_DEPTH` 把每层同时朝镜头推。** `ARC_LEAN 0.78` 让扇面法线在 handle 空间是 (−0.37, −0.70, **+0.71**) —— 有朝镜头的分量，于是 0.048 的错层步长**同时**放大每层 ~10% 并把层心推离画面中心（实测层心 Δz 相对锚点：Arc01 **+0.023** / Arc02 **+0.099** / Arc03 **+0.145**）。
  - **扫过的杠杆（全部否决，留下证据）**：`ARC_LEAD_SLACK` 0.55→2.20 只把 reach 从 1.382 降到 1.294 且**路径最紧 0.0644 ＜ 链条 0.111 ⇒ bend 坏**（2.2 是承重的）；`ARC_DEPTH` **取负**能得 `reach 0.995 FIT` 且物理全绿，**但 margin −0.0831**（吸进中心带）、屏幕读反（最近=最大）、变成「叠圆环」——正是用户禁止的「几个圆盘贴在镜头边」；`ARC_LEAN` 1.05/1.25/π÷2 → reach 1.422/1.489/1.391 全更差且 `chain_min_bend_radius` 升到 0.149/0.202/1.530 ⇒ bend 直接失败；`ARC_SIZE_JITTER` 非单调（1.382/1.445/1.237/1.275，不是主因）；锚点**只往外挪** margin↑但 reach 同步↑（扇面屏幕跨度 ~0.70 NDC ＞ 左带 0.62）。
  - **正解：把浮链推深，不是缩小。** `STOW_ANCHOR z +0.10 → −0.200`（离眼 0.52 → **0.82 m**，**这才是「腰后」**）⇒ 同样的 0.35m 扇面**张角小三成**，walk 就装得下：`reach 1.382→**0.953 FIT**`、`margin +0.0454→**+0.0573**`、逐层 `|max| 0.953/0.756/0.847/0.887`（**外大内小保住**）、物理全绿。**邻域是平台不是刀锋**：x∈[−0.98,−0.96] × z∈[−0.26,−0.20] 全 FIT。渲染复核：余链落在**左下髋位**、4 层嵌套开弧、**中心带干净**、引链从拳头斜穿画面下缘 —— 与用户 brief 一致。**层级 = VISUALLY REVIEWED（1280×720 still）**。
  - **四个链测试全 PASS**（`chain_v4_slice` 含新 `reach` 断言 / `chain_physicality` / `chain_integration` / `chain_combo_memory`）。**顺手还掉注释债**：`_stow_point()` 的「`ARC_START` is 130°」（实际 −1.15 rad）、`ARC_LEAD_SLACK` 旁写着的 0.55（实际 2.2，且它由弯曲半径决定）、`ARC_LEAN` 的旧锚点 NDC 数字。
  - **仍未做**：浮链根是**静态 transform**（`_place_coils`），用户 brief 的「移动 = 四层弧 50–100ms 位置滞后」**尚未实现** —— `margin +0.0573` 就是留给它的预算；A1 段落成片复核 4→2 收链待做。

  - **层级 = TECHNICALLY VERIFIED / VISUALLY REVIEWED**（本会话看的是 1280x720 still）；**手感与「是否掉价」只属于用户**。桌面窗口里的移动/回收滞后仍需 USER GAMEPLAY VERIFIED。

  - **本轮 · 用户「让左边悬浮起来，自然一些，右边的链子和刀链接不要穿模刀手柄」（2026-09-29 晚，CHAIN V4·B 收口）** —— 两个失败、两个病因，都是**先量再改**：
    - **左边「悬浮」：旋钮是两个，不是一个。** 分层**只能沿共享法线**（`ARC_TILT` 已删 —— 每层各自平面 ⇒ 四个法线指向四方 ⇒ **没有任何方向可用来步进**，那是死结不是线圈）；**径向分离在本帧算术上不可能** —— 帧把外半径卡在 ~0.15m 出头，而链**自己弯不到** 0.111m ⇒ 四个半径只挤 ~4cm（每层 ~1cm），而链节**宽 6.2cm**。真正的旋钮：**① 扇面俯仰 `STOW_PITCH 0.18 → 0.42`**（离视轴 52.9°→**65.6°**，「偏扁」由**斜视投影**免费给出，投影 0.41 宽/长 —— 用户裁决④），**② 总绕线 `ARC_SWEEP 3.49 → 2.30`（200°→132°）**。②的判据是 **`coil_max · ARC_SWEEP / 360°`** —— **「线轴 vs 扇面」就是一个量**：2.2 圈 = 线轴（用户说的「一坨金属毛线」），**1.47 圈 = 四条可读的开放弧**（跨层交叠对 21→**15**、链 74→**62**）。`STOW_ANCHOR y 0.189 → 0.260`（**与拳同高**；`y 0.189` 把整束放到**地平线以下**，读起来是「一坨货」而**不是「浮着的东西」**）；`x → −1.040`、`z → −0.270` 是 `STOW_PITCH` 的价格（**左 + 后同时买 reach**；⚠️ **单推 z 会把 margin 推成负**：−0.0058 / −0.0216）。
    - **右边「不要穿模刀手柄」：这件事从来没被量过。** 首次测量当场暴露 `eye ring vs the hilt −0.0450 m`、`rope vs the hilt −0.0177 m @ seam 1`、**环轴横跨绳索 86.3°**、**绳的离开方向离柄轴仅 18.1°**。两个真因：**① torus 是 EYELET —— 绳穿的是它的洞**，所以**环轴必须就是「离开方向」**（环横跨绳索 ≈90° = 绳穿轮圈）；**② 引链的「下」取了世界 −Y**，而刀柄轴线**不是**世界 −Y（差 18.1° ⇒ 绳一出门就沿柄内走）。修法 = 两常量 + 一个共享方向函数：`HANDLE_EYE_OUT 0.030`（链眼移离轴、落到箍肩）+ `_stow_leave()` / `_handle_leave()` 成为**唯一**的离开方向定义 ⇒ `ring-vs-rope 0.0°` / 绳离柄轴 `58.0°` / `+0.0118` / `+0.0300`。
    - **新增 §JOINT 三条断言（已做变异红检，不是装饰）**：`rope vs hilt > 0.010` / `eye ring > 0.005` / `ring-vs-rope < 20°`。⚠️ **阈值不能写 `> 0`**：`HANDLE_EYE_OUT := 0.0` 时读数正好 `+0.0000`，`> 0` 会**通过** —— 改 `> 0.010` 后 MU B 才红（"the lead-in runs 0.0000 m inside the sword's hilt"）。
    - **两条方法教训**：**探针必须调用「定义该量」的那个函数**（第一版 JOINT 探针自己又写了一遍离开方向 `stow_b*(0,−1,0)` ⇒ **修好之后它仍报 18.1°**，在量一个不存在的几何）；**缝距 5.4cm ⇒ 最坏点落在缝与缝之间**（按 seam 采样漏掉 4cm，必须**每段子采样 9 点**）。

  - **§MOTION 运动层已落地（2026-09-29，CHAIN V4·B 第二段）** —— **本条取代上面第 95 行的「仍未做：移动滞后尚未实现」；那件事现在做完了。** 用户 brief §2–§16 的整条运动层：
    - **一个共享根，四条响应曲线**（§6）：一个 `_motion_off` + 一个 `_motion_ang` 作用在**共享 stow root**，每层乘 `MOTION_LAYER_RESPONSE [1.00, 0.94, 0.88, 0.82]`。**层 0 必须是 1.00**（引链焊在它上面），**列表必须单调不增**（反过来 = 最外层跑在手前面）。实测 `layer offsets [0.0, 0.0015, 0.0030, 0.0045]`。
    - **平移滞后**（§2/§3/§8）= `speed × 0.0072`，上限 **5.5cm**；冲刺 ×`1+0.42·clamp(v/6.2)` ⇒ 8m/s 时算得 0.0818 → **被上限截到 0.055**（"克制"）。`ζ 0.58` **欠阻尼** ⇒ 停步要**再往前追几厘米**。实测 `walk lag 0.0301m · overshoot +0.0020m · dodge kick 0.0550m 收于 183ms`（§9 要 150–300ms）。
    - **转动滞后**（§4）上限 **8°**，`MOTION_TURN_PITCH_SHARE 0.30` ⇒ 俯仰只吃三成（§4 的失败模式是"镜头一抬整束链翻过去"）。**预期值是推导出来的**（无稳态误差 ⇒ `pitch ≈ rate × τ(0.075) × share`），不是拍的。实测 `turn 8.00° · pitch 3.37°`。
    - **§7 待机呼吸**：两个**不相通约**的频率 0.17/0.23 Hz，峰 **~1cm**（`> 0.0015` 且 `< 0.032`）—— 目标 **alive, not animated**。
    - **§12/§13/§14**：命中后 `var loaded := rig != Rig.HELD` 闸门 ⇒ **idle/drag/turn 全部归零** + `MOTION_LOAD_TAU 0.022`（**4 帧内收住 = "立即"**），实测 `walk trail 0.0301 → 0.0001m · idle drift while out 0.00000m`。撞击一拍 **CONTACT→BITE 100ms**（曾报 117ms：`0.10 − 6/60` 在浮点下仍 `> 0`，比较必须留 eps）。§14 的手柄回拉 **0.0450m**（要 2–5cm）+ 相机冲量 **0.0041**（**方向不能取 `−normal`** —— 正对镜头的一面墙其屏幕分量恰好 `0.0000`，必须从**绳**派生）。
    - **§16 换武器重置**：`1/2` 回到链 ⇒ `HELD / A1 / 收起的弧归 0 / 不再锚定 / 无残留接触 / 无旧目标`。**§15 已由 `chain_combo_memory` 全覆盖**（combo reset 0.70–1.00s 且**与 `light_window` 不相等** = "两个计时器不许共用一个"），**未新写测试**。
    - **判据 = 真正的变异红检**（不是"测试全绿"）：21 条变异中 **3 条抓到真 bug** —— ① `_lag_safe_scale` 二分**不测自己的上界** ⇒ 完全合法的需求返回 0.984375，于是每帧都报"被压缩"、**关掉钳制变异存活**；② 转动轴留在**旧 basis 的局部系**再点积世界 UP ⇒ **混了两个坐标系**（俯仰读成 yaw 的 0.67 倍：5.33° vs 修正后 3.37°）；③ 俯仰轴取自 stow 自己的倾斜 right ⇒ **本来就没接上**（0.13–0.17° 惰性）。**另有 2 条是测试自己写错**（§7 把 idle 漂移与惯性混进同一个总数 ⇒ 噪声底 1cm 让它永远测不到弹簧收住；§10 的 `climbed >= steps` **自指**）。
    - **⚠️ 两条工具教训**：**模式会腐烂** —— M3 的模式停在旧签名（`MOTION_TURN_TAU` vs 现在传 `lag_tau, lag_zeta`）⇒ 命中 0 次 ⇒ **静默跳过**（"未命中"必须算失败，且改代码要回看模式）；**`finally` 还原挡不住挂起** —— 子进程卡死时 `run()` 不返回 ⇒ 还原不执行 ⇒ **`HANDLE_RESIST → 0.0` 在树里躺了 13 分钟**。已加 `timeout=300`，并**强制先跑未变异基线**（否则并行会话的编译失败会让 NO VERDICT 被读成"变异存活"）。
    - **出片**：`tools/combat_movie_renderer.gd` 新增 **`motion` 巡演**（7 拍 29.6s，**全第一人称** —— §5 是关于"弧在画面里哪儿"的主张）+ `_yaw(rate, seconds)`（§4 要的是**速率**转头；`_turn(90)` 的瞬移只生产一个被上限削平的尖峰，是量具的产物）+ **每拍打印 peak drag / turn / clamp floor / idle / handle / layers / hand speed**（审片分辨率下 4cm 与 3° 看不见，而运动系统坏掉的症状是"看起来什么都没发生" → 会被读成 PASS）。交付脚本 `tools/render_chain_motion_pass.sh`（渲染 → 按实测 fps 编码 → 按 §20 命名归档六张 key frame，**缺一张即失败**）。训练场图例（§17）键位**从 `InputMap` 生成**，因为 brief 写的 Hold E/Q/F **不是本 build 的绑定**。
    - **交付（2026-09-29）**：`.render/chain_v4_floating_motion_pass.mp4`（**30.10s** @960×540/28.43fps，§19 要 20–35s）· 六张 §20 key frame（1280×720）· `.render/training_ground.png`。判读用 `tools/contact_sheet.sh`（**成片抽帧**拼联络表 —— §19 要的是运动评审，**单张静帧证明不了运动**）；§17/§18 由 `tools/shoot_chain_lab.gd` 验（**先打印图例解析出的键**，因为截图只能证明面板画出来了、**不能证明「Skill 1」是 F3**）。实测 8/8 键位全部有绑定：`LMB / F3 / F4 / F / RMB / Shift / Ctrl / V`。
    - **960×540 那趟的读数**（≥30fps 才有效，理由见下）：`01 待机 drag 0.0002 m · clamp(0/89) · idle 0.0160` · `01b 转头 turn 3.63°（§4 要 3–8°）` · `02 冲刺 drag 0.0550 m 饱和 · hand 8.17 m/s`（**与 `combat_tuning.sprint_speed = 8.0` 对上，这是读数可信的交叉检验**）· `03 闪避 drag 0.0550 m · clamp(4/97)` · `04 释放/05 撞墙/06 回收 drag 0.0002/0.0026/0.0001`（撞墙后漂移已停）。
    - **⚠️ 在渲染器里量运动时量具会污染读数（本轮新踩，两次都是"数字看起来合理"）**：① `_stand_in_lab` 是**瞬移**，手速是手的世界坐标差除以一帧 ⇒ 瞬移下一帧报 `hand 183.40 m/s`，从第 0 帧起采样让**站着不动的待机拍印出 `drag 0.0524 m`** —— 而且它**看起来像真读数**，因为视觉把位移截在 `MOTION_LAG_MAX`、尖峰**预先被削成正好 0.055**；② 瞬移还给 `_motion_off` 灌了大位移，ζ 0.58 / τ 0.062 的环按 `e^(−9.4t)` 衰减 ⇒ 从 0.20s 起仍有 15%（`drag 0.0268 m` = idle 漂移的 5 倍）⇒ `MOTION_SETTLE 0.60`，**判据是弹簧衰减常数不是圆整数**；③ **最小值不可单独读**：`clamp 0.0000` 既可能是"某收尾帧被压"也可能是"整拍被吃掉"，是**同一个字符串** ⇒ 改印 `clamp 0.0000 (N/M frames)`，实测 0–4 / 76–123 ⇒ **安全带是罕见的短暂介入**；④ **两次渲染不是奢侈**：1280×720 只有 17.5–19.4fps，而积分步长被 `MOTION_MAX_STEP = 1/30` 截断 ⇒ **低于 30fps 时链自己的钟比墙钟慢**（同一拍 1280 读 `turn 2.64°`、960 读 `3.63°`）⇒ **报数只用 ≥30fps 那趟，1280 只出静帧**。
    - **终态全绿**：`STOW_ANCHOR (−1.040, 0.260, −0.270) · STOW_PITCH 0.42 · ARC_SWEEP 2.30 · ARC_LEAD_SLACK 2.60 · HANDLE_EYE_HEIGHT 0.150 · HANDLE_EYE_OUT 0.030 · ARC_LEAD_CLEAR 0.70` ⇒ `breach 0.0000 · reach 0.850 · margin +0.0314 · nb +0.0023 · ly +0.0134 · flat +0.0079 · bend 0.1268 ≥ 0.1110 · fan 65.6°（偏扁）· ring-vs-rope 0.0°`；`chain_v4_slice` / `chain_physicality` / `chain_integration` / `chain_combo_memory` **四套全 PASS**。**层级 = TECHNICALLY VERIFIED / VISUALLY REVIEWED**，**USER GAMEPLAY VERIFIED 仍只属于用户**。**仍未做**：移动时四层弧的 **50–100ms 位置滞后**（`margin +0.0314` 是它的预算；上一节的 `+0.0573` 已被本轮姿态调整花掉）。台账/扫数 → `docs/CHAIN_STOW_TUNING.md`。

- **缚星链 · I / ULTIMATE 垂直切片（VOID ANCHOR · 现实膜 · 漫画撕裂，2026-09-29）**：**本条的冻结（PART L）由用户指令解除，且只解除这一招** —— 用户原话「优先做出链子的I，我体验一下，本体无所谓，先做效果，这个阶段不要求链子的建模」。九拍按 brief §三 严格实现（起手 0.00 → 前刺 0.15 → 命中锚点 0.45 → 绕两圈 0.65 → 扯膜 1.25 → 漂浮 1.85 → 斩碎 2.15 → 漫画撕裂 2.85 → 恢复 3.20，止于 3.55s），全部是 `t` 的**纯函数**（无积分、无绳索/布料/断裂模拟，brief §二.1）。出片 `chain_ultimate_I_vertical_slice.mp4`（**12.70s** / 1280x720@30 / 25 cues：1.0s lead + 3.55s 技能**连续 take** + 1.0s tail + 同一 take 半速重采样）+ `chain_ultimate_I_keyframes/` 十帧（**切自同一条 take**，不是另跑 shot list）+ `docs/CHAIN_ULTIMATE_I_VERTICAL_SLICE.md`。**层级 = INTERNAL CANDIDATE（`chain_ultimate_integration` PASS，五项突变全红）· 手感仍未验收。**
  - **整个效果的成立点只有一条：`UV2` 是顶点属性**。膜的每个像素是**世界本身**，采样自它被撕下**之前**那个屏幕位置；那个位置在撕裂瞬间由冻结相机的投影烘进顶点 → 膜在哪被拉伸，影像就在哪被拉伸（「一块从世界上剪下来的材质」，不是贴在镜头前的图）。**方形做不到，因为方形没有材质可拉伸**。`nocapture` 消融（捕获换 0.42 平灰 → 膜变平灰）证明这个读**完全**依赖采样而非轮廓。
  - **`capture_tex` 少了 `source_color` 是这个效果第一个诚实测量的代价**：viewport 已经是 tonemap 过、sRGB 编码的**显示参考**数据，没有这个 hint 就交给 shader 当**场景线性**，出栈时再 tonemap 一遍 → 暗部 **×6.04**（world 0.134 → film 0.811）、亮部 **×1.00**（0.728 → 0.729）。观感是「一层发灰的膜飘在一个它本该**是**的房间上」。**测量本身也在说谎**：`measure_film.py` 的亮度比拿膜去比**虚空**，报了 +65%。
  - **「整幅画面被拉走、剩下黑」只能由收缩产生** —— 膜被拽向玩家在屏幕上只会变大，所以露出后面东西的唯一机制是 `sheet_contract_end = 0.33`。实测撕裂瞬间覆盖 **1.0000** 的帧（含帧角 8.57m），漂浮帧 **52%** / 撕裂帧 **66.8%** 像素暗于 0.05，高光溢出 0。
  - **房间必须整体离场，而且它是一个身体**：只藏地板 → 灯锥 / 雨棚梁 / 近处地面从虚空里穿出来。改成整棵 `room` 隐藏，门是 `sheet.frozen()` 且 `t < t_restore_start + hole_close_delay`（**不是钟**）。另注：`MeshInstance3D` 隐藏**不关碰撞**，玩家仍站在地板上。敌人（`TechnicalDummy`）作为**捕获排除**传入（`configure(player, tuning, [dummy])`），否则它同时被**拍进照片**又**站在虚空里** —— 拍两遍。
  - **渲染器一个 `await` 让整条 take 废掉**：`render_pass()` 里有 `await`，不 `await` 它就会并发跑三个 pass 共用一个帧计数 → 90 帧里 60 帧逐字节相同（线索是 `PASS1_FRAMES=0`）。另 tail 的 `_save(-1.0)` 改成 `_save(tuning.t_end)`。
  - **残留：消除的遮罩地板在 0.30 → 末帧还挂着膜**，而**只看亮度的门放它过去了**（149 vs 153 落在容差里）。遮罩推到零（`alpha *= clamp(1.0 - dissolve * (1.0 + 0.60 * grain), 0.0, 1.0)`）后四帧均值 **80.3 → 127.6 → 147.0 → 149.7**；编码器新增**逐像素残留门**（末帧 vs 首帧差 > 24/255 的比例必须 ≤ 24/255，当前 **0/255**）。
  - **未做 / 欠**：链本体建模（本阶段明确不要求，用现有 `ChainVisual`）；「**敌人真的站在膜后面**」**没有被专门构图**（断言证明他不在照片上、且站在虚空里，但**没有一帧是为这个关系拍的**）；音频是既有两层库的**分层占位**（25 cue，零新生成）；`ForegroundWeaponLayer._mirror_world_lighting` 在实验场报一个无害的 `environment` null 赋错。

- **缚星链 · REAL CHAIN PHYSICALITY PASS 02（2026-09-28 第三轮）**：用户裁决 `CHAIN MECHANIC EXISTS / CHAIN FEEL DOES NOT YET FULLY EXIST`，**冻结**游链/律链/更多锁链技能/锁链 Ultimate/复杂元素组合，直到六道门通过（单链 Miss 好看 / Hook 爽 / Tension 不看 HUD 可读 / 三种重量反应明显不同 / 3-hit Combo 不像三次独立 Tween / Orbit Momentum 真正可感知）。本轮新增装置 `godot/tests/chain_physicality.gd`（八组 A–H）**全绿**，并修掉四个一直看不见的 bug：交接姿态两个端点不在同一空间（`_pose_now()`）、`continue_from_head` 的 startup 是死节拍（`carry_anticipation` + 滑行曲线 `CARRY_TURN_SPEED`）、刀尖指着自己的反方向（WHIP 改对称 + `HEAD_TURN_TAU` 0.030）、测量本身在说谎（自由落体污染世界空间速度 / 两条时钟同名）。**突变扫描 13/13 全红**，其中一条是扫描找出来的洞（滑行的形状当初无断言覆盖）。`retract_out` 0.45 → 0.80（可见外漂 0.038m → 0.21m）。**回归：缚星链两套测试 PASS，零回归。手感仍未验收 —— 层级 = TECHNICALLY VERIFIED / INTERNAL CANDIDATE。**
  - **CLEAN TOUR V2 已出片**：`.render/chain_tour_v2_clean.mp4`（760 帧 / 37.24s，字幕无调试数字）+ `.render/chain_tour_v2_silent.mp4`（797 帧 / 37.25s，完全无标题）。九个 take = 松/甩/咬/蓄/拉轻/拉中/拉重/锚/撞，每拍一个**不同的物理问题**。出片时渲染器自己抓出一个 take 缺陷：「拉 · 重」的第三下按压（`heavy → 地砸`）**结构上不可达** —— 缚 的绑定只持续 `bound_time`（重 0.40s）到期即松脱回收，那一刻 `is_hooked()` 已为假，`heavy` 的含义变成"起转"。**根因是那一按本就不该存在**（缚 本身就是那一拉，地砸 属 §23 的另一拍），已删除而非改键。删后九拍零 `!!` 错配。
  - **三个「拉」现在是受控对比**（同一输入 / 同一根链 / 同一 3.6m，只有链头挂的东西不同）：轻 目标 1.720m / 玩家 0.230m（绑 1.00s）· 中 0.828 / 1.035（绑 0.70s）· 重 **0.000 / 0.805**（绑 0.40s）。**绑定时长随重量反向缩放**是白送的第四个信号。
  - **§25 有效链长 A/B 已做，结论 = 不加长**。招式填的是绝对半径（缠锁 4.6 正好等于 `max_radius`），加长放大的是每一式半径的分母：×1.25 / ×1.5 让缠锁只够到 80% / **67%** 的绳长；而在家下垂 **0.950m 三档完全相同**（已被 `SAG_LIMIT` 吃满），钩子的 taut 与长度也无关（`HOOKED` 时恒真）。**加长得到的是更松、更软的一条链，不是更重的一条** → 保留 4.6 / 4.7。力量感的合法旋钮是 `SAG_LIMIT` / `SAG_PER_SLACK` 与招式的 `radius_to`。
  - **未做**：§26 身体动作（左手握柄 / 右手投掷）、§29 recovery A/B（链头落定 / 松绳回位 / 手回收）。**未过**：甩（链头只有 0.015m 的偏离发生在"还松着"的时候）。
- **缚星链（2026-09-28 追加）**：`chain_integration` 全绿，本轮新增两项（`pull()` 距离口径、拉扯顿挫 5 记），两项都做过变异测试。同时回归 `movement_lane` / `combat_lab` / `hitbox` / `combo` 全绿。**"链一条设计文档都没有"这件事一并修掉了**（`COMBAT_DESIGN.md` §19）。手感仍未验收。
- **缚星链 · WEAPON SYSTEM PASS（2026-09-28 第二轮）**：本轮把 §43 的**冲击/回收/绷紧**做成可测量、可变异验证的**断言**（不是调参），并落地 §45 高阶锚点、§13 跟准心抛出、§46 读数闸门、§49 事件接口。**每一项新断言都单独做过一次变异测试**（归零/拆闸门/断瞄准/停广播 → 分别 2/4/1/1 项转红，随后按 md5 逐字恢复）。设计沉淀为 `docs/CHAIN_DESIGN.md`（三形态 V2）。**手感本身仍需可见桌面验收**。
- **本轮判定口径（重要）**：§52 —— 若三形态最终表现为"短链 / 长链 / 四条链"，即 **FAIL**。每形态必须提出**自己的问题**（实链：我能把什么拉过来？游链：我能从哪里借势？律链：我能让哪些东西彼此产生关系？）。
- **技术验证通过**：**18 项 headless 集成测试全部绿**。本轮新增 3 项：`element_magic_integration`（三系行为差异 + 规则即数据 + 5 种交互）、`white_rose_integration`（Measure 给手感不给伤害 / 缠剑是选择）、`combat_lab_integration`（4 流派 × 3 元素全排列）。另有 `hidden_edge_loop_integration` 把 P2 的藏锋循环钉住。
- **已提交**：`59d983c`（通用剑语言层，40 files）、`cd4cbad`（回风 Prototype）。本轮（元素数据层 + 魔法层 + 白蔷庭 + Combat Lab + 文档）单独一个提交：`b33a12f`（41 files, +3798/−154），**仅含战斗线文件**。
- **纪律**：本会话**未** `git add -A`。Iaido 演出线、ART、AUDIO 的未提交改动仍留在各自工作区。
- **交互验收未完成**：字面意义上的"是否有趣"仍未验收 —— 阶段一（通用剑）、阶段二（换流派可辨）、回风"为不断势而主动跑"、白蔷"主动控制距离"、三系魔法"只看行为能否分辨"，**全部需要动起来看**。headless 只能证明逻辑正确。
- **`--editor --quit` 副作用（需对账）**：本会话为注册 8 个新 `class_name`（`WindProps` / `ElementField` / `MagicSchool` / `MagicLibrary` / `SpellDefinition` / `ElementDefinition` / `ElementState` / `ElementLibrary`）跑了 import 一次。**本轮该次 import 后 `IaidoTuning.tres` 的 md5 未变**（`d8437620…`，与 import 前一致），说明此前的 `.tres` 重写与 import 之间不是稳定因果。**Iaido 线请自行确认 `IaidoTuning.tres` 的当前 diff 是否为你的意图。**
- **稳定但非确定**：`combat_music_integration` 在连续快速重跑时偶发退出即段错误（rc=139），**判定仍为 PASS**，单跑 3 次全 rc=0。属 headless 音频设备关闭竞态，非回归。
- 视觉当前为 `TempSwordVisual` 程序化姿态 + 刀光，**无手部、无骨骼动画**；需求见 `docs/COMBAT_ANIMATION_REQUIREMENTS.md`。

阻塞原因：本环境启动 Godot 无可见窗口句柄；AMD RX 6650 XT 上 Forward+ 黑屏，已回退 Compatibility（见 `BLACK_SCREEN_DIAGNOSIS.md`）。所有 gameplay verified 必须在用户可见桌面上完成。

### 环境备注：git push 通道

沙箱默认 HTTP 代理对 `github.com:443` 返回 502（`api.github.com` 正常），因此直接 `git push` 会失败。可行通道是本机 v2RayN SOCKS5：

```bash
export GH_TOKEN=$(gh auth token)
git -c http.proxy=socks5h://127.0.0.1:10808 \
    -c credential.helper= \
    -c credential.helper='!f() { echo username=x-access-token; echo password=$GH_TOKEN; }; f' \
    push origin godot-combat-mvp
```

`gh` 当前登录账号 `y13077816460-eng` 对本仓库有 push 权限；本机 SSH key（`nanhuyiqiu`）无该仓库写权限，不要用 SSH 通道。

---

## B · AUDIO

Suno / SFX / 裁切 / 分层 / FFmpeg / Godot 总线 / 战斗时序

| 任务 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- |
| Iaido 时间轴 15 cue 接入 | P0 | REVIEW | 已对齐 IaidoTuning，无断链；素材为占位 |
| 占位合成音替换（Suno） | P0 | TODO | 13 个 wav 全部 peak 0.898，见 `AUDIO_STATUS.md` |
| Signature SFX：Reality Cut / Blue Void / Collapse | P0 | TODO | Suno 未生成 |
| Basic atoms：metal / air / cloth / glass / stone | P1 | TODO | 需自建可复用库 |
| Sword / guard / perfect guard SFX | P0 | TODO | `COMBAT_SFX_BRIEF.md` Priority A 全未落地 |
| Guard 闭环补充（`guard_hold`/`guard_break`/`riposte`/`blade_glint`） | P0 | TODO | `COMBAT_SFX_BRIEF.md` Priority A2 |
| 流派辨识音（藏锋 / 回风） | P1 | TODO | `COMBAT_SFX_BRIEF.md` Priority D；不看 UI 也能分辨流派 |
| 无明一刻 8 cue（含 `mom_click`） | P0 | TODO | `COMBAT_SFX_BRIEF.md` Priority E；与聚合斩 cue 严格分开 |
| 元素 SFX（火/冰/风/shatter） | P1 | TODO | `COMBAT_SFX_BRIEF.md` Priority B —— **已被 Priority F 取代/扩展，见下** |
| **元素"行为"音层（Priority F）** | P1 | TODO | `mag_burn_loop`（必须不规则）/ `mag_frost_stage` 三声 / `mag_shatter` 两段 / `mag_wind_light` vs `mag_wind_heavy`（同输入不同结果，是本元素的论点）/ `mag_wall_impact` |
| **白蔷庭辨识音（Priority D 扩展）** | P1 | TODO | 10 个 cue，含 `wr_bind_lock` / `wr_bind_thrust` / `wr_bind_disengage`。**硬约束：`wr_jiazhang_read` 前 200ms 必须与 `wr_chuanting_drive` 同源**，否则假章会被听出来 |
| **回风补齐（Priority D 扩展）** | P1 | TODO | `fw_zheliu_slip`（必须听起来像"攻击落空"而不是"挡下"，否则折柳失去身份）/ `fw_changfeng_a/b/c` |
| **藏锋 loop（Priority D 补充）** | P2 | TODO | 截锋之后立刻归鞘的那一下 `he_sheathe` 会**更早**触发；P2 只改了时序，未加 cue |
| BGM | P2 | DONE | 4 首 Suno 已接入（Web 原型期） |
| `NAR-AUDIO-01` 第五次钟声 | P1 | REQUESTED | 独立音型，但**不要"恐怖片第五声"**——只是让细心玩家觉得节奏不太对 |
| `NAR-AUDIO-02` 遗迹方向夜间极低频 | P1 | REQUESTED | barely audible：玩家应该不确定那是风，还是别的东西 |

---

## C · ART & MODELING

ChatGPT Web → Blender Python → Blender MCP → GLB → Godot

> **英雄武器线的例外（用户 2026-09-29 指令）**：`# 这一批资产不要走 GPT / Chat2Blender` / `# DIRECTLY MODEL IN BLENDER`。
> 武器家族由 `tools/blender/wpn_<fam>_build.py` 在 headless Blender 里**直接建模**，`weapon_common.py` 出契约/断言/导出。流程仍是
> `BLOCKOUT → SILHOUETTE REVIEW → SECONDARY FORM → MATERIAL PASS → DETAIL PASS → BLENDER RENDER → CRITIQUE → FIX → GODOT → IN-GAME REVIEW → FIX AGAIN`，
> **≥2 次视觉迭代**；`BUILD FEWER. BUILD BETTER. ITERATE HARD.`

| 资产 | ID | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| First Person Sword | C2B-01 | P0 | **DONE · 待用户手感验收** | 真剑已入 `godot/models/weapons/fp_sword.glb`（**10,378 tris**，AABB 1.0570 × 0.0777 × 0.0697，4 材质）。**换模型未动位置与技能**：作为子节点挂进 `TempSwordVisual`，`Player.tscn` 一行未改，`SwordHitbox` 仍是 `(0, −0.2, −1.4)` / `1.4×1.2×1.6`。训练场武器架摆出货本体。见 `HERO_ASSET_REPORTS.md` W01 |
| First Person Saya（剑鞘） | C2B-01b | P0 | **几何 DONE · PASS 2 待做** | 803 mm，膛内衬 790 mm；鞘口 x −3.405 对齐剑护手 x −3.400，刃 47.3 × 8.0 整根在膛内**不穿模**。金具/栗形/口沿磨损仍是 blockout。见 `HERO_ASSET_REPORTS.md` W02 |
| Star-Bind Chain · 柄 / 链节 / 三叉刀头 | C2B-01c | P0 | **英雄模型 DONE（3 件）· 未入 Godot** | 柄 0.2805 m / 1624 tris；链节 0.09110 × 0.06013 × 0.01367 m / 320 tris（与 `stow_diag.gd` 闭式逐位一致）；三叉头 0.7800 m / 1096 tris。三件均通过 `ASSERT` + `verify_glb`。**手持束 `HELD_ARC_A..D` 未开始**，被 REQ-9 挡住（要 COMBAT 先发 `visible` + `release 0..1`）。三件均**未做 IN-GAME REVIEW**。见 `HERO_ASSET_REPORTS.md` W03 · `docs/weapons/CHAIN_ASSET_DECOMPOSITION.md` |
| Staff Family · 短杖 / 中杖 / 长杖 | C2B-01d | P1 | **英雄模型 DONE（3 件）· 未入 Godot** | M2.5 三族证明的第三族。`shard` 1.0620 m / 2240 tris / X 0.1127 × Z 0.1137；`lattice` 1.3910 m / 3288 tris / 0.1400 × 0.1212；`orrery` 1.5520 m / 3904 tris / **X = Z = 0.2320（闭式 `2 × (0.0860 + 0.0300)` 逐位一致）**。三行 `ASSERT` + `verify_glb` 全绿。**回归**：`CHN` 三件逐位不变、`SWD` 10/10 不变。五轮迭代（PASS B–E），途中发现并修掉：预览用 AgX 而运行时是 FILMIC、缠绳/铜件/浮环三处材质取错岗位、水晶 profile 是泪滴、卫星 5.6:1 读成叶子、四重径向对称读成莲花、剪影读成锤子。三件均**未做 IN-GAME REVIEW**。见 `HERO_ASSET_REPORTS.md` W04 |
| FP Hand / Forearm | C2B-02 | P0 | SPEC READY | brief 本次补写 |
| Lesser Ruin Sentinel | C2B-03 | P0 | SPEC READY | brief 本次补写 |
| Magic Catalyst | C2B-04 | P1 | SPEC READY | brief 本次补写 |
| World Beacon | C2B-05 | P2 | TODO | Combat MVP 之后 |
| Adventurer Guild | C2B-06 | P2 | TODO | 同上 |
| Mistvale Stair / Terrace Kit | C2B-07 | P2 | TODO | 同上 |
| Town Props | C2B-08 | P2 | TODO | 同上 |
| Oren / Mira 人物 | — | P2 | TODO | Tripo / Hunyuan3D 候选，Rig 不阻塞 |
| Sword Pose Anchors ×5（Idle/Guard/Sheath/HeavyWindup/Sprint） | C2B-09 | P0 | REQUESTED | 招式动画的前置；锚点不对则所有招式首尾帧返工 |
| Ultimate 钩子（Ready/Draw/Hold/Sheathe） | C2B-10 | P0 | REQUESTED | 无明一刻专用，独立产线，**禁止复用聚合斩资产** |
| 通用层 7 招动画 | C2B-11 | P0 | REQUESTED | 依赖 C2B-02 + 锚点 |
| 藏锋流 8 招动画 | C2B-12 | P1 | REQUESTED | 需 SheathAnchor 左腰变体 |
| 回风式 8 招动画 | C2B-13 | P1 | REQUESTED | 含 折柳 / 惊鸿 / 长风三段；**长风需要一个侧向镜像版本**（方向由玩家输入决定） |
| 白蔷庭 8 招动画 + `BindHold` | C2B-14 | **P1（本轮升级）** | REQUESTED | 已从"设计态"变为"已实现但无动画"。硬约束：剑尖**始终在中线附近**；`wr_jiazhang` 与 `wr_chuanting` 起手帧需可互换 |
| **风的环境：墙 + 可推动轻物** | C2B-15 | P2 | **PLACEHOLDER** | `WindProps` 现为程序化盒子。ART 可整体替换网格，但**"一面可撞的墙 + 两个轻到能被推的物体"这两个物理角色必须保留**——没有它们，风只是一个击退数字 |
| **施法姿态：QuickMagic / HeavyMagic** | C2B-16 | P2 | REQUESTED | 硬约束：**Quick Magic 时主手剑不得消失**。见 `COMBAT_ANIMATION_REQUIREMENTS.md` |
| **剑身附魔材质通道（火刃 / 霜刃）** | C2B-17 | P2 | REQUESTED | 不需要新动画，需要剑身材质能"泛红/泛白"而不是一层均匀自发光 |
| `NAR-ART-01` 翻倒的商队车（**模块化**） | — | P1 | REQUESTED | cart / wheel / crates / cloth / rope / cargo 可重组；不要一张固定"事故照片" |
| `NAR-ART-02` 钟塔（远景 Landmark） | — | P1 | REQUESTED | 重点 **Silhouette**；雾起时只剩轮廓 |
| `NAR-ART-03` 奥伦后院道具 | — | P1 | REQUESTED | chopping block / wood pile / tool rack。是普通后院，不是训练场；木桩有积年切痕 |
| `NAR-ART-04` 魔法在日常的痕迹 | — | P1 | REQUESTED | 渡口定向磨痕 / 市场结霜库房 / 铁匠铺"看火"。**不做发光特效** |

### C2 · ART 地编 / 道具 / UI（本轮新增）

规划全文见 `docs/ART_KIT_PLAN.md`，UI 规范见 `docs/UI_STYLE_BOARD.md`。

| 资产 | ID | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| **Mistvale Region Masterplan** | **LD-01** | **P0** | **DESIGN LOCKED** | `docs/LD-01-MISTVALE-REGION-MASTERPLAN.md`。区域 660×760 m、高差 161 m、5 地标、9 Vista、22 叙事槽位、8 战斗空间、2 条山路。几何判据已由 `tools/audit_routes.gd` 机器实测通过；人工走查待办 |
| **GATE 1 灰盒** | LD-01 | P0 | **IN GODOT（可从主菜单进入）** | `scenes/world/MistvaleRegion.tscn` + `scripts/world/{mistvale_heights,mistvale_terrain,mistvale_greybox,ld_review_walker}.gd`。全自动审计：4 条路线 0% 不可通行、0 段超 80 m、8 个战斗空间 7 个 OK、**19/19 Vista 视线全通**、任意点 ≥1 地标可见 98.7%。**新增：主菜单第二扇门「探索雾谷（地图漫游）」** —— 见下方 C2c |
| ↳ 第一人称连续走查工具 | LD-01 | P0 | **DONE** | `tools/level_art_walk.gd`。沿 `ROAD_SPINE` 每 10 m 一站、相机在眼高 1.70 m 沿切线看，逐帧输出 `skyL/midL/gndL`、地平线行号、6×8 指纹、以及 **d1/d10/d30 指纹距离**（即附录 §27/§28 的 10 秒 / 30 秒检验，做成数字）。分析在 Godot 内算，不回读 PNG——实测 PNG 是 Paeth 滤波，纯 Python 解滤波约 0.9 s/帧 |
| ↳ 三座 P1 地标建成 | HERO-01/02 | P1 | **IN GODOT（待人工走查）** | `scripts/world/mistvale_landmarks.gd` + `kit_forms.gd`，7 mesh / 1476 tris。**钟塔** 塔身 40.4 m（塔顶 105.2 m）@(−26,−95)、**公会** 27×27×23.6 @(12,−58)、**北门** 31.6×25.5×13.5 @(0,−135)——北门是真门洞（侧墙+过梁+拱券+门柱），不是贴片。`mistvale_greybox.gd` 的 `HERO_REPLACED` 跳掉对应黄盒 |
| ↳ 评审图集（10 张） | LD-01 | — | **DELIVERED** | `assets_source/review/ld01_01..10*.png` + `height_field.csv`。诊断脚本 `diag_vista_blockers.py` / `diag_vista_relocate.py` |
| ↳ V1 林隙石台 | LD-01 | P1 | REQUESTED | 视线审计产物：V1 必须抬到地面 +10.5 m 才能看到河谷（文档原写 Y=36、实测 31）。见 Masterplan §6b |
| ↳ V7 挑台岩台 | KIT-03 | P1 | REQUESTED | 视点移到 (−37,−232)，需一件挑出的岩台构造，否则「我走了很远」不成立 |
| ↳ 走查候选缺陷 A · 3 处地标基座浮空 | LD-01 | P2 | TODO | 本轮区域评审渲染发现。`mistvale_greybox.gd` 的 `LANDMARKS` 基座挂在绝对标高上，与真实地形不符：`A_BellTower` y=72 vs 地形 **62.2**（浮 **9.8 m**，且本表另记「基座实测 Y=62.5」）、`E_RuinsBeacon` y=152 vs **143.3**（浮 **8.7 m**）、`D_RidgeScar` y=160 vs **155.7**（浮 **4.3 m**）。航拍里表现为悬空黄板。**最可能的解释是这三处依赖的人工台地尚未建模**。⚠️ 禁止孤立下沉——地标是 Vista 视线的判据目标物，任何标高改动必须连带重跑 `tools/audit_routes.gd` 的视线审计（现为 9/9 全通） |
| Mistvale Ground / Stair / Terrace Kit（12 件） | ENV-01 | P0 | IN GODOT | 12 件全部按规格建成，5,986 tris；每件一个 GLB 已入 `godot/models/environment/mistvale/`；拼接验证通过；**降级为 STRUCTURAL BASE KIT**，不代表最终品质 |
| ↳ **训练场美术复合场 · 八区** | **ENV-01 / ART** | P1 | **TECHNICALLY VERIFIED** | `scripts/training/training_ground.gd`。**新增 H 擂台**（12 m 台面抬 `LIFT_RAMP` 0.90 / 西面留 2 m 门洞 + 坡道 / kerb 0.28 / 三面双栏杆）、**I 复杂地形**（0.90 · 1.44 · 2.34 m 三层台地 + 台阶 + 双坡道 + 6 m 天桥，层高只用 kit 的 1.44 与 0.90）、**J 远距离大平地**（62×8 m，尽头 55 m 门架），**F 改展廊**（3×4 一座一件，列/行距由馆自身尺寸派生；预留位建成空基座 + 牌）。**本轮三个发现**：① **ENV-01 的 12 件 GLB 全无碰撞**（无 `-col` 后缀 ⇒ 裸 `MeshInstance3D`），楼梯一直是"画出来的图" → `ENV01_BOXES` + `_env_collide()` 补代理，阶梯做成**沿坡法线降半厚的斜板**（19.8° 可走，优于 8 级 0.18 踢面）；② **`ENV01_SLOPED` 两件原点在坡底**，摆在基座中心会**伸出 1.81 m 到走道上** → 按半跑长回退；旧断言只量基座、因此全绿，已改成**量件**；③ 展厅深度 22→30 m（4 m 深的件在 5.5 m 行距下只剩 1 m 走道）。断言 `tests/training_ground_boot.gd`（新增 8 条；突变红检：上一轮 6 处注入抓 5，本轮新增的"件是否站在自己基座上"注入即红）。出片 `tools/training_ground_renderer.gd` **19 张**（新增 14–19），**10 与 13 仍逐字节相同**（`71599c93…`，居合桩自复的证据）；review 机位改**读场景 `Review_*` 锚点**而非手抄坐标 |
| Adventurer Guild Exterior Set（8 件） | ENV-02 | P1 | **HOLD** | 按 ART PASS 02 §39 暂停精模。等 GATE 1/2 通过后按 Masterplan §19 重写 brief |
| Town Prop Set A（12 件） | ENV-05 | P1 | REQUESTED | 道具家族制，见 KIT PLAN §4 |
| **Adventurer Guild V2（公会高台）** | **HERO-01** | **P1** | BLOCKED | 等 GATE 1 人工走查通过。非「放大版民房」：强剪影 / 高台 / 可见入口 / 多层体块 / 生活功能 |
| **Mistvale Bell Tower** | **HERO-02** | **P1** | BLOCKED | 等 GATE 1。强远景、雾中辨识、导航工具；基座实测 Y=62.5 |
| **Town Architecture Kit V2** | **KIT-02** | **P1** | BLOCKED | 换掉「Cube+Roof Prism」体块。必含 assembly_demo，且必须拼出 2–3 个明显不同实例 |
| **Stair / Terrace Kit** | **KIT-02a** | **P0** | **SPEC READY** | brief + 粘贴包已出：`docs/asset_briefs/KIT-02a-STAIR-TERRACE.md` + `prompts/KIT-02a-01-send.txt` / `KIT-02a-02-assembly.txt`。实测全区域**只有 3 个楼梯点**（第 4 条是两路汇合重复计数）：**S-A 公会阶梯** (0,−32)→(0,−36) 35.5° → riser0.22 × 2 段 = 14 级 · 4.00×3.08 m；**S-B 崖路大阶梯** (44,−333)→(29,−339) 39.9° → riser0.24 × 8 段 = **56 级 · 16.00×13.44 m**（全区最大人工构造，只有东线经过）；**S-C 西线岩阶** (−61,−262)→(−59,−270) 35.7° → riser0.22 × 4 段 = 28 级 · 8.00×6.16 m。模数：**踏面锁死 2.00/7 = 0.2857 m**，7 级 = 恰好 1 格 2 m；四档踢面 0.16/0.20/0.22/0.24 → 29.25/34.99/37.60/40.03°。13 件，复用 ENV-01 的 4 个材质。⚠️ **碰撞硬约束**：每段梯必须随 GLB 附带斜坡碰撞代理（`CharacterBody3D` 无自动上台阶，0.24 m 踢面在 trimesh 碰撞下就是墙，玩家会卡死）；必须含 `assembly_demo` 三实例 |
| **Mountain / Cliff Kit** | **KIT-03** | **P1** | BLOCKED | 大崖/中崖/台 shelf/岩簇/山径边缘/碎石 |
| **Bridge / River Kit** | **KIT-04** | **P1** | BLOCKED | 桥、桥墩、渡口、系船、浅滩。三个渡河点坐标已锁定 |
| UI Style Board + UI Kit V1 | UI-01 | P0 | DONE | 5 件 SVG 已入 `godot/ui/kit_v1/`；场景接入待 MAIN |
| **UI PASS 02→03 · DE-AI V2 FINAL** | **UI-05** | **P0** | **FEATURE-LOCK READY（Godot 待接）** | 见下方小节 |
| 主菜单 V1 | UI-02 | P0 | SUPERSEDED BY UI-05 | 原记「依赖 ENV-01 + ENV-02 作为实景背景」。实际做法改为**直接从 `MistvaleRegion.tscn` 出图**（`tools/menu_vista_renderer.gd` → `assets_source/ui/world/mistvale_menu_v1.png`），因此不再等 ENV 资产：真场景交付后重渲一次即可升级标题画面。ART 侧的长期诉求见 `ART_INTEGRATION_REQUESTS.md` REQ-6 |
| Ability Wheel V1 | UI-03 | P0 | REQUESTED | 环与扇区资产已备；逻辑沿用 `radial_wheel.gd` |
| HUD Frame V1 + 状态条 | UI-04 | P0 | REQUESTED | 底板与三态已备；接入 `CombatHUD.tscn` |
| Town House Kit A（9 件） | ENV-03 | P1 | REQUESTED | **须先与 `assets/models/mistvale/` 既有 12 件做一致性审计再合并** |
| Town Market / Stall Kit（7 件） | ENV-04 | P1 | REQUESTED | — |

### C2c · 区域入口 + 漫游（本轮新增）

**问题**：地图此前只以**静图**存在。`MistvaleRegion.tscn` 有 `LDReviewWalker`，但没有任何从游戏里到达它的路径——`Main.tscn` 的主菜单只有一个按钮，进的是 24 m 的战斗竞技场。地图没法被体验，只能被截图。

| 交付物 | 位置 | 状态 |
| --- | --- | --- |
| 主菜单第二扇门「探索雾谷（地图漫游）」 | `scripts/systems/main_menu.gd` + `main_flow.gd`（`region_pressed` / `start_region`） | **DONE** |
| `main_flow.gd` 双世界化 | `active_world()` + 所有战斗专属节点走 `has_node()` 守卫 | **DONE**。区域没有 `IaidoDirector`／`AudioStateController`／`Player`，原来的 `get_node()` 一暂停就抛 |
| 漫游 HUD | `scripts/world/region_walk_hud.gd` | **DONE**。显示**区域名 / 距主线里程 / 海拔 / 坐标 / FPS / 按键**。区域名沿 `ROAD_SPINE` 分 9 段（雾谷东林 → 青竹林 → 林缘眺台 → 渡口石桥 → 南岸缓坡 → 下城区 → 集市广场 → 公会台地 → 上城区北门），用**最近点**而非投影，所以离开路也报得准 |
| 出生点校正 | `ld_review_walker.gd` | **DONE**。场景里写死 y=42，而 (200,320) 真实地面 **34.2** —— 进图先掉 8 m。改为从高度场采样，落地落差 0.46 m |
| 转向跟随鼠标捕获状态 | `ld_review_walker.gd` | **DONE**。原来自己存 `_captured` 标志，被暂停菜单接管 Esc 后**回来转不了视角**且没有任何提示 |
| 自动冒烟测试 | `tools/smoke_region_entry.gd` | **DONE**。headless 走完整链路：挂载 Main → 点第二扇门 → 区域挂上 → 走 90 物理帧落地 → HUD 出字 → 暂停 → 回标题。`=== PASS ===` |

**这一轮量出来的三件事（都不是读代码能读出来的）**：
- **场景此前根本没有环境光**。`ambient_light_source = 2`（COLOR）在 `gl_compatibility` 下**贡献为 0**——把 energy 从 0.32 抬到 2.0，阴影街面亮度**一动没动**。改成 SKY 后同一块石板 13 → 32，向阳面 75 → 95。`ambient_light_energy` 在 SKY 模式下**同样被忽略**，环境光只由天空亮度决定。
- **第二盏平行光几乎不起作用**。`Bounce` 从 0.40 扫到 3.0，阴影只从 32 走到 35。此前"是 Bounce 修好了 R06"的因果说法是**错的**——R06 是被关掉楼梯板投影修的。
- **埋在地下的构件会用不存在的几何投影**。地形 `cast_shadow = OFF`（否则 660×760 m 高度场自阴影起摩尔纹），于是公会 9 m 深的基座在阴影图里是一堵 9 m 高的墙，把 37 m 外的街面从 32 压到 21。修法：**所有没入地面的部分单独成 mesh 且 `cast_shadow = OFF`**，验证回到 32。

**仍未过**：人工在可见窗口里的走查（本环境无窗口句柄）；以及 `WHAT LOOKS FAKE` 清单（树冠是扁平深色蘑菇、河岸缺碎石/泡沫过渡、山侧三座地标仍是黄盒、地表偏塑料、R03 下城街仍平淡）。

### C2b · UI-05 · UI PASS 02 / DE-AI（本轮）

方向：**THE WORLD IS THE UI BACKGROUND**。主菜单先给玩家看 SEKAI 的**世界**，UI 只在上面覆一层。
明确禁止作为核心构图：居中符号 + 放射几何 + 细装饰线 + 大片空暗背景 + 粒子 + 渐变 + 小号英文微文案 + 绝对对称。
判据（每张图都要过）：这一眼像不像**游戏**？看不看得见**世界**？关掉全部装饰 SVG 还立不立得住？菜单是否比背景低一个视觉层级？

| 交付物 | 位置 | 状态 |
| --- | --- | --- |
| 标题画面背景（真游戏内渲染） | `assets_source/ui/world/mistvale_menu_v1.png` 2560×1440 · 出图工具 `godot/tools/menu_vista_renderer.gd`（shot 53 / V1 林隙石台 / fov 30 / 日 19°·34°） | **DONE**（灰盒 + 大气，等 ART 真材质后重渲） |
| V2 网页高保真原型 | `ui_web/v2/`（`v2.config.js` `world/world_bg.*` `ui_v2.css` `launcher/` `main_menu/`） | **DONE**，与 V1 并存不覆盖 |
| 启动序列（§9，2.8s） | `MENU_BOOT.first`：黑 → 只有标记 → 细线划过 → 线变 reveal mask → Logo 成形 → 菜单 | **DONE** |
| 回访启动（§30，1.1s） | `MENU_BOOT.again`：`?boot=again` 或 localStorage `sekai.v2.menu.seen` | **DONE** |
| 主菜单 → 世界（§25，无黑场） | `enterWorld()` + `worldPush()`；世界帧契约 `ENTER.worldFrame = { scale: 1.055, panY: −0.012, scrim: 0 }` | **DONE（网页侧）**；Godot MenuCamera 待接 |
| 审查图 / 片 | `ui_web/previews/ui_pass02_{headline,boot,enter,launcher}.png` + `{launcher,main_menu,main_menu_again,menu_to_game}_v2.mp4` | **DONE** |
| UI SFX 方向 | `docs/UI_SFX_BRIEF.md`（已交 AUDIO；cue ID 对齐 `ui_web/components/ui_cue.js`） | **DONE（方向）**，音源未产 |
| Godot 侧整合 | `boot_splash.gd` / `MenuCamera` 与 `worldFrame` 对齐；`--target=` 接收 | **TODO**（下一步） |

**PASS 03 / FINALIZATION（2026-09-28 晚）—— 方向已冻结，本轮只做「减、收、连、真实化」：**

| 交付物 | 位置 | 状态 |
| --- | --- | --- |
| Launcher final（§A 三信息 + FAST PATH） | `v2/launcher/`：题签 SEKAI/Beyond the Written Fate + 进入世界；meta 缩右下角；`?boot=again` 直落终态 | **DONE** |
| 存档连接（§5/§6） | 「继续旅程 / 雾栖镇 · 01:42」；无存档时该项**整个不进列表**（`?nosave=1` 可验） | **DONE** |
| 设置覆盖层（§H） | 排版行 + hair 分隔线覆盖左区，世界继续动；←→ 调值、↑↓ 移动、Esc 返回；localStorage 持久化；亮度真实作用于世界层 | **DONE** |
| 确认反馈（§13/§14） | 第一帧：未选项 100ms 退场，选中项先 resolve 再退；随后曝光 +4%、雾带擦过、推进 | **DONE** |
| 相机再减半（§10） | drift 3.5%/90s → **1.8%/120s** | **DONE** |
| SVG kit 审计（§D） | 裁决写进 `svg/library.js`；`ring_arc`(demote)/`corner_frame`(delete) **停止导出并删除残留文件**；`emit_svg.mjs` 带 verdict | **DONE** |
| UI SFX 六 cue 化（§I） | `docs/UI_SFX_BRIEF.md` 收成 UI_FOCUS/CONFIRM/BACK/OPEN/CLOSE/BOOT；`ready`/`start` 刻意无声 | **DONE** |
| 最终交付 | `ui_web/previews/{launcher_final,main_menu_final,menu_to_game_final,settings_preview}.mp4` + 定妆帧 + `ui_pass03_compare.png`（三帧对比）+ `ui_pass03_states.png` | **DONE** |
| §L 去 Logo 检验 | `main_menu_final_nologo_test.png`：拿掉 SEKAI，画面仍是「一个地方」—— 但身份目前由**灰盒**承担，真材质到位后须复查 | **PASS（带条件）** |

本轮新增的一个静默坑：`render.mjs` 的 `probe` **不执行 `--events`**（只有 shots/video 跑）——
用 probe 验证事件驱动状态会得到"没生效"的假象，实际是工具没发事件。

本轮修掉的两个**静默**缺陷（都不会报错，只会"看起来没生效"）：
- `SKMotion.animate()` 不接受数组，却有 5 处传数组 → 抛在 motion.js、调用点在页面，症状是"启动播了一半停住"。
  现已加**当场抛错**的守卫 + `animateAll()`。
- 主菜单标记的显示尺寸同时写在宿主 span 与内层 svg 上，页面 CSS 覆盖了通用 CSS → `markHome` 只补间了一个空盒子，
  标记不缩放。症状是"启动头一秒几乎全黑"。尺寸现在只存在于宿主一处。

**PASS 04 / KEY ART MAIN MENU（2026-09-28 深夜）—— §0 裁决：Greybox 实时地图暂不强制做主菜单背景**

地图仍在 Level Art Production，实时画面"雾重/偏灰/白体块"反过来拖累已成熟的 UI。
允许 CUSTOM KEY ART 作为**主菜单展示方案**（SELL THE DREAM）；游戏内继续真实 Level Art（BUILD THE DREAM）。
地图达到 VISUAL CANDIDATE 后再做 Key Art vs Real World 的 A/B 重裁决。

| 交付物 | 位置 | 状态 |
| --- | --- | --- |
| Key Art 三方向候选（image generation，TEXT-FREE，1920×1080） | `assets_source/ui/keyart/keyart_{a,b,c}.png`（A=Vista / B=River Approach / C=Mountain-Sky；裁自 1536×1024，**裁切同时去掉右下平台水印**） | **DONE** |
| A/B 实测图 | `.render/keyart_ab/menu_keyart_{A,B,C}.png`；裁决 **B（River Approach）**：UI 落左下暗色前景可读性最好，村庄/钟楼/桥居右，斩痕+天空环成立，无 AI 壁纸味 | **DONE** |
| 背景接线 | `?bg=a|b|c` 覆盖（`KEYART` 表 + `world_bg.js`）；不传参 = 真 Godot 渲染，默认不变；Key Art 下独立雾带 opacity×0.4（§16） | **DONE** |
| 2.5D 视差（PART B） | sky/fg 为同图软 mask 副本（CSS mask），--par-x/y 驱动 2–8px；lerp 0.06；reduced-motion 全关 | **DONE** |
| Launcher Key Art（PART C） | `v2-keyart`：同图 darker(0.42)/cropped(1.14)/少信息；launch 时 zoom→1.2 淡回 void，交接合同不破 | **DONE** |
| Loading Line 修复（§21） | 成功路径 + RENDER 模式 `max(total, lineMs)` 均调用，240ms 淡出；交接帧干净（曾由 ui_latest_09 抓出残留）。**PASS 05 起并入统一加载符号**（`.v2-load` 特例线已删） | **DONE** |
| 存档摘要（§15） | `01:42 → 1:42`（去零填充，读作游戏存档） | **DONE** |
| 最终出片 | `ui_web/previews/{launcher,main_menu,menu_to_game}_keyart_final.mp4` + `main_menu_keyart_settled.png` + 三版 A/B/C 截图 | **DONE** |

注意：Key Art 只是展示方案，`WORLD.base`（真场景渲染）仍是默认与长期真相源；
`world_bg.js` 头部"§4 禁止幻想城市背景图"的旧约束由本 PASS 的显式裁决取代（附条件与复评节点）。

**PASS 05 / LOADING GLYPH（2026-09-29 凌晨）—— 一个独立加载动画，实装进所有 >3s 的等待点**

| 交付物 | 位置 | 状态 |
| --- | --- | --- |
| 独立加载组件 | `ui_web/components/loading_glyph.js` + `.css`；语言 = **一笔被反复书写的 hairline**（WRITE），非 spinner/非进度环/非百分比。变体 `left`（Main Menu，与菜单同一条栅格线）/ `center`（Launcher） | **DONE** |
| 出现条件 = 时间 | 等待跨过 `LOADING.thresholdMs`(3000ms) 才现身；就绪后至少活 `minVisibleMs`(900) 再淡出。三秒以内的等待保持安静 | **DONE** |
| 实装范围（真实等待点） | `v2/launcher` 启动桥 · `v2/main_menu` 世界图加载 · `v2/main_menu` Menu→Game 启动 —— 三处全走 `loader.watch()`。legacy V1 页面不接（已被取代） | **DONE** |
| 实测证据 | 短等待 2000ms **全程不现身**；长等待 5000ms 在 ≈3000ms 现身、结束后收；相位帧两两像素差非空；片内抽帧验证 | **DONE** |
| 交付 | `ui_web/previews/loading_glyph_{menu,launcher,phases,enter}.png` + `loading_glyph_{menu,launcher}.mp4` + `loading_glyph_capture.txt` | **DONE** |

本轮修掉的两个真 bug：
- **标签永远不显示**：`labelEl` 只在初始 label 非空时才 appendChild，而 watch/engage 后才给文本是常见路径 → 设了 textContent 却不在文档里。
- **细线横穿版本号**：加载符号 left 变体与 `.v2-meta` 同在左下一条栅格线，`0.3.0-ui01` 被读成乱码。
  组件只在 `<body>` 发布 `data-loading="1"`，页面 CSS 决定谁退场（分层，组件不猜页面结构）；
  用 transition 而非补间，因此天然让位于进入序列里本来就有的 meta 淡出。
- 顺带删除 `.v2-load` 特例线（同位、同语言）——**一个等待只允许存在一个书写者**。

### C3 · 里程碑问题（须长期对账）

- `assets/models/mistvale/` 的 12 件 GLB 此前被记为 "Integrated"，实际**从未接入 Godot**，`godot/` 下无任何 `mistvale` 引用。已更正。
- `godot/scenes/ui/*.tscn` 各 7–10 行，`radial_wheel.gd` 为纯 `_draw()` 占位 —— UI 此前完全没有视觉资产。UI Kit V1 是首次补齐。

### C4 · 阻塞与工具链

- **美术线浏览器已独立**：ART 用 Chrome `:9333` + profile `F:\tools\chrome-profile-art`；音频线保留 `:9222` + `F:\tools\chrome-profile`。两者不再互相抢标签页。
- `:9222` 实例的 CDP 浏览器级通道已失效（WebSocket 可连、握手无响应），人类窗口仍可用，但**任何 agent 都无法再连上它** —— 音频线如需自动化，须重启该实例。
- 阻塞原因（原）：Blender MCP 未连接本会话；ChatGPT Web 需用户登录态。Producer 已产出可直接粘贴的 prompt 包（`docs/asset_briefs/C2B-01-CHATGPT-PROMPT.md`，以及新的 `docs/asset_briefs/prompts/ENV-01-01-send.txt`）。
- 已解除：Blender MCP 直连 `127.0.0.1:9876` 可用（裸 JSON over TCP，`execute_code` / `get_scene_info` / `get_viewport_screenshot`），Blender 5.1.2 在线。
- **`tools/audit_routes.gd` 已扩展出「楼梯带报告」**：不再只报"哪里超过 35°"，而是把 35–45° 的**连续段**找出来，反解有效坡度、水平进深、净爬升，并算出落到 2 m 网格上的**模数解**（riser × 段数 = 级数）。选踢面用**联合评分（爬升残差 + 2 × 进深残差）**——只看爬升会选出 24 m 缓梯，只看坡度会落到坡顶下方 0.6 m。这是 KIT-02a 的唯一输入，地形一改就重跑。

---

## C-LIA · CHARACTER LINE（角色线 · 2026-09-29 开工）

独立工作线，与 COMBAT / AUDIO / ART(道具·环境) / UI / NARRATIVE 并列。规格：`docs/characters/CHARACTER_LINE.md`
当前角色：**LIA / 莉娅**（渡工）。目录：`assets_source/characters/lia/`。工具：`tools/character/*.py`。

### C-LIA · PHASE 状态

| PHASE | 内容 | 状态 | 备注 |
| --- | --- | --- | --- |
| 01 | AUDIT | **DONE** | `docs/characters/LIA_V0_AUDIT.md` · 14 项阻塞问题 · 12 格审核表已出 |
| 01b | V1 BASE（归零 + 缩放） | **DONE** | `02_working/LIA_v1_base.blend`：变换烘焙 · 对称面归 x=0（残差 2.95 mm＝网格分辨率）· 原点=脚底中轴 · **×1.5076 → 颅顶 1.580 m**（围盒 `0.942 × 0.516 × 1.692`） |
| 02a | 整体自动重拓扑试跑 | **DONE · 结论=不够** | `02_working/LIA_v2_auto_quadriflow.blend` · **20,478 面 100% 四边面** · 36 s。形体/服装宏观可用，但**脸被抹平、手指并成手套、头发糊成一团、披风变扭带**（中位边长 11.7 mm 太粗）|
| 03a | **部件分割（前置）** | **IN PROGRESS（提前）** | 试跑证明：**密度必须按部件分配 → 分割必须先于重拓扑**。按凹折痕 region-grow 分段 + 按位置归类 |
| 02b | MODEL CLEANUP（按部件重拓扑） | BLOCKED | 依赖 03a。分区目标：头/脸 高密（手工）· 手 手工 · 身+衣 ~15k quad · 头发 ~4k 大块 · 披风 ~1.5k 片 · 靴 ~2k |
| 03b | PART SEPARATION（命名拆件） | TODO | `LIA_HEAD/BODY/HAIR_*/TOP/BOTTOM/CAPE/BELT/BOOTS/ACCESSORY` |
| 04 | UV / NORMAL | TODO | |
| 05 | MATERIAL | TODO | |
| 06 | SKELETON | **DONE**（V3 管线版） | 23 骨 / 22 变形骨 · 关节高度取自 V0 实测地标 · 无 Rigify 控制层 · 手指骨待高精度素材 |
| 07 | WEIGHT | **DONE**（V3 管线版） | 自动权重 → 剥离 → ≤4 影响 → 归一化 → 2 轮平滑 · `unassigned=0` `over_max=0` |
| 08 | DEFORMATION QA | **DONE · 发现阻塞缺陷** | 12 姿势 × 3 视角 + 顶点级诊断。**裙摆/袖侧布片与手臂几何粘连 → 抬臂拉成三角翼**（`LIA_V3_RIG.md §5`） |
| 09 | BASIC ANIMATION | **PARTIAL** | authored Idle 呼吸循环 5 s @ 24 fps 已出 · Walk / Turn / Talk 未做 |
| 10 | GODOT | **DONE** | `lia_v3.glb`（skin 1 / joints 23 / anim 1 实测）· `LiaCharacterTest.tscn` · 五视角审核图 |
| 11 | MISTVALE | TODO | 依赖部件级蒙皮修复 |
| 12 | SELF ITERATION | 持续 | |

> **V3 = 管线验证版**（用户决定：先简单绑定跑起来，高精度素材后期再加）。
> 绑定基底是 **QuadriFlow 自动重拓扑产物**，不是 499 k 原模——因此脸/手/发是被抹平的，
> 属高精度素材阶段重做。V3 的价值在于**打通 `FBX → 骨架 → 蒙皮 → 动画 → GLB → Godot` 全链路**
> 并沉淀一套可复用工具。交付与缺陷清单见 **`docs/characters/LIA_V3_RIG.md`**。

> **顺序修订（2026-09-29）**：原定 `02 → 03`，实测改为 **`03a 分割 → 02b 按部件重拓扑 → 03b 拆件`**。
> 证据：`02_working/LIA_V2_QF_REVIEW.png`（8 格对比表，含四边面线框）。
> **V3 进一步证实该修订**：整体一次重拓扑让布片与手臂几何融合，
> 权重阶段**无法**把它们分开（欧氏 / 测地 Voronoi / 凹折痕区域分割三种方法均失败，全部留档），
> 抬臂时裙摆被拉成三角翼。**部件分割必须先于重拓扑这一结论现已闭环。**

### C-LIA · V0 审计要点（详见 `LIA_V0_AUDIT.md`）

- 源资产 `Lia v-.fbx`（md5 `1f2b6e93…`）**只读留档**，永不覆盖。`Mesh_0` 单对象 · 249,786 verts / **499,748 tris（全三角）**。
- **无 UV · 无材质（0 槽）· 无骨骼 · 无顶点组 · 无权重 · 无形态键**；全身+发+服饰+靴融合为**1 个连通壳**。
- 实测地标：脚底 0 · 下巴 0.912 · 眼 0.971 · 颅顶 1.048 · 马尾尖 1.1223。**头身比 7.7（正常），腿略短，手臂短约 24%。**
- 分区对称性：躯干/骨盆/手/脚本体对称（p50 1–3 mm）→ **可镜像刷权重**；发/披风/腰包/流苏为刻意不对称 → **严禁整体 Symmetrize**。
- 设计方向成立（高马尾 · 左肩长飘带/翼 · 高领菱形饰 · 不对称侧摆裙 · 厚系带靴），保留。

### C-LIA · 决策已定（2026-09-29）

| # | 决策点 | 结论 |
| --- | --- | --- |
| D-01 | 身高锁定 | ✅ **1.580 m**（×1.5076），已应用于 `02_working/LIA_v1_base.blend`（围盒 size `0.942 × 0.516 × 1.692`） |
| D-02 | 披风"翼" | ✅ **保留**，重做为有厚度、可绑骨 `cape_*` 骨链的长披风 |
| D-03 | 重拓扑方式 | ✅ **B 自动重拓扑 + 手工修**：本地 QuadriFlow（Blender 内置 · GPL · 可复现）出四边面基底 → 手工修肩/脸/手 |

> QuadriFlow 必须 **关闭 `use_mesh_symmetry`**：头发与披风刻意不对称，开对称会毁掉两侧。

**新增资产登记（本线专用，不占 C2B 编号）**：`LIA-01` 干净基础网格 · `LIA-02` 部件拆分 · `LIA-03` UV · `LIA-04` PBR 材质 · `LIA-05` 骨架 · `LIA-06` 权重 · `LIA-07` 变形测试 · `LIA-08..15` 基础动作 · `LIA-16` Godot 测试场 · `LIA-17` Mistvale 实机

**并行约束**：不改 combat / level art / audio / ui / narrative；提交只含本线文件；**禁止 `git add -A`**。

---

## C-PH · 外部占位角色线（PLACEHOLDER CHARACTERS · 2026-09-29 开工）

独立于 C-LIA 的一条线。起因：用户决定**"去网上找几个可用的素材来替代，人形和动作"**，
不再等 Lia 的高精度重拓扑，先让角色系统真正跑起来。
**管线文档**：`docs/characters/THIRD_PARTY_CHARACTER_ASSETS.md`。素材登记：`third_party/README.md`。

**方向修正（2026-09-29 二轮）**：不再做"21 个低模的万能动作库"，改为
**CAST → STORY → SCENE → ACTION**。这批低模是 **REHEARSAL ACTORS**（排练演员），
可以丑，但**不许改变角色设计**；真正的问题是"它能不能把写好的剧情演出来"。
**谁演谁 / 数据层 / 动作缺口 → `docs/characters/DEMO_CAST.md`（本条线现行权威）。**

### C-PH · 状态

| 项 | 状态 | 备注 |
| --- | --- | --- |
| 素材调研 + 许可核查 | **DONE** | 只收 CC0；Khronos CesiumMan 为 CC-BY 4.0（**需署名**） |
| Quaternius Universal Animation Library | **DONE** | 46 剪辑 / 53 骨 / Godot 原生 GLB / CC0 |
| Quaternius Ultimate Modular Women · Characters | **DONE** | 21 个角色 FBX（含 Humanoid Rig 版）/ CC0 |
| 重定向管线 `retarget_humanoid.py` | **DONE · 已自检** | 世界增量旋转 · 名字归一化映射 · `A_TPose` 全骨增量 = 0° 证明基准对齐 |
| **rig 归一化：腿链重挂骨盆** | **DONE** | 女包 51 骨把腿挂在根骨上（男包 62 骨挂骨盆）→ 坐/蹲/跪全错。修后重烘 21/21，`head drift 0.000000 m` |
| 占位角色 GLB（**21 个 × 37 剪辑**） | **DONE** | `assets_source/characters/placeholders/` · **身高 1.7000 m 实测（21/21）** |
| 清单式烘焙 `bake_placeholders.sh` + 两张表 | **DONE** | `placeholders.tsv` 21 角色 / `clips_standard.txt` 37 剪辑（数据源，不手敲路径） |
| 尺寸校验器 `glb_extents.py` | **DONE** | 不靠引擎直接解析 GLB —— 引擎的 `get_aabb()` 是 bind-space，会低报身高 |
| **动画通道探针 `glb_anim_probe.py`** | **DONE** | 逐 clip / 逐骨 / 逐轴看位移；**"坐姿不对"最终是它 + 骨骼探针定位的** |
| Godot 检验台 `CharacterAssetTest.tscn` | **DONE** | 通用 + `--report` / `--capture` / `--plan` / `--cast-*` / **`--bone-probe`** |
| **骨骼世界坐标探针 `--bone-probe`** | **DONE** | 回答每个动作都要问的那句：「**脚到底踩在地上了吗**」 |
| 批量出图 `--plan` + `render_review_sheet.sh` | **DONE** | 单进程出全部视图（逐视点启 Godot 要 9 min → 现在 ~1 min） |
| 全员证件照（21 个一格） | **DONE** | `_review/CAST_all.png` · 2520×1440 · `render_cast_sheet.sh` |
| **CAST AUDIT（TASK A）** | **DONE** | 21/21 与用户清单逐字一致，零差异、无需造名 |
| **角色占位映射 + A/B 裁定图（TASK B）** | **DONE** | `_review/CAST_ROLES_AB.png`（12 格）→ 见 `DEMO_CAST.md` §2 |
| **DEMO_CAST 清单（TASK C）** | **DONE** | `godot/resources/cast/demo_cast.json` · 10 角色 / 2 骨架档 / 11 动作档 |
| 清单校验 ×2 | **DONE** | `tools/character/validate_cast.py`（对烘焙）+ `godot/tools/cast_check.gd`（对引擎） |
| **TASK D 统一骨架** | **DONE** | 含上面的缺陷修复 |
| TASK E 基础动作 | 部分 | 库覆盖 16 条；**缺 Look / Point / Turn / Start / Stop，Carry/Stand 仅部分** |
| TASK F 角色特化动作 | TODO | 43 条 action id 已登记（vell 8 / oren 7 / lia 6 / taim 6 / mira 5 / …） |
| 接入 Mistvale / 玩家控制（TASK G） | TODO | 需要 COMBAT 侧的移动与动画状态机对接 |
| Narrative Walkthrough 出片（TASK H–I） | TODO | 目标 `mistvale_cast_vertical_slice.mp4` |

### C-PH · 关键结论

- **动画与美术风格无关** → 这 46 条剪辑是**长期资产**：将来 Lia 高精度本体做好，
  用同一个脚本重定向过去即可，不需要重做动画。这是本条线最大的实际价值。
- **两套 rig 的 rest 完全对齐**（A_TPose 增量恒为 0°），所以重定向数学可信；
  偏差只出现在源动画**刻意保持**的姿态上（人偶恒握拳 → 手指默认排除）。
- 三件事让"21 个角色同一套动画"成立：**名字归一化 + 体位配对**（不靠固定字典）、
  **髋高比例缩放**、**身高归一**。三者的失败方式都是"不报错的错"。
- 五个**静默失败**已在工具里封堵，写进文档以免重犯：
  ① Quaternius FBX 材质 `Alpha=0` → Godot 里全透明、不报错；
  ② 固定骨骼字典在两个包之间只映射 20/62 骨 → 手臂永不动的角色、不报错；
  ③ glTF 导出会把源库动作一起导出 → 45 条死 clip 混在文件里；
  ④ **缩放父子都选 → k 乘两次 → 身高 = h0·k²**，而元数据照样记 `1.7`（请求值当实测值）；
  ⑤ **`--clips all` 撞 `__src__` 前缀 → 烘 0 条 clip**。
- **第六个（本轮）：同一条 clip、同一条管线，两个包的结果不同。**
  女包把腿链挂在**根骨**上、男包挂在**骨盆**上（两个包的 rig 不是同一个）。重定向只写旋转，
  于是女角色坐下时骨盆下沉、腿**冻在原位**——《坐在看不见的椅子上》。修法是导入后把腿链
  归一化到骨盆；`--bone-probe` 量出的前后对照与男 rig 独立收敛到同一组数。
  **教训：源资产"看起来一样"不等于骨架一样；换模前先量骨架。**
- **脚本里给 Godot 传相对路径 = 静默失败**：`FileAccess` 以**工程根**（`godot/`）为基准，
  不是 shell CWD。清单读成空 → `quit(1)`，而报错走 stderr 被管道里的 `grep` 吞掉，
  只剩一句 "FAILED"。**脚本必须绝对化路径，并且失败时不许吞掉原因。**
- **clip 名以 Godot 报告为准，不猜剥离规则**：烘焙元数据记 `Idle_Loop`，运行时是 `Idle`
  （Godot 导入剥掉 `_loop`/`-loop`）。校验器优先读一份 `--report`，并注明来源是
  `authoritative` 还是 `inferred`。
- **纪律**：元数据分开记 `target_height_requested` 与**实测** `target_height_m`；
  变换之后**必须重新测量**（`rescale verify ... drift`），不信任 `transform_apply` 返回 OK。
- 身高统一是**刻意的**：一台摄像机 rig、一个落地偏移、一套状态机吃下全部占位角色。

### ⚠️ 美术方向

占位角色是 **generic low-poly**，违反本仓 `禁 generic low-poly / mobile toy`。
**仅作管线/动画/系统联调使用，不得作为发行外观。**
Lia 正式外观的现实路径（见文档 §2）：VRoid Studio（免费·本地·动漫风）/ Mixamo（需登录）/
或回到 C-LIA 自己的高精度重拓扑。

**并行约束**：本线只新建自己的目录（`third_party/`、`assets_source/characters/placeholders/`、
`godot/assets/characters/placeholders/`）；**未改动 C-LIA 任何文件**；**禁止 `git add -A`**。

---

## D · NARRATIVE & WORLD

世界观 / 主线 / 角色 / 区域叙事 / 文案体系。文档在 `docs/narrative/`。
**定位：Sandbox 证明"怎么玩"，NARRATIVE 决定"为什么值得继续玩"。**
本线不做手感、不写战斗代码、不建模。**实现类的 Fate/Soul Echo/WorldState 仍为 FROZEN**（见 `DESIGN_BACKLOG.md`），本线只做设计。

| 任务 | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- |
| 既有叙事设定审计 + 命名裁决 | P1 | DONE | 结论写入 `narrative/WORLD_BIBLE.md` §0；裁决：雾谷 / 雾栖镇 / 雾谷东林·青竹林 / 遗迹哨兵 / 信标+观察者 |
| `WORLD_BIBLE.md` V0.1 | P1 | DONE | 魔法=理解性质；三种剑=信息/位置/距离；最大悬念=古代文明"不再需要留在这里" |
| `MISTVALE.md` V0.1 | P1 | DONE | 空间 0–9 段各设叙事功能；三股力量（公会/商团/钟塔）+ 治安官；三条独特文化 |
| `CHARACTERS.md` V0.1 | P1 | DONE | 7 位 Act I 人物 + 1 影子角色；每人回答"玩家不在时在做什么"；含学习来源表 |
| `MAIN_STORY.md` V0.1 | P1 | DONE | Premise/Theme/Prologue/Act I 节点/FA-01 六种参与状态/第一段可玩体验 50–70 分钟表；PASS 02 已细化并指向 `ACT1_BEATS.md` |
| `STYLE_GUIDE.md` V0.1 | P1 | DONE | 对白长度、禁用 AI 套话表、命名规则、技能与任务文案标准、自查清单 |
| Narrative Request → ART/AUDIO/MAIN | P1 | DONE | 已编号并入各线：`NAR-ART-01/02/03/04`、`NAR-AUDIO-01/02`、`NAR-MAIN-01/02`。权威清单见 `narrative/ACT1_BEATS.md` §7 |
| `ACT1_BEATS.md`（PASS 02） | P1 | DONE | 七个问题答案 / Prologue beat sheet P0–P6 / Arrival A1–A7 / Act I 脊椎 Q1–Q7 / ECHO-01·02 规格 / FA-01 完整设计 / 请求清单 |
| `RELATIONSHIPS.md`（PASS 02） | P1 | DONE | 关系矩阵（公开关系/真实态度/过去事件/潜在冲突）+ 鲁斯克 + 泰姆 + 作息表 + FA-01 后关系变化 |
| PASS 02 修正落地 | P1 | DONE | 莉娅作息（可被错过）/ Soul Echo #2 改为 NPC 自我否认 / 魔法升格为世界底层规则 + 日常使用 3 例 |
| 连续性规则 + 文档债 | P1 | DONE | 写入 `WORLD_BIBLE.md` §9：代码为准；prototype 不写 Lore；`COMBAT_DESIGN.md` 待 MAIN 回写 |
| **Review：Prologue + Act I Early Game** | P0 | DONE | PASS 02 Review 已通过，三条裁决落地：A 奥伦重心移到"记录≠事实" / B 战后 3–6 秒安静 + 人的声音 / C 能力线不规定顺序 |
| **`NARRATIVE_VERTICAL_SLICE_N01.md`（PASS 03）** | P0 | DONE | **可实施规格**：Scene Spec P00–P06 + A1–A7 / 8 个 Dialogue Scene / Readable R-01 货单 + R-02 ECHO-01（三方案比较，采纳 EC）/ 16 条环境对白 / Cluster 五状态 / VO 表 11 句 / 分钟级 Playthrough / 空间·音频·MAIN 请求 V0.2 |
| **`NARRATIVE_STATE_V01.md`（PASS 03）** | P0 | DONE | 最小状态模型：flag 表 / **INFORMATION GRAPH F1–F10** / HARD vs SOFT / MISS MATRIX / 最小存档结构 / 给 MAIN 的接入优先级 5 步 |
| `CHARACTERS.md` §13 SPEECH PROFILE | P1 | DONE | 8 人说话方式表（句长/用词/直接度/解释欲/停顿/礼貌/注意力）+ 三条跨角色纪律 |
| `STYLE_GUIDE.md` §12 PLAYER VOICE V0.1 | P1 | DONE | 低频发声；禁三个同义句选项；沉默/点头/看向是合法选项 |
| **`NAR-MAIN-01..06` 交 MAIN 实施** | P0 | TODO | `Readable`、最小 flag、`took_cart_blade`、N01 背景信号三件套、**南岸"路还在但没意义"不用空气墙**。详见 slice 文档 §12.3 |
| **`NAR-SPATIAL-01..06` 交 ART（地编）** | P1 | TODO | 事故点声学开放 / Reveal 视角 / 进镇第一帧的魔法生活痕迹 / 奥伦后院不在主街正面 / 渡口看得到不好走 / 南岸不可见墙。见 `MISTVALE.md` §10 |
| **`NAR-AUDIO-01..07` V0.2 交 AUDIO** | P1 | TODO | 第五钟独立音型 / 遗迹低频 / **泰姆远处声音（有距离感的空间声）** / 醒来点来源不明低频 / 镇子生活层 / 冷屋子声 / 后院只有劈柴 |
| `MICRO_NARRATIVE_SLOTS.md`（PASS 04） | P0 | DONE | **回填 LD-01 §10/§11**：NAR-01..07 内容 + 22 槽位逐条（是什么/读到什么/形态/可错过）+ 4 个 Readable（R-03..R-06）+ `NAR-ART-05..08` / `NAR-AUDIO-08..09`。**地编保位置，文案填内容** |
| `ACT1_QUESTS.md`（PASS 04） | P0 | DONE | 八条设计规则（**无 XP/无等级**）/ MQ-C 五状态机 / `took_cart_blade` 裂缝 / Q1–Q7 展开 / 五条支线（S-01..S-05）/ 模板黑名单 / 奖励表 / 11 个 flag 增量 / MAIN 实施顺序 6 步 |
| `DIALOGUE_PASS_02.md`（PASS 04） | P1 | DONE | 第二层 6 场（奥伦木桩/米拉/莉娅/薇尔/格兰/阿诺）+ **三条能力入口（不规定顺序）** + 环境对白 Pass 02（18 条）+ VO 增量 11 句 + 自查 8 项 |
| `VO_PIPELINE.md`（Narrative 侧接口契约） | P1 | DONE | 链路 `Scene → VO Spec → TTS Router → Raw → Post → QA → Manifest → Dialogue Player` 的**划界表**；补两环：**Voice Identity 在 Router 之前** / **Manifest 必带 `text_hash` 做改词检测**；字段标准 + 文本清洗规则 + 9 个 `voice_id` 画像 + **VO MASTER LIST 22 句（`VO-001..022`）** + Player 体验需求 |
| **`VO-001..006`（泰姆）先做** | P1 | TODO | **第一批只验这 6 句**：空间声 + 可中断 + "战后把世界接回来"的节奏。成立才扩到 22 句。交 AUDIO（后端与后期）+ MAIN（Player） |
| Dialogue Pass | P2 | DONE | 五条冻结门已过（`MAIN_STORY.md` §13）；PASS 02 只覆盖 Act I 前半第二层，**Act I 后半对白仍冻结** |
| `TIMELINE.md` / `FACTIONS.md` / `TERMINOLOGY.md` / `NARRATIVE_BACKLOG.md` | P3 | TODO | 第一轮不建，按需再开（`QUESTS.md` 已由 `ACT1_QUESTS.md` 承担） |
| **`ACT1_QUESTS.md` V0.2（PASS 05）** | P0 | DONE | **第一天**：§10 三条主线程（A 立足 / B 商队事故 / C 人）+ 交叉表（**B 不是任务**）/ §11 **进镇→傍晚→第一夜→第二天早晨**节奏 + 第一夜只有声音 / §12 第二天三个变化 / §13 四条新支线 **S-06..S-09** / §14 **FA-01 信号网络 8 个 × 6 渠道** / §15 四条 NON-FAILURE FAILURE / §16 任务 UI 措辞 / §17 **Readables V0.2（R-07..R-11 全文）** / §18 Paper Playtest V0.2 / §19 flag 增量 |
| **`DIALOGUE_PASS_02.md` V0.2（PASS 05）** | P0 | DONE | 新增 **8 场（D15–D22）**：渡口干活 / 炉子 / 少了一件 / 奥伦搬柴 / 一封信 / 第一夜 / 第二天早晨 / 北门没开 + **第一次能力习得三条入口（E1 藏锋 / E2 回风 / E3 性质）** + 18 条 bark + **VO-023..034** + 关系纹理映射 |
| **`INFORMATION_GRAPH.md`（PASS 05）** | P1 | DONE | **玩家知识 K001–K017**（来源 / H·S / 能错过吗 / 还有谁知道 / 以后咬回哪）+ **NPC 信息差表**（谁不知道什么、谁自以为知道但错）+ **关系纹理**（不是好感度）+ 三条对白纪律 |
| `CHARACTERS.md` §14 DAILY PRESENCE | P1 | DONE | 9 位角色的**在哪 / 何时 / 做什么 / 为什么在那 / 玩家不在时**；**奥伦三层认识**（Layer1 普通 → Layer2 动作熟练 → Layer3 木桩切痕，**没人告诉他**） |
| `MISTVALE.md` §11–§14 | P1 | DONE | **本地文化六问**（打招呼 / 外来的 / 四下钟 / 怎么看公会 / 怎么看遗迹 / 失踪不写死）+ **空间叙事层**（9 区密度 3→0 + **四处必须安静**）+ `NAR-AUDIO-10..17` + UI TEXT SPEC V0.1 |
| **`NAR-AUDIO-10..17` V0.2 交 AUDIO** | P1 | TODO | market day / **market close** / **first night**（钟·河·酒馆·北山极低频）/ north gate alert / bell schedule / **ferry ambience** / **forge ambience（风箱要给出节奏，D16 依赖它）** / oren backyard |

未决事项：`COMBAT_DESIGN.md` 与 `moveset_library.gd` 不同步（折柳/惊鸿/长风三段已实现但文档写"未实现"），请 MAIN 回写；Narrative 现按**已实现**为准。
**Combat 同步（PASS 03 只读）**：`white_rose`（白蔷庭）当前为 **prototype** → 本轮**不写它的 Lore**（continuity rule）；三系法术已实现 `火矢/焚环`、`寒流/凝霜`、`风压/风步`，与"火=转化 / 霜=停滞 / 风=动量"的底层规则一致，已用于 §8 的生活痕迹设计。聚合斩来历仍不解释。

**PASS 04 顺序调整说明**：原计划先等 MAIN Review N01 再做 Act I Quest + Dialogue 02，本轮**提前做**，原因是 ART 的 `LD-01` 已把 `NAR-01..07` + 22 个槽位的位置留好并写明「文案填内容，地编保位置」——**槽位回填是时间敏感的，等地编铺完再给就要返工**。任务与对白因此全部**锚定 LD-01 的真实坐标**（Z-01..Z-12 / C-01..C-08 / V1..V9）。

**PASS 05 说明（第一天 / 第一夜 / 第二天早晨）**：本轮把"世界设定扩张"停掉，改为向下深化——玩家今晚睡哪、明天为什么还留在这。**THREAD B（商队事故）明确不是任务**：没有条目、没有日志、没有完成态，全靠别人随口的话拼起来。`day_index` **只能是 0 或 1**（睡一次），**不做日历、不做第三天**。

**PASS 06 门**：MAIN Review 通过 `ACT1_QUESTS.md` V0.2 + `DIALOGUE_PASS_02.md` V0.2 的可实施性 → 才进 Act I 后半与 FA-01 本体。**仍不进 Act II。**
**新增硬约束（交 MAIN / AUDIO / UI）**：
- **第一夜不弹任何"休息"UI、不放过场、不给"新的一天"大字** —— 睡觉只是屏幕暗下去，然后声音先回来（`ACT1_QUESTS.md` §11.1）。
- **`NAR-AUDIO-16` 风箱必须给出节奏信息**，否则 D16「跟着我的手」没法玩。
- **`[沉默]` 必须是真实可点的选项，视觉上不比说话的选项弱**（UI TEXT SPEC）。
**顺序硬约束**：S-05（薇尔·被划掉的那一行）**必须先于** ECHO-01 可被遇到，否则 ECHO-01 效果减半（见 `ACT1_QUESTS.md` §4.6）。

---

## 冲突优先级

1. 当前用户指令
2. MAIN PROJECT
3. ART / AUDIO 实现细节
