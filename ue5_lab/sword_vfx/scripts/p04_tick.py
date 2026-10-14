"""Probe: does a full editor session tick, so compile-wait tools can complete?"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))
import unreal

OUT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p04_tick.txt')


def w(s):
    with open(OUT, "a", encoding="utf-8") as fh:
        fh.write(str(s) + "\n")
    print(s)


open(OUT, "w", encoding="utf-8").close()

state = {"n": 0, "handle": None}


def on_tick(delta):
    state["n"] += 1
    n = state["n"]
    if n in (1, 2, 10, 60, 120):
        w("tick %d  dt=%.4f" % (n, delta))
    if n >= 130:
        unreal.unregister_slate_post_tick_callback(state["handle"])
        w("TOTAL TICKS = %d" % n)
        w("quit")
        unreal.SystemLibrary.quit_editor()


state["handle"] = unreal.register_slate_post_tick_callback(on_tick)
w("registered slate post tick callback")
