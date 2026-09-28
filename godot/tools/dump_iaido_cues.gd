extends SceneTree
##
## Dumps the Iaido audio cue table, read out of `IaidoAudioTimeline` itself.
##
## WHY THIS EXISTS
##
## `encode_iaido_movie.sh` has to place every cue in the mixed audio track at the
## exact time the game fires it, so it carried a hand-typed copy of the cue list.
## By the time this tool was written that copy had already drifted: `pressure`
## was still at the old `suck_start` (2.50 against 2.14) and `spin` was at 6.25
## against 6.45, so the delivered movie's audio was up to 0.36s away from what
## the game actually plays. Nothing failed. A mirror that is only checked by eye
## is a mirror that is wrong.
##
## So the encoder asks for the table at encode time instead of storing one, and
## the drift class is gone rather than re-baselined. `IaidoAudioTimeline` is the
## only place a cue time is written down.
##
## Output: one `CUE <file>:<time>:<gain_db>:<extra>` line per cue, ascending by
## time, which is exactly the format `encode_iaido_movie.sh` consumes. Anything
## that is not a `CUE ` line is a header or a warning.
##
## Usage:
##   godot --headless --path godot --script res://tools/dump_iaido_cues.gd

func _initialize() -> void:
	var timeline := IaidoAudioTimeline.new()
	# `_ready` is what builds the table, and `_ready` needs a tree.
	root.add_child(timeline)
	await process_frame

	if timeline.cues.is_empty():
		push_error("IaidoAudioTimeline produced no cues — no cue file would be placed.")
		quit(1)
		return

	# `cues` carries the time, and the player carries everything else. Sorted so
	# the table is stable across runs and can be diffed.
	var rows: Array = []
	for cue in timeline.cues:
		var name: StringName = cue["name"]
		var player := timeline.players.get(name) as AudioStreamPlayer
		if player == null or player.stream == null:
			push_warning("Iaido cue has no stream: " + String(name))
			continue
		rows.append({
			"time": float(cue["time"]),
			"file": player.stream.resource_path.get_file(),
			"gain": player.volume_db,
			"pitch": player.pitch_scale,
			"name": String(name),
		})
	rows.sort_custom(func(a, b) -> bool: return float(a["time"]) < float(b["time"]))

	print("# %-16s %-22s %8s %6s  %s" % ["cue", "file", "time", "gain", "pitch"])
	for row in rows:
		var pitch := float(row["pitch"])
		# Godot's pitch_scale moves speed and pitch together; `atempo` is the
		# ffmpeg side of the same thing, and only when it is not 1.0.
		var extra := "" if is_equal_approx(pitch, 1.0) else "atempo=%.2f" % pitch
		print("# %-16s %-22s %8.2f %6.1f  %s"
			% [row["name"], row["file"], float(row["time"]), float(row["gain"]), extra])
		print("CUE %s:%.2f:%.1f:%s"
			% [row["file"], float(row["time"]), float(row["gain"]), extra])

	quit(0)
