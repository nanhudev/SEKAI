# MIRROR_HANDOFF

Mirror / 镜 V0.1 system prototype handoff for Codex / Combat Polish.

## FILES

```text
godot/scripts/combat/mirror_weapon/mirror_config.gd
godot/scripts/combat/mirror_weapon/mirror_node.gd
godot/scripts/combat/mirror_weapon/mirror_manager.gd
godot/scripts/combat/mirror_weapon/mirror_attack_logic.gd
godot/scripts/combat/mirror_weapon/mirror_travel.gd
godot/scripts/combat/mirror_weapon/mirror_weapon_controller.gd
godot/scripts/training/mirror_patrol_driver.gd

godot/scenes/combat/mirror_weapon/mirror_node.tscn
godot/scenes/combat/mirror_weapon/mirror_weapon.tscn
godot/resources/tuning/MirrorConfig.tres

godot/tests/mirror_weapon_v01.gd
godot/tools/mirror_weapon_v01_movie.gd
docs/MIRROR_HANDOFF.md
```

Shared minimal wiring (do not expand casually):

```text
godot/scripts/combat/weapon_slot.gd          (+ MIRROR)
godot/scripts/combat/weapon_manager.gd       (+ KEY_3 row)
godot/scenes/player/Player.tscn             (+ MirrorWeaponController)
godot/scripts/combat/developer_panel.gd     (+ Mirror button)
godot/scripts/training/training_ground.gd   (+ Mirror Test court)
godot/tests/weapon_switch_integration.gd    (registry size 3)
```

## SCENES

- Player hosts `MirrorWeaponController` beside `PhantomChainController`.
- TrainingGround zone `M` / `ZONE_MIRROR` — Test A/B/C/D fixtures.
- CombatSandbox inherits Player; movie/tests boot from CombatSandbox.

## INPUTS

| Input | Action |
|---|---|
| `1` | Sword |
| `2` | Phantom Chain |
| `3` | Mirror |
| `LMB` (`light_attack`) | Combo A1→A2→A3(placeholder)→A4; also Exit Cut / Travel confirm |
| `RMB` (`mirror_place`) | Place Mirror Node (while Mirror equipped) |
| `Q` (`mirror_travel`) | Enter Mirror State / confirm exit |
| `F9` | Mirror debug overlay + node labels + world rays |

## EVENTS

Signal: `MirrorWeaponController.mirror_event(event, data)`

```text
EV_MIRROR_EQUIP
EV_MIRROR_PLACE
EV_MIRROR_BREAK
EV_MIRROR_A1
EV_MIRROR_A1_ECHO
EV_MIRROR_A2_RELEASE
EV_MIRROR_A2_REFLECT
EV_MIRROR_ENTER
EV_MIRROR_TRAVEL
EV_MIRROR_EXIT
EV_MIRROR_EXIT_ATTACK
EV_MIRROR_A4_SHIFT
```

## CONFIG PARAMETERS

`MirrorConfig` / `res://resources/tuning/MirrorConfig.tres`

```text
mirror_max_count
mirror_place_min / mirror_place_max
clear_nodes_on_unequip (= true V0.1)
a1_range / a1_echo_delay / a1_echo_damage_scale
a2_range / a2_max_reflections / a2_assist_degrees
a3_* (placeholder double-echo)
a4_transit_ms / a4_shift_range
travel_duration / exit_offset_* / exit_attack_window
exit_cut_range / exit_cut_dash / exit_cut_damage
preserve_view_direction (= true)
travel_invuln (= true while Mirror State only)
```

## WHAT WORKS

- Key `3` Mirror equip; Sword/Chain internal logic untouched.
- Max 3 Mirror Nodes; 4th removes oldest.
- Place via aim raycast (floor stands up, walls offset).
- Safe exit capsule probe per node (`travel_exit_ok` + `safe_exit`).
- A1 player cut + delayed echo from **last created** mirror (true mirror origin).
- A2 segment refraction up to 2 bounces + light 15° assist.
- A3 placeholder: all mirrors light echo (`TODO CODEX: REPLACE WITH MIRROR CLONE`).
- A4 Mirror Shift ENTER→TRANSIT→EXIT.
- Q Mirror Travel select-state (no mirror-world locomotion).
- Exit Attack window after travel/shift exit.
- Debug overlay (F9): combo / count / selected / travel / A2 reflections + world rays.
- Unequip clears all mirrors (`clear_nodes_on_unequip`).

## WHAT IS PLACEHOLDER

```text
Mirror mesh = placeholder (BoxMesh abstract surface)
Hand / tarot card = placeholder
Hand animation = placeholder tweens
Travel screen effect = placeholder ColorRect tint + FOV kick
Slash VFX = placeholder debug lines
Audio = placeholder (none)
A3 = placeholder multi-echo — NOT Mirror Clone
mirror_clone_placeholder() = empty interface
Real-time reflection / SubViewport = intentionally not done
```

## KNOWN BUGS / LIMITS

- Floor placement faces player; wall mirrors use surface normal — assist is crude.
- A2 mirror catch is proximity-to-ray, not exact plane intersection.
- Travel auto-exits when timer ends if player never confirms.
- Rapid sheathe from Sword still uses existing WeaponManager draw/sheathe timings (shared).
- No mana/cooldown (intentional V0.1 spam-friendly locks only).
- Moving Test C dummy is a StaticBody orbit (not full AI).

## CURSOR PROTOTYPE PLACEHOLDER

Mark for Codex replace:

```text
CURSOR PROTOTYPE PLACEHOLDER — visuals, hand poses, travel shader, slash VFX, audio identity, Mirror Clone (A3), skill copy, ultimate.
```

## PROOF

```text
# Integration (20× weapon switch stress + place/echo/travel/unequip)
G:/Godot/Godot_v4.4.1-stable_win64_console.exe --headless --path F:/SEKAI/godot \
  --script res://tests/mirror_weapon_v01.gd
# → MIRROR_V01_OK

# Movie
G:/Godot/Godot_v4.4.1-stable_win64_console.exe --path F:/SEKAI/godot \
  --resolution 1280x720 --audio-driver Dummy \
  --script res://tools/mirror_weapon_v01_movie.gd
# frames → E:/SEKAI-renders/mirror_weapon_v01/frame_*.png (1000 @ 30fps ≈ 33s)

# Encoded proof
out/mirror_weapon_v01_prototype.mp4
mirror_weapon_v01_prototype.mp4   (repo root copy)
E:/SEKAI-renders/mirror_weapon_v01_prototype.mp4
```

## SELF-CHECK (V0.1)

| Q | Answer |
|---|---|
| A Attack origin changes via mirrors? | YES — A1 echo from last-created MirrorNode |
| B Player position changes via mirrors? | YES — Travel / A4 Shift to safe_exit |
| C Placement matters? | YES — echo angle + travel exit choice |
| D Enter/exit feel vs blink? | PARTIAL — tint/FOV placeholder, but ENTER→SELECT→EXIT exists |
| E Too slow for combat? | NO for V0.1 spam locks; travel select ~1.25s tunable |
| F 3 mirrors enough? | YES for prototype spatial thinking |
| G Fun without final VFX? | YES for POSITION / ANGLE / TRAVEL loop |

Stop expanding — Codex owns polish / clone / reflection rendering.
