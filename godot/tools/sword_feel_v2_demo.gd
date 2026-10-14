extends "res://tools/sword_final_test.gd"
# Same TrainingGround recorder and input path, focused on the seven feel gates.
func _initialize() -> void:
	output = "E:/SEKAI-SwordFeelV2-20261012"
	super._initialize()

func boot() -> void:
	await super.boot()
	station(2.1)
	sequence = [
		[0.0,"title","SWORD FEEL V2 / IDLE / scripted TrainingGround review"],
		[1.5,"still","idle_a"],[3.5,"still","idle_b"],
		[5.0,"title","01 / SHEATH AND DRAW / physical bore"],[5.1,"putaway",0],
		[7.2,"equip",0],[8.3,"still","draw"],
		[10.0,"title","02 / A1 PROBE - A2 RETURN - A3 RISE - A4 MAJOR ARC"],
		[10.1,"light_attack",true],[10.2,"light_attack",false],[10.75,"light_attack",true],[10.85,"light_attack",false],
		[11.4,"light_attack",true],[11.5,"light_attack",false],[11.78,"still","a3_rise"],
		[12.25,"light_attack",true],[12.35,"light_attack",false],[12.6,"still","a4_arc"],
		[15.0,"title","03 / BODY CONTACT / fixture reset"],[15.1,"station",2.1],[15.2,"surface","body"],
		[15.5,"light_attack",true],[15.6,"light_attack",false],
		[18.0,"title","04 / METAL CONTACT / fixture reset"],[18.1,"station",2.1],[18.2,"surface","metal"],
		[18.5,"light_attack",true],[18.6,"light_attack",false],
		[21.0,"title","05 / STONE CONTACT / fixture reset"],[21.1,"station",2.1],[21.2,"surface","stone"],
		[21.5,"light_attack",true],[21.6,"light_attack",false],
		[24.8,"title","06 / IAIDO / seat - hold - draw - split - single turn - sheath"],
		[24.9,"station",3.2],[25.1,"skill_1",true],[25.2,"skill_1",false],
		[25.6,"still","iaido_hold"],[26.08,"still","iaido_split"],[27.15,"still","iaido_sheath"],
		[30.0,"title","07 / CLOSE STEEL INSPECTION"],[30.1,"inspect",true],[30.2,"inspect",false],
		[30.8,"still","steel_inspect"],
		[35.0,"title","08 / FINAL SHEATH / seated closure"],[35.1,"putaway",0],[36.7,"still","final_sheath"],
		[38.0,"title","TrainingGround input replay / real-time feel requires hands-on review"],
	]
