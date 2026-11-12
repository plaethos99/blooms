extends Node3D
## LAST LIGHT: match flow, spawning, gate, and shared queries.

const Cfg = preload("res://scripts/cfg.gd")
const WorldScript = preload("res://scripts/world.gd")
const HudScript = preload("res://scripts/hud.gd")
const PlayerScript = preload("res://scripts/player.gd")
const BotScript = preload("res://scripts/bot.gd")
const HollowScript = preload("res://scripts/hollow.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const AudioScript = preload("res://scripts/audio.gd")
const TouchScript = preload("res://scripts/touch.gd")

const C_INFO := Color(1.0, 0.88, 0.7)
const C_DARK := Color(0.75, 0.6, 1.0)
const C_GOOD := Color(1.0, 0.95, 0.6)
const C_BAD := Color(1.0, 0.5, 0.5)

var world
var hud
var sfx
var touch = null
var player
var intro_cam: Camera3D
var intro_t := 0.0
var _last_tick := -1
var _snap_t := 1.0
var _quit_t := 0.0
var gentle := false
var stats := {"bloom": 0.0, "shard": 0.0, "damage": 0.0, "flare": 0.0, "kills": 0, "blooms": 0, "hollows": 0}
var _quitting := false
var survivors: Array = []
var hollows: Array = []
var pickups: Array = []

var state := "intro"
var time_left: float = Cfg.MATCH_TIME
var gate_open := false
var final_phase := false
var next_bloom := 4.0
var next_tool := 7.0
var next_hollow := 10.0
var args := {}
var shot_path := ""
var shot_timer := 0.0
var _frames := 0


func _ready() -> void:
	randomize()
	_parse_args()
	_setup_input()
	if args.has("bake-audio"):
		AudioScript.new().bake_to_disk()
		get_tree().quit()
		return
	sfx = AudioScript.new()
	sfx.main = self
	add_child(sfx)
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build()
	if OS.has_feature("mobile") or args.has("touch"):
		# Phones: on-screen controls, and stop taps from also acting as mouse clicks.
		Input.emulate_mouse_from_touch = false
		touch = TouchScript.new()
		touch.main = self
	hud = HudScript.new()
	add_child(hud)
	hud.setup(self)
	if touch:
		add_child(touch)
	_spawn_survivors()
	if args.has("skip"):
		time_left = Cfg.MATCH_TIME - float(args["skip"])
	if args.has("bright"):
		for s in survivors:
			s.light = 85.0
	world.update_time(frac())
	_update_shrines()
	if args.has("overview"):
		var c := Camera3D.new()
		c.far = 2500.0
		add_child(c)
		c.global_position = Vector3(0, 40, 60)
		c.look_at(Vector3(0, 2, 0))
		c.current = true
	if args.has("timescale"):
		Engine.time_scale = float(args["timescale"])
		Engine.max_physics_steps_per_frame = 24
	if args.has("autopilot"):
		player.autopilot = true
	if (shot_path != "" and not args.has("intro")) or args.has("autostart"):
		start_match()
	elif not args.has("overview"):
		# Slow orbit around the island behind the title screen.
		intro_cam = Camera3D.new()
		intro_cam.far = 2500.0
		intro_cam.fov = 60.0
		add_child(intro_cam)
		intro_cam.current = true
		_update_intro_cam(0.0)


func _exit_tree() -> void:
	HollowScript._shaders.clear()


func _update_intro_cam(delta: float) -> void:
	intro_t += delta
	var a := intro_t * 0.05 + 2.2
	intro_cam.global_position = Vector3(cos(a) * 62.0, 21.0 + sin(intro_t * 0.2) * 3.0, sin(a) * 62.0)
	intro_cam.look_at(Vector3(0, 3.5, 0))


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			var kv := s.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if args.has("shot"):
		shot_path = args["shot"]
		shot_timer = float(args.get("delay", "5"))


func _setup_input() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("sprint", [KEY_SHIFT])
	_add_action("swing", [KEY_F], [MOUSE_BUTTON_LEFT])
	_add_action("brace", [KEY_C], [MOUSE_BUTTON_RIGHT])
	_add_action("flare", [KEY_SPACE, KEY_Q])
	_add_action("restart", [KEY_R])


func _add_action(action: String, keys: Array, buttons: Array = []) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


func frac() -> float:
	return clampf(1.0 - time_left / Cfg.MATCH_TIME, 0.0, 1.0)


func start_match(gentle_mode := false) -> void:
	if state != "intro":
		return
	gentle = gentle_mode or args.has("gentle")
	state = "playing"
	hud.hide_intro()
	if intro_cam:
		player.cam.current = true
		intro_cam.queue_free()
		intro_cam = null
	if shot_path == "":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sfx.play("toll", null, -4.0)
	feed("The sun is setting. Keep your lantern bright.", C_INFO)


# ---------------------------------------------------------------- spawning

func _spawn_survivors() -> void:
	for i in Cfg.SURVIVOR_COUNT:
		var a := TAU * float(i) / Cfg.SURVIVOR_COUNT + 0.3
		var p := Vector3(cos(a) * 35.0, 0.3, sin(a) * 35.0)
		var s = PlayerScript.new() if i == 0 else BotScript.new()
		s.setup(self, Cfg.NAMES[i], Cfg.COLORS[i], p)
		add_child(s)
		s.face_toward(Vector3.ZERO)
		survivors.append(s)
		if i == 0:
			player = s


func _find_item_spawn():
	for attempt in 30:
		var p: Vector3 = world.random_island_point(37.0)
		if not world.is_clear(p, 1.2):
			continue
		if world.in_any_shrine(p, 1.0):
			continue
		var g: float = world.ground_at(p)
		if g < -5.0:
			continue
		p.y = g
		var ok := true
		for pk in pickups:
			if is_instance_valid(pk) and pk.global_position.distance_to(p) < 3.0:
				ok = false
				break
		if ok:
			return p
	return null


func _spawn_pickup(kind: String, at = null) -> void:
	var p = at
	if p == null and kind == "tool":
		var blooms := _list("bloom")
		if not blooms.is_empty() and randf() < 0.7:
			var b = blooms.pick_random()
			var a := randf() * TAU
			var q: Vector3 = b.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 6.0)
			if world.is_clear(q, 1.0) and not world.in_any_shrine(q, 1.0):
				var g: float = world.ground_at(q)
				if g > -5.0:
					q.y = g
					p = q
	if p == null:
		p = _find_item_spawn()
	if p == null:
		return
	var pk = PickupScript.new()
	pk.kind = kind
	if kind == "bloom":
		stats["blooms"] += 1
	if kind == "bloom":
		pk.heal = randf_range(Cfg.BLOOM_HEAL.x, Cfg.BLOOM_HEAL.y)
	elif kind == "shard":
		pk.heal = Cfg.SHARD_HEAL
	else:
		pk.tool_name = Cfg.TOOL_NAMES.pick_random()
	pk.position = p
	add_child(pk)
	pickups.append(pk)


func _find_hollow_spawn():
	var min_d: float = Cfg.HOLLOW_SPAWN_MIN_DIST * (0.7 if final_phase else 1.0)
	for attempt in 40:
		var p := Vector3.ZERO
		var blooms := _list("bloom")
		if final_phase:
			var a := deg_to_rad(30.0 if randf() < 0.5 else 210.0) + randf_range(-0.5, 0.5)
			var r := randf_range(13.0, 24.0)
			p = Vector3(cos(a) * r, 0, sin(a) * r)
		elif not blooms.is_empty() and randf() < 0.4:
			var b = blooms.pick_random()
			var a := randf() * TAU
			p = b.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(5.0, 9.0)
		else:
			p = world.random_island_point(37.0)
		var g: float = world.ground_at(p)
		if g < -5.0:
			continue
		p.y = g + 1.4
		if world.in_any_shrine(p, 0.8):
			continue
		if _min_survivor_dist(p) < min_d:
			continue
		return p
	return null


func _spawn_hollow(at = null) -> void:
	var p = at if at != null else _find_hollow_spawn()
	if p == null:
		return
	var h = HollowScript.new()
	h.main = self
	h.position = p
	h.persistent = final_phase
	add_child(h)
	hollows.append(h)
	stats["hollows"] += 1
	if player.alive and not player.escaped and p.distance_to(player.global_position) < 24.0:
		feed("A hollow is forming nearby…", C_DARK)


func _min_survivor_dist(p: Vector3) -> float:
	var best := INF
	for s in survivors:
		if s.alive and not s.escaped:
			best = minf(best, s.global_position.distance_to(p))
	return best


func _list(kind: String) -> Array:
	var out: Array = []
	for pk in pickups:
		if is_instance_valid(pk) and pk.kind == kind:
			out.append(pk)
	return out


func _active_hollows() -> int:
	var n := 0
	for h in hollows:
		if is_instance_valid(h) and h.state != 3: # 3 = DYING
			n += 1
	return n


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	_frames += 1
	if _frames == 10 and args.has("navtest"):
		var nm: NavigationMesh = world.nav_region.navigation_mesh
		print("nav polys: ", nm.get_polygon_count(), " verts: ", nm.get_vertices().size())
		var map: RID = world.get_world_3d().navigation_map
		for from in [Vector3(35, 0, 0), Vector3(0, 0, 35), Vector3(20, 2.5, 5), Vector3(10, 5, 2)]:
			var path := NavigationServer3D.map_get_path(map, from, world.gate_pos, true)
			var endp := path[path.size() - 1] if path.size() > 0 else Vector3.INF
			print("path from ", from, " -> pts ", path.size(), " end ", endp, " closest_to_gate ", NavigationServer3D.map_get_closest_point(map, world.gate_pos))
	if _frames == 30 and args.has("demohollow"):
		var fwd: Vector3 = -player.global_position.normalized()
		var hp: Vector3 = player.global_position + fwd * 6.0 + Vector3(1.5, 1.4, 0)
		_spawn_hollow(hp)
	if _frames == 4:
		# A starter bloom a few steps in front of you, so your first goal is easy.
		var inward: Vector3 = -Vector3(player.global_position.x, 0, player.global_position.z).normalized()
		var sp: Vector3 = player.global_position + inward * 7.0
		var sg: float = world.ground_at(sp)
		if sg > -5.0:
			_spawn_pickup("bloom", Vector3(sp.x, sg, sp.z))
			pickups[-1].reserved_for = player
			pickups[-1].reserved_until = Time.get_ticks_msec() + 15000
		for i in 2:
			_spawn_pickup("bloom")
		for i in 2:
			_spawn_pickup("tool")
	hollows = hollows.filter(func(h): return is_instance_valid(h))
	pickups = pickups.filter(func(p): return is_instance_valid(p))
	if state != "playing":
		return
	time_left = maxf(0.0, time_left - delta)
	world.update_time(frac())
	_update_shrines()
	if not gate_open and time_left <= Cfg.GATE_OPEN_AT:
		_open_gate()
	if not final_phase and time_left <= Cfg.FINAL_PHASE_AT:
		_start_final()
	var sec := int(ceil(time_left))
	if sec <= 10 and sec != _last_tick:
		_last_tick = sec
		sfx.play("tick", null, -2.0 + (10 - sec) * 0.4, 1.0 + (10 - sec) * 0.03)
		hud.pulse_clock()
	_tick_spawns(delta)
	if args.has("log") and int(time_left * 60.0) % 600 == 0:
		_log_status()
	if args.has("trace") and int(time_left * 60.0) % 120 == 0:
		for s in survivors.slice(2, 5):
			print("  %s pos=%s goal=%s light=%d vel=%s" % [s.display_name, s.global_position.snapped(Vector3.ONE * 0.1), s.goal.snapped(Vector3.ONE * 0.1), int(s.light), s.velocity.snapped(Vector3.ONE * 0.1)])
	_check_pickups()
	_check_gate()
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


func _tick_spawns(delta: float) -> void:
	next_bloom -= delta
	if next_bloom <= 0.0:
		next_bloom = randf_range(Cfg.BLOOM_INTERVAL.x, Cfg.BLOOM_INTERVAL.y) 
		if _list("bloom").size() < Cfg.MAX_BLOOMS:
			_spawn_pickup("bloom")
	next_tool -= delta
	if next_tool <= 0.0:
		next_tool = randf_range(Cfg.TOOL_INTERVAL.x, Cfg.TOOL_INTERVAL.y)
		if _list("tool").size() < Cfg.MAX_TOOLS:
			_spawn_pickup("tool")
	next_hollow -= delta
	if next_hollow <= 0.0:
		var f := frac()
		var lo := lerpf(Cfg.HOLLOW_INTERVAL_EARLY.x, Cfg.HOLLOW_INTERVAL_LATE.x, f)
		var hi := lerpf(Cfg.HOLLOW_INTERVAL_EARLY.y, Cfg.HOLLOW_INTERVAL_LATE.y, f)
		if final_phase:
			lo = 3.5
			hi = 5.0
		next_hollow = randf_range(lo, hi)
		if _active_hollows() < Cfg.MAX_HOLLOWS:
			_spawn_hollow()


func _update_shrines() -> void:
	var k := clampf((time_left - Cfg.FINAL_PHASE_AT) / Cfg.SHRINE_SHRINK_SPAN, 0.0, 1.0)
	world.set_shrine_radius(Cfg.SHRINE_MAX_RADIUS * k)


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check_pickups() -> void:
	for pk in pickups.duplicate():
		if not is_instance_valid(pk):
			continue
		for s in survivors:
			if not s.alive or s.escaped:
				continue
			if _flat(s.global_position, pk.global_position) > 1.3:
				continue
			if absf(s.global_position.y - pk.global_position.y) > 2.2:
				continue
			if not pk.can_take(s):
				continue
			if pk.kind == "tool":
				if s.tool_swings > 0:
					continue
				s.give_tool(pk.tool_name)
				if s.is_player:
					hud.toast("Picked up %s (4 swings)" % pk.tool_name)
				_take(pk, Color(1.0, 0.8, 0.4), "tool", s.is_player)
				break
			var before: float = s.light
			if s.heal(pk.heal * heal_mult(s)):
				stats[pk.kind] += s.light - before
				if s.is_player:
					hud.toast("+%d%% light" % int(round(pk.heal)))
				_take(pk, Color(1.0, 0.6, 0.75) if pk.kind == "bloom" else Color(0.55, 0.9, 1.0), pk.kind, s.is_player)
				break


func _take(pk, col: Color, sound: String, by_player: bool) -> void:
	var p: Vector3 = pk.global_position
	fx_ring(p + Vector3(0, 0.3, 0), col, 1.8, 0.45)
	fx_burst(p + Vector3(0, 0.8, 0), col, 24, false)
	sfx.play(sound, null if by_player else p, 0.0 if by_player else -2.0)
	if not by_player and sound == "bloom" and player.alive and not player.escaped \
			and _flat(p, player.global_position) < 30.0:
		hud.tip("taken", "Someone else grabbed that bloom. Everyone competes for light, so be quick!")
	pickups.erase(pk)
	pk.queue_free()


func _check_gate() -> void:
	var gp: Vector3 = world.gate_pos
	for s in survivors:
		if not s.alive or s.escaped:
			continue
		if _flat(s.global_position, gp) > 1.7 or s.global_position.y < gp.y - 1.0:
			continue
		if not gate_open:
			if s.is_player and s.gate_msg_cd <= 0.0:
				s.gate_msg_cd = 3.0
				hud.toast("The Sun Gate is sealed until 01:00")
			continue
		if s.light >= Cfg.ESCAPE_LIGHT:
			s.escape()
		else:
			var out := Vector3(s.global_position.x - gp.x, 0, s.global_position.z - gp.z)
			if out.length() < 0.1:
				out = Vector3(1, 0, 0)
			s.push(out.normalized() * 9.0)
			if s.is_player and s.gate_msg_cd <= 0.0:
				s.gate_msg_cd = 2.0
				sfx.play("deny")
				player.shake = 0.3
				hud.banner("The gate rejects your dim light\nYou have %d%%, you need 80%%" % int(s.light), 2.5)


func _open_gate() -> void:
	gate_open = true
	world.set_gate_open()
	sfx.play("gate_open")
	sfx.play("toll", null, -3.0, 1.5)
	hud.banner("THE SUN GATE IS OPEN\nStep through with 80% light", 5.0)
	feed("The Sun Gate has opened on the summit.", C_GOOD)


func _start_final() -> void:
	final_phase = true
	for h in hollows:
		if is_instance_valid(h):
			h.persistent = true
	sfx.play("toll", null, 0.0, 0.6)
	hud.banner("NIGHT FALLS\nThe shrines are dark. The hollows gather at the gate.", 4.5)
	feed("The shrines have gone dark.", C_DARK)


func _end_match() -> void:
	if state == "ended":
		return
	state = "ended"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var title := ""
	if player.escaped:
		title = "YOU ESCAPED"
	elif player.alive:
		title = "LEFT IN THE DARK"
	else:
		title = "YOUR LANTERN WENT OUT"
	var escaped_names: Array = []
	var lost_names: Array = []
	for s in survivors:
		if s.escaped:
			escaped_names.append(s.display_name)
		else:
			if s.alive:
				s.lost = true
				s.collapse(true)
			lost_names.append(s.display_name)
	world.lights_out()
	sfx.play("toll", null, 0.0, 0.5)
	if player.escaped:
		sfx.play("escape", null, -4.0, 0.8)
	hud.show_end(title, escaped_names, lost_names)
	if args.has("log"):
		print("MATCH OVER: ", title, " | escaped: ", escaped_names, " | lost: ", lost_names)
		print("RESULT esc=%d player=%s bloom=%d shard=%d damage=%d flare=%d kills=%d blooms=%d hollows=%d" % [
			escaped_names.size(), "esc" if player.escaped else ("alive" if player.lost else "dead"),
			stats["bloom"], stats["shard"], stats["damage"], stats["flare"], stats["kills"], stats["blooms"], stats["hollows"]])


func _log_status() -> void:
	var parts: Array = []
	for s in survivors:
		var tag := "esc" if s.escaped else ("%d" % int(s.light) if s.alive else "X")
		parts.append("%s:%s%s" % [s.display_name, tag, "*" if s.tool_swings > 0 else ""])
	print("t=%03d hollows=%d blooms=%d | %s" % [int(time_left), _active_hollows(), _list("bloom").size(), " ".join(PackedStringArray(parts))])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and state == "ended":
		get_tree().reload_current_scene()
	elif state == "intro" and event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_1, KEY_2, KEY_KP_1, KEY_KP_2, KEY_P]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.keycode == KEY_P:
			player.set_autopilot(true)
		start_match(event.keycode in [KEY_1, KEY_KP_1])
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		hud.toast("Music on" if sfx.toggle_music() else "Music off")


func _process(delta: float) -> void:
	if intro_cam:
		_update_intro_cam(delta)
	if args.has("introsecs") and state == "intro":
		# Demo recording: show the title card briefly, then let the AI play.
		if intro_t > float(args["introsecs"]):
			player.set_autopilot(true)
			start_match(args.has("gentle"))
	if args.has("snapevery") and state == "playing":
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = float(args["snapevery"])
			var dir: String = args.get("snapdir", OS.get_user_data_dir())
			var path := "%s/snap_%03d.png" % [dir, int(Cfg.MATCH_TIME - time_left)]
			get_viewport().get_texture().get_image().save_png(path)
			print("snap ", path, " light=", int(player.light), " pos=", player.global_position.snapped(Vector3.ONE * 0.1))
	if args.has("quitend") and state == "ended":
		_quit_t += delta
		if _quit_t > 6.0 * Engine.time_scale:
			_quit_clean()
	if shot_path != "":
		shot_timer -= delta
		if shot_timer <= 0.0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			print("Saved screenshot: ", shot_path)
			for h in hollows:
				if is_instance_valid(h):
					print("  hollow state=", h.state, " pos=", h.global_position, " scale=", h.body_root.scale, " player=", player.global_position)
			shot_path = ""
			_quit_clean()


# ---------------------------------------------------------------- queries for actors

func nearest_target(from: Vector3):
	var best = null
	var bd := INF
	for s in survivors:
		if not s.alive or s.escaped:
			continue
		if world.shrine_protects(s.global_position):
			continue
		var d: float = s.global_position.distance_to(from)
		if gentle and s.is_player:
			d += 6.0 # in Gentle mode hollows prefer other targets
		if d < bd:
			bd = d
			best = s
	return best


func nearest_hollow(from: Vector3, max_d: float):
	var best = null
	var bd := max_d
	for h in hollows:
		if not is_instance_valid(h) or not h.is_active():
			continue
		var d := _flat(h.global_position, from)
		if d < bd:
			bd = d
			best = h
	return best


func find_hollow_in_arc(origin: Vector3, facing: Vector3, reach: float):
	var best = null
	var bd := reach
	for h in hollows:
		if not is_instance_valid(h) or not h.is_active():
			continue
		var to: Vector3 = h.global_position - origin
		if absf(to.y - 1.2) > 2.5:
			continue
		to.y = 0.0
		var d := to.length()
		if d > reach:
			continue
		if d > 0.9 and to.normalized().dot(facing) < 0.3:
			continue
		if d < bd:
			bd = d
			best = h
	return best


func best_pickup(s, want_tool: bool):
	var best = null
	var best_score := INF
	var sp: Vector3 = s.global_position
	var greed: float = s.greed
	for pk in pickups:
		if not is_instance_valid(pk):
			continue
		if want_tool != (pk.kind == "tool"):
			continue
		if s.is_blocked(pk) or not pk.can_take(s):
			continue
		var d := _flat(sp, pk.global_position)
		if d > 45.0:
			continue
		var closer := 0
		for o in survivors:
			if o == s or not o.alive or o.escaped:
				continue
			if _flat(o.global_position, pk.global_position) + 3.0 < d:
				closer += 1
		var score := d + closer * lerpf(14.0, 4.0, greed)
		if score < best_score:
			best_score = score
			best = pk
	return best


func nearest_pickup(from: Vector3, kinds: Array):
	var best = null
	var bd := INF
	for pk in pickups:
		if not is_instance_valid(pk) or not kinds.has(pk.kind):
			continue
		var d := _flat(from, pk.global_position)
		if d < bd:
			bd = d
			best = pk
	return best


func hollow_speed() -> float:
	return lerpf(Cfg.HOLLOW_SPEED, Cfg.HOLLOW_SPEED_NIGHT, frac())


## Gentle mode only helps the human player; the bots keep normal rules.
func bite_mult(target) -> float:
	return 0.5 if gentle and target.is_player else 1.0


func heal_mult(s) -> float:
	return 1.4 if gentle and s.is_player else 1.0


func do_flare(s) -> void:
	var p: Vector3 = s.global_position
	fx_ring(p + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.6), Cfg.FLARE_RADIUS, 0.5)
	fx_light(p + Vector3(0, 1.5, 0), Color(1.0, 0.85, 0.6), 8.0, 12.0, 0.6)
	fx_burst(p + Vector3(0, 1.2, 0), Color(1.0, 0.9, 0.6), 40, false, 6.0)
	sfx.play("flare", null if s.is_player else p, 0.0)
	for h in hollows:
		if is_instance_valid(h) and h.is_active() and _flat(h.global_position, p) <= Cfg.FLARE_RADIUS:
			h.stagger(p, Cfg.FLARE_PUSH)


func on_hollow_killed(h) -> void:
	stats["kills"] += 1
	var p: Vector3 = h.global_position
	fx_ring(p, Color(0.75, 0.55, 1.0), 2.5, 0.5)
	fx_burst(p, Color(0.7, 0.5, 1.0), 36, false, 5.0)
	sfx.play("hollow_die", p, 2.0)
	var g: float = world.ground_at(p)
	if g > -5.0:
		_spawn_pickup("shard", Vector3(p.x, g, p.z))
	if player.alive and _flat(p, player.global_position) < 25.0:
		feed("A hollow shatters into a light shard.", C_GOOD)


func on_survivor_down(s) -> void:
	feed("%s's lantern went out." % s.display_name, C_BAD)
	fx_burst(s.global_position + Vector3(0, 1.0, 0), Color(0.12, 0.08, 0.18), 30, true, 1.5)
	sfx.play("lantern_out", null if s.is_player else s.global_position, 0.0)
	if s.is_player:
		hud.banner("YOUR LANTERN WENT OUT\nSpectating. Press Tab to switch.", 4.0)


func on_survivor_escaped(s) -> void:
	fx_light(world.gate_pos + Vector3(0, 2.5, 0), Color(1.0, 0.85, 0.5), 12.0, 20.0, 1.2)
	world.escape_beam()
	sfx.play("escape", null if s.is_player else world.gate_pos + Vector3(0, 2, 0), 0.0)
	feed("%s stepped through the Sun Gate." % s.display_name, C_GOOD)
	if s.is_player:
		hud.banner("YOU PASSED THROUGH THE SUN GATE", 4.0)


## One-shot particle burst: sparkles (glow) or a dark smoke puff.
func fx_burst(pos: Vector3, col: Color, amount: int, smoke: bool, speed := 3.0) -> void:
	var ps := GPUParticles3D.new()
	ps.one_shot = true
	ps.explosiveness = 0.95
	ps.amount = amount
	ps.lifetime = 1.6 if smoke else 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 0.8, 0) if smoke else Vector3(0, -3.0, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6 if smoke else 1.0
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	ps.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.18 if smoke else 0.04
	sm.height = sm.radius * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	if smoke:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = col
	else:
		m.albedo_color = Color(0, 0, 0)
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 5.0
	sm.material = m
	ps.draw_pass_1 = sm
	add_child(ps)
	ps.global_position = pos
	ps.emitting = true
	ps.finished.connect(ps.queue_free)


func feed(text: String, col: Color) -> void:
	hud.feed(text, col)


# ---------------------------------------------------------------- fx

func fx_ring(pos: Vector3, col: Color, radius: float, dur := 0.5) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.88
	tm.outer_radius = 1.0
	tm.rings = 40
	tm.ring_segments = 6
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col.r, col.g, col.b, 1.0)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(radius, 1.0, radius), dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.tween_property(m, "emission_energy_multiplier", 0.0, dur)
	tw.chain().tween_callback(mi.queue_free)


func fx_light(pos: Vector3, col: Color, energy: float, rng: float, dur: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 0.0, dur)
	tw.tween_callback(l.queue_free)


## Scripted exits (screenshots, recordings): silence audio first so the audio server
## releases its streams, then quit a moment later.
func _quit_clean() -> void:
	if _quitting:
		return
	_quitting = true
	for c in sfx.get_children():
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
	await get_tree().create_timer(0.3, true, false, true).timeout
	get_tree().quit()
