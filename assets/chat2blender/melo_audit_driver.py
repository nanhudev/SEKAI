"""Driver for the MELO audit, so the batch range lives in a config file.

Kept separate from melo_audit.py because the MCP socket executes one code payload
per call: a driver that reads a JSON config means a batch can be re-run or
re-scoped by editing a file rather than by re-quoting a code string.
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import importlib.util
import json
import os
import traceback

CFG = str(_SEKAI_ROOT / 'assets_source/review/melo/melo_audit_cfg.json')
MODULE = str(_SEKAI_ROOT / 'assets/chat2blender/melo_audit.py')

cfg = json.load(open(CFG, encoding="utf-8"))

spec = importlib.util.spec_from_file_location("melo_audit", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

mode = cfg.get("mode", "run")

try:
    if mode == "run":
        views = None
        if cfg.get("views"):
            views = []
            for name, vec in cfg["views"]:
                views.append((name, mod.Vector(vec)))
        n = mod.run_audit(cfg.get("from", 0), cfg.get("to"), views=views,
                          prefix=cfg.get("prefix", ""))
        print("DRIVER run -> %d tiles" % n)
    elif mode == "report":
        mod.write_audit_report()
    elif mode == "objects":
        mod.dump_objects(cfg.get("from", 0), top=cfg.get("top", 45))
    elif mode == "close":
        print("DRIVER close -> active scene %s" % mod.close_audit())
    elif mode == "probe":
        # Question-answering mode: report what the module can see, without rendering.
        entries = json.load(open(mod.INDEX, encoding="utf-8"))
        print("DRIVER probe -> %d glb indexed, active scene %s"
              % (len(entries), mod.bpy.context.window.scene.name))
        print("  engine:", mod.bpy.context.scene.render.engine)
        print("  view_transform:", mod.bpy.context.scene.view_settings.view_transform)
        print("  first:", entries[0]["rel"])
        print("  last :", entries[-1]["rel"])
    else:
        print("DRIVER unknown mode %r" % mode)
except Exception as exc:
    print("DRIVER ERROR %s" % exc)
    traceback.print_exc()
finally:
    try:
        where = mod.flush_log()
        print("DRIVER log -> %s (%d lines)" % (where, len(mod._rows)))
    except Exception:
        pass
