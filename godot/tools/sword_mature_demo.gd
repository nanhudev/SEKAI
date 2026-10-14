extends "res://tools/sword_feel_v2_demo.gd"

func _initialize() -> void:
	output = "E:/SEKAI-SwordMature-20261013"
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("boot")

func boot() -> void:
	await super.boot()
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.get_node("CameraRig/LookPivot").rotation = Vector3.ZERO
	sequence = [
		[0.0,"title","SWORD / TWO-HANDED GUARD / TrainingGround input review"],
		[1.5,"still","idle_a"],[3.5,"still","idle_b"],
		[5.0,"title","DRAW / independent physical scabbard action"],[5.1,"putaway",0],
		[7.2,"equip",0],[8.3,"still","draw"],
		[10.0,"title","FOUR CUTS / probe - return - rise - committed major arc"],
		[10.1,"light_attack",true],[10.2,"light_attack",false],[10.75,"light_attack",true],[10.85,"light_attack",false],
		[11.4,"light_attack",true],[11.5,"light_attack",false],[12.05,"still","a3_rise"],
		[12.35,"light_attack",true],[12.45,"light_attack",false],[12.78,"still","a4_arc"],
		[15.0,"title","WHIFF / no contact bite / fixture reset"],[15.1,"station",10.0],
		[15.5,"light_attack",true],[15.6,"light_attack",false],[15.72,"still","whiff"],
		[16.15,"title","HEAVY / load - hold - immediate release"],[16.2,"heavy_attack",true],
		[16.62,"still","heavy_load"],[16.65,"heavy_attack",false],[16.80,"still","heavy_release"],
		[18.0,"title","BODY CONTACT / blade bite and recovery / fixture reset"],[18.1,"station",2.1],[18.2,"surface","body"],
		[18.5,"light_attack",true],[18.6,"light_attack",false],[18.72,"still","body_contact"],
		[21.0,"title","METAL CONTACT / greater resistance / fixture reset"],[21.1,"station",2.1],[21.2,"surface","metal"],
		[21.5,"light_attack",true],[21.6,"light_attack",false],[21.73,"still","metal_contact"],
		[24.0,"title","STONE CONTACT / strongest resistance / fixture reset"],[24.1,"station",2.1],[24.2,"surface","stone"],
		[24.5,"light_attack",true],[24.6,"light_attack",false],
		[28.8,"title","IAIDO / sheath - hold - draw - split - single turn - closure"],
		[28.9,"station",3.2],[29.1,"skill_1",true],[29.2,"skill_1",false],
		[29.6,"still","iaido_hold"],[30.08,"still","iaido_split"],[31.15,"still","iaido_sheath"],
		[34.0,"title","CLOSE STEEL INSPECTION / both hands remain connected"],
		[34.1,"inspect",true],[34.2,"inspect",false],[34.8,"still","steel_inspect"],
		[37.0,"title","SHEATH / final seated click"],[37.1,"putaway",0],[38.7,"still","final_sheath"],
		[40.0,"title","Scripted real-input review / hands-on feel acceptance pending"],
	]

func station(distance:float) -> void:
	super.station(distance)
	if is_instance_valid(player):
		player.get_node("CameraRig/LookPivot").rotation = Vector3.ZERO
