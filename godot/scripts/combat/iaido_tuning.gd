extends Resource
class_name IaidoTuning

# ---------------------------------------------------------------------------
# SEKAI · Iaido / 聚合斩 — Signature Skill master timeline.
#
# Artistic direction: this is a 7.2 second high-rank sword ceremony, NOT a
# 1-2 second flourish. Do NOT compress it to make it "feel responsive".
# Every phase below is deliberate. Compression is only allowed after the
# user playtests, and even then it should arrive as an "Iaido mastery"
# talent, not as a silent tuning change.
#
# All timings are real seconds from the moment the skill is activated.
# Nothing here should be 0.1 / 0.12 / 0.15 / 0.2 except the true draw.
# ---------------------------------------------------------------------------

# --- PHASE A · WORLD SILENCE ---------------------------------------------
@export_group("A · World Silence")
@export var silence_start := 0.0
@export var silence_end := 0.45
@export var silence_fov := 4.0
@export var silence_desaturation := 0.60

# --- PHASE B · RETURN TO SHEATH ------------------------------------------
@export_group("B · Return To Sheath")
@export var sheath_start := 0.45
@export var sheath_end := 1.20
@export var sheath_move_cue := 0.80

# --- PHASE C · REVERSE WAVE ----------------------------------------------
@export_group("C · Reverse Wave")
@export var wave_start := 1.20
@export var ring1_start := 1.20
@export var ring1_end := 1.50
@export var ring2_start := 1.45
@export var ring2_end := 1.80
@export var ring3_start := 1.70
@export var ring3_end := 2.05
@export var wave_end := 2.20
@export var wave_fov := 7.0

# --- PHASE D · COMPRESSION HOLD ------------------------------------------
@export_group("D · Compression Hold")
@export var hold_start := 2.20
@export var hold_end := 2.85
@export var hold_fov := 9.0
@export var hold_desaturation := 0.66

# --- PHASE E · SHEATH LOCK ------------------------------------------------
@export_group("E · Sheath Lock")
@export var fov_pull_start := 2.75
@export var fov_pull_end := 2.95
@export var first_click := 2.85
@export var draw_fov := 13.0
@export var ivory_flash_duration := 0.035
@export var ivory_flash_strength := 0.30

# --- PHASE F · INSTANT DRAW -----------------------------------------------
@export_group("F · Instant Draw")
@export var draw_start := 2.95
@export var draw_end := 3.08

# --- PHASE G · WORLD CUT ---------------------------------------------------
@export_group("G · World Cut")
@export var cut_start := 3.08
@export var gap_mid_time := 3.20
@export var cut_end := 3.40
@export var gap_start_px := 3.0
@export var gap_mid_px := 8.0
@export var gap_max_px := 22.0

# --- PHASE H · WORLD SEPARATION ------------------------------------------
@export_group("H · World Separation")
@export var separate_start := 3.40
@export var separate_end := 3.90
@export var separation_px := 22.0
@export var depth_parallax := 0.006

# --- PHASE I · TENSION FREEZE ---------------------------------------------
@export_group("I · Tension Freeze")
@export var freeze_start := 3.90
@export var freeze_frame_end := 4.02
@export var freeze_end := 4.25
@export var cut_desaturation := 0.70

# --- PHASE J · GLASS FAILURE ----------------------------------------------
@export_group("J · Glass Failure")
@export var glass_start := 4.25
@export var shard_burst := 4.58
@export var glass_end := 4.75
@export var post_break_slide_px := 16.0

# --- PHASE K · SWORD CONTROL ----------------------------------------------
@export_group("K · Sword Control")
@export var spin_start := 4.40
@export var spin_first_end := 4.90
@export var spin_end := 5.35

# --- PHASE L · SLOW SHEATHE -----------------------------------------------
@export_group("L · Slow Sheathe")
@export var slow_sheathe_start := 5.35
@export var slow_sheathe_end := 6.20
@export var final_click := 6.20
@export var void_narrow_px := 14.0

# --- PHASE M · REALITY COLLAPSE -------------------------------------------
@export_group("M · Reality Collapse")
@export var collapse_start := 6.20
@export var collapse_end := 6.65
@export var collapse_gap_px := 24.0

# --- PHASE N · RESTORE -----------------------------------------------------
@export_group("N · Restore")
@export var restore_start := 6.65
@export var restore_end := 7.20
@export var reconnect_pulse := 0.030

# --- Combat resolution -----------------------------------------------------
@export_group("Combat")
@export var damage_time := 3.03

# --- Framing ---------------------------------------------------------------
@export_group("Framing")
@export var sheath_position := Vector3(-0.52, -0.43, -0.80)
@export var sheath_rotation := Vector3(0.15, -0.10, 2.25)
@export var drawn_position := Vector3(0.36, -0.24, -0.82)
@export var drawn_rotation := Vector3(-0.30, 0.10, -0.75)
@export var cut_angle_degrees := -30.0
@export var cut_center := Vector2(0.5, 0.5)
@export var void_core_width := 0.16
@export var void_edge_width_px := 1.2

# --- Void palette (cold, airless, NOT sci-fi portal) -----------------------
@export_group("Void Palette")
@export var void_edge_color := Color(0.010, 0.020, 0.055)
@export var void_mid_color := Color(0.055, 0.085, 0.215)
@export var void_core_color := Color(0.620, 0.760, 0.880)
@export var void_life := 1.0

# --- Glass -----------------------------------------------------------------
@export_group("Glass")
@export var shard_count := 14
@export var shard_min_delay := 0.03
@export var shard_max_delay := 0.08
@export var shard_drag := 3.2
@export var shard_gravity := 1.1
@export var refract_px := 4.0
@export var rim_px := 2.5

# --- Playback --------------------------------------------------------------
@export_group("Playback")
@export_range(0.25, 2.0, 0.05) var debug_speed := 1.0


# --- Easing helpers --------------------------------------------------------
# Kept here so every stage uses the same curves. Do not inline raw lerps
# in the director; a signature skill lives or dies on its easing.

static func span(t: float, start: float, end: float) -> float:
	return clampf((t - start) / maxf(end - start, 0.0001), 0.0, 1.0)


static func ease_out_cubic(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 3.0)


static func ease_out_quint(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - u, 5.0)


static func ease_in_cubic(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return pow(u, 3.0)


static func ease_in_accel(x: float) -> float:
	# Slow release, violent finish. Used by the instant draw.
	var u := clampf(x, 0.0, 1.0)
	return pow(u, 2.6)


static func ease_in_out(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func smooth(x: float) -> float:
	var u := clampf(x, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


func total_duration() -> float:
	return restore_end
