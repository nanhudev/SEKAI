# PHANTOM CHAIN / 虚链 · V0.1

独立于 Sword 与缚星链（Star-Bind）的第二战斗语言。

## 幻想

> 只要两点之间被我定义为连接，它们就必须服从这条连接。

链不是武器 mesh，是**规则生效时的可视化**。

## 热键

| Key | Weapon |
| --- | --- |
| 1 | Sword |
| 2 | **Phantom Chain / 虚链** |

缚星链仍可通过 rack / lab / `WeaponSlot.equip(CHAIN)` 装备，不占热键 2。

## 代码

```
godot/scripts/combat/phantom_chain/
  phantom_chain_controller.gd   # A1–A4, bind rule, hand, camera
  phantom_chain_renderer.gd     # MultiMesh deterministic curve
  phantom_chain_profile.gd      # numbers
  phantom_chain_vfx.gd          # hand ring / idle / bind ring / pulse
godot/vfx/phantom_chain/phantom_chain.gdshader
```

Weapon Manager 最小钩子：`WeaponSlot.PHANTOM_CHAIN` + registry row。

## Combo V0.1

| Move | Rule proved |
| --- | --- |
| A1 Sweep | Path |
| A2 Snap | Speed / direction (curve→tension) |
| A3 Bind | Connection + MAX DISTANCE + Pull |
| A4 Orbit | Space range (arcs spawn in world) |

## 证明物

- 测试：`godot/tests/phantom_chain_v01.gd`
- 成片：`phantom_chain_v01.mp4`
- 录制：`godot/tools/phantom_chain_v01_movie.gd`

## 明确不做（V0.1）

Physics rope · 常驻武器 mesh · Mana · multi-bind · swing traversal · boss bind
