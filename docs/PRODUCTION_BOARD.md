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
| Movement（WASD/sprint/jump/dodge） | P0 | REVIEW | TECH VERIFIED；手感未验收 |
| Running camera feedback | P0 | REVIEW | 三档预设 + F8 面板；可读性未验收 |
| Sword combo / heavy / block | P0 | REVIEW | TECH VERIFIED；视觉为 TempSwordVisual 三方块 |
| Perfect Guard | P0 | REVIEW | 窗口 0.18s；音效未接入 |
| Magic / Ability Wheel | P0 | REVIEW | 火冰风已验证；轮盘是技术占位 |
| Shatter | P0 | REVIEW | Area3D + shard + 85ms hitstop；音画未验收 |
| Iaido 7.2s 张力序列 | P0 | REVIEW | 14 phase 全实现；音频为占位合成 |
| Enemy telegraph / AI | P1 | TODO | 现为 technical_dummy，非 Lesser Ruin Sentinel |
| Iaido 5–8s Cinematic Tension Pass | P0 | REVIEW | 已到 7.2s，超出目标区间上限；待视听验收后再谈压缩 |
| Git：提交本轮未落地改动 | P0 | DONE | 已由 MAIN 提交并推送：`c485aeb` + `8c71561`（7.2s Iaido 全序列）。远端 `godot-combat-mvp` = `8c71561` |

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
| 元素 SFX（火/冰/风/shatter） | P1 | TODO | `COMBAT_SFX_BRIEF.md` Priority B |
| BGM | P2 | DONE | 4 首 Suno 已接入（Web 原型期） |

---

## C · ART & MODELING

ChatGPT Web → Blender Python → Blender MCP → GLB → Godot

| 资产 | ID | 优先级 | 状态 | 备注 |
| --- | --- | --- | --- | --- |
| First Person Sword | C2B-01 | P0 | SPEC READY | brief 已成文；Blender 脚本未生成 |
| FP Hand / Forearm | C2B-02 | P0 | SPEC READY | brief 本次补写 |
| Lesser Ruin Sentinel | C2B-03 | P0 | SPEC READY | brief 本次补写 |
| Magic Catalyst | C2B-04 | P1 | SPEC READY | brief 本次补写 |
| World Beacon | C2B-05 | P2 | TODO | Combat MVP 之后 |
| Adventurer Guild | C2B-06 | P2 | TODO | 同上 |
| Mistvale Stair / Terrace Kit | C2B-07 | P2 | TODO | 同上 |
| Town Props | C2B-08 | P2 | TODO | 同上 |
| Oren / Mira 人物 | — | P2 | TODO | Tripo / Hunyuan3D 候选，Rig 不阻塞 |

阻塞原因：Blender MCP 未连接本会话；ChatGPT Web 需用户登录态。Producer 已产出可直接粘贴的 prompt 包（`docs/asset_briefs/C2B-01-CHATGPT-PROMPT.md`），人工或连接后即可执行。

---

## 冲突优先级

1. 当前用户指令
2. MAIN PROJECT
3. ART / AUDIO 实现细节
