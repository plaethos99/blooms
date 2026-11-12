extends Node
## Procedural audio for LAST LIGHT. Every sound is synthesized in code (no audio files,
## no downloads), on a background thread while the intro screen is up. To swap in a real
## recording later, put any AudioStream into `bank` under the same name.

const RATE := 22050
const AMB := ["wind", "pad", "night", "pulse", "drive"]
const BAKE_DIR := "res://audio/"
const SOUND_NAMES := [
	"wind", "pad", "night", "pulse", "chime0", "chime1", "chime2", "chime3", "chime4",
	"hollow_loop", "hollow_form", "bite", "hit", "swing", "hollow_die", "flare", "bloom",
	"shard", "tool", "brace", "hurt", "gate_open", "escape", "lantern_out", "heart",
	"tick", "step", "deny", "toll",
	"jump", "swish", "shove", "fall", "screech", "hiss", "roar", "wyrm_burst", "drop_warn",
	"drop_impact", "flare_get", "drum", "go", "water", "drive",
]

var bank := {}

var main
var pool: Array = []
var pool_i := 0
var amb := {}
var amb_level := {}
var heart: AudioStreamPlayer
var chime_t := 3.0
var music_on := true
var ready_ := false
var _task := -1
var _built := {}


func _ready() -> void:
	_setup_buses()
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		pool.append(p)
	heart = AudioStreamPlayer.new()
	heart.bus = "SFX"
	heart.volume_db = -3.0
	add_child(heart)
	if bank.is_empty() and not _load_baked():
		_task = WorkerThreadPool.add_task(_build_bank, false, "LAST LIGHT audio synthesis")
	else:
		_on_bank_ready()


## Loads pre-synthesized sounds from res://audio/*.res (made by `-- --bake-audio`).
func _load_baked() -> bool:
	var b := {}
	for n in SOUND_NAMES:
		var path: String = BAKE_DIR + n + ".res"
		if not ResourceLoader.exists(path):
			return false
		var r = load(path)
		if r == null:
			return false
		b[n] = r
	bank = b
	return true


## Synthesizes every sound and saves it to res://audio/ so the game loads them instantly.
func bake_to_disk() -> void:
	var t0 := Time.get_ticks_msec()
	_build_bank()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BAKE_DIR))
	for n in SOUND_NAMES:
		var err := ResourceSaver.save(_built[n], BAKE_DIR + n + ".res")
		if err != OK:
			push_error("Could not save sound %s (%d)" % [n, err])
	print("Baked %d sounds to %s in %d ms" % [SOUND_NAMES.size(), BAKE_DIR, Time.get_ticks_msec() - t0])


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	# Stop everything so the audio server releases its streams before shutdown.
	for c in get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
			c.stream = null


func _setup_buses() -> void:
	for spec in [["Ambience", 0.3, 0.85, -4.0], ["SFX", 0.18, 0.55, 0.0]]:
		if AudioServer.get_bus_index(spec[0]) != -1:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, spec[0])
		AudioServer.set_bus_send(idx, "Master")
		AudioServer.set_bus_volume_db(idx, spec[3])
		var rv := AudioEffectReverb.new()
		rv.wet = spec[1]
		rv.room_size = spec[2]
		rv.damping = 0.45
		rv.dry = 1.0
		AudioServer.add_bus_effect(idx, rv)


func _on_bank_ready() -> void:
	ready_ = true
	if main and main.args.has("log"):
		print("audio bank ready: %d sounds after %d ms" % [bank.size(), Time.get_ticks_msec()])
	for n in AMB:
		var a := AudioStreamPlayer.new()
		a.stream = bank[n]
		a.bus = "Ambience"
		a.volume_db = -80.0
		add_child(a)
		a.play()
		amb[n] = a
		amb_level[n] = 0.0
	heart.stream = bank["heart"]
	# Every waterfall roars softly where it pours off its island.
	if main and main.world:
		for lip in main.world.waterfalls:
			var w := AudioStreamPlayer3D.new()
			w.stream = bank["water"]
			w.bus = "Ambience"
			w.unit_size = 5.0
			w.max_distance = 45.0
			w.volume_db = -4.0
			add_child(w)
			w.global_position = lip - Vector3(0, 2.0, 0)
			w.play(randf() * 3.0)


# ---------------------------------------------------------------- playback API

func play(sound: String, pos = null, vol_db := 0.0, pitch := 1.0) -> void:
	if not bank.has(sound):
		return
	if pos == null:
		var p: AudioStreamPlayer = pool[pool_i]
		pool_i = (pool_i + 1) % pool.size()
		p.stream = bank[sound]
		p.volume_db = vol_db
		p.pitch_scale = pitch
		p.play()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = bank[sound]
		p3.volume_db = vol_db
		p3.pitch_scale = pitch
		p3.bus = "SFX"
		p3.unit_size = 6.0
		p3.max_distance = 70.0
		add_child(p3)
		p3.global_position = pos
		p3.play()
		p3.finished.connect(p3.queue_free)


func attach_loop(player: AudioStreamPlayer3D, sound: String) -> void:
	if bank.has(sound):
		player.stream = bank[sound]
		player.play(randf() * 2.0)


func toggle_music() -> bool:
	music_on = not music_on
	return music_on


func _process(delta: float) -> void:
	if not ready_:
		if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			bank = _built
			_on_bank_ready()
		return
	if main == null:
		return
	var f: float = main.frac()
	var night := smoothstep(0.5, 1.0, f)
	var st: String = main.state
	var target := {
		"wind": 0.5 + 0.3 * night,
		"pad": 0.42 * (1.0 - night) + 0.04,
		"night": 0.55 * night,
		"pulse": 0.65 if (main.final_phase and st == "playing") else 0.0,
		"drive": 0.0,
	}
	if st == "playing" or st == "countdown":
		# A driving rhythm under the whole match that swells when things get hairy.
		var hot := 0.0
		if not main.drops.is_empty():
			hot += 0.15
		if main.wyrm and main.wyrm.is_threatening():
			hot += 0.25
		var p0 = main.player
		if p0 and p0.alive and main.nearest_hollow(p0.global_position, 12.0) != null:
			hot += 0.15
		target["drive"] = clampf(0.2 + 0.2 * f + hot, 0.0, 0.7)
	if st == "ended":
		target = {"wind": 0.6, "pad": 0.0, "night": 0.3, "pulse": 0.0, "drive": 0.0}
	if not music_on:
		target["pad"] = 0.0
		target["night"] = 0.0
		target["pulse"] = 0.0
		target["drive"] = 0.0
	for k in AMB:
		amb_level[k] = move_toward(float(amb_level[k]), float(target[k]), delta * 0.35)
		amb[k].volume_db = linear_to_db(maxf(float(amb_level[k]), 0.0001))

	# Wind chimes drift across the gardens while the sun is up.
	chime_t -= delta
	if chime_t <= 0.0:
		chime_t = randf_range(2.5, 7.0) + night * 8.0
		if night < 0.85 and st != "ended":
			var a := randf() * TAU
			var r := randf_range(6.0, 30.0)
			var c: Vector3 = main.player.global_position if main.player else Vector3.ZERO
			play("chime%d" % (randi() % 5), c + Vector3(cos(a) * r, 4.0, sin(a) * r), -6.0 - night * 8.0)

	# Heartbeat when the player's lantern is fading.
	var p = main.player
	var low: bool = st == "playing" and p.alive and not p.escaped and p.light < 20.0
	if low and not heart.playing:
		heart.play()
	elif not low and heart.playing:
		heart.stop()
	if low:
		heart.pitch_scale = 1.0 + (20.0 - float(p.light)) / 20.0 * 0.5


# ---------------------------------------------------------------- synthesis (worker thread)

func _build_bank() -> void:
	var b := {}
	b["wind"] = _wav(_wind(), true)
	b["pad"] = _wav(_pad([110.0, 164.81, 220.0, 277.18, 329.63]), true)
	b["night"] = _wav(_night(), true)
	b["pulse"] = _wav(_pulse(), true)
	var chimes := [1046.5, 1174.66, 1318.51, 1567.98, 1760.0]
	for i in chimes.size():
		b["chime%d" % i] = _wav(_norm(_bell(_buf(2.6), 0.0, chimes[i], 0.5, 0.6, 3), 0.45))
	b["hollow_loop"] = _wav(_hollow_loop(), true)
	b["hollow_form"] = _wav(_hollow_form())
	b["bite"] = _wav(_norm(_noise(_sweep(_buf(0.35), 0.0, 0.3, 110.0, 45.0, 0.9, 1), 0.0, 0.12, 0.8, 0.05, 0.6, 1), 0.8))
	b["hit"] = _wav(_norm(_noise(_sweep(_buf(0.3), 0.0, 0.26, 170.0, 60.0, 1.0, 1), 0.0, 0.05, 0.6, 0.2, 0.9, 1), 0.8))
	b["swing"] = _wav(_norm(_noise(_buf(0.32), 0.0, 0.3, 1.0, 0.06, 0.12, 2, 0.6), 0.45))
	var die := _noise(_buf(1.4), 0.0, 0.5, 1.0, 0.35, 0.95, 1)
	die = _bell(die, 0.02, 1567.98, 0.4, 0.35, 3)
	die = _bell(die, 0.11, 2093.0, 0.3, 0.3, 3)
	die = _sweep(die, 0.0, 0.6, 200.0, 900.0, 0.3, 1)
	b["hollow_die"] = _wav(_norm(die, 0.7))
	var fl := _noise(_buf(1.2), 0.0, 1.0, 1.0, 0.02, 0.35, 1, 0.04)
	fl = _bell(fl, 0.0, 880.0, 0.25, 0.4, 3)
	fl = _bell(fl, 0.03, 1318.51, 0.2, 0.4, 3)
	fl = _sweep(fl, 0.0, 0.45, 95.0, 50.0, 0.5, 1)
	b["flare"] = _wav(_norm(fl, 0.75))
	var bl := _buf(1.1)
	bl = _bell(bl, 0.0, 659.25, 0.35, 0.35, 4)
	bl = _bell(bl, 0.08, 987.77, 0.35, 0.35, 4)
	bl = _bell(bl, 0.16, 1318.51, 0.35, 0.4, 4)
	b["bloom"] = _wav(_norm(bl, 0.6))
	b["shard"] = _wav(_norm(_bell(_bell(_buf(0.8), 0.0, 1567.98, 0.4, 0.25, 3), 0.06, 2349.32, 0.35, 0.25, 3), 0.5))
	b["tool"] = _wav(_norm(_noise(_bell(_buf(0.7), 0.0, 740.0, 0.6, 0.15, 5), 0.0, 0.03, 0.4, 0.3, 0.9, 1), 0.6))
	b["brace"] = _wav(_norm(_noise(_bell(_bell(_buf(1.0), 0.0, 330.0, 0.6, 0.3, 5), 0.0, 467.0, 0.4, 0.25, 4), 0.0, 0.05, 0.5, 0.2, 0.8, 1), 0.7))
	b["hurt"] = _wav(_norm(_noise(_sweep(_buf(0.35), 0.0, 0.3, 95.0, 50.0, 1.0, 1), 0.0, 0.2, 0.5, 0.01, 0.08, 1), 0.7))
	b["gate_open"] = _wav(_choir())
	var esc := _sweep(_buf(2.2), 0.0, 1.6, 300.0, 1500.0, 0.35, 2)
	esc = _bell(esc, 0.4, 1046.5, 0.3, 0.5, 3)
	esc = _bell(esc, 0.55, 1318.51, 0.3, 0.5, 3)
	esc = _bell(esc, 0.7, 1567.98, 0.3, 0.6, 3)
	b["escape"] = _wav(_norm(esc, 0.6))
	b["lantern_out"] = _wav(_norm(_noise(_sweep(_buf(1.4), 0.0, 1.2, 520.0, 130.0, 0.6, 0), 0.0, 0.5, 0.6, 0.01, 0.1, 1), 0.6))
	b["heart"] = _wav(_norm(_sweep(_sweep(_buf(0.9), 0.0, 0.14, 62.0, 45.0, 1.0, 1), 0.24, 0.14, 58.0, 42.0, 0.7, 1), 0.85), true)
	b["tick"] = _wav(_norm(_noise(_sweep(_buf(0.1), 0.0, 0.05, 2400.0, 2000.0, 0.5, 1), 0.0, 0.02, 0.5, 0.3, 0.95, 1), 0.5))
	b["step"] = _wav(_norm(_noise(_buf(0.15), 0.0, 0.13, 1.0, 0.02, 0.25, 1), 0.4))
	b["deny"] = _wav(_norm(_sweep(_sweep(_buf(0.7), 0.0, 0.6, 140.0, 120.0, 0.5, 0), 0.0, 0.6, 148.0, 127.0, 0.5, 0), 0.6))
	b["toll"] = _wav(_norm(_bell(_bell(_buf(4.0), 0.0, 196.0, 0.6, 1.1, 5), 0.0, 98.0, 0.4, 1.4, 3), 0.7))
	b["jump"] = _wav(_norm(_noise(_sweep(_buf(0.22), 0.0, 0.14, 170.0, 420.0, 0.6, 1), 0.0, 0.18, 0.5, 0.05, 0.3, 1), 0.5))
	b["swish"] = _wav(_norm(_noise(_buf(0.28), 0.0, 0.26, 1.0, 0.05, 0.1, 2, 0.5), 0.45))
	b["shove"] = _wav(_norm(_noise(_sweep(_buf(0.3), 0.0, 0.22, 130.0, 55.0, 1.0, 1), 0.0, 0.08, 0.8, 0.05, 0.5, 1), 0.85))
	b["fall"] = _wav(_fall())
	b["screech"] = _wav(_screech())
	b["hiss"] = _wav(_norm(_noise(_buf(0.5), 0.0, 0.45, 1.0, 0.3, 0.9, 3), 0.55))
	b["roar"] = _wav(_roar())
	var wb := _noise(_buf(1.8), 0.0, 1.6, 1.0, 0.004, 0.05, 2, 0.5)
	wb = _sweep(wb, 0.0, 1.4, 85.0, 32.0, 0.8, 0)
	b["wyrm_burst"] = _wav(_norm(wb, 0.85))
	var dw := _buf(1.6)
	for i in 3:
		dw = _sweep(dw, i * 0.42, 0.34, 700.0, 1500.0, 0.45, 2)
		dw = _bell(dw, i * 0.42 + 0.3, 1568.0, 0.25, 0.15, 3)
	b["drop_warn"] = _wav(_norm(dw, 0.6))
	var di := _sweep(_buf(2.2), 0.0, 1.6, 95.0, 28.0, 1.0, 1)
	di = _noise(di, 0.0, 0.9, 0.9, 0.01, 0.35, 1)
	di = _bell(di, 0.0, 220.0, 0.25, 0.6, 4)
	b["drop_impact"] = _wav(_norm(di, 0.9))
	var fg := _buf(1.2)
	for i in 4:
		fg = _bell(fg, i * 0.06, [784.0, 1046.5, 1318.5, 1568.0][i], 0.3, 0.35, 4)
	fg = _noise(fg, 0.0, 0.5, 0.25, 0.2, 0.8, 1)
	b["flare_get"] = _wav(_norm(fg, 0.65))
	b["drum"] = _wav(_norm(_noise(_sweep(_buf(0.7), 0.0, 0.55, 150.0, 52.0, 1.0, 1), 0.0, 0.05, 0.5, 0.1, 0.6, 1), 0.85))
	var go := _sweep(_buf(1.8), 0.0, 0.6, 160.0, 48.0, 1.0, 1)
	go = _noise(go, 0.0, 0.9, 0.6, 0.02, 0.4, 2, 0.05)
	for f in [392.0, 523.25, 659.25, 783.99]:
		go = _bell(go, 0.05, f, 0.22, 0.5, 4)
	b["go"] = _wav(_norm(go, 0.8))
	b["water"] = _wav(_water(), true)
	b["drive"] = _wav(_drive(), true)
	_built = b


func _buf(sec: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(sec * RATE))
	return s


func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


func _norm(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in s.size():
		s[i] *= k
	return s


## Crossfades the last `xf` samples into the start so noise-based loops are seamless.
func _loopify(s: PackedFloat32Array, xf: int) -> PackedFloat32Array:
	var n := s.size() - xf
	var out := s.slice(0, n)
	for i in xf:
		var k := float(i) / xf
		out[i] = s[i] * k + s[n + i] * (1.0 - k)
	return out


func _env(k: float, i: int, mode: int) -> float:
	var att := minf(1.0, i / 40.0)
	match mode:
		0:
			return (1.0 - k) * att
		1:
			return pow(1.0 - k, 4.0) * att
		2:
			return sin(PI * k)
		3:
			return k * k
	return att


func _bell(s: PackedFloat32Array, at: float, f: float, amp: float, decay: float, parts := 5) -> PackedFloat32Array:
	var ratios := [1.0, 2.0, 2.76, 5.4, 8.93]
	var gains := [1.0, 0.45, 0.35, 0.16, 0.07]
	var i0 := int(at * RATE)
	var count := mini(s.size() - i0, int(decay * 5.0 * RATE))
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for p in parts:
			var r: float = ratios[p]
			var g: float = gains[p]
			v += sin(TAU * f * r * t) * g * exp(-t * (1.0 + p * 0.8) / decay)
		s[i0 + i] += v * amp * minf(1.0, t * 300.0)
	return s


func _sweep(s: PackedFloat32Array, at: float, dur: float, f0: float, f1: float, amp: float, env: int) -> PackedFloat32Array:
	var i0 := int(at * RATE)
	var count := mini(s.size() - i0, int(dur * RATE))
	var ph := 0.0
	for i in count:
		var k := float(i) / count
		ph += TAU * f0 * pow(f1 / f0, k) / RATE
		s[i0 + i] += sin(ph) * amp * _env(k, i, env)
	return s


## Band-limited noise: one-pole lowpass at k_hi minus lowpass at k_lo (k = 0..1).
func _noise(s: PackedFloat32Array, at: float, dur: float, amp: float, k_lo: float, k_hi: float, env: int, k_end := -1.0) -> PackedFloat32Array:
	var i0 := int(at * RATE)
	var count := mini(s.size() - i0, int(dur * RATE))
	var a := 0.0
	var b := 0.0
	for i in count:
		var k := float(i) / count
		var kh := k_hi if k_end < 0.0 else lerpf(k_hi, k_end, k)
		a += kh * (randf() * 2.0 - 1.0 - a)
		b += k_lo * (a - b)
		s[i0 + i] += (a - b) * amp * _env(k, i, env)
	return s


func _wind() -> PackedFloat32Array:
	var s := _buf(7.0)
	var a := 0.0
	var b := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var gust := 0.5 + 0.3 * sin(TAU * t * 0.17) + 0.2 * sin(TAU * t * 0.43 + 1.3)
		a += (0.025 + 0.06 * gust) * (randf() * 2.0 - 1.0 - a)
		b += 0.002 * (a - b)
		s[i] = (a - b) * gust
	return _loopify(_norm(s, 0.6), RATE)


## Warm drone chord. Frequencies are snapped to multiples of 1/8 Hz so the loop is seamless.
func _pad(notes: Array) -> PackedFloat32Array:
	var L := 8.0
	var s := _buf(L)
	var fs: Array = []
	for f in notes:
		fs.append(roundf(float(f) * L) / L)
	var lfo := PackedFloat32Array()
	lfo.resize(fs.size())
	for i in s.size():
		var t := float(i) / RATE
		if i % 256 == 0:
			for j in fs.size():
				lfo[j] = 0.55 + 0.45 * sin(TAU * t * float(j + 1) / L + j * 1.7)
		var v := 0.0
		for j in fs.size():
			var f: float = fs[j]
			v += (sin(TAU * f * t) + 0.45 * sin(TAU * (f + 1.0 / L) * t + 1.0)) * lfo[j]
		s[i] = v
	return _norm(s, 0.5)


func _night() -> PackedFloat32Array:
	var s := _pad([73.42, 110.0, 146.83, 174.61])
	var n := _loopify(_noise(_buf(9.0), 0.0, 9.0, 1.0, 0.004, 0.05, 4), RATE)
	for i in s.size():
		var t := float(i) / RATE
		s[i] = s[i] * 0.8 + n[i] * 1.2 * (0.6 + 0.4 * sin(TAU * t / 4.0)) \
			+ sin(TAU * 1760.0 * t) * 0.025 * (0.5 + 0.5 * sin(TAU * t * 3.0 / 8.0))
	return _norm(s, 0.5)


func _pulse() -> PackedFloat32Array:
	var s := _buf(2.0)
	for beat in [0.0, 1.0]:
		s = _sweep(s, beat, 0.5, 70.0, 38.0, 0.9, 1)
		s = _noise(s, beat, 0.15, 0.3, 0.01, 0.1, 1)
	return _norm(s, 0.7)


func _hollow_loop() -> PackedFloat32Array:
	var s := _buf(3.5)
	var a := 0.0
	var b := 0.0
	var ph := 0.0
	var flut := 0.5
	var flut_s := 0.5
	for i in s.size():
		var t := float(i) / RATE
		if i % 220 == 0:
			flut = randf()
		flut_s += 0.01 * (flut - flut_s)
		a += 0.25 * (randf() * 2.0 - 1.0 - a)
		b += 0.03 * (a - b)
		var whisper := (a - b) * (0.3 + 0.7 * flut_s) * (0.5 + 0.5 * sin(TAU * t * 0.9))
		ph += TAU * (52.0 + 6.0 * sin(TAU * t * 0.7)) / RATE
		var growl := tanh(sin(ph) * 2.5) * 0.3 * (0.6 + 0.4 * sin(TAU * t * 1.3))
		s[i] = whisper * 1.4 + growl
	return _loopify(_norm(s, 0.6), int(0.5 * RATE))


func _hollow_form() -> PackedFloat32Array:
	var s := _buf(2.3)
	s = _noise(s, 0.0, 2.0, 1.2, 0.01, 0.02, 3, 0.4)
	s = _sweep(s, 0.0, 2.0, 420.0, 70.0, 0.5, 3)
	s = _sweep(s, 1.95, 0.3, 90.0, 40.0, 0.9, 1)
	return _norm(s, 0.7)


func _choir() -> PackedFloat32Array:
	var s := _buf(4.5)
	var notes := [261.63, 329.63, 392.0, 523.25]
	for i in s.size():
		var t := float(i) / RATE
		var e := minf(1.0, t / 1.5) * clampf((4.5 - t) / 1.0, 0.0, 1.0)
		var v := 0.0
		for j in notes.size():
			var f: float = notes[j]
			var vib := 0.0012 * f * sin(TAU * 5.2 * t + j)
			for h in range(1, 4):
				v += sin(TAU * f * h * t + vib * h) / float(h * h)
		s[i] = v * e
	s = _bell(s, 0.0, 130.81, 2.0, 1.2, 5)
	return _norm(s, 0.7)


func _fall() -> PackedFloat32Array:
	var s := _buf(1.9)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / 1.9
		var f := lerpf(820.0, 170.0, pow(k, 0.7)) * (1.0 + 0.03 * sin(TAU * 6.0 * t))
		ph += TAU * f / RATE
		s[i] = (sin(ph) + 0.3 * sin(ph * 2.0)) * (1.0 - k) * minf(1.0, t * 30.0) * 0.6
	s = _noise(s, 0.0, 1.9, 0.5, 0.005, 0.06, 3)
	return _norm(s, 0.7)


func _screech() -> PackedFloat32Array:
	var s := _buf(1.0)
	var ph := 0.0
	var ph2 := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / 1.0
		var f := lerpf(1500.0, 620.0, k) + 90.0 * sin(TAU * 31.0 * t)
		ph += TAU * f / RATE
		ph2 += TAU * f * 1.507 / RATE
		var env := minf(1.0, t * 40.0) * pow(1.0 - k, 1.5)
		s[i] = tanh(3.0 * (sin(ph) + 0.6 * sin(ph2))) * env * 0.5
	s = _noise(s, 0.0, 0.9, 0.6, 0.25, 0.9, 1)
	return _norm(s, 0.7)


func _roar() -> PackedFloat32Array:
	var s := _buf(3.0)
	var ph := 0.0
	var a := 0.0
	var b := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.4) * clampf((3.0 - t) / 1.4, 0.0, 1.0)
		var f := 42.0 + 14.0 * sin(TAU * 0.6 * t) + 6.0 * sin(TAU * 7.0 * t)
		ph += TAU * f / RATE
		var rumble := 0.6 + 0.4 * sin(TAU * 9.0 * t)
		a += 0.08 * (randf() * 2.0 - 1.0 - a)
		b += 0.01 * (a - b)
		s[i] = (tanh(4.0 * (sin(ph) + 0.5 * sin(ph * 2.02) + 0.3 * sin(ph * 3.1))) * 0.6 * rumble + (a - b) * 2.5) * env
	return _norm(s, 0.9)


func _water() -> PackedFloat32Array:
	var s := _buf(5.0)
	var a := 0.0
	var b := 0.0
	for i in s.size():
		var t := float(i) / RATE
		a += 0.35 * (randf() * 2.0 - 1.0 - a)
		b += 0.02 * (a - b)
		s[i] = (a - b) * (0.85 + 0.15 * sin(TAU * t * 0.8))
	return _loopify(_norm(s, 0.5), RATE)


## Two seconds of rhythm at 120 bpm: kick, toms and a shaker.
func _drive() -> PackedFloat32Array:
	var s := _buf(2.0)
	for beat in [0.0, 0.5, 1.0, 1.5]:
		s = _sweep(s, beat, 0.32, 95.0, 42.0, 0.9, 1)
	for tom in [0.75, 1.25, 1.75]:
		s = _sweep(s, tom, 0.22, 170.0, 95.0, 0.45, 1)
	for k in 16:
		s = _noise(s, k * 0.125, 0.06, 0.12 if k % 2 == 0 else 0.07, 0.4, 0.95, 1)
	return _norm(s, 0.6)
