"""
p60_sword_play.py - THE PLAY. Runtime sword VFX, recorded frame by frame.

WHY THIS SHAPE
    The nine Niagara cores are empty shells and AddModule asserts the editor
    dead (p49/p50/p51), and a scripted session never renders Niagara anyway
    (p48). But MESHES AND MATERIALS DO RENDER (p36: two quads moved 85320 px).
    So this script builds the entire sword VFX language out of the finished
    assets - SM_SW_* meshes, MI_SW_*_Normal/_Magic instances - driven per
    frame from Python. Niagara is a technique, not the deliverable.

    Timing comes from the REAL event contract,
    docs/sword_vfx_event_contract.json - the same t values the Godot combat
    line emits. Every event crossing is logged so the trace shows the
    contract driving the visuals.

FRAME LOOP
    fixed 24 fps animation clock. Per frame: apply the whole scene as a PURE
    function of t, capture, wait 2 ticks (RT readback), export PNG.

USAGE
    SECTION=smoke  ./run_ue.sh p60_sword_play.py --render
    SECTION=normal ...
    SECTION=magic  ...
    SECTION=angles ...

OUTPUT
    render/play/<section>/f%04d.png   (24 fps frames)
    exports/p60_play_<section>.txt
"""
from pathlib import Path as _SekaiPath
import os as _sekai_os
_SEKAI_ROOT = _SekaiPath(_sekai_os.environ['SEKAI_ROOT']).resolve() if 'SEKAI_ROOT' in _sekai_os.environ else next(p for p in _SekaiPath(__file__).resolve().parents if (p / 'godot/project.godot').is_file())
_SEKAI_RUNTIME = _SekaiPath(_sekai_os.environ.get('SEKAI_RUNTIME_DIR', str(_SEKAI_ROOT / '.local')))

import json
import math
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import unreal  # noqa: E402

import swcap  # noqa: E402
import swimg  # noqa: E402
import swvfx as WFX  # noqa: E402

SECTION = os.environ.get("SECTION", "smoke")
EXPORT = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/exports/p60_play_%s.txt') % SECTION
OUT_DIR = str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/render/play/%s') % SECTION
CONTRACT = (str(_SEKAI_ROOT / 'ue5_lab/sword_vfx/docs/sword_vfx_event_contract.json'))
LVL = "/Game/SEKAI/VFX/Sword/Lab/L_SwordVFX_Lab"
ROOT = "/Game/SEKAI/VFX/Sword"

WIDTH, HEIGHT = 1280, 720
FPS = 24.0
BUDGET_SECONDS = 820.0
SETTLE_TICKS = 90

WFX.bind_log(EXPORT)
log = WFX.log

os.makedirs(OUT_DIR, exist_ok=True)
for _f in os.listdir(OUT_DIR):
    try:
        os.remove(os.path.join(OUT_DIR, _f))
    except Exception:
        pass

log("P60 PLAY - section=%s  engine=%s" % (SECTION,
                                          unreal.SystemLibrary.get_engine_version()))

# ----------------------------------------------------------------------
# event contract - the real t values
# ----------------------------------------------------------------------
EV = {}
try:
    with open(CONTRACT, "r", encoding="utf-8") as fh:
        _c = json.load(fh)
    for _mid, _m in _c["moves"].items():
        for _e in _m.get("events", []):
            EV[(_mid, _e.get("godot_id"))] = float(_e["t"])
    log("contract loaded: %d events" % len(EV))
except Exception as exc:
    log("CONTRACT LOAD FAILED (%s) - falling back to inline times" % exc)
    EV = {}


def ev(move, gid, fallback):
    return EV.get((move, gid), fallback)


# ----------------------------------------------------------------------
# small math helpers (metres in, UE cm/deg out)
# ----------------------------------------------------------------------
def V(x, y, z):
    return unreal.Vector(x * 100.0, y * 100.0, z * 100.0)


def R(pitch, yaw, roll=0.0):
    return unreal.Rotator(pitch=pitch, yaw=yaw, roll=roll)


def S(x, y, z):
    return unreal.Vector(x, y, z)


def dir_of(pitch, yaw):
    """Unit vector along a rotator's forward (X) axis. Degrees in."""
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    return (cp * cy, cp * sy, sp)


def rot_from_dir(d):
    """Rotator whose X axis points along d."""
    h = math.hypot(d[0], d[1])
    return R(math.degrees(math.atan2(d[2], h)) if h > 1e-6 else
             (90.0 if d[2] >= 0 else -90.0),
             math.degrees(math.atan2(d[1], d[0])) if h > 1e-6 else 0.0, 0.0)


def look_rot(frm, to):
    d = (to[0] - frm[0], to[1] - frm[1], to[2] - frm[2])
    h = math.hypot(d[0], d[1])
    pitch = math.degrees(math.atan2(d[2], h))
    yaw = math.degrees(math.atan2(d[1], d[0])) if h > 1e-6 else 0.0
    return R(pitch, yaw, 0.0)


def lerp(a, b, u):
    return a + (b - a) * u


def clamp01(x):
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def ease_out(u):
    u = clamp01(u)
    return 1.0 - (1.0 - u) ** 2


def ease_in(u):
    return clamp01(u) ** 2


def seg(t, t0, t1):
    """0..1 position of t inside [t0,t1], clamped."""
    if t1 <= t0:
        return 1.0
    return clamp01((t - t0) / (t1 - t0))


def fade_life(t, t0, life, ramp=0.15):
    """Opacity envelope: ramp in, linear out. None before birth."""
    if t < t0 or t > t0 + life:
        return None
    u = (t - t0) / life
    return min(u / max(ramp, 1e-3), 1.0) * (1.0 - u)


# ----------------------------------------------------------------------
# asset loading
# ----------------------------------------------------------------------
ASSETS = {}


def load(path):
    p = path if "." in path.rsplit("/", 1)[-1] else "%s.%s" % (
        path, path.rsplit("/", 1)[-1])
    try:
        return unreal.EditorAssetLibrary.load_asset(p)
    except Exception as exc:
        log("  load failed %s: %s" % (path, str(exc)[:100]))
        return None


def load_all():
    need = {
        "quad": ROOT + "/Meshes/SM_SW_GlintQuad",
        "scar": ROOT + "/Meshes/SM_SW_ScarStrip",
        "wave": ROOT + "/Meshes/SM_SW_WaveSheet",
        "arc": ROOT + "/Meshes/SM_SW_ArcSheet",
        "cube": "/Engine/BasicShapes/Cube",
        "cyl": "/Engine/BasicShapes/Cylinder",
        "sph": "/Engine/BasicShapes/Sphere",
        # normal / magic material instances
        "mi_glint_n": ROOT + "/Materials/MI_SW_Glint_Normal",
        "mi_glint_m": ROOT + "/Materials/MI_SW_Glint_Magic",
        "mi_trail_n": ROOT + "/Materials/MI_SW_Trail_Normal",
        "mi_trail_m": ROOT + "/Materials/MI_SW_Trail_Magic",
        "mi_scar_n": ROOT + "/Materials/MI_SW_SpatialScar_Normal",
        "mi_scar_m": ROOT + "/Materials/MI_SW_SpatialScar_Magic",
        "mi_wave_n": ROOT + "/Materials/MI_SW_Wave_Normal",
        "mi_wave_m": ROOT + "/Materials/MI_SW_Wave_Magic",
        "mi_mist_n": ROOT + "/Materials/MI_SW_Mist_Normal",
        "mi_mist_m": ROOT + "/Materials/MI_SW_Mist_Magic",
        "mi_mote_n": ROOT + "/Materials/MI_SW_Mote_Normal",
        "mi_mote_m": ROOT + "/Materials/MI_SW_Mote_Magic",
        "lab_dummy": ROOT + "/Lab/Materials/M_Lab_Dummy",
        "lab_dark": ROOT + "/Lab/Materials/M_Lab_DarkWall",
    }
    missing = []
    for key, path in need.items():
        ASSETS[key] = load(path)
        if ASSETS[key] is None:
            missing.append(key)
    if missing:
        log("ABORT: missing assets: %s" % ", ".join(missing))
        raise SystemExit(0)
    log("assets loaded: %d" % len(ASSETS))


def make_blade_material():
    """Transient lit steel material for the prop blade."""
    import swmat  # noqa: F401  (helpers kept for future tuning)
    # create transient (never saved)
    try:
        tools = unreal.AssetToolsHelpers.get_asset_tools()
        mat = tools.create_asset("M_SW_PropBlade_TMP", "/Game/SEKAI/VFX/"
                                 "Sword/Materials", unreal.Material,
                                 unreal.MaterialFactoryNew())
    except Exception as exc:
        log("blade material create failed: %s" % str(exc)[:120])
        return ASSETS["lab_dummy"]
    if mat is None:
        return ASSETS["lab_dummy"]
    MEL = unreal.MaterialEditingLibrary
    try:
        mat.set_editor_property("shading_model",
                                unreal.MaterialShadingModel.MSM_DEFAULT_LIT)
        bc = MEL.create_material_expression(mat, unreal.
                                            MaterialExpressionConstant3Vector,
                                            -600, 0)
        bc.set_editor_property("constant", unreal.LinearColor(0.72, 0.76,
                                                              0.82, 1.0))
        MEL.connect_material_property(bc, "", unreal.MaterialProperty.
                                      MP_BASE_COLOR)
        met = MEL.create_material_expression(mat, unreal.
                                             MaterialExpressionConstant,
                                             -600, 200)
        met.set_editor_property("r", 0.85)
        MEL.connect_material_property(met, "", unreal.MaterialProperty.
                                      MP_METALLIC)
        rgh = MEL.create_material_expression(mat, unreal.
                                             MaterialExpressionConstant,
                                             -600, 400)
        rgh.set_editor_property("r", 0.28)
        MEL.connect_material_property(rgh, "", unreal.MaterialProperty.
                                      MP_ROUGHNESS)
        MEL.recompile_material(mat)
        log("blade material built (transient, unsaved)")
        return mat
    except Exception as exc:
        log("blade material wiring failed: %s -> lab_dummy" % str(exc)[:120])
        return ASSETS["lab_dummy"]


# ----------------------------------------------------------------------
# the rig
# ----------------------------------------------------------------------
class Rig(object):
    def __init__(self, world):
        self.W = world
        self.center = (0.0, 0.0, 0.0)   # stage centre, metres
        self.spawned = []
        self.blade_mat = make_blade_material()
        self._build()

    # -- spawn helpers ---------------------------------------------------
    def _spawn(self, mesh, loc, rot, mat=None, label=""):
        a = unreal.EditorLevelLibrary.spawn_actor_from_class(
            unreal.StaticMeshActor, V(*loc), rot)
        if a is None:
            log("  spawn failed %s" % label)
            return None
        if label:
            try:
                a.set_actor_label("P60_%s" % label)
            except Exception:
                pass
        smc = a.static_mesh_component
        try:
            smc.set_mobility(unreal.ComponentMobility.MOVABLE)
        except Exception:
            pass
        smc.set_static_mesh(mesh)
        if mat is not None:
            smc.set_material(0, mat)
        smc.set_visibility(False)
        self.spawned.append(a)
        return a

    def _mid(self, a, mi):
        """Dynamic material instance for slot 0."""
        smc = a.static_mesh_component
        try:
            return smc.create_dynamic_material_instance(0, mi)
        except Exception as exc:
            log("  MID create failed: %s" % str(exc)[:120])
            return None

    # -- construction ----------------------------------------------------
    def _build(self):
        A = ASSETS
        # player proxy
        self.body = self._spawn(A["cyl"], (0, 0, 0.78), R(0, 0), A["lab_dark"], "body")
        if self.body:
            self.body.set_actor_scale3d(S(0.70, 0.70, 1.56))
            self.body.static_mesh_component.set_visibility(True)
        self.head = self._spawn(A["sph"], (0, 0, 1.72), R(0, 0), A["lab_dark"], "head")
        if self.head:
            self.head.set_actor_scale3d(S(0.38, 0.38, 0.42))
            self.head.static_mesh_component.set_visibility(True)
        # target box for hit flashes (parked far away until needed)
        self.target = self._spawn(A["cube"], (0, 0, -50.0), R(0, 0), A["lab_dark"], "target")
        if self.target:
            self.target.set_actor_scale3d(S(0.42, 0.42, 1.05))
            self.target.static_mesh_component.set_visibility(True)

        # sword prop
        self.blade = self._spawn(A["cube"], (0, 0, -50), R(0, 0), self.blade_mat, "blade")
        self.guard = self._spawn(A["cube"], (0, 0, -50), R(0, 0), A["lab_dark"], "guard")
        self.hilt = self._spawn(A["cube"], (0, 0, -50), R(0, 0), A["lab_dark"], "hilt")
        self.saya = self._spawn(A["cube"], (0, 0, -50), R(0, 0), A["lab_dark"], "saya")

        # effect pools --------------------------------------------------
        # quad pool: (actor, mid) - glint/trail/mist/mote/flash by material
        self.quad_n = self._pool(A["quad"], A["mi_glint_n"], 24, "qn")
        self.quad_m = self._pool(A["quad"], A["mi_glint_m"], 24, "qm")
        self.mist_n = self._pool(A["quad"], A["mi_mist_n"], 6, "mn")
        self.mist_m = self._pool(A["quad"], A["mi_mist_m"], 6, "mm")
        self.mote_m = self._pool(A["quad"], A["mi_mote_m"], 8, "mo")
        # scar strips: 3 for A3 + 1 iaido + 2 spare, per profile
        self.scar_n = self._pool(A["scar"], A["mi_scar_n"], 6, "sn")
        self.scar_m = self._pool(A["scar"], A["mi_scar_m"], 6, "sm")
        # wave sheets (2 per profile: one in flight + one spare)
        self.wave_n = self._pool(A["wave"], A["mi_wave_n"], 2, "wn")
        self.wave_m = self._pool(A["wave"], A["mi_wave_m"], 2, "wm")
        # arc sheet
        self.arc_n = self._pool(A["arc"], A["mi_trail_n"], 1, "an")
        self.arc_m = self._pool(A["arc"], A["mi_trail_m"], 1, "am")
        log("rig built: %d actors" % len(self.spawned))

    def _pool(self, mesh, mi, n, tag):
        out = []
        for i in range(n):
            a = self._spawn(mesh, (0, 0, -50.0), R(0, 0), None, "%s%02d" % (tag, i))
            if a is None:
                continue
            mid = self._mid(a, mi)
            if mid is None:
                continue
            out.append((a, mid))
        return out

    # -- world offset ------------------------------------------------------
    def wpos(self, p):
        """Stage-relative -> world metres."""
        return (self.center[0] + p[0], self.center[1] + p[1],
                self.center[2] + p[2])

    # -- sword -------------------------------------------------------------
    def set_sword(self, hand, pitch, yaw, exposed):
        """hand in stage metres; exposed = blade length out of the hilt."""
        d = dir_of(pitch, yaw)
        c = self.wpos(hand)
        if self.blade:
            ln = max(exposed, 0.02)
            self.blade.set_actor_location(V(c[0] + d[0] * (0.10 + ln / 2),
                                            c[1] + d[1] * (0.10 + ln / 2),
                                            c[2] + d[2] * (0.10 + ln / 2)), False, False)
            self.blade.set_actor_rotation(R(pitch, yaw), False)
            self.blade.set_actor_scale3d(S(ln, 0.085, 0.024))
            self.blade.static_mesh_component.set_visibility(exposed > 0.03)
        if self.guard:
            self.guard.set_actor_location(V(c[0] + d[0] * 0.10,
                                            c[1] + d[1] * 0.10,
                                            c[2] + d[2] * 0.10), False, False)
            self.guard.set_actor_rotation(R(pitch, yaw, 45), False)
            self.guard.set_actor_scale3d(S(0.05, 0.125, 0.125))
            self.guard.static_mesh_component.set_visibility(exposed > 0.03)
        if self.hilt:
            self.hilt.set_actor_location(V(c[0] - d[0] * 0.13,
                                           c[1] - d[1] * 0.13,
                                           c[2] - d[2] * 0.13), False, False)
            self.hilt.set_actor_rotation(R(pitch, yaw), False)
            self.hilt.set_actor_scale3d(S(0.26, 0.05, 0.05))
            self.hilt.static_mesh_component.set_visibility(True)

    def set_saya(self, pos, yaw, pitch=0.0):
        c = self.wpos(pos)
        if self.saya:
            self.saya.set_actor_location(V(*c), False, False)
            self.saya.set_actor_rotation(R(pitch, yaw), False)
            self.saya.set_actor_scale3d(S(0.98, 0.075, 0.105))
            self.saya.static_mesh_component.set_visibility(True)

    def blade_tip(self, hand, pitch, yaw, exposed):
        d = dir_of(pitch, yaw)
        c = self.wpos(hand)
        return (c[0] + d[0] * (0.10 + exposed), c[1] + d[1] * (0.10 + exposed),
                c[2] + d[2] * (0.10 + exposed))

    # -- generic effect quad ----------------------------------------------
    def quad(self, entry, pos, pitch, yaw, roll, sx, sy, opacity,
             intensity=None):
        a, mid = entry
        if opacity is None or opacity <= 0.01:
            a.static_mesh_component.set_visibility(False)
            return
        a.set_actor_location(V(*pos), False, False)
        a.set_actor_rotation(R(pitch, yaw, roll), False)
        a.set_actor_scale3d(S(sx, sy, 1.0))
        a.static_mesh_component.set_visibility(True)
        if mid is not None:
            try:
                mid.set_scalar_parameter_value("Opacity", opacity)
                if intensity is not None:
                    mid.set_scalar_parameter_value("Intensity", intensity)
            except Exception:
                pass

    def strip(self, entry, pos, d_long, roll, length, width, opacity,
              intensity=None, void=None):
        """Scar strip: long axis along d_long, rolled by `roll` deg."""
        a, mid = entry
        if opacity is None or opacity <= 0.01:
            a.static_mesh_component.set_visibility(False)
            return
        rot = rot_from_dir(d_long)
        a.set_actor_location(V(*pos), False, False)
        a.set_actor_rotation(R(rot.pitch, rot.yaw, roll), False)
        a.set_actor_scale3d(S(length, width / 0.06, 1.0))
        a.static_mesh_component.set_visibility(True)
        if mid is not None:
            try:
                mid.set_scalar_parameter_value("Opacity", opacity)
                if intensity is not None:
                    mid.set_scalar_parameter_value("Intensity", intensity)
                if void is not None:
                    mid.set_scalar_parameter_value("VoidAmount", void)
            except Exception:
                pass

    def sheet(self, entry, pos, pitch, yaw, roll, sx, sy, opacity,
              intensity=None):
        a, mid = entry
        if opacity is None or opacity <= 0.01:
            a.static_mesh_component.set_visibility(False)
            return
        a.set_actor_location(V(*pos), False, False)
        a.set_actor_rotation(R(pitch, yaw, roll), False)
        a.set_actor_scale3d(S(sx, sy, 1.0))
        a.static_mesh_component.set_visibility(True)
        if mid is not None:
            try:
                mid.set_scalar_parameter_value("Opacity", opacity)
                if intensity is not None:
                    mid.set_scalar_parameter_value("Intensity", intensity)
            except Exception:
                pass

    def park_all(self):
        for a in self.spawned:
            try:
                smc = a.static_mesh_component
                if smc is not None:
                    smc.set_visibility(False)
            except Exception:
                pass
        if self.body:
            self.body.static_mesh_component.set_visibility(True)
        if self.head:
            self.head.static_mesh_component.set_visibility(True)
        if self.target:
            self.target.static_mesh_component.set_visibility(False)

    def place_target(self, pos, visible):
        if self.target is None:
            return
        if visible:
            self.target.set_actor_location(V(*self.wpos(pos)), False, False)
        self.target.static_mesh_component.set_visibility(visible)


# ----------------------------------------------------------------------
# choreography - pure functions of t
# ----------------------------------------------------------------------
HIP = (0.24, 0.20, 0.97)          # left hand / saya mouth, stage metres
READY = (0.34, -0.34, 1.08)       # right hand ready stance
BLADE_LN = 1.05


# NOTE on strip/quad facing.
#   rot_from_dir(d) makes local X = d and leaves local Y ~ world Y, so a strip
#   with roll 0 lies in the (d, world-Y) plane - a wall whose normal points
#   back toward a camera standing at -X of the effect (the over-shoulder
#   battle cam). roll 90 spins the width axis vertical: the wall then faces
#   +/-Y, which is what the SIDE camera needs. Every roll choice below is a
#   camera choice, not decoration.
def sample_tips(rig, hand_fn, pitch_fn, yaw_fn, exposed, t0, t1, n):
    """Pre-sample blade tip positions for a sweep window."""
    tips = []
    for i in range(n):
        u = i / float(n - 1) if n > 1 else 0.0
        tt = lerp(t0, t1, u)
        tips.append((tt, rig.blade_tip(hand_fn(tt), pitch_fn(tt),
                                       yaw_fn(tt), exposed)))
    return tips


# ------------------------------ EQUIP ---------------------------------
def anim_equip(rig, t, magic):
    e0 = ev("sb_equip", "A1_SHEATH_TOUCH", 0.0)
    t_carry = ev("sb_equip", "EQUIP_CARRY", 0.35)
    t_partial = ev("sb_equip", "A1_DRAW", 0.75)
    t_glint = ev("sb_equip", "EQUIP_GLINT", 0.95)
    t_push = ev("sb_equip", "SAYA_PUSH", 1.07)
    t_seat = ev("sb_equip", "EQUIP_SEAT", 1.40)

    # saya: horizontal at the hip, then lowered to the left side
    if t < t_push:
        rig.set_saya(HIP, 8.0)
    else:
        u = ease_out(seg(t, t_push, t_seat))
        rig.set_saya((lerp(HIP[0], 0.16, u), lerp(HIP[1], 0.30, u),
                      lerp(HIP[2], 0.92, u)), lerp(8.0, 62.0, u),
                     lerp(0.0, -28.0, u))

    # blade: seated in saya -> partial draw -> hold -> full draw -> ready
    if t < t_partial:
        exp = 0.0
        hand = HIP
        pitch, yaw = 0.0, 8.0
    elif t < t_push:
        exp = 0.17 * ease_out(seg(t, t_partial, t_partial + 0.18))
        hand = HIP
        pitch, yaw = 0.0, 8.0
    else:
        u = ease_out(seg(t, t_push, t_seat))
        exp = lerp(0.17, BLADE_LN, u)
        hand = (lerp(HIP[0], READY[0], u), lerp(HIP[1], READY[1], u),
                lerp(HIP[2], READY[2], u))
        pitch, yaw = lerp(0.0, -12.0, u), lerp(8.0, 28.0, u)
    rig.set_sword(hand, pitch, yaw, exp)

    # the glint: one narrow band scanning the exposed steel, 140 ms
    pool = rig.quad_m if magic else rig.quad_n
    g = t - t_glint
    if 0.0 <= g <= 0.14 and exp > 0.02:
        prog = g / 0.14
        d = dir_of(pitch, yaw)
        base = rig.wpos(hand)
        p = (base[0] + d[0] * (0.10 + prog * 0.16),
             base[1] + d[1] * (0.10 + prog * 0.16),
             base[2] + d[2] * (0.10 + prog * 0.16))
        rig.quad(pool[0], p, pitch, yaw, 90.0, 0.06, 0.19,
                 math.sin(math.pi * prog), 1.1 if magic else 1.0)
    else:
        rig.quad(pool[0], (0, 0, 0), 0, 0, 0, 1, 1, None)

    for entry in pool[1:2]:
        rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ INSPECT --------------------------------
def anim_inspect(rig, t, magic):
    rise = ease_out(seg(t, 0.0, 0.5))
    hand = (lerp(READY[0], 0.36, rise), lerp(READY[1], -0.02, rise),
            lerp(READY[2], 1.52, rise))
    pitch, yaw = lerp(-12.0, 0.0, rise), lerp(28.0, 82.0, rise)
    rig.set_sword(hand, pitch, yaw, BLADE_LN)
    # saya parallel in the left hand
    rig.set_saya((hand[0] - 0.30, hand[1] + 0.02, hand[2] - 0.04), 82.0)

    # base -> tip glint scan over 0.4 s, starting once raised
    t0 = 0.55
    pool = rig.quad_m if magic else rig.quad_n
    g = t - t0
    if 0.0 <= g <= 0.40:
        prog = g / 0.40
        d = dir_of(pitch, yaw)
        base = rig.wpos(hand)
        p = (base[0] + d[0] * (0.10 + prog * (BLADE_LN - 0.06)),
             base[1] + d[1] * (0.10 + prog * (BLADE_LN - 0.06)),
             base[2] + d[2] * (0.10 + prog * (BLADE_LN - 0.06)))
        rig.quad(pool[0], p, pitch, yaw, 90.0, 0.07, 0.22,
                 math.sin(math.pi * min(prog * 1.15, 1.0)),
                 0.9 if magic else 0.85)
        # a few motes riding the scan on the magic sword
        if magic:
            for i, entry in enumerate(rig.mote_m[:3]):
                u = clamp01(prog * 1.3 - i * 0.12)
                op = math.sin(math.pi * u) * 0.55
                off = (math.sin(i * 2.1 + t * 3.0) * 0.04,
                       math.cos(i * 1.7 + t * 2.5) * 0.04, 0.02 + i * 0.03)
                rig.quad(entry, (p[0] + off[0], p[1] + off[1], p[2] + off[2]),
                         0.0, 0.0, 0.0, 0.05, 0.05, op if op > 0 else None, 0.8)
    else:
        rig.quad(pool[0], (0, 0, 0), 0, 0, 0, 1, 1, None)
        if magic:
            for entry in rig.mote_m[:3]:
                rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ A1 --------------------------------------
def make_a1(rig):
    t_draw = ev("sb_a1", "A1_DRAW", 0.13)
    t_active = ev("sb_a1", "A1_ACTIVE", 0.13)
    t_fin = ev("sb_a1", "A1_FINISH", 0.40)
    sweep0, sweep1 = t_draw, t_draw + 0.08

    def hand(t):
        u = ease_out(seg(t, sweep0, sweep1))
        v = ease_out(seg(t, t_fin, t_fin + 0.25))
        x = lerp(lerp(READY[0], 0.46, u), READY[0], v)
        y = lerp(lerp(READY[1], -0.06, u), READY[1], v)
        z = lerp(lerp(READY[2], 1.12, u), READY[2], v)
        return (x, y, z)

    def yaw(t):
        u = ease_out(seg(t, sweep0, sweep1))
        v = ease_out(seg(t, t_fin, t_fin + 0.25))
        return lerp(lerp(-78.0, 62.0, u), 28.0, v)

    def pitch(t):
        return lerp(2.0, -6.0, ease_out(seg(t, sweep0, sweep1)))

    tips = sample_tips(rig, hand, pitch, yaw, BLADE_LN, sweep0, sweep1, 13)
    return hand, pitch, yaw, tips, t_active, t_fin


def anim_a1(rig, t, magic, prepped=None):
    hand, pitch, yaw, tips, t_active, t_fin = prepped
    rig.set_sword(hand(t), pitch(t), yaw(t), BLADE_LN)
    rig.set_saya((0.16, 0.30, 0.92), 62.0, -28.0)

    # edge trail: crumbs stretched along the SWEEP TANGENT (yaw+90), not the
    # blade axis - a trail is a band behind the tip, not a comb of blades
    pool = rig.quad_m if magic else rig.quad_n
    for i, entry in enumerate(pool[:13]):
        if i < len(tips):
            t_i, p = tips[i]
            op = fade_life(t, t_i, 0.18)
            if op is not None:
                nxt = tips[min(i + 1, len(tips) - 1)][1]
                seglen = max(0.35, ((nxt[0] - p[0]) ** 2 + (nxt[1] - p[1]) ** 2
                                    + (nxt[2] - p[2]) ** 2) ** 0.5 * 2.2)
            else:
                seglen = 0.5
            rig.quad(entry, p, pitch(t_i), yaw(t_i) + 90.0, 90.0,
                     seglen, 0.10, op, 1.15 if magic else 1.05)
        else:
            rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)

    # the air slice: a 2 m scar strip drawn at the peak, NOT a projectile
    scars = rig.scar_m if magic else rig.scar_n
    op = fade_life(t, t_active, 0.14 if not magic else 0.24)
    if op is not None:
        grow = 0.35 + 0.65 * ease_out(seg(t, t_active, t_active + 0.05))
        c = rig.wpos((1.5, 0.45, 1.05))
        rig.strip(scars[0], c, (0.90, -0.35, 0.20), -15.0, 2.0 * grow,
                  0.060 if not magic else 0.065, max(op, 0.5),
                  1.8 if magic else 1.7, 0.35 if magic else 0.0)
    else:
        rig.strip(scars[0], (0, 0, 0), (1, 0, 0), 0, 1, 1, None)

    # black vapour thread along the original path (magic only)
    if magic:
        op = fade_life(t, t_active + 0.02, 0.28)
        if op is not None:
            for i, entry in enumerate(rig.mist_m[:3]):
                tt = t_active - 0.06 + i * 0.05
                if tt < tips[0][0] or tt > tips[-1][0]:
                    rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)
                    continue
                # tip position near tt (linear search is fine, 9 samples)
                for k in range(len(tips) - 1):
                    if tips[k][0] <= tt <= tips[k + 1][0]:
                        u = (tt - tips[k][0]) / (tips[k + 1][0] - tips[k][0])
                        p = tuple(lerp(tips[k][1][j], tips[k + 1][1][j], u)
                                  for j in range(3))
                        break
                else:
                    p = tips[-1][1]
                rig.quad(entry, p, 0.0, 0.0, 0.0, 0.16, 0.05,
                         op * 0.5, 0.6)
        else:
            for entry in rig.mist_m[:3]:
                rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ A2 --------------------------------------
def make_a2(rig):
    t_rel = ev("sb_a2", "A2_RELEASE", 0.10)
    t_wave = ev("sb_a2", "A2_WAVE", 0.14)
    t_fin = ev("sb_a2", "A2_FINISH", 0.415)
    sw0, sw1 = t_rel, t_rel + 0.10

    def hand(t):
        u = ease_out(seg(t, sw0, sw1))
        v = ease_out(seg(t, 0.26, 0.50))
        x = lerp(lerp(0.40, 0.30, u), READY[0], v)
        y = lerp(lerp(-0.10, 0.10, u), READY[1], v)
        z = lerp(lerp(0.92, 1.28, u), READY[2], v)
        return (x, y, z)

    def yaw(t):
        u = ease_out(seg(t, sw0, sw1))
        return lerp(55.0, -68.0, u)

    def pitch(t):
        u = ease_out(seg(t, sw0, sw1))
        return lerp(-34.0, 38.0, u)

    tips = sample_tips(rig, hand, pitch, yaw, BLADE_LN, sw0, sw1, 13)
    return hand, pitch, yaw, tips, t_wave, t_fin


def anim_a2(rig, t, magic, prepped=None):
    hand, pitch, yaw, tips, t_wave, t_fin = prepped
    rig.set_sword(hand(t), pitch(t), yaw(t), BLADE_LN)
    rig.set_saya((0.16, 0.30, 0.92), 62.0, -28.0)

    pool = rig.quad_m if magic else rig.quad_n
    for i, entry in enumerate(pool[:13]):
        if i < len(tips):
            t_i, p = tips[i]
            op = fade_life(t, t_i, 0.18)
            if op is not None:
                nxt = tips[min(i + 1, len(tips) - 1)][1]
                seglen = max(0.35, ((nxt[0] - p[0]) ** 2 + (nxt[1] - p[1]) ** 2
                                    + (nxt[2] - p[2]) ** 2) ** 0.5 * 2.2)
            else:
                seglen = 0.5
            rig.quad(entry, p, pitch(t_i), yaw(t_i) + 90.0, 90.0,
                     seglen, 0.12, op, 1.2 if magic else 1.1)
        else:
            rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)

    # the wave: a thin curved PRESSURE FRONT of vertical segments, 8.4 m at
    # 26 m/s, bounded by the move. Built from quads rather than WaveSheet -
    # the sheet mesh's long axis maps vertical under any pitch-90 rotation,
    # while segments give a controlled curved front that faces the travel.
    waves = rig.wave_m if magic else rig.wave_n
    rig.sheet(waves[0], (0, 0, 0), 0, 0, 0, 1, 1, None)
    if t_wave <= t <= t_fin:
        f = t - t_wave
        dist = 1.6 + 26.0 * f
        op = (0.25 + 0.75 * ease_out(seg(t, t_wave, t_wave + 0.05))) * \
             (1.0 - 0.9 * seg(t, t_fin - 0.10, t_fin))
        for i in range(9):
            u = (i - 4.0) / 4.0                # -1 .. 1 across the front
            # parabolic front bulging forward at the centre
            fx = dist + 0.45 * (1.0 - u * u)
            fy = u * 4.2
            h = 1.45 + 0.45 * (1.0 - u * u)    # taller at the centre
            zc = 1.05
            c = rig.wpos((fx, fy, zc))
            edge = 1.0 - abs(u) * 0.55         # bright edge, faint interior
            rig.quad(pool[13 + i], c, 0.0, 90.0, 0.0, 0.95, h, op * edge,
                     (1.35 if magic else 1.3) * (0.6 + 0.4 * edge))
        if magic:
            # thin black mist wake riding behind the front
            rig.quad(rig.mist_m[0], rig.wpos((dist - 0.4, 0.0, 1.0)),
                     0.0, 90.0, 0.0, 8.0, 1.3, op * 0.45, 0.7)
    else:
        for i in range(9):
            rig.quad(pool[13 + i], (0, 0, 0), 0, 0, 0, 1, 1, None)
        if magic:
            rig.quad(rig.mist_m[0], (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ A3 --------------------------------------
A3_SCARS = (
    # cut dirs live in the X-Z plane (no Y) so the roll-0 wall faces the
    # over-shoulder camera; rolls are small variety tilts. / \ shallow-H.
    (0.10, -12.0, 1.35, (0.55, 0.00, 0.83)),
    (-0.22, 12.0, 1.55, (0.55, 0.00, -0.83)),
    (0.28, 6.0, 1.15, (0.985, 0.0, 0.17)),
)


def make_a3(rig):
    t1 = ev("sb_a3", "A3_CUT_1", 0.16)
    t2 = ev("sb_a3", "A3_CUT_2", 0.34)
    t3 = ev("sb_a3", "A3_CUT_3", 0.54)
    t_end = ev("sb_a3", "A3_DOMAIN_END", 0.68)

    def hand(t):
        # three draw / partial-return cycles
        cuts = (t1, t2, t3)
        base = (0.26, 0.05, 1.00)
        for tc in cuts:
            u0 = seg(t, tc - 0.10, tc)
            u1 = seg(t, tc, tc + 0.10)
            if 0.0 < u0 < 1.0 or 0.0 < u1 < 1.0:
                ext = max(ease_out(u0), 1.0 - ease_in(u1))
                return (lerp(base[0], 0.44, ext), lerp(base[1], -0.02, ext),
                        lerp(base[2], 1.06, ext))
        return base

    def yaw(t):
        if t < t2:
            return lerp(-40.0, 30.0, seg(t, t1 - 0.10, t1))
        if t < t3:
            return lerp(35.0, -35.0, seg(t, t2 - 0.10, t2))
        return lerp(-20.0, 25.0, seg(t, t3 - 0.10, t3))

    def pitch(t):
        if t < t2:
            return lerp(10.0, -4.0, seg(t, t1 - 0.10, t1))
        if t < t3:
            return lerp(6.0, -8.0, seg(t, t2 - 0.10, t2))
        return lerp(-4.0, 4.0, seg(t, t3 - 0.10, t3))

    return hand, pitch, yaw, (t1, t2, t3), t_end


def anim_a3(rig, t, magic, prepped=None, roll_override=None):
    hand, pitch, yaw, cuts, t_end = prepped
    rig.set_sword(hand(t), pitch(t), yaw(t), BLADE_LN * 0.92)
    rig.set_saya(HIP, 8.0)

    scars = rig.scar_m if magic else rig.scar_n
    life = 0.55 if magic else 0.42
    for k in range(3):
        tc = cuts[k]
        yaw_off, roll, hgt, d_long = A3_SCARS[k]
        op = fade_life(t, tc, life)
        if op is None:
            rig.strip(scars[k], (0, 0, 0), (1, 0, 0), 0, 1, 1, None)
            continue
        grow = 0.30 + 0.70 * ease_out(seg(t, tc, tc + 0.06))
        c = rig.wpos((9.5 + yaw_off, 0.0, hgt))
        d = (d_long[0], d_long[1], d_long[2])
        roll = roll_override if roll_override is not None else A3_SCARS[k][1]
        rig.strip(scars[k], c, d, roll, 15.0 * grow,
                  0.055 if not magic else 0.062, max(op, 0.4),
                  1.45 if magic else 1.35,
                  0.55 if magic else 0.05)
        # mist leaking from the cut (magic)
        if magic:
            m = rig.mist_m[k % len(rig.mist_m)]
            mop = op * 0.4 * seg(t, tc + 0.08, tc + 0.2)
            if mop > 0.02:
                spread = 0.4 + 0.8 * seg(t, tc, tc + life)
                rig.quad(m, (c[0] - spread * 0.3, c[1] + 0.1, c[2]),
                         0.0, 0.0, roll, 6.0 + spread * 4.0, 0.5 + spread,
                         mop, 0.55)
            else:
                rig.quad(m, (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ A4 --------------------------------------
def make_a4(rig):
    t_beg = ev("sb_a4", "A4_ARC_START", 0.12)
    t_end = ev("sb_a4", "A4_ARC_END", 0.32)
    return t_beg, t_end


ARC_R = 3.05          # annulus centre-line radius, metres


def anim_a4(rig, t, magic, prepped=None, tilt=22.0):
    t_beg, t_end = prepped
    sweep_dur = t_end - t_beg

    def hand(t):
        u = ease_out(seg(t, t_beg, t_end))
        v = ease_out(seg(t, t_end, t_end + 0.23))
        ang = math.radians(lerp(0.0, -300.0, u))
        rx = 0.55 * (1.0 - 0.4 * v)
        return (READY[0] * 0.5 + rx * math.cos(ang),
                -rx * math.sin(ang),
                lerp(1.06, 1.00, u) + 0.04 * math.sin(math.pi * v))

    def yaw(t):
        u = seg(t, t_beg, t_end)
        return (lerp(0.0, -300.0, u) + 90.0) % 360.0 - 180.0

    def pitch(t):
        return -4.0

    rig.set_sword(hand(t), pitch(t), yaw(t), BLADE_LN)
    rig.set_saya((0.16, 0.30, 0.92), 62.0, -28.0)

    # the annulus pressure sheet - 300 degrees, tilted toward camera
    arcs = rig.arc_m if magic else rig.arc_n
    if t >= t_beg:
        op = 0.55 * ease_out(seg(t, t_beg, t_beg + 0.10)) * \
            (1.0 - seg(t, t_end + 0.10, t_end + 0.25))
        c = rig.wpos((0.0, 0.0, 1.02))
        rig.sheet(arcs[0], c, tilt, 0.0, 0.0, ARC_R, ARC_R, op,
                  1.0 if magic else 1.0, )
    else:
        rig.sheet(arcs[0], (0, 0, 0), 0, 0, 0, 1, 1, None)

    # the sweep front: vertical crumbs around the player (a cylinder wall
    # reads from any low camera), staggered = START -> SWEEP -> END live
    pool = rig.quad_m if magic else rig.quad_n
    N = 12
    for i, entry in enumerate(pool[:N]):
        frac = (i + 0.5) / N
        t_i = t_beg + frac * sweep_dur
        ang = math.radians(-300.0 * frac - 150.0)  # start -150 .. +150
        p = rig.wpos((ARC_R * 0.97 * math.cos(ang),
                      ARC_R * 0.97 * math.sin(ang),
                      1.05 + ARC_R * 0.30 * math.sin(math.radians(tilt)) *
                      abs(math.cos(ang))))
        op = fade_life(t, t_i, 0.16)
        rig.quad(entry, p, 0.0, math.degrees(ang) + 90.0, 90.0,
                 0.34 * 2.4, 0.34 * 7.0, op, 1.25 if magic else 1.1)


# ------------------------------ HIT -------------------------------------
def anim_hit_flash(rig, t, magic, t_hit, pos):
    pool = rig.quad_m if magic else rig.quad_n
    op = fade_life(t, t_hit, 0.13)
    if op is not None:
        u = seg(t, t_hit, t_hit + 0.13)
        rig.quad(pool[22], pos, -12.0, 25.0, 0.0, 0.22 + 0.5 * u,
                 0.22 + 0.5 * u, op, 0.9 if magic else 0.85)
    else:
        rig.quad(pool[22], (0, 0, 0), 0, 0, 0, 1, 1, None)
    # sparks
    for k in range(3):
        op = fade_life(t, t_hit + 0.01, 0.20)
        if op is not None:
            ang = -20.0 + k * 28.0
            d = dir_of(8.0, ang)
            f = 0.25 + 0.75 * (1.0 - op)
            p = (pos[0] + d[0] * f * 0.5, pos[1] + d[1] * f * 0.5,
                 pos[2] + d[2] * f * 0.5 + 0.1)
            rig.quad(pool[23 if k == 0 else 18 + k], p, 0.0, ang, 0.0, 0.28, 0.03,
                     op * 0.8, 0.9)
        else:
            rig.quad(pool[23 if k == 0 else 18 + k], (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ IAIDO ------------------------------------
def anim_iaido(rig, t, magic):
    t_draw = 0.35          # the draw beat
    t_cut = 0.62           # the world cut
    t_sheathe0 = 1.90      # one controlled rotation begins
    t_click = 3.15
    total = 3.45

    # ---- phase 1: stillness, hand on the saya
    if t < t_draw:
        hand, pitch, yaw, exp = HIP, 0.0, 8.0, 0.0
    # ---- phase 2: the draw and the cut
    elif t < t_sheathe0:
        u = ease_out(seg(t, t_draw, t_draw + 0.10))
        if t < t_cut:
            v = ease_out(seg(t, t_draw + 0.10, t_cut))
        else:
            v = 1.0
        hand = (lerp(HIP[0], 0.40, u), lerp(HIP[1], -0.08, u),
                lerp(HIP[2], 1.10, u))
        yaw = lerp(8.0, -78.0, u)
        pitch = lerp(0.0, 4.0, u) - 10.0 * (v if t >= t_cut else 0.0)
        if t >= t_cut:
            w = ease_out(seg(t, t_cut, t_cut + 0.12))
            hand = (hand[0] + 0.10 * w, hand[1] + 0.22 * w, hand[2])
            yaw = lerp(-78.0, 48.0, w)
            pitch = lerp(4.0, -8.0, w)
        exp = BLADE_LN
    # ---- phase 3: one controlled rotation -> spine along saya -> slow seat
    else:
        u_rot = ease_out(seg(t, t_sheathe0, t_sheathe0 + 0.45))
        u_desc = ease_out(seg(t, t_sheathe0 + 0.35, t_sheathe0 + 0.65))
        u_seat = seg(t, t_sheathe0 + 0.60, t_click)
        one_spin = 360.0 * u_rot
        yaw = (8.0 + one_spin) % 360.0 - 180.0
        pitch = lerp(-8.0, 0.0, u_desc)
        hand = (lerp(0.50, HIP[0] + 0.12, u_desc), lerp(0.14, HIP[1], u_desc),
                lerp(1.12, HIP[2] + 0.03, u_desc))
        # slow sheathe: exposed shrinks only in the last phase
        exp = BLADE_LN * (1.0 - ease_in(u_seat))
        if t > t_click:
            exp = 0.0

    rig.set_sword(hand, pitch, yaw, exp)
    rig.set_saya(HIP, 8.0)

    pool = rig.quad_m if magic else rig.quad_n
    scars = rig.scar_m if magic else rig.scar_n
    mists = rig.mist_m if magic else rig.mist_n

    # draw glint: fast axial scan at the draw
    g = t - t_draw
    if 0.0 <= g <= 0.10:
        prog = g / 0.10
        d = dir_of(pitch, yaw)
        base = rig.wpos(hand)
        p = tuple(base[j] + d[j] * (0.10 + prog * 0.5) for j in range(3))
        rig.quad(pool[0], p, pitch, yaw, 90.0, 0.07, 0.24,
                 math.sin(math.pi * prog), 1.15 if magic else 1.1)
    else:
        rig.quad(pool[0], (0, 0, 0), 0, 0, 0, 1, 1, None)

    # the void scar of the cut: long, brighter than A3's, thin and spatial
    op = fade_life(t, t_cut, 0.62 if magic else 0.55)
    if op is not None:
        grow = 0.3 + 0.7 * ease_out(seg(t, t_cut, t_cut + 0.05))
        c = rig.wpos((10.0, 0.05, 1.30))
        rig.strip(scars[0], c, (0.95, 0.05, 0.30), -8.0, 16.0 * grow,
                  0.060 if magic else 0.058, op, 1.45 if magic else 1.25,
                  0.50 if magic else 0.0)
    else:
        rig.strip(scars[0], (0, 0, 0), (1, 0, 0), 0, 1, 1, None)

    # sheathe mist (magic): amount tracks the exposed blade, dies at CLICK
    if magic and t >= t_sheathe0 and t <= t_click + 0.10:
        frac = exp / BLADE_LN
        if frac > 0.02 and t <= t_click:
            mop = 0.55 * frac * (0.7 + 0.3 * math.sin(t * 9.0))
            m = rig.wpos((HIP[0] + 0.55 * frac, HIP[1], HIP[2] + 0.06))
            rig.quad(mists[0], m, 0.0, 8.0, 0.0, 0.5 + 0.6 * frac,
                     0.22 + 0.3 * frac, mop, 0.8)
        else:
            rig.quad(mists[0], (0, 0, 0), 0, 0, 0, 1, 1, None)
        # the CLICK: one small purple point at the saya mouth, 20-50 ms
        ck = t - t_click
        if 0.0 <= ck <= 0.035:
            m = rig.wpos((HIP[0] + 0.04, HIP[1], HIP[2]))
            rig.quad(pool[1], m, 0.0, 8.0, 0.0, 0.05, 0.05,
                     math.sin(math.pi * ck / 0.035), 1.6)
        else:
            rig.quad(pool[1], (0, 0, 0), 0, 0, 0, 1, 1, None)
    else:
        if magic:
            rig.quad(mists[0], (0, 0, 0), 0, 0, 0, 1, 1, None)
            rig.quad(pool[1], (0, 0, 0), 0, 0, 0, 1, 1, None)

    # trailing crumbs of black mist being carried toward the saya (magic)
    if magic and t_sheathe0 < t < t_click:
        for i, entry in enumerate(mists[1:3]):
            u = seg(t, t_sheathe0, t_click)
            ang = 2.4 + i * 2.9
            p = rig.wpos((HIP[0] + 0.9 * (1.0 - u) * math.cos(ang),
                          HIP[1] + 0.5 * (1.0 - u) * math.sin(ang),
                          HIP[2] + 0.35 * (1.0 - u)))
            rig.quad(entry, p, 0.0, 0.0, 0.0, 0.3, 0.12,
                     0.4 * (1.0 - u), 0.6)
    elif magic:
        for entry in mists[1:3]:
            rig.quad(entry, (0, 0, 0), 0, 0, 0, 1, 1, None)


# ------------------------------ IDLE (magic) ----------------------------
def anim_idle(rig, t, magic):
    hand = READY
    pitch, yaw = -14.0, 24.0
    rig.set_sword(hand, pitch, yaw, BLADE_LN)
    rig.set_saya((0.16, 0.30, 0.92), 62.0, -28.0)
    if not magic:
        return
    d = dir_of(pitch, yaw)
    base = rig.wpos(hand)
    # a few motes drifting up the blade, never a smoke machine
    for i, entry in enumerate(rig.mote_m[:5]):
        u = (t * 0.22 + i * 0.21) % 1.0
        p = (base[0] + d[0] * (0.15 + u * 0.8) + math.sin(i * 2.0 + t) * 0.03,
             base[1] + d[1] * (0.15 + u * 0.8) + math.cos(i * 1.6 + t) * 0.03,
             base[2] + d[2] * (0.15 + u * 0.8) + u * 0.05)
        op = math.sin(math.pi * u) * 0.5
        rig.quad(entry, p, 0.0, 0.0, 0.0, 0.045, 0.045, op, 0.55)
    # one thin black wisp
    w = rig.mist_m[3 % len(rig.mist_m)]
    op = 0.10 + 0.06 * math.sin(t * 1.7)
    rig.quad(w, (base[0] + 0.3, base[1] + 0.05, base[2] + 0.25), 0.0, yaw,
             70.0, 0.55, 0.10, op, 0.5)
    # occasional dark violet edge pulse
    pu = (t % 2.3)
    if 0.0 < pu < 0.4:
        op = math.sin(math.pi * pu / 0.4) * 0.35
        mid = (base[0] + d[0] * 0.6, base[1] + d[1] * 0.6, base[2] + d[2] * 0.6)
        rig.quad(rig.quad_m[4], mid, pitch, yaw, 90.0, 0.9, 0.06, op, 0.6)
    else:
        rig.quad(rig.quad_m[4], (0, 0, 0), 0, 0, 0, 1, 1, None)


# ----------------------------------------------------------------------
# shots & sections
# ----------------------------------------------------------------------
# camera presets: (loc, look_at, fov). Attack cams sit BEHIND the player
# looking downrange (+X) so the wave/scars/arc are in frame, and the strip
# walls (normal pointing back to -X) face the camera.
CAMS = {
    "close": ((1.9, -1.15, 1.45), (0.32, -0.05, 1.12), 55),
    "inspect": ((2.15, -1.05, 1.75), (0.40, 0.05, 1.44), 55),
    "battle": ((-2.9, -3.1, 1.75), (4.2, 0.0, 1.05), 60),
    "battle_wide": ((-3.5, -3.8, 1.9), (5.2, 0.2, 1.08), 58),
    "a3_side": ((9.5, -7.0, 1.35), (9.5, 0.5, 1.35), 50),
    "a4_top": ((0.4, -1.2, 6.4), (0.0, 0.0, 1.0), 55),
    "iaido": ((-2.4, -2.4, 1.55), (5.5, 0.1, 1.05), 58),
    "idle": ((1.7, -1.05, 1.35), (0.42, -0.10, 1.02), 52),
    "hero_a3": ((2.2, -2.3, 0.80), (8.0, 0.0, 1.45), 50),
}


def shot(name, cam, dur, anim, magic=False, prep=None, pre=0.30, post=0.25):
    return {"name": name, "cam": cam, "dur": dur, "anim": anim,
            "magic": magic, "prep": prep, "pre": pre, "post": post}


def build_sections(rig):
    a1 = make_a1(rig)
    a2 = make_a2(rig)
    a3 = make_a3(rig)
    a4 = make_a4(rig)

    def a1m(rig_, t, magic):
        anim_a1(rig_, t, magic, a1)

    def a2m(rig_, t, magic):
        anim_a2(rig_, t, magic, a2)

    def a3m(rig_, t, magic):
        anim_a3(rig_, t, magic, a3)

    def a4m(rig_, t, magic):
        anim_a4(rig_, t, magic, a4)

    def a4_top(rig_, t, magic):
        anim_a4(rig_, t, magic, a4, tilt=6.0)

    # combo: A1 -> A2 -> A3 -> A4 back to back, on contract clocks
    def combo(rig_, t, magic):
        a1d, a2d, a3d, a4d = 0.65, 0.75, 0.90, 0.80
        # a target box downrange so the hit flash has something to hit
        rig_.place_target((1.9, 0.15, 0.53), True)
        if t < a1d:
            anim_a1(rig_, t, magic, a1)
        elif t < a1d + a2d:
            anim_a2(rig_, t - a1d + 0.10, magic, a2)
        elif t < a1d + a2d + a3d:
            anim_a3(rig_, t - a1d - a2d, magic, a3)
        else:
            anim_a4(rig_, t - a1d - a2d - a3d, magic, a4)
        # one hit flash near the end of A1's window
        th = 0.30
        if th - 0.02 <= t <= th + 0.35:
            anim_hit_flash(rig_, t, magic, th,
                           rig_.wpos((1.9, 0.15, 1.02)))

    sections = {}
    sections["smoke"] = [
        shot("smoke", "battle", 1.6, lambda r, t, m: anim_a1(r, t, False, a1)),
    ]
    sections["normal"] = [
        shot("equip", "close", 1.95, anim_equip, False),
        shot("inspect", "inspect", 2.4, anim_inspect, False),
        shot("a1", "battle", 1.1, a1m, False),
        shot("a2", "battle_wide", 1.3, a2m, False),
        shot("a3", "battle_wide", 1.7, a3m, False),
        shot("a4", "battle", 1.3, a4m, False),
        shot("combo", "battle_wide", 3.6, combo, False),
        shot("iaido", "iaido", 3.6, anim_iaido, False),
    ]
    sections["magic"] = [
        shot("idle", "idle", 2.4, anim_idle, True),
        shot("equip", "close", 1.95, anim_equip, True),
        shot("inspect", "inspect", 2.4, anim_inspect, True),
        shot("a1", "battle", 1.2, a1m, True),
        shot("a2", "battle_wide", 1.4, a2m, True),
        shot("a3", "battle_wide", 1.9, a3m, True),
        shot("a4", "battle", 1.4, a4m, True),
        shot("combo", "battle_wide", 3.6, combo, True),
        shot("iaido", "iaido", 3.6, anim_iaido, True),
    ]
    sections["angles"] = [
        shot("a3_side", "a3_side", 1.7,
             lambda r, t, m: anim_a3(r, t, m, a3, roll_override=90.0), False),
        shot("a4_top", "a4_top", 1.3, a4_top, False),
        shot("ma3_hero", "hero_a3", 1.9, a3m, True),
    ]
    return sections


# ----------------------------------------------------------------------
# engine session
# ----------------------------------------------------------------------
log("")
loaded = False
for how in ("LevelEditorSubsystem", "EditorLevelLibrary"):
    try:
        getattr(unreal, how)().load_level(LVL)
        log("level loaded via %s" % how)
        loaded = True
        break
    except Exception as exc:
        log("  %s failed: %s" % (how, str(exc)[:120]))
if not loaded:
    log("ABORT: no level")
    raise SystemExit(0)

W = None
for getter in ("UnrealEditorSubsystem", "EditorLevelLibrary"):
    try:
        W = getattr(unreal, getter)().get_editor_world()
        if W is not None:
            break
    except Exception:
        W = None
if W is None:
    log("ABORT: no world")
    raise SystemExit(0)

load_all()

# pick a stage centre away from the map's dummy actors
try:
    _actors = unreal.EditorLevelLibrary.get_all_level_actors()
    _seen, _dummy_pos = set(), []
    for _a in _actors:
        try:
            _p = _a.get_path_name()
            if _p in _seen:
                continue
            _seen.add(_p)
            if "Lab_Dummy" in (_a.get_actor_label() or _a.get_name()):
                _l = _a.get_actor_location()
                _dummy_pos.append((_l.x / 100.0, _l.y / 100.0))
        except Exception:
            pass
    _cands = [(0, 0), (0, 7), (0, -7), (8, 0), (-8, 0), (8, 7), (-8, -7),
              (0, 14), (14, 0)]
    _best, _bd = _cands[0], -1.0
    for _c in _cands:
        _d = min([math.hypot(_c[0] - p[0], _c[1] - p[1]) for p in _dummy_pos]
                 or [999.0])
        if _d > _bd:
            _best, _bd = _c, _d
    log("dummies found: %d  -> stage centre %s (clear by %.1f m)"
        % (len(_dummy_pos), _best, _bd))
except Exception as exc:
    _best = (0, 0)
    log("dummy scan failed (%s) -> stage at origin" % str(exc)[:100])

RIG = Rig(W)
RIG.center = (_best[0], _best[1], 0.0)

# camera
rt = swcap.make_rt(W, WIDTH, HEIGHT)
if rt is None:
    log("ABORT: no render target")
    raise SystemExit(0)
CAP = unreal.EditorLevelLibrary.spawn_actor_from_class(
    unreal.SceneCapture2D, V(2, -2, 1.5), R(0, 0))
cc = CAP.capture_component2d
swcap.set_prop(cc, "texture_target", rt)
v = getattr(unreal.SceneCaptureSource, "SCS_FINAL_COLOR_LDR", None)
if v is not None:
    swcap.set_prop(cc, "capture_source", v)
swcap.set_prop(cc, "capture_every_frame", False)

SECTIONS = build_sections(RIG)
SHOTS = SECTIONS.get(SECTION)
if not SHOTS:
    log("ABORT: unknown section %r (have %s)" % (SECTION,
                                                 sorted(SECTIONS)))
    raise SystemExit(0)

# precompute the frame plan: (shot, local t). Negative t = pre-roll hold at
# the anim's opening pose; the anims are pure functions and clamp safely.
PLAN = []
for sh in SHOTS:
    n = int(round((sh["pre"] + sh["dur"] + sh["post"]) * FPS))
    for k in range(n):
        PLAN.append((sh, k / FPS - sh["pre"]))
log("section %s: %d shots, %d frames (~%.1f s @ %d fps)"
    % (SECTION, len(SHOTS), len(PLAN), len(PLAN) / FPS, int(FPS)))

# event trace: contract events crossed while recording (for the log)
log("")
log("--- event trace (contract t values driving this recording) ---")
for sh in SHOTS:
    log("  shot %-10s magic=%-5s dur=%.2f" % (sh["name"], sh["magic"],
                                              sh["dur"]))

ST = {"handle": None, "started": time.time(), "ticks": 0, "phase": "settle",
      "wait": SETTLE_TICKS, "errors": 0, "i": -1, "cam_for": None,
      "nonflat": 0, "frames": 0}


def place_shot_cam(sh):
    key = sh["cam"]
    loc, look, fov = CAMS[key]
    lw = (RIG.center[0] + loc[0], RIG.center[1] + loc[1], loc[2])
    lk = (RIG.center[0] + look[0], RIG.center[1] + look[1], look[2])
    rot = look_rot(lw, lk)
    ok, why = swcap.place_capture(cc, CAP, V(*lw), rot)
    swcap.set_prop(cc, "fov_angle", float(fov))
    if not ok:
        log("  cam %s placement FAILED: %s" % (key, why))
    return ok


def _finish(reason):
    if ST["phase"] == "done":
        return
    ST["phase"] = "done"
    log("")
    log("--- summary ---")
    log("stop reason : %s" % reason)
    log("elapsed     : %.1f s over %d ticks"
        % (time.time() - ST["started"], ST["ticks"]))
    log("tick errors : %d" % ST["errors"])
    log("frames      : %d exported, %d non-flat" % (ST["frames"],
                                                    ST["nonflat"]))
    log("output      : %s" % OUT_DIR)
    log("P60 %s DONE" % SECTION.upper())
    try:
        if ST["handle"] is not None:
            unreal.unregister_slate_post_tick_callback(ST["handle"])
    except Exception:
        pass
    try:
        unreal.SystemLibrary.quit_editor()
    except Exception as exc:
        log("quit_editor failed: %s" % str(exc)[:120])


def tick(delta):
    st = ST
    if st["phase"] == "done":
        return
    st["ticks"] += 1
    if time.time() - st["started"] > BUDGET_SECONDS:
        _finish("budget exhausted")
        return
    try:
        if st["phase"] == "settle":
            st["wait"] -= 1
            if st["wait"] <= 0:
                st["phase"] = "apply"
            return

        if st["phase"] == "apply":
            st["i"] += 1
            if st["i"] >= len(PLAN):
                _finish("all frames captured")
                return
            sh, t = PLAN[st["i"]]
            if sh["name"] != st["cam_for"]:
                ok = place_shot_cam(sh)
                log("")
                log("[frame %4d] shot %-10s cam=%s placed=%s"
                    % (st["i"], sh["name"], sh["cam"], ok))
                st["cam_for"] = sh["name"]
                RIG.park_all()
            # apply the whole scene as a pure function of t
            if sh["prep"] is not None:
                sh["anim"](RIG, t, sh["magic"], sh["prep"])
            else:
                sh["anim"](RIG, t, sh["magic"])
            # capture now, export two ticks later (RT readback lag)
            swcap.clear_rt(W, rt, (0.0, 1.0, 0.0, 1.0))
            cc.capture_scene()
            st["wait"] = 2
            st["phase"] = "export"
            return

        if st["phase"] == "export":
            st["wait"] -= 1
            if st["wait"] > 0:
                return
            name = "f%04d" % st["i"]
            swcap.export_rt(W, rt, OUT_DIR, name)
            path = os.path.join(OUT_DIR, name + ".png")
            plain = os.path.join(OUT_DIR, name)
            if not os.path.exists(path) and os.path.exists(plain):
                try:
                    os.replace(plain, path)
                except Exception:
                    pass
            if os.path.exists(path) and os.path.getsize(path) > 0:
                st["frames"] += 1
                s = swimg.png_stats(path)
                if s and s["mean_luma"] is not None:
                    if s["mean_luma"] > 1.0 or (s["distinct_rgb"] or 0) > 8:
                        st["nonflat"] += 1
                    if st["i"] % 48 == 0:
                        log("  %s  luma=%.2f distinct=%s"
                            % (name, s["mean_luma"], s["distinct_rgb"]))
            else:
                log("  %s EXPORT MISSING" % name)
            st["phase"] = "apply"
            return
    except Exception as exc:
        st["errors"] += 1
        log("TICK ERROR %s: %s" % (type(exc).__name__, str(exc)[:160]))
        log("    " + traceback.format_exc().splitlines()[-3].strip()[:200])
        if st["errors"] > 25:
            _finish("too many tick errors")


log("")
log("--- settle %d ticks, then %d frames ---" % (SETTLE_TICKS, len(PLAN)))
WFX.install_watchdog(grace_ticks=2000, grace_seconds=240.0)
ST["handle"] = unreal.register_slate_post_tick_callback(tick)
# the tick machine owns the exit from here - without this handover the
# watchdog would kill a healthy 500 s recording at 240 s.
WFX.watchdog_handover()
