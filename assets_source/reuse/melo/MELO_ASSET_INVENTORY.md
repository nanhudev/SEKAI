# MELO ASSET INVENTORY

Round 1 output of `MELO LEGACY ASSET AUDIT`. Read-only: nothing in the
melo project was modified, moved or deleted.

Generated from `melo_measured.json`, which is produced by instantiating
each GLB in Blender and measuring the imported result - not from file
names and not from the Godot scene tree.

## Totals

| metric | value |
| --- | --- |
| GLB files | 84 |
| triangle count (visual only, helpers excluded) | 274,950 |
| binary size | 17.4 MB |
| Blender `.blend` sources | 21 |
| assets shipping a collision/helper mesh | 21 |

## Category rollup

| category | files | tris | size |
| --- | ---: | ---: | ---: |
| A - BOSS | 1 | 45,784 | 0.9 MB |
| A - CREATURE / CONSTRUCT | 1 | 18,188 | 1.1 MB |
| A - HERO BODY | 16 | 115,816 | 8.9 MB |
| C - ENVIRONMENT (ancient ruin kit) | 62 | 50,454 | 3.7 MB |
| C - ENVIRONMENT (cinematic landmark) | 1 | 10,976 | 0.7 MB |
| C - ENVIRONMENT (cinematic set) | 1 | 16,364 | 1.1 MB |
| C - ENVIRONMENT / PROP (cinematic cannon) | 1 | 15,764 | 0.9 MB |
| D - PROP | 1 | 1,604 | 0.1 MB |

## Reuse rating summary

| rating | files |
| --- | ---: |
| REJECT | 22 |
| REUSE-A | 16 |
| REUSE-B | 16 |
| REUSE-C | 14 |
| REUSE-C (hero body - reference only, see below) | 15 |
| unrated | 1 |

## Full listing

### A - BOSS

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_bos_city_core_devourer_v001 | 75.00 x 75.00 x 48.00 | 45,784 | REUSE-C | M_Boss_AncientGold.001, M_Boss_DarkStructure.001, M_Boss_EnergyCore.001, M_Boss_EnergyHot.001, M_Boss_IvoryCeramic.001, M_Boss_WhiteCeramic.001 |

### A - CREATURE / CONSTRUCT

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_cre_ancient_sentinel_lod0_v001 | 0.92 x 0.29 x 1.06 | 18,188 | REUSE-A | M_Creature_AncientGold.009, M_Creature_DarkMetal.009, M_Creature_EnergyCore.009, M_Creature_EnergyGlow.009, M_Creature_IvoryCeramic.009 |

### A - HERO BODY

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| melo | 1.60 x 0.55 x 2.18 | 7,056 | unrated | Melo_Core.017, Melo_Dark.017, Melo_Gold.017, Melo_Ivory.017 |
| msh_chr_melo_body_honor_v005 | 1.60 x 1.49 x 2.63 | 7,472 | REUSE-C (later authored variant, 7472 tris) | M_Hero_AncientGold.006, M_Hero_DarkStructure.006, M_Hero_EnergyCore.006, M_Hero_Ivory.006, Melo_Core.018, Melo_Dark.018, Melo_Gold.018, Melo_Ivory.018 |
| msh_chr_melo_body_lod0 | 1.60 x 0.55 x 2.18 | 7,056 | REUSE-C (runtime LOD0 body - the real one) | Melo_Core.019, Melo_Dark.019, Melo_Gold.019, Melo_Ivory.019 |
| msh_chr_melo_body_lod0_pre_g3_1 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.020, Melo_Dark.020, Melo_Gold.020, Melo_Ivory.020 |
| msh_chr_melo_body_polish_v002 | 1.61 x 1.49 x 2.71 | 8,232 | REJECT (duplicate export) | M_Hero_AncientGold.007, M_Hero_DarkStructure.007, M_Hero_EnergyCore.007, M_Hero_Ivory.007, Melo_Core.021, Melo_Dark.021, Melo_Gold.021, Melo_Ivory.021 |
| msh_chr_melo_body_polish_v003 | 1.61 x 1.49 x 2.71 | 8,232 | REJECT (duplicate export) | M_Hero_AncientGold.008, M_Hero_DarkStructure.008, M_Hero_EnergyCore.008, M_Hero_Ivory.008, Melo_Core.022, Melo_Dark.022, Melo_Gold.022, Melo_Ivory.022 |
| msh_chr_melo_body_polish_v004 | 1.61 x 1.49 x 2.63 | 7,208 | REUSE-C (highest-detail polish pass, 7208 tris) | M_Hero_AncientGold.009, M_Hero_DarkStructure.009, M_Hero_EnergyCore.009, M_Hero_Ivory.009, Melo_Core.023, Melo_Dark.023, Melo_Gold.023, Melo_Ivory.023 |
| msh_chr_melo_flight_anim_test_v002 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.024, Melo_Dark.024, Melo_Gold.024, Melo_Ivory.024 |
| msh_chr_melo_g5_2_skills_test_v001 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.025, Melo_Dark.025, Melo_Gold.025, Melo_Ivory.025 |
| msh_chr_melo_g5_3_combat_test_v001 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.026, Melo_Dark.026, Melo_Gold.026, Melo_Ivory.026 |
| msh_chr_melo_spin_dodge_axial_test_v001 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.027, Melo_Dark.027, Melo_Gold.027, Melo_Ivory.027 |
| msh_chr_melo_spin_dodge_impulse_test_v002 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.028, Melo_Dark.028, Melo_Gold.028, Melo_Ivory.028 |
| msh_chr_melo_spin_dodge_impulse_test_v003 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.029, Melo_Dark.029, Melo_Gold.029, Melo_Ivory.029 |
| msh_chr_melo_spin_dodge_test_v003 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.030, Melo_Dark.030, Melo_Gold.030, Melo_Ivory.030 |
| msh_chr_melo_wing_dynamics_test_v001 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.031, Melo_Dark.031, Melo_Gold.031, Melo_Ivory.031 |
| msh_chr_melo_wing_dynamics_test_v001_pre_g3_1 | 1.60 x 0.55 x 2.18 | 7,056 | REJECT (duplicate export) | Melo_Core.032, Melo_Dark.032, Melo_Gold.032, Melo_Ivory.032 |

### C - ENVIRONMENT (ancient ruin kit)

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_arc_altar_main_v001 | 4.03 x 3.76 x 1.42 | 1,280 | REUSE-A | M_Env_AncientGold.045, M_Env_Energy.029, M_Env_WhiteCeramic.014 |
| msh_arc_ancient_terminal_v001 | 1.60 x 1.42 x 1.41 | 764 | REUSE-A | M_Env_AncientGold.046, M_Env_DarkStone.049, M_Env_Energy.030, M_Env_IvoryStone.045 |
| msh_arc_arch_frame_v001 | 5.20 x 1.08 x 5.48 | 1,252 | REUSE-A | M_Env_AncientGold.047, M_Env_DarkStone.050, M_Env_IvoryStone.046 |
| msh_arc_brick_a_v001 | 1.00 x 0.56 x 0.36 | 216 | REJECT | M_Env_AncientGold.048, M_Env_Damage.022 |
| msh_arc_brick_b_v001 | 1.08 x 0.69 x 0.36 | 216 | REJECT | M_Env_AncientGold.049, M_Env_Damage.023 |
| msh_arc_bridge_broken_v001 | 2.67 x 10.41 x 0.87 | 756 | REUSE-C | M_Env_Damage.024, M_Env_Energy.031 |
| msh_arc_bridge_long_v001 | 2.10 x 14.05 x 0.03 | 864 | REJECT | M_Env_Energy.032 |
| msh_arc_bridge_short_v001 | 3.20 x 8.00 x 0.97 | 864 | REUSE-B | M_Env_AncientGold.052, M_Env_DarkStone.053, M_Env_Energy.033, M_Env_IvoryStone.049 |
| msh_arc_broken_block_a_v001 | 2.08 x 1.55 x 0.94 | 216 | REJECT | M_Env_Damage.025, M_Env_IvoryStone.050 |
| msh_arc_broken_block_b_v001 | 2.13 x 1.53 x 1.21 | 216 | REJECT | M_Env_Damage.026, M_Env_IvoryStone.051 |
| msh_arc_bush_a_v001 | 1.33 x 1.42 x 1.23 | 1,204 | REUSE-C | M_Env_AncientGold.053, M_Env_Crystal.008 |
| msh_arc_bush_b_v001 | 1.72 x 1.73 x 1.53 | 1,204 | REUSE-C | M_Env_AncientGold.054, M_Env_Crystal.009 |
| msh_arc_crystal_cluster_a_v001 | 0.87 x 0.88 x 1.13 | 900 | REUSE-A | M_Env_Crystal.010, M_Env_DarkStone.054 |
| msh_arc_crystal_cluster_b_v001 | 1.35 x 1.44 x 1.81 | 900 | REUSE-B | M_Env_Crystal.011, M_Env_DarkStone.055 |
| msh_arc_dead_tree_a_v001 | 1.58 x 1.41 x 3.27 | 520 | REUSE-C | M_Env_DarkStone.056 |
| msh_arc_door_frame_v001 | 3.20 x 1.08 x 3.60 | 1,036 | REUSE-B | M_Env_AncientGold.055, M_Env_DarkStone.057, M_Env_IvoryStone.052 |
| msh_arc_energy_core_large_v001 | 3.23 x 3.23 x 3.68 | 2,050 | REUSE-A | M_Env_AncientGold.056, M_Env_BlackStructure.010, M_Env_DarkStone.058, M_Env_Energy.034, M_Env_IvoryStone.053, M_Env_WhiteCeramic.015 |
| msh_arc_energy_core_medium_v001 | 1.85 x 1.85 x 2.17 | 2,050 | REUSE-A | M_Env_AncientGold.057, M_Env_BlackStructure.011, M_Env_DarkStone.059, M_Env_Energy.035, M_Env_IvoryStone.054, M_Env_WhiteCeramic.016 |
| msh_arc_energy_core_small_v001 | 1.04 x 1.04 x 1.28 | 2,050 | REUSE-B | M_Env_AncientGold.058, M_Env_BlackStructure.012, M_Env_DarkStone.060, M_Env_Energy.036, M_Env_IvoryStone.055, M_Env_WhiteCeramic.017 |
| msh_arc_energy_door_frame_v001 | 4.40 x 1.08 x 4.75 | 1,468 | REUSE-A | M_Env_AncientGold.059, M_Env_DarkStone.061, M_Env_Energy.037, M_Env_IvoryStone.056 |
| msh_arc_floating_floor_a_v001 | 8.00 x 8.00 x 1.91 | 1,144 | REJECT | M_Env_AncientGold.060, M_Env_DarkStone.062, M_Env_Energy.038, M_Env_IvoryStone.057 |
| msh_arc_floating_floor_b_v001 | 8.00 x 16.00 x 1.91 | 1,144 | REJECT | M_Env_AncientGold.061, M_Env_DarkStone.063, M_Env_Energy.039, M_Env_IvoryStone.058 |
| msh_arc_floating_rock_a_v001 | 2.80 x 1.94 x 3.91 | 808 | REUSE-B | M_Env_Damage.027, M_Env_DarkStone.064, M_Env_Energy.040 |
| msh_arc_floating_rock_b_v001 | 4.99 x 4.22 x 5.95 | 808 | REUSE-B | M_Env_Damage.028, M_Env_DarkStone.065, M_Env_Energy.041 |
| msh_arc_floor_4x4_v001 | 4.00 x 4.00 x 0.71 | 540 | REJECT | M_Env_AncientGold.062, M_Env_DarkStone.066, M_Env_Energy.042, M_Env_IvoryStone.059 |
| msh_arc_floor_8x16_v001 | 8.00 x 16.00 x 0.71 | 540 | REJECT | M_Env_AncientGold.063, M_Env_DarkStone.067, M_Env_Energy.043, M_Env_IvoryStone.060 |
| msh_arc_floor_8x8_v001 | 8.00 x 8.00 x 0.71 | 540 | REJECT | M_Env_AncientGold.064, M_Env_DarkStone.068, M_Env_Energy.044, M_Env_IvoryStone.061 |
| msh_arc_floor_broken_a_v001 | 8.00 x 8.00 x 0.90 | 756 | REJECT | M_Env_AncientGold.065, M_Env_Damage.029, M_Env_DarkStone.069, M_Env_Energy.045, M_Env_IvoryStone.062 |
| msh_arc_floor_broken_b_v001 | 8.00 x 16.00 x 0.90 | 756 | REJECT | M_Env_AncientGold.066, M_Env_Damage.030, M_Env_DarkStone.070, M_Env_Energy.046, M_Env_IvoryStone.063 |
| msh_arc_gate_frame_large_v001 | 7.00 x 1.08 x 7.30 | 1,252 | REUSE-A | M_Env_AncientGold.067, M_Env_DarkStone.071, M_Env_IvoryStone.064 |
| msh_arc_grass_clump_a_v001 | 0.82 x 0.87 x 0.91 | 756 | REUSE-C | M_Env_Crystal.012 |
| msh_arc_grass_clump_b_v001 | 0.83 x 0.86 x 0.91 | 756 | REUSE-C | M_Env_Crystal.013 |
| msh_arc_pillar_broken_v001 | 2.40 x 1.55 x 4.49 | 1,256 | REUSE-A | M_Env_AncientGold.068, M_Env_Damage.031, M_Env_DarkStone.072, M_Env_IvoryStone.065, M_Env_WhiteCeramic.018 |
| msh_arc_pillar_large_v001 | 1.45 x 1.45 x 7.42 | 928 | REUSE-A | M_Env_AncientGold.069, M_Env_DarkStone.073, M_Env_WhiteCeramic.019 |
| msh_arc_pillar_medium_v001 | 1.45 x 1.45 x 4.42 | 1,148 | REUSE-A | M_Env_AncientGold.070, M_Env_DarkStone.074, M_Env_IvoryStone.067, M_Env_WhiteCeramic.020 |
| msh_arc_pillar_small_v001 | 1.45 x 1.45 x 2.92 | 1,148 | REUSE-B | M_Env_AncientGold.071, M_Env_DarkStone.075, M_Env_IvoryStone.068, M_Env_WhiteCeramic.021 |
| msh_arc_platform_floating_v001 | 8.00 x 8.00 x 2.37 | 1,036 | REJECT | M_Env_AncientGold.072, M_Env_BlackStructure.013, M_Env_DarkStone.076, M_Env_Energy.047, M_Env_IvoryStone.069 |
| msh_arc_platform_large_v001 | 16.00 x 16.00 x 0.92 | 432 | REJECT | M_Env_AncientGold.073, M_Env_BlackStructure.014, M_Env_IvoryStone.070 |
| msh_arc_platform_medium_v001 | 8.00 x 8.00 x 0.92 | 432 | REJECT | M_Env_AncientGold.074, M_Env_BlackStructure.015, M_Env_IvoryStone.071 |
| msh_arc_platform_small_v001 | 4.00 x 4.00 x 0.92 | 432 | REJECT | M_Env_AncientGold.075, M_Env_BlackStructure.016, M_Env_IvoryStone.072 |
| msh_arc_ramp_v001 | 4.00 x 7.97 x 1.99 | 188 | REUSE-B | M_Env_DarkStone.077, M_Env_IvoryStone.073 |
| msh_arc_ring_device_large_v001 | 3.78 x 2.40 x 3.78 | 1,478 | REUSE-A | M_Env_AncientGold.076, M_Env_DarkStone.078, M_Env_Energy.048, M_Env_IvoryStone.074 |
| msh_arc_ring_device_small_v001 | 1.70 x 1.08 x 1.70 | 1,478 | REUSE-A | M_Env_AncientGold.077, M_Env_DarkStone.079, M_Env_Energy.049, M_Env_IvoryStone.075 |
| msh_arc_rock_large_a_v001 | 6.03 x 5.27 x 6.32 | 232 | REUSE-C | M_Env_Damage.032, M_Env_DarkStone.080 |
| msh_arc_rock_medium_a_v001 | 1.96 x 1.17 x 2.50 | 232 | REUSE-C | M_Env_Damage.033, M_Env_DarkStone.081 |
| msh_arc_rock_medium_b_v001 | 2.98 x 2.52 x 3.36 | 232 | REUSE-C | M_Env_Damage.034, M_Env_DarkStone.082 |
| msh_arc_rock_small_a_v001 | 0.88 x 0.53 x 1.10 | 232 | REUSE-C | M_Env_Damage.035, M_Env_DarkStone.083 |
| msh_arc_rock_small_b_v001 | 1.27 x 1.08 x 1.41 | 232 | REUSE-C | M_Env_Damage.036, M_Env_DarkStone.084 |
| msh_arc_ruin_fragment_a_v001 | 1.52 x 1.66 x 1.68 | 244 | REUSE-B | M_Env_Damage.037, M_Env_IvoryStone.076 |
| msh_arc_ruin_fragment_b_v001 | 1.76 x 1.58 x 1.91 | 244 | REUSE-B | M_Env_Damage.038, M_Env_IvoryStone.077 |
| msh_arc_ruin_fragment_c_v001 | 1.93 x 1.50 x 2.04 | 244 | REUSE-A | M_Env_Damage.039, M_Env_IvoryStone.078 |
| msh_arc_shrine_device_v001 | 3.00 x 2.40 x 3.15 | 900 | REUSE-A | M_Env_AncientGold.078, M_Env_DarkStone.085, M_Env_Energy.050, M_Env_IvoryStone.079 |
| msh_arc_stairs_v001 | 4.00 x 8.00 x 2.20 | 972 | REUSE-B | M_Env_AncientGold.079, M_Env_IvoryStone.080 |
| msh_arc_stone_shard_a_v001 | 1.03 x 1.16 x 1.38 | 136 | REUSE-B | M_Env_Damage.040 |
| msh_arc_stone_shard_b_v001 | 1.19 x 1.09 x 1.48 | 136 | REUSE-B | M_Env_Damage.041 |
| msh_arc_tree_a_v001 | 2.69 x 2.49 x 5.35 | 1,644 | REUSE-B | M_Env_AncientGold.080, M_Env_Crystal.014, M_Env_DarkStone.086 |
| msh_arc_tree_b_v001 | 3.18 x 2.97 x 6.42 | 1,644 | REUSE-B | M_Env_AncientGold.081, M_Env_Crystal.015, M_Env_DarkStone.087 |
| msh_arc_wall_4x4_v001 | 4.18 x 0.89 x 4.00 | 648 | REJECT | M_Env_AncientGold.082, M_Env_DarkStone.088, M_Env_Energy.051, M_Env_IvoryStone.081, M_Env_WhiteCeramic.022 |
| msh_arc_wall_8x4_v001 | 8.18 x 0.89 x 4.00 | 648 | REJECT | M_Env_AncientGold.083, M_Env_DarkStone.089, M_Env_Energy.052, M_Env_IvoryStone.082, M_Env_WhiteCeramic.023 |
| msh_arc_wall_broken_a_v001 | 4.29 x 1.20 x 4.25 | 864 | REJECT | M_Env_AncientGold.084, M_Env_Damage.042, M_Env_DarkStone.090, M_Env_Energy.053, M_Env_IvoryStone.083, M_Env_WhiteCeramic.024 |
| msh_arc_wall_broken_b_v001 | 8.34 x 1.42 x 4.32 | 864 | REJECT | M_Env_AncientGold.085, M_Env_Damage.043, M_Env_DarkStone.091, M_Env_Energy.054, M_Env_IvoryStone.084, M_Env_WhiteCeramic.025 |
| msh_arc_wall_corner_v001 | 4.12 x 4.12 x 4.50 | 324 | REJECT | M_Env_AncientGold.086, M_Env_DarkStone.092 |

### C - ENVIRONMENT (cinematic landmark)

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_cin_brutalist_megagate_v001 | 112.46 x 142.04 x 44.00 | 10,976 | REUSE-C | M_Env_AncientGold.087, M_Env_BlackStructure.017, M_Env_DarkStone.093, M_Env_Energy.055, M_Env_IvoryStone.085 |

### C - ENVIRONMENT (cinematic set)

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_cin_tianji_ambush_set_v001 | 47.05 x 35.63 x 124.34 | 16,364 | REJECT | M_Env_AncientGold.088, M_Env_BlackStructure.018, M_Env_DarkStone.094, M_Env_Energy.056, M_Env_IvoryStone.086, M_Env_WhiteCeramic.026 |

### C - ENVIRONMENT / PROP (cinematic cannon)

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_cin_tianji_cannon_v001 | 22.04 x 14.40 x 22.04 | 15,764 | REUSE-C | M_Env_AncientGold.089, M_Env_BlackStructure.019, M_Env_DarkStone.095, M_Env_Energy.057, M_Env_IvoryStone.087, M_Env_WhiteCeramic.027 |

### D - PROP

| GLB | dims (m) | tris | rating | materials |
| --- | --- | ---: | --- | --- |
| msh_drone_cannon_a_v001 | 0.35 x 0.48 x 0.55 | 1,604 | REUSE-B | DroneCrystal.001, DroneDark.001, DroneGold.001, DroneIvory.001 |

## Non-mesh assets worth recording

| asset | path | what it is | rating |
| --- | --- | --- | --- |
| M_Env_IvoryStone | `asset_library/material/master/mat_env_ivory_stone.tres` | albedo 0.76,0.72,0.64 / metallic 0.04 / roughness 0.74 | REUSE-A value |
| M_Env_AncientGold | `.../mat_env_ancient_gold.tres` | albedo 0.70,0.50,0.22 / metallic 0.86 / roughness 0.34, faint self-emission | REUSE-A value |
| M_Env_DarkStone | `.../mat_env_dark_stone.tres` | albedo 0.11,0.13,0.17 / roughness 0.80 | REUSE-A value |
| M_Env_Crystal | `.../mat_env_crystal.tres` | blue 0.62,0.78,0.94 / roughness 0.08 / emission 0.75 | REUSE-B |
| M_Env_Energy | `.../mat_env_energy.tres` | emission (0.28,0.78,1) at energy 2.1 | REUSE-B |
| mat_energy_core (shader) | `.../mat_energy_core.tres` | pulses a core: intensity 4.0, pulse 2.0 Hz, rim 1.8 | REUSE-A |
| shd_energy_core.gdshader | `asset_library/shader/spatial/` | pulsing emissive + rim, 7 uniforms | REUSE-A |
| shd_melo_fx_energy.gdshader | `asset_library/shader/spatial/` | additive rim energy FX | REUSE-A |
| shd_melo_energy_wing.gdshader | `asset_library/shader/spatial/` | energy membrane + edge rim + shimmer | REUSE-B |
| prp_ancient_module_kit | `asset_library/props/prp_ancient_module_kit/` | 7 modules extracted by node name from the hero GLB | REUSE-A idea |
| ancient_ruins_kit.gd | `asset_library/environments/ancient_ruins_kit/` | greybox primitives, header says "No hi-poly" | REJECT (reference only) |

## The module kit, restated

`prp_ancient_module_kit` does not hold meshes. It holds seven `.tscn` files that
instance the hero GLB and hide all but a named subset, then re-centre the origin.
That is a runtime mask, so reusing a module in SEKAI means exporting the named
nodes as real meshes. Node names, verbatim:

| module | source nodes | material slots | scale range |
| --- | --- | --- | --- |
| `mod_cone_head` | Melo_Crown, Melo_CrownGold | ivory, ancient_gold | 0.50-2.00 |
| `mod_floating_ring_joint` | Melo_BackHalo_0, Melo_BackHalo_1, Melo_BackHalo_2, Melo_NeckHalo | ancient_gold | 0.25-3.00 |
| `mod_shard_hand` | Melo_Arm_L, Melo_ArmGold_L, Melo_JointA_L, Melo_JointB_L, Melo_JointC_L | ivory, ancient_gold | 0.50-2.50 |
| `mod_triangular_cloak` | Melo_Cape_L_Gold, Melo_Cape_L_Ivory, Melo_CapeEmblem_L, Melo_Cape_R_Gold, Melo_Cape_R_Ivory, Melo_CapeEmblem_R | ivory, ancient_gold | 0.50-2.00 |
| `mod_energy_core` | Melo_Core, Melo_CoreHousing, Melo_CoreInner, Melo_CoreOuter, Melo_CoreRearRing | energy_core, dark_inlay, ivory, ancient_gold | 0.25-4.00 |
| `mod_shoulder_triangle` | Melo_Shoulder_L_Gold, Melo_Shoulder_L_Ivory, Melo_Shoulder_R_Gold, Melo_Shoulder_R_Ivory | ivory, ancient_gold | 0.50-3.00 |
| `mod_ancient_panel` | Melo_TorsoFacet_L_Gold, Melo_TorsoFacet_L_Ivory, Melo_TorsoFacet_R_Gold, Melo_TorsoFacet_R_Ivory, Melo_TorsoRib_L, Melo_TorsoRib_R | ivory, ancient_gold | 0.50-5.00 |
