extends "res://scripts/main.gd"
## LEVEL 1, THE GAUNTLET: match flow for the lane race (see course.gd for the course).
## Phases per pilgrim: 1 fire blades -> lamp, 2 moving steps (weapons), 3 arena
## (bring down monsters), 4 rope chasm, 5 walk into the Sun Gate. Falling after the
## lamp costs a short respawn at the start of your current phase; before it, the run ends.

const CourseScript = preload("res://scripts/course.gd")
const CourseHudScript = preload("res://scripts/course_hud.gd")
const FlyerScript = preload("res://scripts/flyer.gd")
const Arms2 = preload("res://scripts/arms.gd")

static var quick_start := false # set by Play Again: skip the title card

var flyers: Array = []
var next_flyer := 2.0
var arrows: Array = [] # {node, pos, vel, t, by}
var saws: Array = [] # {node, pos, dir, t, by, back, hit}
var finish_order: Array = []
var gate_opened := false
var _respawns := 0


func _ready() -> void:
	is_course = true
	randomize()
	Fonts.install()
	_parse_args()
	_setup_input()
	time_left = Cfg.COURSE_TIME
	sfx = AudioScript.new()
	sfx.main = self
	add_child(sfx)
	world = CourseScript.new()
	world.name = "Course"
	add_child(world)
	world.build()
	blades = BladesScript.new()
	blades.name = "Blades"
	blades.main = self
	add_child(blades)
	blades.build(world)
	if args.has("log"):
		print("COURSE lamp_z=%.1f entry_z=%.1f arena_z=%.1f exit_z=%.1f gate_z=%.1f" % [world.lamp_z, world.entry_z, world.arena_z, world.exit_z, world.gate_z])
	if OS.has_feature("mobile") or args.has("touch"):
		Input.emulate_mouse_from_touch = false
		touch = TouchScript.new()
		touch.main = self
	hud = CourseHudScript.new()
	add_child(hud)
	hud.setup(self)
	if touch:
		add_child(touch)
	_spawn_survivors()
	world.update_time(frac())
	if args.has("cam"):
		var v: PackedFloat64Array = PackedFloat64Array(Array(String(args["cam"]).split(",")).map(func(t): return float(t)))
		var dc := Camera3D.new()
		dc.far = 2500.0
		dc.fov = 60.0
		add_child(dc)
		dc.global_position = Vector3(v[0], v[1], v[2])
		dc.look_at(Vector3(v[3], v[4], v[5]))
		dc.current = true
		hud.visible = false
	if args.has("autopilot"):
		player.autopilot = true
	if args.has("phase"):
		_debug_jump_to_phase(int(args["phase"]))
	if (shot_path != "" and not args.has("intro")) or args.has("autostart") or quick_start:
		quick_start = false
		intro_cam = Camera3D.new()
		intro_cam.far = 2500.0
		add_child(intro_cam)
		state = "intro"
		hud.hide_intro()
		if shot_path == "" and not args.has("autostart"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_begin_countdown()
	else:
		intro_cam = Camera3D.new()
		intro_cam.far = 2500.0
		intro_cam.fov = 60.0
		add_child(intro_cam)
		intro_cam.current = true
		_update_intro_cam(0.0)


func frac() -> float:
	return clampf(1.0 - time_left / Cfg.COURSE_TIME, 0.0, 1.0)


func elapsed() -> float:
	return Cfg.COURSE_TIME - time_left


func restart() -> void:
	quick_start = true
	super.restart()


func go_classic() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _update_intro_cam(delta: float) -> void:
	intro_t += delta
	if state == "flyover":
		_update_flyover(delta)
		return
	# Behind the title: drift slowly down the course towards the gate.
	var z := -20.0 - fmod(intro_t * 4.0, 140.0)
	intro_cam.global_position = Vector3(sin(intro_t * 0.15) * 10.0, 14.0, z + 18.0)
	intro_cam.look_at(Vector3(0, 4.0, z - 10.0))


func _begin_flyover() -> void:
	state = "flyover"
	fly_t = 0.0
	var g: Vector3 = world.gate_pos
	var a := Vector3(0, world.ARENA_Y, world.arena_z)
	var c := Vector3(0, world.LAMP_Y, world.lamp_z)
	player.cam_pivot.global_position = player.global_position + Vector3(0, 1.6, 0)
	player.cam_pivot.rotation = Vector3(player.pitch, player.yaw, 0)
	var back: Vector3 = player.cam_pivot.global_transform.basis.z
	var end_pos: Vector3 = player.cam_pivot.global_position + back * 5.8
	var end_look: Vector3 = end_pos - back * 30.0
	_fly_keys = [
		[0.0, g + Vector3(4.0, 3.5, 11.0), g + Vector3(0, 3.0, 0)],
		[2.4, g + Vector3(-6.0, 9.0, 26.0), g + Vector3(0, 3.0, 0)],
		[4.2, a + Vector3(14.0, 12.0, -10.0), a + Vector3(0, 0, 10.0)],
		[5.8, c + Vector3(-10.0, 9.0, -8.0), c + Vector3(0, 0, 18.0)],
		[7.2, end_pos + Vector3(0, 5.0, 6.0), end_look],
		[8.2, end_pos, end_look],
	]
	hud.flyover_caption(true)


func _begin_countdown() -> void:
	super._begin_countdown()
	if args.has("cam"):
		for c in get_children():
			if c is Camera3D and c != intro_cam:
				c.current = true
	player.yaw = 0.0
	player.pitch = -0.36


func _update_countdown(delta: float) -> void:
	super._update_countdown(delta)
	if state == "playing":
		hud.phase_banner(1)


# ---------------------------------------------------------------- spawning

func _spawn_survivors() -> void:
	var mid := int(Cfg.LANES / 2.0)
	var rows: Array = []
	for l in Cfg.LANES:
		rows.append([])
	for i in Cfg.SURVIVOR_COUNT:
		var l := mid
		if i > 0:
			l = (i - 1) % Cfg.LANES
			if Cfg.LANES == 3:
				l = [0, 2, 1][(i - 1) % 3]
		rows[l].append(i)
	# You stand in the middle of your lane's row.
	var r0: Array = rows[mid]
	r0.erase(0)
	r0.insert(int(r0.size() / 2.0), 0)
	for l in Cfg.LANES:
		var row: Array = rows[l]
		for j in row.size():
			var i: int = row[j]
			var p := Vector3(world.lane_x(l) + (float(j) - float(row.size() - 1) * 0.5) * 1.6, 0.3, 2.2)
			var s = PlayerScript.new() if i == 0 else BotScript.new()
			s.setup(self, Cfg.NAMES[i], Cfg.COLORS[i], p, i)
			add_child(s)
			s.face_toward(p + Vector3(0, 0, -1))
			s.lane = l
			s.cphase = 1
			s.light = Cfg.COURSE_START_LIGHT
			s.checkpoint = p
			survivors.append(s)
			if i == 0:
				player = s


## Debug: start everyone at a later phase (--phase=N).
func _debug_jump_to_phase(ph: int) -> void:
	for s in survivors:
		var l: int = s.lane
		s.cphase = ph
		if ph >= 2:
			s.has_lamp = true
			s.light = 100.0
		if ph >= 3:
			for k in ["bow", "axe", "saw"]:
				s.weapons[k] = true
			s.select_weapon("bow")
		if ph >= 4:
			s.kills = Cfg.KILLS_NEEDED
			s.has_rope = true
		var p: Vector3 = world.checkpoint(ph, l) + Vector3(randf_range(-1.5, 1.5), 0.3, randf_range(-0.5, 0.5))
		s.position = p
		s.checkpoint = p


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_frames += 1
	flyers = flyers.filter(func(f): return is_instance_valid(f))
	if state == "countdown":
		_update_countdown(delta)
	if state != "playing":
		return
	time_left = maxf(0.0, time_left - delta)
	world.update_time(frac())
	var sec := int(ceil(time_left))
	if sec <= 10 and sec != _last_tick:
		_last_tick = sec
		sfx.play("tick", null, -2.0 + (10 - sec) * 0.4, 1.0 + (10 - sec) * 0.03)
		hud.pulse_clock()
	_tick_rules()
	_tick_flyers(delta)
	_tick_projectiles(delta)
	_update_guide()
	if args.has("log") and _frames % (60 if args.has("trace") else 600) == 0:
		_log_status()
	if time_left <= 0.0:
		_end_match()
		return
	var any_active := false
	for s in survivors:
		if s.alive and not s.escaped:
			any_active = true
			break
	if not any_active:
		_end_match()


func _tick_rules() -> void:
	var w = world
	for s in survivors:
		if not s.alive or s.escaped or s.respawn_t > 0.0:
			continue
		var p: Vector3 = s.global_position
		var l: int = w.lane_of(p.x)
		match int(s.cphase):
			1:
				var lp: Vector3 = w.lamps[l]["pos"]
				if _flat(p, lp) < 1.6 and absf(p.y - lp.y) < 2.5:
					_take_lamp(s, l)
			2:
				if s.is_on_floor() and w.in_arena(p):
					_set_phase(s, 3, w.checkpoint(3, l))
					if s.weapons.is_empty():
						# Missed every weapon on the steps: a spare axe waits at the arena.
						s.give_weapon("axe")
						sfx.play("tool", null if s.is_player else p, -3.0)
			3:
				if p.z < w.exit_z + 3.4:
					if s.kills >= Cfg.KILLS_NEEDED:
						s.has_rope = true
						_set_phase(s, 4, w.checkpoint(4, l))
						sfx.play("tool", null if s.is_player else p, 0.0, 0.9)
						fx_ring(p + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.45), 1.8, 0.4)
						if s.is_player:
							w.take_rope_visual(l)
							hud.hint("rope")
					else:
						s.push(Vector3(0, 0, 9.0))
						s.velocity.z = absf(s.velocity.z) + 2.0
						if s.is_player and s.gate_msg_cd <= 0.0:
							s.gate_msg_cd = 1.5
							sfx.play("deny")
							hud.need_kills()
			4:
				if s.is_on_floor() and w.on_gate_isle(p):
					_set_phase(s, 5, w.checkpoint(5, l))
					if not gate_opened:
						gate_opened = true
						gate_open = true
						w.set_gate_open()
						sfx.play("gate_open")
			5:
				var gp: Vector3 = w.gate_pos
				if _flat(p, gp) < 1.8 and p.y > gp.y - 1.0:
					_finish(s)
		# Weapons floating over the moving steps: each pilgrim can take one of each.
		if s.cphase == 2:
			for spot in w.weapon_spots:
				var kind: String = spot["kind"]
				if s.weapons.has(kind):
					continue
				var n: Node3D = spot["node"]
				var q: Vector3 = n.global_position
				if _flat(p, q) < 1.75 and p.y > q.y - 3.2 and p.y < q.y + 0.8:
					s.give_weapon(kind)
					sfx.play("tool", null if s.is_player else q, 0.0 if s.is_player else -3.0)
					fx_ring(q, Color(1.0, 0.85, 0.45), 1.4, 0.35)
					if s.is_player:
						var beam := n.get_node_or_null("Beam")
						if beam:
							beam.visible = false
						hud.weapon_taken(kind)


func _set_phase(s, ph: int, cp: Vector3) -> void:
	s.cphase = ph
	s.checkpoint = cp
	if s.is_player:
		hud.phase_banner(ph)
		sfx.play("chime%d" % clampi(ph - 1, 0, 4), null, -2.0)
	if args.has("log"):
		print("PHASE %s -> %d t=%.1f" % [s.display_name, ph, elapsed()])


func _take_lamp(s, l: int) -> void:
	s.has_lamp = true
	s.light = Cfg.LAMP_LIGHT
	var lp: Vector3 = world.lamps[l]["pos"]
	fx_ring(lp + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.5), 2.2, 0.5)
	fx_burst(s.global_position + Vector3(0, 1.4, 0), Color(1.0, 0.85, 0.5), 30, false, 4.0)
	sfx.play("flare_get", null if s.is_player else lp, 0.0 if s.is_player else -3.0)
	if s.is_player:
		world.set_lamp_taken(l)
		fx_light(s.global_position + Vector3(0, 2.0, 0), Color(1.0, 0.85, 0.5), 6.0, 10.0, 0.8)
	_set_phase(s, 2, world.checkpoint(2, l))


func _finish(s) -> void:
	s.cphase = 6
	s.finish_time = elapsed()
	finish_order.append(s)
	s.place = finish_order.size()
	s.escape()


## The player's guide wisp floats to the next thing to do.
func _update_guide() -> void:
	var w = world
	var p = player
	if not p.alive or p.escaped or p.respawn_t > 0.0:
		w.set_guide(null)
		w.highlight_ring(-1)
		return
	var pos: Vector3 = p.global_position
	var l: int = w.lane_of(pos.x)
	var ring := -1
	match int(p.cphase):
		3:
			if p.kills >= Cfg.KILLS_NEEDED:
				w.set_guide(Vector3(w.lane_x(l), w.ARENA_Y, w.exit_z + 2.2))
			else:
				w.set_guide(null)
		4:
			w.set_guide(null)
			if p.has_rope:
				var r: Array = p.cam_ray()
				ring = w.pick_ring(pos + Vector3(0, 1.6, 0), r[1], p.rope_ring)
		_:
			var i: int = w.next_wp(l, pos, p.cphase)
			w.set_guide(w.wp_pos(w.routes[l][i]))
	w.highlight_ring(ring)
	hud.rope_target = ring


# ---------------------------------------------------------------- weapons

## Attack with the current weapon towards `aim` (a direction from the chest).
func course_attack(s, aim: Vector3) -> void:
	if s.attack_cd > 0.0 or s.weapon == "" or not s.alive:
		return
	var chest: Vector3 = s.global_position + Vector3(0, 1.3, 0)
	match String(s.weapon):
		"axe":
			s.attack_cd = Cfg.AXE_COOLDOWN
			s.play_once("swing", 0.5)
			sfx.play("swing", null if s.is_player else chest, -1.0, randf_range(0.8, 0.95))
			var best = null
			var bd: float = Cfg.AXE_REACH
			for f in flyers:
				if not f.is_active():
					continue
				var to: Vector3 = f.core() - chest
				var d := to.length()
				if d > bd:
					continue
				var flat := Vector3(to.x, 0, to.z)
				if d > 1.3 and flat.length() > 0.1 and flat.normalized().dot(s.facing) < 0.0:
					continue
				bd = d
				best = f
			if best != null:
				best.hit(Cfg.AXE_DAMAGE, chest, s)
				if s.is_player:
					s.shake = maxf(s.shake, 0.2)
		"bow":
			s.attack_cd = Cfg.ARROW_COOLDOWN
			s.play_once("swing", 0.3)
			sfx.play("swing", null if s.is_player else chest, -4.0, randf_range(1.6, 1.8))
			var dir := _assist(chest, aim, Cfg.ARROW_SPEED)
			arrows.append({"node": _arrow_node(), "pos": chest + dir * 0.6, "vel": dir * Cfg.ARROW_SPEED, "t": 0.0, "by": s})
		"saw":
			if s.saw_out:
				return
			s.attack_cd = 0.3
			s.saw_out = true
			s.play_once("swing", 0.45)
			sfx.play("swish", null if s.is_player else chest, 0.0, randf_range(1.2, 1.35))
			var dir := _assist(chest, aim, Cfg.SAW_SPEED)
			var n := Arms2.make("saw")
			n.scale = Vector3.ONE * 2.2
			add_child(n)
			n.global_position = chest
			saws.append({"node": n, "pos": chest, "dir": dir, "t": 0.0, "by": s, "back": false, "hit": {}, "went": 0.0})
			if s._weapon_nodes.has("saw"):
				s._weapon_nodes["saw"].visible = false


## Bend a shot towards a monster close to the aim (leading it a little).
func _assist(from: Vector3, aim: Vector3, speed: float) -> Vector3:
	var best = null
	var ba: float = Cfg.AIM_ASSIST
	for f in flyers:
		if not f.is_active():
			continue
		var to: Vector3 = f.core() - from
		var a := aim.angle_to(to)
		if a < ba and to.length() < 40.0:
			ba = a
			best = f
	if best == null:
		return aim
	var tp: Vector3 = best.core() + best.vel * (from.distance_to(best.core()) / speed)
	return (tp - from).normalized()


func _arrow_node() -> Node3D:
	var n := Node3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.02
	shaft.bottom_radius = 0.02
	shaft.height = 0.7
	shaft.radial_segments = 5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.55)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.3)
	m.emission_energy_multiplier = 3.0
	var mi := MeshInstance3D.new()
	mi.mesh = shaft
	mi.material_override = m
	mi.rotation.x = PI / 2.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	add_child(n)
	return n


func _tick_projectiles(delta: float) -> void:
	for a in arrows.duplicate():
		var prev: Vector3 = a["pos"]
		var v: Vector3 = a["vel"]
		v.y -= 5.0 * delta
		a["vel"] = v
		var np := prev + v * delta
		a["pos"] = np
		a["t"] = float(a["t"]) + delta
		var n: Node3D = a["node"]
		n.global_position = np
		if v.length() > 0.1 and absf(v.normalized().dot(Vector3.UP)) < 0.99:
			n.look_at(np + v, Vector3.UP)
		var done := float(a["t"]) > 1.4
		for f in flyers:
			if not f.is_active():
				continue
			if Geometry3D.get_closest_point_to_segment(f.core(), prev, np).distance_to(f.core()) < 0.8:
				f.hit(Cfg.ARROW_DAMAGE, prev, a["by"])
				done = true
				break
		if done:
			n.queue_free()
			arrows.erase(a)
	for s in saws.duplicate():
		var by = s["by"]
		var n: Node3D = s["node"]
		var pos: Vector3 = s["pos"]
		s["t"] = float(s["t"]) + delta
		var alive_owner: bool = is_instance_valid(by) and by.alive and not by.escaped
		if not bool(s["back"]):
			var step: Vector3 = s["dir"] * Cfg.SAW_SPEED * delta
			pos += step
			s["went"] = float(s["went"]) + step.length()
			if float(s["went"]) >= Cfg.SAW_RANGE:
				s["back"] = true
		elif alive_owner:
			var home: Vector3 = by.global_position + Vector3(0, 1.3, 0)
			var to := home - pos
			if to.length() < 0.9:
				s["t"] = 99.0
			else:
				pos += to.normalized() * minf(to.length(), Cfg.SAW_SPEED * 1.15 * delta)
		s["pos"] = pos
		n.global_position = pos
		n.rotation.y += delta * 25.0
		for f in flyers:
			if not f.is_active() or s["hit"].has(f.get_instance_id()):
				continue
			if f.core().distance_to(pos) < 1.1:
				s["hit"][f.get_instance_id()] = true
				f.hit(Cfg.SAW_DAMAGE, pos, by)
		if float(s["t"]) > 3.0 or not alive_owner:
			n.queue_free()
			saws.erase(s)
			if is_instance_valid(by):
				by.saw_out = false
				if by.weapon == "saw" and by._weapon_nodes.has("saw"):
					by._weapon_nodes["saw"].visible = true


# ---------------------------------------------------------------- the rope

## Player: fire the rope at the ring under (or nearest to) the crosshair.
func course_rope(s) -> void:
	if not s.has_rope or s.cphase != 4:
		return
	var r: Array = s.cam_ray()
	var i: int = world.pick_ring(s.global_position + Vector3(0, 1.6, 0), r[1], s.rope_ring)
	if i < 0:
		sfx.play("deny", null, -6.0)
		return
	s.rope_fire(i)
	hud.rope_used()


# ---------------------------------------------------------------- monsters

func _tick_flyers(delta: float) -> void:
	var fighters := 0
	for s in survivors:
		if s.alive and not s.escaped and s.cphase == 3:
			fighters += 1
	var active := 0
	for f in flyers:
		if f.is_active():
			active += 1
	var want := clampi(2 + fighters, Cfg.FLYERS_MIN, Cfg.FLYERS_MAX) if fighters > 0 else 0
	next_flyer -= delta
	if active < want and next_flyer <= 0.0:
		next_flyer = 1.1
		var c := Vector3(0, world.ARENA_Y, world.arena_z)
		var a := randf() * TAU
		var f = FlyerScript.new()
		f.setup(self, c, c + Vector3(cos(a) * 26.0, 10.0, sin(a) * 18.0))
		add_child(f)
		flyers.append(f)


## Who a monster should dive at: someone fighting in the arena (not already a target).
func flyer_pick_target(f):
	var best = null
	var bs := INF
	for s in survivors:
		if not s.alive or s.escaped or s.cphase != 3 or s.invuln > 0.0 or s.respawn_t > 0.0:
			continue
		if not world.in_arena(s.global_position):
			continue
		var d: float = s.global_position.distance_to(f.global_position)
		for o in flyers:
			if o != f and is_instance_valid(o) and o.target == s:
				d += 12.0
		if s.is_player:
			d -= 3.0
		d += randf() * 8.0
		if d < bs:
			bs = d
			best = s
	return best


func nearest_flyer(from: Vector3, max_d: float):
	var best = null
	var bd := max_d
	for f in flyers:
		if not f.is_active():
			continue
		var d: float = f.core().distance_to(from)
		if d < bd:
			bd = d
			best = f
	return best


## The monster closest to a camera ray (within a few degrees), for aiming.
func nearest_flyer_on_ray(o: Vector3, dir: Vector3, max_d: float):
	var best = null
	var ba := 0.09
	for f in flyers:
		if not f.is_active():
			continue
		var to: Vector3 = f.core() - o
		if to.length() > max_d:
			continue
		var a := dir.angle_to(to)
		if a < ba:
			ba = a
			best = f
	return best


func on_flyer_killed(f, by) -> void:
	stats["kills"] += 1
	var p: Vector3 = f.global_position
	fx_ring(p, Color(0.75, 0.55, 1.0), 2.2, 0.45)
	fx_burst(p, Color(0.8, 0.5, 1.0), 36, false, 5.0)
	sfx.play("hollow_die", p, 2.0, 1.2)
	if by != null and is_instance_valid(by) and by.alive:
		by.kills += 1
		by.heal(Cfg.KILL_HEAL)
		if by.is_player:
			hud.kill_pulse()
			if by.kills == Cfg.KILLS_NEEDED:
				sfx.play("chime4", null, -2.0)
	if args.has("log"):
		print("KILL by %s t=%.1f" % [by.display_name if by != null and is_instance_valid(by) else "-", elapsed()])


# ---------------------------------------------------------------- falls, the end

func on_course_respawn(s) -> void:
	_respawns += 1
	stats["fell"] += 1
	sfx.play("fall", null if s.is_player else s.global_position, -4.0, randf_range(1.0, 1.15))
	if s.is_player:
		hud.flash_hurt()
	if args.has("log"):
		print("RESPAWN %s phase=%d t=%.1f" % [s.display_name, s.cphase, elapsed()])


func on_survivor_down(s) -> void:
	if args.has("log"):
		print("DOWN %s cause=%s phase=%d t=%.1f" % [s.display_name, s.cause, s.cphase, elapsed()])
	if s.cause == "fell":
		sfx.play("fall", null if s.is_player else s.global_position, 0.0, randf_range(0.9, 1.1))
	else:
		sfx.play("lantern_out", null if s.is_player else s.global_position, 0.0)


func on_survivor_escaped(s) -> void:
	fx_light(world.gate_pos + Vector3(0, 2.5, 0), Color(1.0, 0.85, 0.5), 12.0, 20.0, 1.2)
	world.escape_beam()
	sfx.play("escape", null if s.is_player else world.gate_pos + Vector3(0, 2, 0), 0.0)
	if args.has("log"):
		print("FINISH %s place=%d time=%.1f" % [s.display_name, s.place, s.finish_time])


func medal(t: float) -> String:
	if t < 0.0:
		return ""
	if t <= Cfg.MEDAL_GOLD:
		return "GOLD"
	if t <= Cfg.MEDAL_SILVER:
		return "SILVER"
	return "BRONZE"


## Race position of s right now (1 = leading).
func race_place(s) -> int:
	if s.place > 0:
		return s.place
	var me := _progress(s)
	var n := 1
	for o in survivors:
		if o != s and _progress(o) > me:
			n += 1
	return n


func _progress(s) -> float:
	if s.place > 0:
		return 100000.0 - float(s.place)
	if not s.alive:
		return -100000.0
	return float(s.cphase) * 1000.0 - s.global_position.z


func _end_match() -> void:
	if state == "ended":
		return
	state = "ended"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for s in survivors:
		if s.alive and not s.escaped:
			s.lost = true
	world.lights_out()
	sfx.play("toll", null, 0.0, 0.5)
	hud.show_results()
	if args.has("log"):
		var parts: Array = []
		for s in finish_order:
			parts.append("%s %.1f" % [s.display_name, s.finish_time])
		print("RESULT finished=%d player=%s place=%d time=%.1f respawns=%d kills=%d | %s" % [finish_order.size(),
			"fin" if player.place > 0 else ("out" if not player.alive else "dnf"), player.place, player.finish_time,
			_respawns, stats["kills"], ", ".join(PackedStringArray(parts))])


func _log_status() -> void:
	var parts: Array = []
	for s in survivors:
		var tag := "fin" if s.place > 0 else ("p%d" % s.cphase if s.alive else "X")
		parts.append("%s:%s" % [s.display_name, tag])
	print("t=%03d fps=%d flyers=%d | %s" % [int(elapsed()), Engine.get_frames_per_second(), flyers.size(), " ".join(PackedStringArray(parts))])
	if args.has("trace"):
		for s in survivors.filter(func(q): return q.display_name == String(args.get("who", q.display_name))).slice(0, 4):
			var l: int = world.lane_of(s.global_position.x)
			var i: int = world.next_wp(l, s.global_position, s.cphase)
			print("  %s pos=%s floor=%s vel=%s wp=%d %s at %s rope=%s/%d" % [s.display_name, s.global_position.snapped(Vector3.ONE * 0.1), s.is_on_floor(), s.velocity.snapped(Vector3.ONE * 0.1), i, world.routes[l][i]["kind"], world.wp_pos(world.routes[l][i]).snapped(Vector3.ONE * 0.1), s.rope_state, s.rope_ring])


func _unhandled_input(event: InputEvent) -> void:
	if state == "intro" and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		go_classic()
		return
	super._unhandled_input(event)


# Not used in Level 1.
func _check_gate() -> void:
	pass
