extends RefCounted
class_name AudioBusCapture
## Records a real audio bus straight off the audio thread and writes a .wav while
## the take is still running.
##
## WHY TAP THE BUS INSTEAD OF MIXING THE CAPTURED TIMELINE OFFLINE.
## The chain line mixes offline from a timeline, and for that brief it was right -
## the question was "does the weapon have a voice", and arithmetic answers it. This
## pass is judged on two things arithmetic cannot produce:
##   * the CONTACT layer is SPATIAL (PART M). Question F in the brief is literally
##     "does the contact arrive from the target's direction" - that is the engine's
##     own panner doing the work, so a mono re-mix of the same cue ids would answer
##     a different question and look like a pass.
##   * the mix has to survive being the mix. Level, voice stealing and bus routing
##     are decisions the game makes at runtime; a second implementation of them in
##     python is a second set of decisions that can be wrong in the dark.
##
## Works under `--audio-driver Dummy`: the dummy driver still runs the mix graph in
## real time (measured 163840 frames in 3.70 s of wall clock at 44.1 kHz), so a
## render needs no sound card and makes no noise on the machine doing it.
##
## Streaming write, not "collect then save": a 40 s take at 44.1 kHz stereo is
## 7 MB of PackedVector2Array per second if it is held in memory.

const HEADER_BYTES := 44
const CHANNELS := 2
const BITS := 16

var bus: StringName = &"SFX"
var mix_rate := 44100
var frames_written := 0
var path := ""
var error := ""

var _effect: AudioEffectCapture
var _bus_index := -1
var _file: FileAccess
var _started_msec := 0


## Tap `bus_name` and open `out_path`. Returns false (with `error` set) rather than
## throwing, because this runs inside a render loop that has to be able to say what
## went wrong instead of hanging.
func begin(out_path: String, bus_name: StringName = &"SFX", seconds := 12.0) -> bool:
	path = out_path
	bus = bus_name
	_bus_index = AudioServer.get_bus_index(bus)
	if _bus_index == -1:
		error = "no audio bus named '%s'" % String(bus)
		return false
	mix_rate = AudioServer.get_mix_rate()
	_effect = AudioEffectCapture.new()
	_effect.buffer_length = seconds
	AudioServer.add_bus_effect(_bus_index, _effect, 0)
	_file = FileAccess.open(out_path, FileAccess.WRITE)
	if _file == null:
		error = "cannot open %s (%d)" % [out_path, FileAccess.get_open_error()]
		_remove_effect()
		return false
	_write_header(0)
	_started_msec = Time.get_ticks_msec()
	return true


## Call once per frame. Draining every frame is the point: `get_frames_available`
## grows with the mix, and a tap that is only read at the end of a take loses
## whatever the ring buffer had to throw away in between.
func drain() -> void:
	if _effect == null or _file == null:
		return
	var available := _effect.get_frames_available()
	if available <= 0:
		return
	var block := _effect.get_buffer(available)
	var bytes := PackedByteArray()
	bytes.resize(block.size() * 4)
	for i in block.size():
		var frame := block[i]
		bytes.encode_s16(i * 4, int(clampf(frame.x, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 4 + 2, int(clampf(frame.y, -1.0, 1.0) * 32767.0))
	_file.store_buffer(bytes)
	frames_written += block.size()


## Patch the header with the real sizes, close the file and give the bus back.
## Returns the recorded duration in seconds.
func finish() -> float:
	if _effect != null:
		drain()
	if _file != null:
		_file.seek(4)
		_file.store_32(HEADER_BYTES - 8 + frames_written * CHANNELS * (BITS / 8))
		_file.seek(40)
		_file.store_32(frames_written * CHANNELS * (BITS / 8))
		_file.close()
		_file = null
	_remove_effect()
	return float(frames_written) / float(maxi(mix_rate, 1))


func elapsed() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


func _write_header(data_size: int) -> void:
	_file.store_string("RIFF")
	_file.store_32(HEADER_BYTES - 8 + data_size)
	_file.store_string("WAVE")
	_file.store_string("fmt ")
	_file.store_32(16)
	_file.store_16(1)                          # PCM
	_file.store_16(CHANNELS)
	_file.store_32(mix_rate)
	_file.store_32(mix_rate * CHANNELS * (BITS / 8))
	_file.store_16(CHANNELS * (BITS / 8))
	_file.store_16(BITS)
	_file.store_string("data")
	_file.store_32(data_size)


func _remove_effect() -> void:
	if _effect != null and _bus_index != -1:
		AudioServer.remove_bus_effect(_bus_index, 0)
	_effect = null
