mod = obj.modifiers.new(name="ENV01_Chamfer", type='BEVEL')
mod.width = float(width)
mod.segments = int(segments)
mod.limit_method = 'ANGLE'
mod.angle_limit = math.radians(20.0)

bpy.ops.object.select_all(action='DESELECT')
obj.select_set(True)
bpy.context.view_layer.objects.active = obj

try:
    bpy.ops.object.modifier_apply(modifier=mod.name)
except Exception as exc:
    raise RuntimeError(
        f"ENV-01: failed applying bevel to {obj.name}: {exc}"
    ) from exc