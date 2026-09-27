# SFX SELECTION — Suno Raw Captures（2026-09-27）

状态标记：`KEEP` / `MAYBE` / `REJECT` 均为**波形分析初判（PROVISIONAL）**，
最终以实机试听为准。裁切起点参考 `raw/CAPTURE_MANIFEST.md`（内容起点 0.95–1.35s）。

| SOURCE | BEST SECTION (s) | ROLE | STATUS | NOTES |
| --- | --- | --- | --- | --- |
| suno_cap_air_suck_A | 1.35–1.80 | world_suck | KEEP | 三连吸气脉冲 1.38/1.70/2.06，取最干净一个；峰 -6 dB，尾净 |
| suno_cap_air_suck_B | 2.35–2.85 | world_suck 备选 | MAYBE | 2.42/-4 最响但偏"风声"，不如 A 像真空 |
| suno_cap_draw_slash_A | 1.10–1.45（draw）/ 1.52–1.90（slash） | instant_draw + reality_cut | KEEP | 1.14/-14 拔刀，1.56 后是斜斩；一段素材两个 cue |
| suno_cap_draw_slash_B | 1.08–1.45 | draw 备选 / atom air_fast_02 | KEEP | 与 A 同构，留作 variation |
| suno_cap_sheath_click_A | 2.66–2.80（小 click）/ 4.62–4.86（大 click） | sheath_lock + final_click | KEEP | 4.66/-7 是全素材最硬 click；2.70/-13 做 prepare |
| suno_cap_sheath_click_B | 2.66–2.80 | metal_sharp atom | KEEP | 与 A 同构，variation 用 |
| suno_cap_sword_handling_A | 1.05–1.50（腕旋）/ 4.30–5.20（慢回鞘） | spin + slow_sheathe + sheath_move | KEEP | 慢回鞘段 3.80–6.05 内 4.66 附近有 click，避开 |
| suno_cap_sword_handling_B | 7.42–7.90 | cloth atom | MAYBE | 与 A 重复度高，仅当 atom 源 |
| suno_cap_glass_shatter_A | 1.05–1.45（首裂）/ 7.35–8.20（大爆） | glass_detach + collapse 备选 | KEEP | 1.10/-11 首裂干净；7.38/-10 次强爆 |
| suno_cap_glass_shatter_B | 11.40–12.25 | reality_collapse | KEEP | 11.46/-6 全素材最强单次爆发；16.5s 里只取这一下 |
| suno_cap_glass_stress_A | 1.10–1.80 | glass_stress | KEEP | 渐紧吱声，1.6 附近有 tick 可切 atom |
| suno_cap_glass_stress_B | 4.95–5.65 | glass_stress 备选 / crack atom | MAYBE | 5.04/-6 是开裂不是应力，音质好但性格偏爆 |
| suno_cap_space_tear_A | 2.55–3.20（void 低身）/ 4.00–4.60（air_low atom） | void_open | KEEP | 8.4s 里最有价值是 3s 后的低频持续，宽而不吵 |
| suno_cap_space_tear_B | 2.90–3.55 | void_open 备选 | MAYBE | 与 A 高度相似，留作 A/B 试听对比 |
| suno_cap_spatial_compress_A | 1.55–2.40（上升段） | reverse_compression | KEEP | 1.84/-7 主瞬态，上升"被吸走"感明确；段尾收在 pressure 之前 |
| suno_cap_spatial_compress_B | 4.45–5.30 | reverse 备选 / wind_pressure atom | MAYBE | 双脉冲结构不如 A 连贯 |
| suno_cap_reality_restore_A | 1.76–2.10（snap）/ 2.90–3.25（settle） | reality_restore | KEEP | 1.80/-7 是 snap-back 主瞬态；settle 段可切 atom |
| suno_cap_reality_restore_B | 1.75–2.30 | restore 备选 | MAYBE | 与 A 同构略糊，对比试听用 |

## REJECT 判据备忘

整段 REJECT 的来源目前没有——每条至少有一个可用核心；但**只用核心段**，
全部整段原始输出（含队列连播尾巴）不直接进游戏。

## 待实机确认（AWAITING AUDITION）

1. reality_cut 用 draw_slash 斩段 vs space_tear 攻击段，哪个更"裂开"而非"挥棒"
2. void_open A vs B 的低频深度
3. collapse 用 glass_shatter_B@11.46 是否比 A@7.38 更有"结果感"
4. sheath_lock 的 prepare/final 亮度差是否足够形成 signature 对
