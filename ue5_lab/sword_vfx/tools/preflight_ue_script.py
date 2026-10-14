"""Catch NameError-class bugs in an engine script WITHOUT launching the engine.

    C:/Users/Administrator/AppData/Local/Programs/Python/Python311/python.exe \\
        tools/preflight_ue_script.py scripts/p26_lighting_ladder.py [...]

WHY, AND WHAT IT COST TO LEARN

    `py_compile` checks syntax and nothing else. Three bugs in this project were
    syntactically perfect and died at runtime:

      * a function referenced inside a PLAN dict literal BEFORE it was defined
        (NameError at import);
      * `"%s%s" % (one_value)` - two format specifiers, one argument
        (TypeError, and only on the rung that used it);
      * `tuple(some_unreal_vector)` (TypeError, and only at runtime).

    Each one cost a full engine launch - 1m40s warm, up to 9 minutes when the
    editor hangs at shutdown. `tools/verify_png_probe.py` proved the value of
    checking a thing against an independent implementation; this does the same
    for "does the script even load".

HOW IT WORKS

    It installs a permissive fake `unreal` module and EXECUTES the target
    script's module body. That is what catches NameError and import-time
    ordering bugs: everything at module level really runs. Anything that needs
    a live engine (registering a tick callback, spawning actors) lands on a mock
    and is harmless.

    It does NOT prove the script is correct. It proves it loads.

TWO THINGS TO KNOW

    * Each engine script truncates its own export file at import. So this
      REDIRECTS writes instead of letting them land: anything written under an
      `exports/` or `render/` directory is diverted to a temp folder and thrown
      away. Without that, preflighting after a real run would empty the
      artefacts it just produced - which is exactly the kind of self-inflicted
      data loss that makes a useful tool one nobody dares use. (The engine
      stdout, and therefore the `<name>_run.log` in scripts/exports/, is not
      touched.)
    * It now also TICK-DRY-RUNS any callback the script registered, to
      completion, against the mock. That is not decoration: for a tick-driven
      probe the module body only builds a plan, so load-only preflight says
      almost nothing about the code that matters. Failures inside functions the
      module body never calls are still not caught if the script aborts before
      registering its callback - so a script that refuses to start under mocks
      gets the weaker check and the output says which one it got.
"""
import builtins
import importlib.util
import os
import shutil
import sys
import tempfile
import traceback
from unittest.mock import MagicMock

_REAL_OPEN = builtins.open
_SANDBOX = None


def _sandbox_path(path):
    """Divert any path under an exports/ or render/ dir into the sandbox."""
    if _SANDBOX is None:
        return path
    try:
        p = os.path.abspath(str(path))
    except Exception:
        return path
    parts = p.replace("\\", "/").split("/")
    if "exports" in parts or "render" in parts:
        return os.path.join(_SANDBOX, os.path.basename(p))
    return path


def _install_sandbox():
    global _SANDBOX
    _SANDBOX = tempfile.mkdtemp(prefix="wb_preflight_")

    def sandboxed_open(file, *args, **kwargs):
        return _REAL_OPEN(_sandbox_path(file), *args, **kwargs)

    builtins.open = sandboxed_open

    real_makedirs = os.makedirs

    def sandboxed_makedirs(name, *args, **kwargs):
        try:
            return real_makedirs(_sandbox_path(name), *args, **kwargs)
        except Exception:
            return None

    os.makedirs = sandboxed_makedirs


def _drop_sandbox():
    builtins.open = _REAL_OPEN
    if _SANDBOX:
        shutil.rmtree(_SANDBOX, ignore_errors=True)


# Names that must behave like NUMBERS, not like mocks.
#
# WHY THIS IS NEEDED, learned by trying the tick dry-run without it: several
# scripts verify that a moved capture really arrived where the shot wants it,
# by comparing `rot.pitch`, `loc.x` and so on. A plain MagicMock makes every one
# of those another mock, so `max(adiff(gr.pitch, rot.pitch), ...)` raises
#     TypeError: '>' not supported between instances of 'MagicMock' and 'MagicMock'
# and the module "fails to load" for a reason that has nothing to do with the
# script. That is a false positive, and a tool that cries wolf gets ignored -
# which would be worse than not having it.
_NUMERIC = frozenset(("pitch", "yaw", "roll", "x", "y", "z", "w",
                      "r", "g", "b", "a", "temperature", "intensity"))


class NumMock(MagicMock):
    """A mock whose numeric-looking attributes are real floats, and whose
    children are also NumMocks (so `.get_actor_rotation().pitch` is a float)."""

    def _get_child_mock(self, **kw):
        return NumMock(**kw)

    def __getattr__(self, name):
        if name in _NUMERIC:
            return 1.0
        return super().__getattr__(name)


def fake_unreal():
    """A permissive stand-in.

    `MagicMock` alone is enough: attribute access always succeeds and every call
    returns another mock. That is deliberate - this preflight is looking for
    errors in MY code (undefined names, bad format strings, wrong ordering at
    import), not for whether the engine API is being used correctly.

    `NumMock` is used for everything so that geometry maths does not raise on
    mock-vs-mock comparisons. Values are 1.0 rather than 0.0: 0.0 is FALSY, and
    a falsy coordinate can silently take a different branch inside a script's
    own logic, so the dry-run would stop exercising the path it is there to
    exercise.
    """
    mod = NumMock(name="unreal")
    mod.__version__ = "preflight"
    return mod


def dry_run_ticks(mock_unreal, max_ticks=2000):
    """Drive any tick callback the module registered, until it quits.

    WHY THIS WAS ADDED, and it earned its place the first time it was needed:

        A probe's module body only BUILDS its plan; all the real work happens
        inside the callback it registers. So a preflight that merely loads the
        module proves almost nothing about such a script - and the failures that
        actually cost runs live in exactly that callback. One of them was
        written and caught by hand: a rewritten `measure()` had lost the
        `capture_scene()` call, so every rung would have exported the previous
        frame under a new name and the whole run would have been a table of
        stale images that looked like results.

        Load-only preflight cannot see that. Ticking can.

    It runs to completion rather than a fixed few ticks, so the finish/verdict
    path is exercised too - which is where the report text is built, and a
    wrong `%` argument there is a TypeError that kills the run after all the
    measurements have already been taken.

    Mocks make this cheap and side-effect free, and the sandboxed `open` keeps
    the log writes out of the real artefacts. It does NOT validate the numbers.
    """
    reg = getattr(mock_unreal, "register_slate_post_tick_callback", None)
    calls = list(getattr(reg, "call_args_list", []) or [])
    if not calls:
        return None
    args, kwargs = calls[-1]
    cb = args[0] if args else kwargs.get("callback")
    if not callable(cb):
        return ("no callback found in register_slate_post_tick_callback", None)
    quit_mock = getattr(getattr(mock_unreal, "SystemLibrary", None),
                        "quit_editor", None)
    for i in range(max_ticks):
        try:
            cb(0.016)
        except SystemExit:
            return ("quit via SystemExit", i)
        except Exception as exc:
            print("    TICK DRY-RUN RAISED on tick %d: %s: %s"
                  % (i, type(exc).__name__, exc))
            for line in traceback.format_exc().splitlines()[-6:]:
                print("        %s" % line)
            return ("raised", i)
        if quit_mock is not None and quit_mock.called:
            return ("completed and quit", i)
    return ("still ticking after %d ticks - never reached its finish path"
            % max_ticks, max_ticks)


def load_as_main(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError("cannot load %s" % path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def preflight(paths, scripts_dir):
    failures = []
    for path in paths:
        name = "_preflight_" + os.path.splitext(os.path.basename(path))[0]
        print("=" * 72)
        print("%s" % path)
        if not os.path.isfile(path):
            print("    MISSING")
            failures.append((path, "file not found"))
            continue
        # The scripts import their siblings directly (`import swcap`), so the
        # scripts folder has to be importable.
        if scripts_dir not in sys.path:
            sys.path.insert(0, scripts_dir)
        # Reset the two mocks this run inspects, so one script's tick
        # registration cannot be mistaken for the next script's.
        _mock = sys.modules.get("unreal")
        if _mock is not None:
            try:
                _mock.register_slate_post_tick_callback.reset_mock()
                _mock.SystemLibrary.quit_editor.reset_mock()
            except Exception:
                pass
        try:
            load_as_main(path, name)
            print("    LOADS OK")
            outcome = dry_run_ticks(sys.modules["unreal"])
            if outcome is None:
                print("    no tick callback registered (module body only)")
            else:
                why, where = outcome
                if why == "raised":
                    print("    TICK DRY-RUN FAILED - see traceback above")
                    failures.append((path, "tick dry-run raised on tick %d" % where))
                else:
                    print("    TICK DRY-RUN: %s (at tick %d)" % (why, where))
        except SystemExit as exc:
            # A script that aborts at import did so deliberately (an abort()
            # path writing its own log). Not a load failure, but say so.
            print("    exited at import with SystemExit(%s) - aborts early on"
                  " purpose; not counted as a failure" % exc.code)
        except Exception as exc:
            print("    LOAD FAILED: %s: %s" % (type(exc).__name__, exc))
            for line in traceback.format_exc().splitlines()[-6:]:
                print("        %s" % line)
            failures.append((path, "%s: %s" % (type(exc).__name__, exc)))
    print("=" * 72)
    print("checked %d script(s), %d load failure(s)" % (len(paths), len(failures)))
    for path, why in failures:
        print("    ! %s -> %s" % (os.path.basename(path), why))
    return len(failures)


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    scripts_dir = os.path.join(os.path.dirname(here), "scripts")
    sys.modules["unreal"] = fake_unreal()
    _install_sandbox()
    print("note: writes under exports/ and render/ are diverted to a temp folder")
    try:
        return preflight(argv, scripts_dir)
    finally:
        _drop_sandbox()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
