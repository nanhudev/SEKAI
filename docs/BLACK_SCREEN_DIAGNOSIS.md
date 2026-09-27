# Godot combat black screen

## Root cause

On this machine Godot 4.4.1 Forward+ (Vulkan 1.4.315, AMD Radeon RX 6650 XT) renders the environment background and 2D UI but does not render 3D meshes. The same standalone scene renders its magenta unlit cube and cyan unlit ground in Compatibility (OpenGL 3.3). This isolates the failure to the Forward+ rendering path on the current machine. The verbose Vulkan log also reports a missing Epic EOS overlay layer JSON; its causal role has not been established.

## Reproduction and isolation

| Test | Result | Conclusion | Next |
| --- | --- | --- | --- |
| Main → Start, Forward+ desktop window | HUD visible; 3D black | Black screen reproduced | Build standalone probe |
| RenderProbe, Forward+, 12 captured frames | Background only; no cube or ground | Main, HUD, combat code and lighting are not required to reproduce | Compare renderer |
| Same RenderProbe, Compatibility, 12 frames | Magenta cube, cyan ground and background visible | Camera, viewport and mesh setup work | Run combat scene |
| CombatSandbox direct, Compatibility, 16 frames | Ground, platform, enemy and HUD visible | Combat scene renders correctly on fallback | Test main flow |
| Main.start_game(), project default Compatibility, 21 frames | Ground, platform, enemy and HUD visible; menu hidden, camera current | Main flow renders correctly on fallback | Desktop acceptance and sword visual |

## Fix

`godot/project.godot` temporarily selects Compatibility. Godot 4.4.1 remains in use. `RenderProbe.tscn` is retained as a renderer sanity scene. The earlier environment color and ScreenFX default visibility changes remain as defensive corrections; they did not resolve the Forward+ mesh failure. No claim is made that the AMD driver itself is defective.

## Regression

The independent probe and Main → Start capture both show 3D meshes with the project default renderer. A desktop shortcut opens the project editor. A final interactive desktop click should still be checked because the recording script called `start_game()` directly, although it followed the same method used by the button signal.
