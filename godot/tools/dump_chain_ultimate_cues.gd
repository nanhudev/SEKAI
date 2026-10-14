extends SceneTree
##
## Dumps the chain ultimate's audio cue table, read out of
## `ChainUltimateAudioTimeline` itself.
##
## WHY THIS EXISTS
##
## `encode_chain_ultimate_movie.sh` has to place every cue in the mixed track at
## the exact time the game fires it. The iaido line already paid for the
## alternative: its encoder carried a hand-typed copy of the cue list, the copy
## drifted a third of a second, and nothing failed because nothing compared the
## two. So the encoder ASKS for the table and `ChainUltimateAudioTimeline` stays
## the only file in this ceremony that names a sound.
##
## Output: one `CUE <relative-path-under-audio/>:<time>:<gain_db>:<extra>` line
## per cue, ascending by time. The path is relative to `res://audio/` because this
## ceremony draws from two libraries (the chain's metal and iaido's world layer)
## and a single fixed directory would silently fail to find half of them.
##
## Usage:
##   godot --headless --path godot --script res://tools/dump_chain_ultimate_cues.gd

func _initialize() -> void:
	var timeline := ChainUltimateAudioTimeline.new()
	timeline.configure(ChainUltimateTuning.new())
	# `_ready` is what builds the table, and `_ready` needs a tree.
	root.add_child(timeline)
	await process_frame

	if timeline.cues.is_empty():
		push_error("ChainUltimateAudioTimeline produced no cues — no cue file would be placed.")
		quit(1)
		return

	var rows: Array = []
	for cue in timeline.cues:
		var name: StringName = cue["name"]
		var player := timeline.players.get(name) as AudioStreamPlayer
		if player == null or player.stream == null:
			push_warning("Chain ultimate cue has no stream: " + String(name))
			continue
		var path := player.stream.resource_path
		if not path.begins_with("res://audio/"):
			push_error("cue %s is outside res://audio/ : %s" % [String(name), path])
			quit(1)
			return
		rows.append({
			"time": float(cue["time"]),
			"file": path.substr("res://audio/".length()),
			"gain": player.volume_db,
			"pitch": player.pitch_scale,
			"name": String(name),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["time"]) < float(b["time"]))

	print("# %-16s %-52s %8s %6s  %s" % ["cue", "file", "time", "gain", "pitch"])
	for row in rows:
		var pitch := float(row["pitch"])
		# Godot's pitch_scale moves speed and pitch together; `atempo` is the
		# ffmpeg side of the same thing, and only when it is not 1.0.
		var extra := "" if is_equal_approx(pitch, 1.0) else "atempo=%.2f" % pitch
		print("# %-16s %-52s %8.2f %6.1f  %s"
			% [row["name"], row["file"], float(row["time"]), float(row["gain"]), extra])
		print("CUE %s:%.2f:%.1f:%s"
			% [row["file"], float(row["time"]), float(row["gain"]), extra])

	quit(0)
