# SEKAI · VO PIPELINE · Narrative 侧接口契约 V0.1

> 用户给出的链路：
> `Narrative Scene → VO Spec → TTS Router（AivisSpeech / Local A / Local B·future API）→ Raw Voice → Auto Post-process → Manual QA / Regenerate → VO Manifest → Godot Dialogue Player`
>
> 本文件**只定义 Narrative 拥有的那一段**（第一、二步）以及**它与后段之间的契约**。
> TTS Router / 后端选型 / 后期链 / QA 属于 **AUDIO**；Dialogue Player 的实现属于 **MAIN**。
> Narrative 不做 TTS、不录、不调参、不写播放器。

---

## §0 谁负责哪一段

| 环节 | 负责 | Narrative 交出什么 |
| --- | --- | --- |
| Narrative Scene | **NARRATIVE** | 场景 + 台词 + 情绪意图 |
| **VO Spec** | **NARRATIVE** | **本文件 §2 字段标准 + §5 清单** |
| Voice Identity | **NARRATIVE 定方向，AUDIO 定参数** | §4 音色画像（只写"像什么 / 不像什么"） |
| TTS Router / 后端 | **AUDIO** | — |
| Raw Voice / Post / QA | **AUDIO** | — |
| VO Manifest | **AUDIO 产出，MAIN 消费** | §6 字段契约（Narrative 只提需求） |
| Godot Dialogue Player | **MAIN** | §7 体验需求 |

---

## §1 我在这条链里补两环（不补会出事）

**① Voice Identity 必须在 Router 之前。**
Router 知道"用哪个引擎"，但不知道"奥伦该是什么声音"。现在缺一张**角色 → 音色**的绑定表，结果是同一句台词换个后端就换个人。见 §4。

**② Manifest 必须带 `text_hash`，否则改词不会被发现。**
SEKAI 的台词会反复改（这是常态）。如果 manifest 只有 `id → 文件`，改了词、没改 id，播放器就会播旧的那一条，而且**没人会注意到**。§6 里 `text_hash` 是硬字段：hash 不匹配 → 标记 `STALE` → 必须重生成或显式豁免。

---

## §2 VO Spec 字段标准（Narrative 交付格式）

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `line_id` | ✅ | **稳定 ID，永不变**。`VO-001` 起。改词不改 id；删句**不复用** id |
| `character` | ✅ | 大写角色名，与 `CHARACTERS.md` 一致 |
| `voice_id` | ✅ | 指向 §4 的音色绑定，不是角色名（`OREN` → `v_oren`） |
| `text_clean` | ✅ | **TTS 实际朗读的文本**。已去掉所有括号、舞台指示、引号、破折号演出。见 §3 |
| `text_display` | ✅ | 字幕显示的文本（**可以和 `text_clean` 不同**——允许字幕带省略号而 TTS 不读） |
| `emotion` | ✅ | 情绪意图（中文短语，不是英文标签） |
| `tts_hint` | ✅ | 语速 / 强度 / 音高偏移的**方向**，不给具体数值（数值归 AUDIO） |
| `volume` | ✅ | very quiet / quiet / normal / loud |
| `pace` | ✅ | slow / even / fast / uneven / clipped |
| `interruptible` | ✅ | 玩家可否打断。**决定播放器要不要给打断窗口** |
| `spatial` | — | 需要距离感 / 遮挡 / 方向的（如坡下的泰姆） |
| `context` | ✅ | 一句话：这句发生在什么之后 |
| `priority` | ✅ | **must / should / no**。`no` 的句子不进这条管线 |

---

## §3 文本清洗规则（TTS 不读什么）

| 写法 | `text_clean` 怎么处理 |
| --- | --- |
| `（停）` `（劈完这一块，才再次开口）` 等舞台指示 | **全部删除**，不属于台词 |
| `……` | 开头/结尾的省略号**不读**；句中的保留为停顿（AUDIO 用停顿时长表达，不读"点点点"） |
| `"…"` 引号 | 删除 |
| `——` 破折号 | 句中断裂读成停顿；句首的删除 |
| `**加粗**`（如"**别拿**"） | 删除标记，重音交给 `tts_hint` |
| `[沉默]` `[看向货车]` | **这不是台词，不进管线**。它是播放器的一个等待状态，见 §7 |
| 外语 / 数字 | 目前没有；出现时单独约定读法 |

**一条硬规则**：`text_clean` 里**不能有任何括号**。带括号的一律视为没洗干净。

---

## §4 Voice Identity V0.1（8 人音色方向）

> 只写"像什么 / 不像什么"。**具体模型、speaker id、pitch、speed 数值全部归 AUDIO。**
> 参考 `CHARACTERS.md` §13 SPEECH PROFILE（说话方式），这里是**声音质地**，两者互补。

| voice_id | 角色 | 声音方向 | **不要** |
| --- | --- | --- | --- |
| `v_oren` | 奥伦 | 中年男性，偏低，气声少，说话时嘴不太张开那种。**句子短，尾音收得快** | 不要"沧桑剑客"。不要低沉到像旁白。不要任何英雄感 |
| `v_mira` | 米拉 | 年轻女性，中偏高，**语速快且会突然在数字上变慢** | 不要"傲娇天才少女"。不要元气。不要播音腔 |
| `v_lia` | 莉娅 | 年轻女性，中性偏低，音量平稳，**说话时像同时在看别处** | 不要活泼导游。不要温柔治愈系 |
| `v_garran` | 格兰 | 中年男性，粗，但**不是吼**。胸腔音，干活时的呼吸在句子之间 | 不要粗暴大汉。不要喜剧化 |
| `v_brann` | 布兰 | 中年男性，偏薄，礼貌的平调，**像在念一张表** | 不要官僚反派。不要谄媚 |
| `v_vell` | 薇尔 | 女性，中年以上，音色**干**，几乎没有情绪起伏 | 不要刻薄。不要神秘。她只是不寒暄 |
| `v_rusk` | 鲁斯克 | 中年男性，疲惫，句尾常常掉下去 | 不要威严长者。不要阴谋感 |
| `v_taim` | 泰姆 | 青年男性，**疼的时候句子会断**，气短 | 不要英雄式惨叫。不要"勇者救我"的腔 |
| `v_arn` | 阿诺 | 青年男性，音量小，经常像在自言自语 | 不要怯懦到卡通化 |

**跨角色纪律**：同一 `voice_id` 在任何后端上都必须听起来是**同一个人**。换后端时宁可整体降级，也不要"奥伦在 AivisSpeech 是一个声音、在 Local A 是另一个声音"。

---

## §5 VO MASTER LIST V0.1（22 句）

> 来源：`NARRATIVE_VERTICAL_SLICE_N01.md` §9（V1–V11）+ `DIALOGUE_PASS_02.md` §9（D12–D22）。
> **这是第一批也是唯一一批**：Act I 前半只配这 22 句。其余全部不配。

### 5.1 Prologue · 泰姆（远处 · 需要空间感）

| line_id | CHARACTER | text_clean | emotion | vol | pace | interrupt | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `VO-001` | TAIM | 喂。 | pain / 不敢喊太大声 | very quiet | slow | yes | 战斗后静默结束，隔着一个坡 |
| `VO-002` | TAIM | 喂，这边。 | 稍微放开一点 | quiet | slow | yes | **必须与 VO-001 同一声源** |
| `VO-003` | TAIM | 你别过来抬我。先告诉我，坡上那个东西还在动吗。 | fear + practical | quiet | uneven | yes | 第一次请求 |
| `VO-004` | TAIM | ……好。 | exhale / relief | breathy | — | no | 得知威胁结束 |
| `VO-005` | TAIM | 车上的货不是我的。是公会的。 | serious | quiet | slow | no | 第一次托付 |
| `VO-006` | TAIM | ……别往北。 | flat / 刻意不说得像预警 | low | slow | no | **同声源**，一致性 > 演出 |

### 5.2 进镇 · 格兰 / 布兰 / 奥伦

| line_id | CHARACTER | text_clean | emotion | vol | pace | interrupt |
| --- | --- | --- | --- | --- | --- | --- |
| `VO-007` | GARRAN | 别站在门口挡光。 | working / 不抬头 | normal | normal | yes |
| `VO-008` | GARRAN | ……你手上有茧。干什么活的。 | 评估 | normal | slow | no |
| `VO-009` | BRANN | 我不是不让你留。是没有这个手续。 | procedural | normal | even | yes |
| `VO-010` | OREN | 别踩柴。 | flat / 不打算继续对话 | low | clipped | yes |

### 5.3 ECHO-01

| line_id | CHARACTER | text_clean | emotion | vol | pace | interrupt | 备注 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `VO-011` | VELL | ……这行没署名。不对。 | pedantic irritation | quiet | even | no | **全 Slice 最重要的一句**。它必须听起来像"一个登记员发现了一个错"，**不是**"她发现了惊天秘密" |

### 5.4 Act I 第二层

| line_id | CHARACTER | text_clean | emotion | vol | pace | interrupt |
| --- | --- | --- | --- | --- | --- | --- |
| `VO-012` | OREN | 那木头硬。砍不动就别砍。 | flat / working | quiet | slow | yes |
| `VO-013` | OREN | 你刚才没砍。 | flat / 第一次注意到 | quiet | slow | no |
| `VO-014` | MIRA | 十四天前。不，十三。 | correcting herself | normal | fast→short | yes |
| `VO-015` | MIRA | 我不懂魔法。 | 纠正说法，不是反驳 | normal | fast | yes |
| `VO-016` | LIA | 你要是天亮才来，我已经走了。 | matter-of-fact | normal | even | no |
| `VO-017` | LIA | 你站得太死了。 | 干活中说 | normal | even | yes |
| `VO-018` | VELL | ……这不是我划的。 | 被打断的确认 | quiet | slow | no |
| `VO-019` | VELL | 这行没署名。 | flat / 不舒服 | quiet | even | no |
| `VO-020` | GARRAN | 你非自己干，你老婆也非自己干。 | 骂，但不是恶意 | loud | fast | no |
| `VO-021` | ARN | 我不是说不能拿。我是说别拿。 | 自己也说不清 | quiet | 断 | yes |
| `VO-022` | ARN | 我哥没走。他在北坡。 | 不是回答，是自言 | quiet | slow | no |

**注**：`VO-011` 与 `VO-019` 是同一句"这行没署名"的两次出现。**必须用同一次生成的音频**（同一 `voice_id`、同一参数、不同上下文只允许在播放器层做音量/空间处理）。**合成两次会让薇尔变成两个人。**

---

## §6 VO Manifest 契约（Narrative 提需求，AUDIO 定格式）

每行至少一个 line_id 对应一条记录，建议字段：

```
line_id, voice_id, backend, src_file, duration_ms,
text_hash,           # ← 硬字段：改词即失配
status,              # ok / stale / missing / waived
interruptible, spatial, loudness_lufs
```

**Narrative 的三条需求**

1. **`text_hash` 必填。** hash 与当前 `text_clean` 不符 → `stale` → 不可进包，除非显式标 `waived`（豁免必须写理由）。
2. **`status` 必须能被机器检查。** 打包时若存在 `stale` / `missing`，构建应该报警而不是静默用旧音频。
3. **`backend` 要记录。** 同一角色换后端后，需要一次整体重听（见 §4 跨角色纪律）。

---

## §7 Godot Dialogue Player · 体验需求（Narrative 只定体验）

- **可中断**：`interruptible = yes` 的行必须允许玩家在开头 ~0.4 s 后打断（走开 / 出手 / 交互）。**打断不是"跳过字幕"，是玩家真的转身走了，那句话应该被环境盖掉。**
- **沉默选项不产生音频**。`[沉默]` / `[点头]` / `[看向货车]` 是**播放器的一个等待状态**，不是一条空音频。
- **不配音的行**：环境对白、Readable、UI 目标行**只出字幕或只出文字**。不要为了"统一"给它们配一条 placeholder 音。
- **字幕与语音可以不完全一致**：允许 `text_display` 带省略号而 `text_clean` 不带。
- **空间声**：`spatial` 的行必须走世界空间（有距离与遮挡），不能走 UI 总线——泰姆那六句的关键就在于"他在坡下"。
- **禁止结算化**：说完一句**不要**弹提示、不要播放"对话完成"音、不要给奖励弹窗。

---

## §8 优先级与不做

**第一批只做 `VO-001..006`（泰姆）**。理由：它同时验证三件最贵的事——空间声、可中断、以及"战斗后把世界接回来"那一段节奏。**这六句成立，管线才值得扩到 22 句。**

**不做**

- 不配环境对白（§8 Pass 02 的 18 条）、不配四个 Readable（R-03..R-06 永远只是纸面的字）。
- 不做主角配音。PLAYER VOICE 是低频的，且当前不配音——**玩家不出声不等于没有态度**，态度靠选项与沉默表达。
- 不做多语言、不做 lip-sync、不做口型动画。
- 不做"情绪自动识别"。`emotion` 是 Narrative 手写的意图，**不要让后端自己猜**。
- 不替换 AUDIO 对后端与后期链的选型权。
