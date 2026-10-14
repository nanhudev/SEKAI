"""Fixed camera greybox audit. Generated images are review evidence, not beauty output."""
import unreal


@unreal.AutomationScheduler.add_latent_command
def load_map():
    unreal.EditorLevelLibrary.load_level("/Game/Maps/Mistvale_Rebuild_Blockout")


@unreal.AutomationScheduler.add_latent_command
def capture():
    wanted = {"C01_SouthReveal", "C02_RiverHero", "C03_MainBridge", "C04_Market",
              "C05_Guild", "C06_Church", "C07_RooftopDensity", "C08_NorthGate",
              "C10_WalkStreet"}
    cameras = [a for a in unreal.EditorLevelLibrary.get_all_level_actors()
               if isinstance(a, unreal.CameraActor) and a.get_actor_label() in wanted]
    assert len(cameras) == len(wanted), f"missing cameras: {wanted - {a.get_actor_label() for a in cameras}}"
    for cam in sorted(cameras, key=lambda a: a.get_actor_label()):
        task = unreal.AutomationLibrary.take_high_res_screenshot(
            1280, 720, cam.get_actor_label(), camera=cam)
        assert task.is_valid_task(), cam.get_actor_label()
        while not task.is_task_done():
            yield
