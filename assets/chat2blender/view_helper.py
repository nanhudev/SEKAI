"""Producer viewport helper. Frames an asset so the screenshot is readable.

Not modelling code: it removes the default startup cube and points the visible
3D viewport at the requested objects with material shading on.

Override the target list with a leading comment, e.g.:
    # VIEW_TARGETS: Blade,Guard,Grip,Pommel
"""

import bpy

DEFAULT_TARGETS = ["Blade", "Guard", "Grip", "Pommel"]
OPTIONAL_DROP = ["Cube", "Light"]

targets = [bpy.data.objects[t] for t in DEFAULT_TARGETS if t in bpy.data.objects]

# Remove the startup cube so it never sits inside the asset.
for name in OPTIONAL_DROP:
    obj = bpy.data.objects.get(name)
    if obj is not None and name == "Cube":
        bpy.data.objects.remove(obj, do_unlink=True)

if not targets:
    print("view_helper: no target objects present")
else:
    for area in bpy.context.screen.areas:
        if area.type != 'VIEW_3D':
            continue
        area.spaces.active.shading.type = 'MATERIAL'
        for region in area.regions:
            if region.type != 'WINDOW':
                continue
            with bpy.context.temp_override(area=area, region=region):
                bpy.ops.object.select_all(action='DESELECT')
                for obj in targets:
                    obj.select_set(True)
                bpy.context.view_layer.objects.active = targets[0]
                try:
                    bpy.ops.view3d.view_selected()
                except Exception as exc:
                    print("view_selected failed:", exc)
                area.spaces.active.region_3d.view_perspective = 'PERSP'
        area.tag_redraw()

    names = ", ".join(o.name for o in targets)
    print("view_helper: framed " + names)
