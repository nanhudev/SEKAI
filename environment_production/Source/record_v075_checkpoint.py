from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
from pathlib import Path
import shutil
root=Path(str(_SEKAI_ROOT / 'environment_production'))
shutil.copy2(str(_SEKAI_RUNTIME / 'water_graph_pins.json'),root/'Terrain/v075/water_graph_pins.json')
note='''LATEST AUTHORITATIVE CHECKPOINT (2026-10-14 v075): fixed actual UE water UV flow connection. Native pin preflight proves TextureSample input is UVs, not Coordinates; old Panner->sample calls silently returnedfalse. Time->Panner was valid. v075 uses UVs and asserts water clock/normal/foam/fall connections, imported and six fixed views captured/inspected; geometry/cameras/light preserved v074. Water_Clock_Probe repeated phase waterdelta0, changed phase waterdelta7.33/10.50/9.02 but background4.6-5; Water_Viewport_Probe piloted camera improves background to.55-.89, repeated waterdelta.091 versus changed7.34/10.50/9.02. This supports genuine rendered water-time response. Strict existing static-ROI<.2 checker remains FALSE; do not relax to make it green or call whole water/shoreline accepted. Diagnostic render console changes not saved. Report Terrain/v075/ART_CHECKPOINT.md, graph pins receipt there. Full goal ACTIVE: reference visuals still bare, houses/vegetation/tree/terrain/count estate/high bridge/clouds/water/shoreline/full-route all open. Godot menu remains v071 with prior native water and movement/menu receipts; v072-v075 art not synced. UE desktop tour default v067. Latest user permits Godot integration now, superseding older wait-for-UE timing. No agents/threads/timers/auth/reference generation.

'''
for p in [root/'Terrain/CURRENT_STATE.md',root/'Source/RESUME_BRIEF.md']:
    text=p.read_text(encoding='utf-8');assert note.splitlines()[0] not in text
    p.write_text(note+text,encoding='utf-8')
