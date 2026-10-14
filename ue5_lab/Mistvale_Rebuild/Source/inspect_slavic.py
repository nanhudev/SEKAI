"""Read geometry dimensions of the already imported Fab architecture family."""
import json
from pathlib import Path
import unreal

root = "/Game/Fab/SlavicLite"
names = [p for p in unreal.EditorAssetLibrary.list_assets(root, recursive=False)
         if p.endswith("_LOD0.EA03_Town_Building_Administrative__01a_LOD0")
         or "_LOD0." in p]
subsystem = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
rows = []
for path in names:
    mesh = unreal.load_asset(path)
    if not isinstance(mesh, unreal.StaticMesh):
        continue
    actor = subsystem.spawn_actor_from_class(unreal.StaticMeshActor, unreal.Vector(0,0,0))
    actor.static_mesh_component.set_static_mesh(mesh)
    centre, extent = actor.get_actor_bounds(False)
    materials = [str(item.get_editor_property("material_interface"))
                 for item in mesh.get_editor_property("static_materials")]
    rows.append({"asset": path, "name": mesh.get_name(),
                 "size_m": [round(v*2/100,3) for v in (extent.x, extent.y, extent.z)],
                 "centre_m": [round(v/100,3) for v in (centre.x, centre.y, centre.z)],
                 "materials": materials})
    subsystem.destroy_actor(actor)
out = Path(__file__).with_name("slavic_mesh_dimensions.json")
out.write_text(json.dumps(rows, indent=2), encoding="utf-8")
print("SLAVIC_MESHES", len(rows), "RESULT", out)
