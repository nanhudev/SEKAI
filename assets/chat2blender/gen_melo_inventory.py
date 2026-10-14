"""Generate MELO_ASSET_INVENTORY.md from the measured audit data.

Generating rather than hand-writing the 84-row table: the numbers come from the
same JSON the contact sheets were captioned from, so the document and the images
cannot drift apart.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import os
from collections import defaultdict

OUT_DIR = str(_SEKAI_ROOT / 'assets_source/review/melo')
DEST = str(_SEKAI_ROOT / 'assets_source/reuse/melo/MELO_ASSET_INVENTORY.md')

# Which of the brief's categories each source folder maps to. Kept explicit so a
# new folder shows up as "UNCLASSIFIED" instead of being silently bucketed.
CATEGORY = {
    "arc_ancient_sanctuary_kit": "C - ENVIRONMENT (ancient ruin kit)",
    "cin_brutalist_megagate": "C - ENVIRONMENT (cinematic landmark)",
    "cin_tianji_ambush_set": "C - ENVIRONMENT (cinematic set)",
    "cin_tianji_cannon": "C - ENVIRONMENT / PROP (cinematic cannon)",
    "chr_melo": "A - HERO BODY",
    "melo.glb": "A - HERO BODY",
    "bos_city_core_devourer": "A - BOSS",
    "cre_ancient_sentinel": "A - CREATURE / CONSTRUCT",
    "drone_cannon": "D - PROP",
}

REUSE = {
    "msh_arc_ring_device_large_v001": "REUSE-A",
    "msh_arc_ring_device_small_v001": "REUSE-A",
    "msh_arc_shrine_device_v001": "REUSE-A",
    "msh_arc_altar_main_v001": "REUSE-A",
    "msh_arc_energy_core_large_v001": "REUSE-A",
    "msh_arc_energy_core_medium_v001": "REUSE-A",
    "msh_arc_energy_core_small_v001": "REUSE-B",
    "msh_arc_arch_frame_v001": "REUSE-A",
    "msh_arc_gate_frame_large_v001": "REUSE-A",
    "msh_arc_door_frame_v001": "REUSE-B",
    "msh_arc_energy_door_frame_v001": "REUSE-A",
    "msh_arc_pillar_large_v001": "REUSE-A",
    "msh_arc_pillar_medium_v001": "REUSE-A",
    "msh_arc_pillar_small_v001": "REUSE-B",
    "msh_arc_pillar_broken_v001": "REUSE-A",
    "msh_arc_stairs_v001": "REUSE-B",
    "msh_arc_ramp_v001": "REUSE-B",
    "msh_arc_ruin_fragment_a_v001": "REUSE-B",
    "msh_arc_ruin_fragment_b_v001": "REUSE-B",
    "msh_arc_ruin_fragment_c_v001": "REUSE-A",
    "msh_arc_stone_shard_a_v001": "REUSE-B",
    "msh_arc_stone_shard_b_v001": "REUSE-B",
    "msh_arc_ancient_terminal_v001": "REUSE-A",
    "msh_arc_crystal_cluster_a_v001": "REUSE-A",
    "msh_arc_crystal_cluster_b_v001": "REUSE-B",
    "msh_arc_tree_a_v001": "REUSE-B",
    "msh_arc_tree_b_v001": "REUSE-B",
    "msh_arc_bush_a_v001": "REUSE-C",
    "msh_arc_bush_b_v001": "REUSE-C",
    "msh_arc_grass_clump_a_v001": "REUSE-C",
    "msh_arc_grass_clump_b_v001": "REUSE-C",
    "msh_arc_dead_tree_a_v001": "REUSE-C",
    "msh_arc_rock_large_a_v001": "REUSE-C",
    "msh_arc_rock_medium_a_v001": "REUSE-C",
    "msh_arc_rock_medium_b_v001": "REUSE-C",
    "msh_arc_rock_small_a_v001": "REUSE-C",
    "msh_arc_rock_small_b_v001": "REUSE-C",
    "msh_arc_brick_a_v001": "REJECT",
    "msh_arc_brick_b_v001": "REJECT",
    "msh_arc_broken_block_a_v001": "REJECT",
    "msh_arc_broken_block_b_v001": "REJECT",
    "msh_arc_bridge_broken_v001": "REUSE-C",
    "msh_arc_bridge_long_v001": "REJECT",
    "msh_arc_bridge_short_v001": "REUSE-B",
    "msh_arc_floor_4x4_v001": "REJECT",
    "msh_arc_floor_8x8_v001": "REJECT",
    "msh_arc_floor_8x16_v001": "REJECT",
    "msh_arc_floor_broken_a_v001": "REJECT",
    "msh_arc_floor_broken_b_v001": "REJECT",
    "msh_arc_floating_floor_a_v001": "REJECT",
    "msh_arc_floating_floor_b_v001": "REJECT",
    "msh_arc_floating_rock_a_v001": "REUSE-B",
    "msh_arc_floating_rock_b_v001": "REUSE-B",
    "msh_arc_platform_floating_v001": "REJECT",
    "msh_arc_platform_large_v001": "REJECT",
    "msh_arc_platform_medium_v001": "REJECT",
    "msh_arc_platform_small_v001": "REJECT",
    "msh_arc_wall_4x4_v001": "REJECT",
    "msh_arc_wall_8x4_v001": "REJECT",
    "msh_arc_wall_broken_a_v001": "REJECT",
    "msh_arc_wall_broken_b_v001": "REJECT",
    "msh_arc_wall_corner_v001": "REJECT",
    "msh_cre_ancient_sentinel_lod0_v001": "REUSE-A",
    "msh_bos_city_core_devourer_v001": "REUSE-C",
    "msh_cin_brutalist_megagate_v001": "REUSE-C",
    "msh_cin_tianji_cannon_v001": "REUSE-C",
    "msh_cin_tianji_ambush_set_v001": "REJECT",
    "msh_drone_cannon_a_v001": "REUSE-B",
}

# The hero body is one asset re-exported for animation tests. Only the ones that
# actually differ are worth naming.
HERO_PRIMARY = {
    "msh_chr_melo_body_lod0": "runtime LOD0 body - the real one",
    "assets/melo.glb": "hero GLB at project root - duplicate of LOD0",
    "msh_chr_melo_body_honor_v005": "later authored variant, 7472 tris",
    "msh_chr_melo_body_polish_v004": "highest-detail polish pass, 7208 tris",
}


def main():
    idx = json.load(open(os.path.join(OUT_DIR, "melo_glb_index.json"), encoding="utf-8"))
    meas = json.load(open(os.path.join(OUT_DIR, "melo_measured.json"), encoding="utf-8"))

    total_tris = sum(v["triangles"] for v in meas.values())
    total_bytes = sum(v["size_bytes"] for v in meas.values())
    helpers = [k for k, v in meas.items() if v.get("helper_objects")]

    L = []
    L.append("# MELO ASSET INVENTORY")
    L.append("")
    L.append("Round 1 output of `MELO LEGACY ASSET AUDIT`. Read-only: nothing in the")
    L.append("melo project was modified, moved or deleted.")
    L.append("")
    L.append("Generated from `melo_measured.json`, which is produced by instantiating")
    L.append("each GLB in Blender and measuring the imported result - not from file")
    L.append("names and not from the Godot scene tree.")
    L.append("")
    L.append("## Totals")
    L.append("")
    L.append("| metric | value |")
    L.append("| --- | --- |")
    L.append("| GLB files | %d |" % len(idx))
    L.append("| triangle count (visual only, helpers excluded) | %s |" % f"{total_tris:,}")
    L.append("| binary size | %.1f MB |" % (total_bytes / 1048576))
    L.append("| Blender `.blend` sources | 21 |")
    L.append("| assets shipping a collision/helper mesh | %d |" % len(helpers))
    L.append("")
    L.append("## Category rollup")
    L.append("")
    buckets = defaultdict(lambda: [0, 0, 0])
    for e in idx:
        key = CATEGORY.get(e["owner"], "UNCLASSIFIED")
        m = meas.get(e["rel"], {})
        buckets[key][0] += 1
        buckets[key][1] += m.get("triangles", 0)
        buckets[key][2] += e["size"]
    L.append("| category | files | tris | size |")
    L.append("| --- | ---: | ---: | ---: |")
    for k in sorted(buckets):
        n, t, b = buckets[k]
        L.append("| %s | %d | %s | %.1f MB |" % (k, n, f"{t:,}", b / 1048576))
    L.append("")
    L.append("## Reuse rating summary")
    L.append("")
    rc = defaultdict(int)
    for e in idx:
        base = os.path.basename(e["rel"]).replace(".glb", "")
        if e["owner"] == "chr_melo":
            rc["REUSE-C (hero body - reference only, see below)"] += 1
        else:
            rc[REUSE.get(base, "unrated")] += 1
    L.append("| rating | files |")
    L.append("| --- | ---: |")
    for k in sorted(rc):
        L.append("| %s | %d |" % (k, rc[k]))
    L.append("")
    L.append("## Full listing")
    L.append("")

    for cat in sorted({CATEGORY.get(e["owner"], "UNCLASSIFIED") for e in idx}):
        rows = [e for e in idx if CATEGORY.get(e["owner"], "UNCLASSIFIED") == cat]
        L.append("### %s" % cat)
        L.append("")
        L.append("| GLB | dims (m) | tris | rating | materials |")
        L.append("| --- | --- | ---: | --- | --- |")
        for e in rows:
            base = os.path.basename(e["rel"]).replace(".glb", "")
            m = meas.get(e["rel"])
            if not m:
                L.append("| %s | - | - | - | - |" % base)
                continue
            note = ""
            if e["owner"] == "chr_melo":
                if base in HERO_PRIMARY:
                    note = "REUSE-C (%s)" % HERO_PRIMARY[base]
                else:
                    note = "REJECT (duplicate export)"
            else:
                note = REUSE.get(base, "unrated")
            L.append("| %s | %.2f x %.2f x %.2f | %s | %s | %s |" % (
                base, m["dims_m"][0], m["dims_m"][1], m["dims_m"][2],
                f"{m['triangles']:,}", note,
                ", ".join(m["materials"]) or "-"))
        L.append("")

    L.append("## Non-mesh assets worth recording")
    L.append("")
    L.append("| asset | path | what it is | rating |")
    L.append("| --- | --- | --- | --- |")
    L.append("| M_Env_IvoryStone | `asset_library/material/master/mat_env_ivory_stone.tres` | "
             "albedo 0.76,0.72,0.64 / metallic 0.04 / roughness 0.74 | REUSE-A value |")
    L.append("| M_Env_AncientGold | `.../mat_env_ancient_gold.tres` | "
             "albedo 0.70,0.50,0.22 / metallic 0.86 / roughness 0.34, faint self-emission | REUSE-A value |")
    L.append("| M_Env_DarkStone | `.../mat_env_dark_stone.tres` | albedo 0.11,0.13,0.17 / roughness 0.80 | REUSE-A value |")
    L.append("| M_Env_Crystal | `.../mat_env_crystal.tres` | blue 0.62,0.78,0.94 / roughness 0.08 / emission 0.75 | REUSE-B |")
    L.append("| M_Env_Energy | `.../mat_env_energy.tres` | emission (0.28,0.78,1) at energy 2.1 | REUSE-B |")
    L.append("| mat_energy_core (shader) | `.../mat_energy_core.tres` | pulses a core: intensity 4.0, pulse 2.0 Hz, rim 1.8 | REUSE-A |")
    L.append("| shd_energy_core.gdshader | `asset_library/shader/spatial/` | pulsing emissive + rim, 7 uniforms | REUSE-A |")
    L.append("| shd_melo_fx_energy.gdshader | `asset_library/shader/spatial/` | additive rim energy FX | REUSE-A |")
    L.append("| shd_melo_energy_wing.gdshader | `asset_library/shader/spatial/` | energy membrane + edge rim + shimmer | REUSE-B |")
    L.append("| prp_ancient_module_kit | `asset_library/props/prp_ancient_module_kit/` | "
             "7 modules extracted by node name from the hero GLB | REUSE-A idea |")
    L.append("| ancient_ruins_kit.gd | `asset_library/environments/ancient_ruins_kit/` | "
             "greybox primitives, header says \"No hi-poly\" | REJECT (reference only) |")
    L.append("")
    L.append("## The module kit, restated")
    L.append("")
    L.append("`prp_ancient_module_kit` does not hold meshes. It holds seven `.tscn` files that")
    L.append("instance the hero GLB and hide all but a named subset, then re-centre the origin.")
    L.append("That is a runtime mask, so reusing a module in SEKAI means exporting the named")
    L.append("nodes as real meshes. Node names, verbatim:")
    L.append("")
    mods = json.load(open(
        r"C:\Users\Administrator\Desktop\项目_开发与研究\Melo-Godot-Prototype"
        r"\asset_library\props\prp_ancient_module_kit\data\module_definitions.json",
        encoding="utf-8"))["modules"]
    L.append("| module | source nodes | material slots | scale range |")
    L.append("| --- | --- | --- | --- |")
    for name, d in mods.items():
        L.append("| `%s` | %s | %s | %s |" % (
            name, ", ".join(d["source_nodes"]), ", ".join(d["material_slots"]),
            "%.2f-%.2f" % tuple(d["scale_range"])))

    os.makedirs(os.path.dirname(DEST), exist_ok=True)
    open(DEST, "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("wrote %s (%d lines)" % (DEST, len(L)))


if __name__ == "__main__":
    main()
