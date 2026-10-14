from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
from pathlib import Path
root=Path(str(_SEKAI_ROOT / 'environment_production'))
status='''LATEST AUTHORITATIVE CHECKPOINT (2026-10-14): UE v071 imported and captured at six fixed +33 diagnostic/route views. Six views inspected; NOT reference quality. v065 continuous road; v067 world-projected slope grass/rock; v068 two additional houses; v071 ground-reaching foundation/porch/step supports and UE water material trial. v066/v070 imports failed, v069 source support transform unsafe; do not use them. Whole goal remains ACTIVE: vegetation/buildings/tree/terrain, estate/high bridge, clouds and independently verified water all remain. Clouds still absent in primary views. USER OVERRIDE: user explicitly authorized Godot exploration integration NOW in the latest turn, superseding older after-UE-only timing. Main menu exploration loads StarterVillagePlayable.tscn via main_flow.gd; preserves old MistvalePlayable and all combat code. Current Godot source res://models/starter_village/v071/ includes corrected glTF and 29-body collision bake, original village axes converted (x,z,-y). v068b real entrance movement ~9.49m, 14 route floor rays, menu entry/pause/resume/return passed. v068b isolated native water-time captures show water changes with static-region delta0: E:/SEKAI_Environment_Runtime/GodotReview/v068b/. Wave realism, shoreline penetration, whole route, new-house full close review and UE independent flow remain open. Runtime tests must unload scene in process frames before quit; immediate physics-frame teardown crashed. Existing zero-target/look_at and resource residual warnings remain; don't call tests clean. Desktop UE tour default v067 until later prepared/verified update. Report Terrain/v071/ART_CHECKPOINT.md. Preserve E-drive checkpoint Junctions and licensed source textures. No new agents/threads/timers/auth changes/reference generation.

'''
for path in [root/'Source/RESUME_BRIEF.md',root/'Terrain/CURRENT_STATE.md']:
    text=path.read_text(encoding='utf-8')
    assert 'LATEST AUTHORITATIVE CHECKPOINT (2026-10-14)' not in text
    path.write_text(status+text,encoding='utf-8')
