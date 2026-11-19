class_name ProceduralAudio
extends RefCounted
## Placeholder combat sounds synthesised in code (no external assets, no
## licence questions). To be replaced in phase 7.

const RATE := 22050
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func get_stream(id: StringName) -> AudioStreamWAV:
	if not _cache.has(id):
		_cache[id] = _make(id)
	return _cache[id]


static func _make(id: StringName) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	match id:
		&"swing":
			samples = _noise_sweep(0.16, 0.25, 900.0, 300.0)
		&"hit":
			samples = _mix(_tone(0.18, 90.0, 0.9, 18.0), _noise_sweep(0.12, 0.6, 2500.0, 400.0))
		&"heavy_hit":
			samples = _mix(_tone(0.32, 60.0, 1.0, 9.0), _noise_sweep(0.22, 0.7, 1800.0, 200.0))
		&"guard":
			samples = _mix(_tone(0.2, 520.0, 0.5, 14.0), _tone(0.2, 780.0, 0.3, 16.0))
		&"guard_break":
			samples = _mix(_tone(0.35, 140.0, 0.8, 7.0), _noise_sweep(0.3, 0.6, 3000.0, 300.0))
		&"parry":
			samples = _mix(_mix(_tone(0.45, 1320.0, 0.45, 6.0), _tone(0.45, 1980.0, 0.3, 7.0)), _tone(0.08, 300.0, 0.6, 40.0))
		&"reflect":
			samples = _mix(_tone(0.3, 1760.0, 0.4, 8.0), _noise_sweep(0.1, 0.2, 4000.0, 2000.0))
		&"telegraph":
			samples = _tone(0.25, 440.0, 0.25, 4.0, 220.0)
		&"ult":
			samples = _mix(_mix(_tone(1.2, 261.6, 0.35, 1.5), _tone(1.2, 329.6, 0.3, 1.5)), _tone(1.2, 392.0, 0.3, 1.5))
		&"death":
			samples = _mix(_tone(0.8, 80.0, 0.9, 3.0, -40.0), _noise_sweep(0.6, 0.5, 1200.0, 100.0))
		_:
			samples = _tone(0.1, 440.0, 0.3, 20.0)
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s


## Decaying sine; `slide` Hz/s pitch glide.
static func _tone(len: float, freq: float, amp: float, decay: float, slide: float = 0.0) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * (freq + slide * t) / RATE
		out[i] = sin(phase) * amp * exp(-decay * t)
	return out


## Filtered noise burst whose brightness slides from f0 to f1.
static func _noise_sweep(len: float, amp: float, f0: float, f1: float) -> PackedFloat32Array:
	var n := int(len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := lerpf(f0, f1, t)
		var a := clampf(TAU * cutoff / RATE, 0.0, 1.0)
		y += a * (rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * amp * (1.0 - t) * minf(t * 20.0, 1.0) * 2.0
	return out


static func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var n := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out
