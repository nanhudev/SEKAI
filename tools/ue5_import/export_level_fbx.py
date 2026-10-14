"""Re-export the saved Mistvale level to FBX, without touching the UE project.

Why this exists: the export checked into Source/ (Mistvale_ActualScene_Review.fbx)
is timestamped 16:11, but save_handoff.py later (16:22) DELETED
MainStoneBridge_SouthRamp/NorthRamp and added the three SM_Handoff_* ramp meshes.
A ray march down the town spine against the 16:11 export measures three hard
steps on the bridge -- +0.417, +0.530 and +1.046 m -- which is precisely what
that handoff pass existed to remove. So the committed export is one pass stale
and the bridge in it is not walkable.

This mirrors the export block of audit_saved_art_scene.py exactly (same
LevelExporterFBX, same FbxExportOption flags, bake_material_inputs DISABLED --
which is why the FBX carries material NAMES but no colours). Two differences:
it writes to _handoff/ instead of Source/, and it also dumps the per-actor
material assignment so the Godot side can colour by name instead of inventing a
palette.

This script only LOADS the level. It never saves it.

Run via the project's commandlet pattern:
  "/f/UE_5.8/Engine/Binaries/Win64/UnrealEditor-Cmd.exe" \
      "F:/SEKAI/ue5_lab/Mistvale_Rebuild/Mistvale_Rebuild.uproject" \
      -run=pythonscript -script="F:/SEKAI/tools/ue5_import/export_level_fbx.py" \
      -unattended -nosplash -nullrhi -stdout -nopause
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import json
from pathlib import Path

import unreal

HANDOFF = Path(str(_SEKAI_ROOT / 'ue5_lab/Mistvale_Rebuild/_handoff'))
DEST = HANDOFF / "mistvale_current.fbx"
ACTORS_OUT = HANDOFF / "actor_materials.json"

unreal.EditorLevelLibrary.load_level("/Game/Maps/L_Mistvale_Rebuild")
world = unreal.get_editor_subsystem(unreal.UnrealEditorSubsystem).get_editor_world()
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
meshes = [a for a in actors if isinstance(a, unreal.StaticMeshActor)]

HANDOFF.mkdir(parents=True, exist_ok=True)
if DEST.exists():
    DEST.unlink()

task = unreal.AssetExportTask()
task.object = world
task.exporter = unreal.LevelExporterFBX()
task.filename = str(DEST)
task.automated = True
task.prompt = False
task.selected = False
task.replace_identical = True
options = unreal.FbxExportOption()
options.ascii = False
options.collision = False
options.level_of_detail = False
options.bake_material_inputs = unreal.FbxMaterialBakeMode.DISABLED
task.options = options

ok = unreal.Exporter.run_asset_export_task(task)

# Per-actor material names. The FBX export has material baking DISABLED, so the
# only way the runtime can colour this map is by matching these names against
# the palette the art line already authored.
rows = []
for a in meshes:
    smc = a.static_mesh_component
    rows.append({
        "label": a.get_actor_label(),
        "folder": str(a.get_folder_path()),
        "mesh": (smc.get_editor_property("static_mesh").get_name()
                 if smc.get_editor_property("static_mesh") else None),
        "materials": [smc.get_material(i).get_name() if smc.get_material(i) else None
                      for i in range(smc.get_num_materials())],
    })
ACTORS_OUT.write_text(json.dumps(rows, indent=1), encoding="utf-8")

starts = [a for a in actors if isinstance(a, unreal.PlayerStart)]
start_rows = []
for s in starts:
    loc = s.get_actor_location()
    rot = s.get_actor_rotation()
    start_rows.append({
        "label": s.get_actor_label(),
        "location_cm": [loc.x, loc.y, loc.z],
        "rotation_degrees": [rot.pitch, rot.yaw, rot.roll],
    })

print("EXPORT_LEVEL meshes=%d ok=%s exists=%s size=%s"
      % (len(meshes), ok, DEST.exists(), DEST.stat().st_size if DEST.exists() else -1))
print("EXPORT_LEVEL actors=%d" % len(rows))
print("EXPORT_LEVEL player_starts=%s" % json.dumps(start_rows))
handoff = [r for r in rows if "Handoff" in (r["label"] or "")]
print("EXPORT_LEVEL handoff_actors=%s" % [r["label"] for r in handoff])
ramps = [r["label"] for r in rows if "Ramp" in (r["label"] or "")]
print("EXPORT_LEVEL ramp_actors=%s" % ramps)

if not ok or not DEST.exists():
    raise RuntimeError("level export failed")
