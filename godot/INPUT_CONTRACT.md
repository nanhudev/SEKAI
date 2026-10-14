# SEKAI INPUT CONTRACT V0.1

All combat / movement / world agents must bind gameplay to these **semantic actions**.
Do not invent new physical keys per weapon.

```text
SEKAI INPUT CONTRACT V0.1

COMBAT
LMB = Primary Attack          → attack_primary / light_attack
RMB = Parry                   → parry / block

E = Skill 1                   → skill_1
X = Skill 2                   → skill_2
C = Skill 3                   → skill_3
V = Ultimate                  → ultimate

MOVEMENT
Shift Tap  = Dodge            → dodge (fired by InputContract on Shift Down)
Shift Hold = Dodge → Sprint   → sprint (pressed after dodge recovery while held)
Space      = Jump             → jump
Ctrl       = Crouch           → crouch  (placeholder OK if no crouch system)

WORLD
F = Interact                  → interact

UI
Tab Tap  = Backpack           → InputContract.backpack_requested
Tab Hold = Combat UI          → InputContract.combat_ui_hold_started / _ended

DEVELOPMENT QUICK SWITCH
1 = Sword                     → weapon_1 / weapon_slot_1
2 = Phantom Chain             → weapon_2 / weapon_slot_2
3 = Mirror                    → weapon_3 / weapon_slot_3

RESERVED
R = Unassigned                (draw_sword may still use R as legacy story control)
```

Owner script: `res://scripts/input/input_contract.gd` (autoload `InputContract`).

---

## Weapon Skill Mapping (real project state)

### SWORD
| Action | Binding | Function |
|--------|---------|----------|
| E / skill_1 | → `iaido` adapter | Existing Iaido / 聚合斩 |
| X / skill_2 | → `heavy_attack` | Existing Heavy / Charge (was Hold F) |
| C / skill_3 | style_skill / TBD | No dedicated sword skill yet |
| V / ultimate | `ultimate` | Existing Ultimate (无明一刻) |
| LMB | light_attack | A1→A4 combo |
| RMB | block | Existing Parry / Block |

### PHANTOM CHAIN (虚链)
| Action | Binding | Function |
|--------|---------|----------|
| LMB | light_attack | Existing light combo |
| E / X / C / V | — | No skill implementations yet (no-op) |
| RMB | block | Global parry if available |

### STAR-BIND CHAIN (缚星链 / ChainDirector — lab / rack)
| Action | Binding | Function |
|--------|---------|----------|
| LMB | light_attack | Light |
| E / skill_1 | → style_skill_1 | chain_hook (缚) |
| X / skill_2 | → heavy_attack | Heavy / 蓄势 (was Hold F) |
| C / skill_3 | → style_skill_2 | chain_lock (锁) |
| V | ultimate | TBD / none |
| RMB | block | Block |

### MIRROR
| Action | Binding | Function |
|--------|---------|----------|
| LMB | light_attack | Light / exit cut |
| E / skill_1 | was RMB place | Place Mirror |
| X / skill_2 | was Q travel | Mirror Travel |
| C / V | — | No-op |
| RMB | parry | Global parry (no longer Place) |

---

## Relocated (not deleted)

| Old | Was | Now |
|-----|-----|-----|
| Cast selected | E | Q (`cast_selected`) |
| Fire cast | Z | Z (unchanged) |
| Frost cast | R | G (`frost_cast`) — R reserved |
| Wind cast | C | B (`wind_cast`) |
| Walk pace | V | Alt (`walk`) |
| Sprint | Ctrl | Shift Hold (via InputContract) |
| Dodge | Shift | Shift Down immediate (via InputContract) |
| Interact | E | F |
| Iaido | I | E |
| Heavy / Charge | F | X |

---

## Legacy status

| Legacy | Status |
|--------|--------|
| I → Iaido | REMOVED (default). `ENABLE_LEGACY_ALIASES` can re-enable for debug. |
| F → Heavy | REMOVED from combat. F = Interact only. |
| E → Interact | MIGRATED to F. |
| E → Cast | MIGRATED to Q. |
| Q → Mirror Travel | MIGRATED to X / skill_2. |
| RMB → Mirror Place | MIGRATED to E / skill_1. |
| Ctrl → Sprint | MIGRATED to Shift Hold. Ctrl = Crouch. |
| V → Walk | MIGRATED to Alt. V = Ultimate. |
| R → Frost cast | REMOVED from R. |
| R → draw_sword | STILL USED (story / plaza). Contract keeps R reserved for new features. |
| 1 / 2 / 3 weapon switch | STILL USED — DEVELOPMENT QUICK SWITCH. |

---

## Architecture rule

Input layer emits semantic actions only.

```text
skill_1 → current_weapon.handle / existing adapter (iaido, place, hook, …)
```

Do **not** put `if weapon == MIRROR` skill branches in the global input router.
