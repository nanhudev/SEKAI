extends Node3D
class_name PlazaStele
# 广场中央石碑 — the centre of the square, and the world's first unexplained event.
#
# §1 asks the plaza for a centrepiece; §3 and §19 ask for the same object to do
# something it does not explain. Both jobs belong to one prop on purpose: a
# separate "monument" and a separate "anomaly" would be two objects, and the whole
# force of the second anomaly is that the player ALREADY KNOWS THIS STONE.
#
# WHAT `pulse()` IS. Not a spell, not a beacon lighting up - a stone whose
# inscription briefly becomes legible and then stops. The runes are emissive
# geometry that is dark until asked, the light they throw is a short-lived
# OmniLight3D, and the whole event is under 1.5 s. Every number is derived from
# the `strength` the director passes, so the opening (1.0) and the second
# anomaly (1.7) are the same event at two volumes rather than two effects.
#
# IT IS DELIBERATELY NOT A QUEST MARKER. It never glows on approach, never has a
# prompt, and cannot be interacted with. The moment it becomes a thing you walk
# up to and press E on, it stops being an anomaly and becomes furniture.

const TB := preload("res://scripts/training/training_build.gd")

const STONE := Color(0.372, 0.372, 0.352)
const STONE_DARK := Color(0.252, 0.256, 0.246)
const BASE := Color(0.428, 0.420, 0.398)
const RUNE := Color(0.72, 0.90, 1.0)

const HEIGHT := 2.35
const WIDTH := 0.86
const THICK := 0.30
const BASE_R := 1.55

signal pulsed(strength: float)

var _runes: Array[MeshInstance3D] = []
var _rune_materials: Array[StandardMaterial3D] = []
var _light: OmniLight3D = null
var _flash := 0.0
var _flash_peak := 0.0


func _ready() -> void:
	_build()
	set_process(true)


func _build() -> void:
	var stone := TB.material(STONE, 0.82)
	var dark := TB.material(STONE_DARK, 0.88)
	var base_mat := TB.material(BASE, 0.80)

	# A two-step round plinth, so the stone stands ON something. Without it a
	# 2.35 m slab in the middle of a square reads as a dropped object.
	var lower := MeshInstance3D.new()
	lower.name = "PlinthLower"
	var lc := CylinderMesh.new()
	lc.height = 0.17
	lc.top_radius = BASE_R
	lc.bottom_radius = BASE_R + 0.10
	lc.radial_segments = 24
	lower.mesh = lc
	lower.position = Vector3(0.0, 0.085, 0.0)
	lower.material_override = base_mat
	add_child(lower)
	var upper := MeshInstance3D.new()
	upper.name = "PlinthUpper"
	var uc := CylinderMesh.new()
	uc.height = 0.19
	uc.top_radius = BASE_R - 0.30
	uc.bottom_radius = BASE_R - 0.24
	uc.radial_segments = 24
	upper.mesh = uc
	upper.position = Vector3(0.0, 0.26, 0.0)
	upper.material_override = dark
	add_child(upper)

	var plinth_body := StaticBody3D.new()
	plinth_body.name = "PlinthBody"
	var pc := CollisionShape3D.new()
	var pcyl := CylinderShape3D.new()
	pcyl.height = 0.36
	pcyl.radius = BASE_R
	pc.shape = pcyl
	pc.position = Vector3(0.0, 0.18, 0.0)
	plinth_body.add_child(pc)
	add_child(plinth_body)

	# The stone itself, slightly tapered, with its face toward +Z. The taper is
	# what stops it reading as a shipping crate.
	var shaft := MeshInstance3D.new()
	shaft.name = "Shaft"
	var box := BoxMesh.new()
	box.size = Vector3(WIDTH, HEIGHT, THICK)
	shaft.mesh = box
	shaft.position = Vector3(0.0, 0.36 + HEIGHT * 0.5, 0.0)
	shaft.material_override = stone
	add_child(shaft)
	var shaft_body := StaticBody3D.new()
	shaft_body.name = "ShaftBody"
	var sc := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3(WIDTH, HEIGHT, THICK)
	sc.shape = sbox
	sc.position = shaft.position
	shaft_body.add_child(sc)
	add_child(shaft_body)

	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var cbox := BoxMesh.new()
	cbox.size = Vector3(WIDTH + 0.10, 0.13, THICK + 0.10)
	cap.mesh = cbox
	cap.position = Vector3(0.0, 0.36 + HEIGHT + 0.06, 0.0)
	cap.material_override = dark
	add_child(cap)

	_build_runes()

	_light = OmniLight3D.new()
	_light.name = "RuneLight"
	_light.position = Vector3(0.0, 0.36 + HEIGHT * 0.55, 0.42)
	_light.omni_range = 5.6
	_light.light_color = Color(0.62, 0.84, 1.0)
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	add_child(_light)


## THE INSCRIPTION. A column of marks down the face, each one its own mesh with
## its own material instance.
##
## WHY NOT A TEXTURE. There is no rune texture in the project and this round must
## not commission one; geometry also lets the glow be per-mark, so a pulse can
## travel down the column rather than lighting the whole face at once, which is
## what makes it read as something being READ rather than something being lit.
func _build_runes() -> void:
	var rows := 7
	var top := 0.36 + HEIGHT - 0.24
	var step := (HEIGHT - 0.46) / float(rows - 1)
	var face_z := THICK * 0.5 + 0.006
	for i in rows:
		# Deterministic pseudo-random widths, so the inscription is the same
		# stone every run - a randomly generated face would be a different
		# monument each time and the second anomaly would land on a stranger.
		var seed_i := float(i)
		var w := 0.40 - 0.16 * absf(sin(seed_i * 2.399))
		var offset := 0.055 * sin(seed_i * 1.71)
		var mi := MeshInstance3D.new()
		mi.name = "Rune%02d" % i
		var rm := BoxMesh.new()
		rm.size = Vector3(w, 0.045, 0.012)
		mi.mesh = rm
		mi.position = Vector3(offset, top - step * i, face_z)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.10, 0.13, 0.15)
		mat.emission_enabled = true
		mat.emission = RUNE
		mat.emission_energy_multiplier = 0.0
		mi.material_override = mat
		add_child(mi)
		_runes.append(mi)
		_rune_materials.append(mat)


# ================================================================ public API

## The world blinked. `strength` 1.0 is the opening (barely there, and gone
## before the player is sure they saw it), 1.7 is the closing one (the same
## event, and now the character standing next to you has seen it too).
func pulse(strength := 1.0) -> void:
	_flash_peak = clampf(strength, 0.2, 3.0)
	_flash = _flash_peak
	pulsed.emit(strength)


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	# A fast rise and a slow tail, so the marks do not switch off - they stop.
	_flash = maxf(0.0, _flash - delta * 1.35)
	var u := _flash / maxf(_flash_peak, 0.001)
	var lead := (1.0 - u) * float(_runes.size()) * 1.5
	for i in _runes.size():
		# A WAVE DOWN THE COLUMN. Each mark lights when the front reaches it, so
		# the inscription reads top-to-bottom in about a third of a second.
		var local := clampf(1.0 - absf(float(i) - lead) * 0.9, 0.0, 1.0)
		local = local * local
		_rune_materials[i].emission_energy_multiplier = local * 7.0 * _flash_peak
	if _light != null:
		_light.light_energy = u * 5.2 * _flash_peak
