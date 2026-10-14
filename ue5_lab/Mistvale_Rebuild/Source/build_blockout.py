"""Build a reproducible independent Mistvale UE5 town massing level.

All building geometry is temporary. Replace the 3-6 chosen Fab asset families
after visual, license and compatibility review; preserve the spatial plan.
"""
import math
import sys
from pathlib import Path
import unreal

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from generate_heightmap import elevation, river_y

LEVEL = "/Game/Maps/Mistvale_Rebuild_Blockout"
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem)
assets = unreal.AssetToolsHelpers.get_asset_tools()
cube = unreal.load_asset("/Engine/BasicShapes/Cube.Cube")
cylinder = unreal.load_asset("/Engine/BasicShapes/Cylinder.Cylinder")


def vec(x, y, z):
    return unreal.Vector(x * 100.0, y * 100.0, z * 100.0)


def mesh_actor(name, x, y, z, sx, sy, sz, mesh=cube, folder="Blockout"):
    a = actors.spawn_actor_from_class(unreal.StaticMeshActor, vec(x, y, z))
    a.set_actor_label(name)
    a.set_folder_path(folder)
    a.static_mesh_component.set_static_mesh(mesh)
    a.set_actor_scale3d(unreal.Vector(sx, sy, sz))
    return a


def mass(name, x, y, w, d, h, folder):
    return mesh_actor(name, x, y, elevation(x, y) + h / 2.0, w, d, h, folder=folder)


def road(name, pts, width, folder="Roads"):
    for n, ((x0, y0), (x1, y1)) in enumerate(zip(pts, pts[1:])):
        length = math.hypot(x1 - x0, y1 - y0)
        steps = max(1, math.ceil(length / 4.0))
        for i in range(steps):
            t0, t1 = i/steps, (i+1)/steps
            ax, ay = x0+(x1-x0)*t0, y0+(y1-y0)*t0
            bx, by = x0+(x1-x0)*t1, y0+(y1-y0)*t1
            x, y = (ax+bx)/2.0, (ay+by)/2.0
            # The bridge owns this crossing. Terrain-following slabs here would
            # cut through its deck and drop into the river channel.
            if name == "GoldenRoute" and -115.0 <= y <= -55.0:
                continue
            h0, h1 = elevation(ax, ay), elevation(bx, by)
            a = mesh_actor(f"{name}_{n:02d}_{i:02d}", x, y,
                           (h0+h1)/2.0,
                           length/steps+0.06, width, 0.16, folder=folder)
            a.set_actor_rotation(unreal.Rotator(
                pitch=math.degrees(math.atan2(h1-h0, length/steps)),
                yaw=math.degrees(math.atan2(y1-y0, x1-x0)), roll=0), False)


def river_ribbon():
    for i, x in enumerate(range(-250, 250, 10)):
        nx = x + 10
        y0, y1 = river_y(x), river_y(nx)
        cx, cy = (x+nx)/2.0, (y0+y1)/2.0
        spread = min(1.0, max(0.0, (cx+85.0)/155.0))
        width = 2.0 * (10.5 + 4.5 * spread)
        length = math.hypot(nx-x, y1-y0)
        a = mesh_actor(f"TEMP_River_{i:02d}", cx, cy, 2.9,
                       length+0.12, width, 0.08, folder="01_River")
        a.set_actor_rotation(unreal.Rotator(
            pitch=0, yaw=math.degrees(math.atan2(y1-y0, nx-x)), roll=0), False)
        a.set_actor_enable_collision(False)


def import_terrain():
    task = unreal.AssetImportTask()
    task.filename = str(HERE / "Mistvale_Terrain_Proxy.obj")
    task.destination_path = "/Game/Blockout"
    task.destination_name = "SM_Mistvale_Terrain_Proxy"
    task.automated = True
    task.save = True
    task.replace_existing = True
    assets.import_asset_tasks([task])
    terrain = unreal.load_asset("/Game/Blockout/SM_Mistvale_Terrain_Proxy")
    if not terrain:
        raise RuntimeError("Terrain proxy import failed")
    body = terrain.get_editor_property("body_setup")
    body.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    unreal.EditorAssetLibrary.save_loaded_asset(terrain)
    mesh_actor("TEMP_Landscape_Proxy_Replace_With_R16", 0, 0, 0, 1, 1, 1,
               mesh=terrain, folder="00_Terrain")


def import_guild():
    task = unreal.AssetImportTask()
    task.filename = str(HERE / "SM_Mistvale_Guild.fbx")
    task.destination_path = "/Game/MistvaleArchitecture"
    task.destination_name = "SM_Mistvale_Guild"
    task.automated = True
    task.save = True
    task.replace_existing = True
    assets.import_asset_tasks([task])
    guild = unreal.load_asset("/Game/MistvaleArchitecture/SM_Mistvale_Guild")
    if not guild:
        raise RuntimeError("Custom guild FBX import failed")
    body = guild.get_editor_property("body_setup")
    body.set_editor_property("collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    unreal.EditorAssetLibrary.save_loaded_asset(guild)
    return guild


def import_stone_bridge():
    task = unreal.AssetImportTask()
    task.filename = str(HERE / "SM_Mistvale_StoneBridge.fbx")
    task.destination_path = "/Game/MistvaleArchitecture"
    task.destination_name = "SM_Mistvale_StoneBridge"
    task.automated = True
    task.save = True
    task.replace_existing = True
    assets.import_asset_tasks([task])
    bridge = unreal.load_asset("/Game/MistvaleArchitecture/SM_Mistvale_StoneBridge")
    if not bridge:
        raise RuntimeError("Custom stone bridge FBX import failed")
    bridge.get_editor_property("body_setup").set_editor_property(
        "collision_trace_flag", unreal.CollisionTraceFlag.CTF_USE_COMPLEX_AS_SIMPLE)
    unreal.EditorAssetLibrary.save_loaded_asset(bridge)
    return bridge


def camera(name, x, y, z, yaw, pitch):
    a = actors.spawn_actor_from_class(unreal.CameraActor, vec(x, y, z))
    a.set_actor_label(name)
    a.set_folder_path("Review_Cameras")
    a.set_actor_rotation(unreal.Rotator(pitch=pitch, yaw=yaw, roll=0), False)


def build():
    if unreal.EditorAssetLibrary.does_asset_exist(LEVEL):
        unreal.EditorLevelLibrary.load_level(LEVEL)
        for existing in actors.get_all_level_actors():
            actors.destroy_actor(existing)
    elif not unreal.EditorLevelLibrary.new_level(LEVEL):
        raise RuntimeError("Could not create new editor level")
    import_terrain()
    guild_mesh = import_guild()
    bridge_mesh = import_stone_bridge()

    # A river is a town-forming corridor. The ribbon is only a water stand-in;
    # the R16 terrain already contains its varied 21-30 m wide channel.
    river_ribbon()

    main = [(6,-320), (5,-235), (-7,-165), (0,-115), (0,-55),
            (-9,-20), (-5,34), (0,72), (-8,117), (-30,155),
            (-16,205), (0,265), (0,330)]
    road("GoldenRoute", main, 5.2)
    road("LowerMarketLoop", [(-75,38),(-54,60),(-31,71),(-21,88),
                              (-27,119),(-63,137),(-90,117),(-75,38)], 3.3)
    road("MarketEastLoop", [(24,73),(47,72),(73,102),(55,132),
                             (27,131),(24,73)], 3.2)
    road("RiversideStreet", [(-174,-141),(-120,-133),(-70,-126),
                               (0,-117),(71,-113),(155,-116)], 3.2)
    road("UpperResidential", [(-84,160),(-66,199),(-52,234),
                                (-25,252),(15,253),(61,231),(81,201)], 3.3)
    road("ChurchLane", [(8,165),(45,174),(89,194),(104,219)], 2.8)
    road("DockTrack", [(-158,-117),(-131,-103),(-98,-87),(-67,-74)], 2.7)

    # Two crossings create distinct everyday and ceremonial traffic paths.
    for name, x, w in [("MainStoneBridge",0,7.0),("SmallServiceBridge",-132,3.2)]:
        ry = river_y(x)
        top = max(elevation(x, ry-18.0), elevation(x, ry+18.0)) + 0.15
        if name == "MainStoneBridge":
            mesh_actor(name+"_DECK", x, ry, top-6.3,
                       1, 1, 1, mesh=bridge_mesh, folder="02_Bridges")
        else:
            mesh_actor(name+"_DECK", x, ry, top-0.35, w, 37.0, 0.7, folder="02_Bridges")
            for dx in (-w/2+0.3,w/2-0.3):
                mesh_actor(name+"_PARAPET", x+dx, ry, top+0.55,
                           0.45, 37.0, 1.1, folder="02_Bridges")
        for side in (-1,1):
            near = ry + side*18.0
            far = ry + side*30.0
            shore = elevation(x, far) + 0.16
            midpoint = (near+far)/2.0
            ramp = mesh_actor(name+("_SouthRamp" if side < 0 else "_NorthRamp"),
                              x, midpoint, (top+shore)/2.0-0.16,
                              w, 12.0, 0.32, folder="02_Bridges")
            ramp.set_actor_rotation(unreal.Rotator(
                pitch=0, yaw=0,
                roll=math.degrees(math.atan2(top-shore, near-far))), False)

    # Hero forms express distinct silhouettes before asset selection.
    mesh_actor("HERO_Guild_HorizontalHall", -55, 165,
               elevation(-55, 165), 1, 1, 1, mesh=guild_mesh, folder="03_Hero")
    mass("HERO_Guild_TrainingYard", -82, 162, 22, 19, 0.35, "03_Hero")
    mass("HERO_Church_Nave", 99, 217, 18, 32, 16, "03_Hero")
    mass("HERO_Church_BellTower", 99, 234, 8, 8, 34, "03_Hero")
    mass("HERO_MainInn", 32, 83, 20, 14, 12, "03_Hero")
    mass("HERO_Blacksmith", -63, 65, 15, 13, 10, "03_Hero")
    mass("HERO_DockWarehouse", -106, -123, 26, 14, 11, "03_Hero")
    mass("HERO_NorthGate_Left", -9, 283, 7, 9, 14, "03_Hero")
    mass("HERO_NorthGate_Right", 9, 283, 7, 9, 14, "03_Hero")
    mesh_actor("HERO_NorthGate_Lintel", 0, 283, elevation(0,283)+13,
               12, 9, 2.8, folder="03_Hero")
    mass("MarketSquare_Well", 0, 100, 3, 3, 2, "04_Market")
    for i in range(8):
        ang = i * math.pi / 4.0
        x, y = 12*math.cos(ang), 100+12*math.sin(ang)
        mass(f"MarketStall_{i+1:02d}", x, y, 3.4, 2.5, 2.6, "04_Market")

    # Hand-authored street walls: rows follow the changing street edges and
    # preserve alleys. No random scatter or copied old Godot coordinates.
    rows = [
        ("LowerWestA", -49, 0, 8, 12.0, -1, 9, 7),
        ("LowerWestB", -12, 1, 7, 11.5, -1, 8, 7),
        ("LowerEastA", 12, -2, 8, 11.5, 1, 9, 7),
        ("LowerEastB", 53, 1, 7, 12.0, 1, 9, 7),
        ("MarketWest", -25, 78, 5, 13.0, -1, 9, 9),
        ("MarketEast", 25, 78, 5, 12.0, 1, 9, 8),
        ("UpperWest", -20, 188, 7, 11.5, -1, 9, 9),
        ("UpperEast", 20, 177, 6, 12.0, 1, 9, 9),
        ("Riverside", -173, -151, 9, 12.0, 1, 9, 7),
    ]
    count = 0
    for district, x0, y0, n, step, side, w, d in rows:
        for i in range(n):
            bend = math.sin(i * 0.76 + len(district) * 0.31)
            x = x0 + 2.7 * bend + (i % 3) * (0.9 if side > 0 else -0.9)
            y = y0 + i * step + 1.4 * math.sin(i * 1.7 + len(district))
            if abs(x) < 18 and 75 < y < 128:
                continue
            height = 7.0 + (i % 3) * 2.4
            house = mass(f"{district}_House_{i+1:02d}", x, y,
                         w + (i % 2) * 1.5, d + (i % 3), height, "05_DenseTown/"+district)
            house.set_actor_rotation(unreal.Rotator(pitch=0, yaw=4.0*bend, roll=0), False)
            count += 1
    # Larger corner forms and edge workshops hold the street rather than
    # leaving detached boxes in grass.
    for i, (x,y,w,d,h) in enumerate([
        (-72,96,15,11,10),(67,80,14,10,11),(-70,215,14,12,12),
        (66,222,15,12,12),(-133,-155,18,12,9),(115,-132,16,11,9),
        (-94,22,14,11,8),(82,38,15,12,9)]):
        mass(f"CornerBuilding_{i+1:02d}",x,y,w,d,h,"05_DenseTown/Corners")
        count += 1
    for i, (x,y,w,d,h) in enumerate([
        (-17,-46,10,9,8),(17,-46,10,9,9),(-19,-24,10,9,9),(19,-24,10,9,8),
        (-32,26,9,8,9),(31,32,10,8,11),
        (-29,-142,10,8,8),(29,-142,10,8,8),
        (-16,267,10,9,10),(16,267,10,9,10),
        (53,184,10,9,10),(75,237,10,9,10)]):
        mass(f"InfillBuilding_{i+1:02d}",x,y,w,d,h,"05_DenseTown/Infill")
        count += 1

    camera("C01_SouthReveal", -12,-233,12,90,-5)
    camera("C02_RiverHero", -72,-116,13,54,-6)
    camera("C03_MainBridge", 0,-129,10,90,-4)
    camera("C04_Market", 3,75,15,88,-5)
    camera("C05_Guild", -12,137,17,158,-5)
    camera("C06_Church", 61,187,19,54,-8)
    camera("C07_RooftopDensity", 36,103,42,150,-35)
    camera("C08_NorthGate", 0,255,22,90,-4)
    camera("C10_WalkStreet", -10,38,14,95,-5)

    light = actors.spawn_actor_from_class(unreal.DirectionalLight, vec(0,0,80))
    light.set_actor_label("ClearDay_Sun")
    light.set_folder_path("06_Lighting")
    light.set_actor_rotation(unreal.Rotator(pitch=-42,yaw=-35,roll=0), False)
    sky = actors.spawn_actor_from_class(unreal.SkyLight, vec(0,0,40))
    sky.set_actor_label("ClearDay_Sky")
    sky.set_folder_path("06_Lighting")
    atmosphere = actors.spawn_actor_from_class(unreal.SkyAtmosphere, vec(0,0,0))
    atmosphere.set_actor_label("ClearDay_Atmosphere")
    atmosphere.set_folder_path("06_Lighting")
    player = actors.spawn_actor_from_class(unreal.PlayerStart,
        vec(6,-320,elevation(6,-320)+1.3))
    player.set_actor_label("SouthForest_PlayerStart")
    player.set_folder_path("07_GameplayReview")

    unreal.EditorLevelLibrary.save_current_level()
    (HERE / "build_result.txt").write_text(
        f"level={LEVEL}\nresidential_commercial_masses={count}\n"
        f"hero_masses=10\nmarket_stalls=8\nreview_cameras=9\n"
        f"river_reach=500m\nbridges=2\n", encoding="utf-8")


build()
