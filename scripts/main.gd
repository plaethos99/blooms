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
const WyrmScript = preload("res://scripts/wyrm.gd")
const BladesScript = preload("res://scripts/blades.gd")
const Fonts = preload("res://scripts/fonts.gd")
const DropScript = preload("res://scripts/drop.gd")
const TrialsScript = preload("res://scripts/trials.gd")

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
var stats := {"bloom": 0.0, "shard": 0.0, "damage": 0.0, "flare": 0.0, "kills": 0, "blooms": 0, "hollows": 0, "fruit": 0, "potion": 0, "beast": 0, "crawler": 0, "doused": 0, "ready": 0,
	"fell": 0, "shoves": 0, "pushed_off": 0, "wyrm": 0, "drops": 0}
var wyrm
var blades
var trials
var next_ext := 3.0
var next_ward := 8.0
var drops: Array = []
var next_drop: float = Cfg.DROP_FIRST
var next_wyrm: float = Cfg.WYRM_FIRST
var _wyrm_tries := 0
var fly_t := 0.0
var count_t := 0.0
var _count_last := -1
var _fly_keys: Array = []
var _quitting := false
var survivors: Array = []
var hollows: Array = []
var pickups: Array = []

var state := "intro"
var time_left: float = Cfg.MATCH_TIME
var gate_open := true # the portal is always open; the fire seal and the relics guard it
var final_phase := false
var next_bloom := 4.0
var next_tool := 7.0
var next_hollow := 10.0
var args := {}
var shot_path := ""
var shot_timer := 0.0
var _frames := 0
var _hitch_t := 0.0


func _ready() -> void:
	randomize()
	Fonts.install()
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
	wyrm = WyrmScript.new()
	wyrm.main = self
	add_child(wyrm)
	blades = BladesScript.new()
	blades.name = "Blades"
	blades.main = self
	add_child(blades)
	blades.build(world)
	trials = TrialsScript.new()
	trials.name = "Trials"
	add_child(trials)
	trials.build(self)
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
	if OS.has_feature("mobile") or args.has("mobileprofile"):
		_apply_mobile_profile()
	if args.has("skip"):
		time_left = Cfg.MATCH_TIME - float(args["skip"])
	if args.has("bright"):
		for s in survivors:
			s.light = 85.0
	world.update_time(frac())
	_update_shrines()
	if args.has("cam"):
		# Debug camera: --cam=x,y,z,look_x,look_y,look_z
		var v: PackedFloat64Array = PackedFloat64Array(Array(String(args["cam"]).split(",")).map(func(t): return float(t)))
		var dc := Camera3D.new()
		dc.far = 2500.0
		dc.fov = 60.0
		add_child(dc)
		dc.global_position = Vector3(v[0], v[1], v[2])
		dc.look_at(Vector3(v[3], v[4], v[5]))
		dc.current = true
		hud.visible = false
	if args.has("overview"):
		var c := Camera3D.new()
		c.far = 2500.0
		add_child(c)
		c.global_position = Vector3(70, 55, 45)
		c.look_at(world.CENTER + Vector3(0, -5, 0))
		c.current = true
	if args.has("timescale"):
		Engine.time_scale = float(args["timescale"])
		Engine.max_physics_steps_per_frame = 24
	if args.has("autopilot"):
		player.autopilot = true
	if args.has("clicktest") or args.has("outclick"):
		print("CLICKTEST scene ready, state=", state, " instance=", get_instance_id())
	if (shot_path != "" and not args.has("intro")) or args.has("autostart"):
		start_match()
	elif not args.has("overview"):
		# Behind the title screen: a slow orbit around the portal, the way out.
		intro_cam = Camera3D.new()
		intro_cam.far = 2500.0
		intro_cam.fov = 60.0
		add_child(intro_cam)
		intro_cam.current = true
		_update_intro_cam(0.0)
		_warm_up()


## Phones compile each shader the first time something using it is drawn, which froze the
## first minute of a match (first hollow, first Sunflare, first flare...). So while the
## title is up, draw one of everything that only appears later, far in front of the title
## camera behind the title card, then remove it.
func _warm_up() -> void:
	var cam_fwd: Vector3 = -intro_cam.global_transform.basis.z
	var p: Vector3 = intro_cam.global_position + cam_fwd * 30.0
	var side: Vector3 = intro_cam.global_transform.basis.x
	var temp: Array = []
	fx_burst(p, Color(1.0, 0.8, 0.5), 8, false)
	fx_burst(p, Color(0.2, 0.15, 0.25), 8, true)
	fx_ring(p, Color(1.0, 0.9, 0.6), 1.5, 1.5)
	fx_light(p, Color(1.0, 0.8, 0.5), 0.5, 2.0, 1.5)
	var kinds := ["bloom", "shard", "tool", "flare", "fruit", "potion", "extinguisher", "ward"]
	for i in kinds.size():
		var pk = PickupScript.new()
		pk.kind = kinds[i]
		pk.tool_name = Cfg.TOOL_NAMES[0]
		pk.position = p + side * (float(i) - 3.5) * 1.5
		add_child(pk)
		temp.append(pk)
	var h = HollowScript.new()
	h.main = self
	h.warm = true
	h.position = p + Vector3(0, 2.0, 0)
	add_child(h)
	temp.append(h)
	var d = DropScript.new()
	d.main = self
	d.warm = true
	d.position = p - Vector3(0, 2.0, 0)
	add_child(d)
	temp.append(d)
	if trials and trials._knife_mesh:
		var kn := MeshInstance3D.new()
		kn.mesh = trials._knife_mesh
		kn.material_override = trials._knife_mat
		kn.position = p + side * 2.0
		add_child(kn)
		temp.append(kn)
	# The red hurt flash, guardian warning disc and brace ring use their own materials.
	var mats: Array = [player.hurt_mat, player.brace_ring.material_override]
	for g in trials.guardians():
		mats.append(g.warn_mat)
		mats.append(g.overlay)
	for i in mats.size():
		if mats[i] == null:
			continue
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		mi.mesh = sm
		mi.material_override = mats[i]
		mi.position = p + side * (float(i) - 2.0) + Vector3(0, -1.0, 0)
		add_child(mi)
		temp.append(mi)
	get_tree().create_timer(2.5).timeout.connect(func():
		for n in temp:
			if is_instance_valid(n):
				n.queue_free())


## Phones: render the 3D scene at a lower internal resolution (upscaled with FSR), keep a
## steady 60 fps cap, and thin out purely decorative particles.
func _apply_mobile_profile() -> void:
	var vp := get_viewport()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	vp.scaling_3d_scale = 0.7
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	Engine.max_fps = 60
	RenderingServer.directional_shadow_atlas_set_size(2048, true)
	if world.fireflies:
		world.fireflies.amount = 140


func _exit_tree() -> void:
	HollowScript._shaders.clear()
	WorldScript._shader_cache.clear()


func _update_intro_cam(delta: float) -> void:
	intro_t += delta
	if state == "flyover":
		_update_flyover(delta)
		return
	var g: Vector3 = world.gate_pos
	var a := intro_t * 0.06 + 1.2
	intro_cam.global_position = g + Vector3(cos(a) * 26.0, 9.0 + sin(intro_t * 0.2) * 2.0, sin(a) * 26.0)
	intro_cam.look_at(g + Vector3(0, 3.0, 0))


## Before the match: show the portal, the gauntlet, the garden and the cave, then fly back to you.
func _begin_flyover() -> void:
	state = "flyover"
	fly_t = 0.0
	var g: Vector3 = world.gate_pos
	var h: Vector3 = world.island_center(world.HEART_ISLAND)
	player.cam_pivot.global_position = player.global_position + Vector3(0, 1.6, 0)
	player.cam_pivot.rotation = Vector3(player.pitch, player.yaw, 0)
	var back: Vector3 = player.cam_pivot.global_transform.basis.z
	var end_pos: Vector3 = player.cam_pivot.global_position + back * 5.0
	var end_look: Vector3 = end_pos - back * 30.0
	# [time, camera position, look-at]
	var gd: Vector3 = world.garden_center
	var cv: Vector3 = world.cave_center
	var cd: Vector3 = world.cave_dir
	_fly_keys = [
		[0.0, g + Vector3(4.0, 3.0, 10.0), g + Vector3(0, 3.5, 0), "portal"],
		[2.8, g + Vector3(-5.0, 7.0, 24.0), g + Vector3(0, 2.5, 0), "portal"],
		[4.6, h + Vector3(6.0, 9.0, -14.0), h + Vector3(0, 2.0, -34.0), "gauntlet"],
		[6.6, gd + Vector3(14.0, 11.0, 8.0), gd + Vector3(0, 2.5, 0), "garden"],
		[8.6, gd + Vector3(8.0, 6.0, -6.0), gd + Vector3(1.0, 2.0, 1.0), "garden"],
		[10.6, cv + cd * 17.0 + Vector3(0, 6.0, 0), cv + Vector3(0, 1.5, 0), "cave"],
		[12.6, cv + cd * 12.0 + Vector3(0, 3.0, 0), cv + Vector3(0, 1.0, 0), "cave"],
		[14.6, end_pos + Vector3(0, 6.0, 8.0), end_look, ""],
		[15.8, end_pos, end_look, ""],
	]
	hud.flyover_caption(true, "portal")


func _update_flyover(delta: float) -> void:
	fly_t += delta
	var last: Array = _fly_keys[-1]
	if fly_t >= float(last[0]):
		_begin_countdown()
		return
	for i in _fly_keys.size() - 1:
		var a: Array = _fly_keys[i]
		var b: Array = _fly_keys[i + 1]
		if fly_t <= float(b[0]):
			var k := smoothstep(float(a[0]), float(b[0]), fly_t)
			var pa: Vector3 = a[1]
			var pb: Vector3 = b[1]
			var la: Vector3 = a[2]
			var lb: Vector3 = b[2]
			intro_cam.global_position = pa.lerp(pb, k)
			intro_cam.look_at(la.lerp(lb, k))
			hud.flyover_caption(String(a[3]) != "", String(a[3]))
			return


func _begin_countdown() -> void:
	state = "countdown"
	count_t = 0.0
	_count_last = -1
	hud.flyover_caption(false)
	hud.show_game_ui()
	if intro_cam:
		player.cam.current = true
		intro_cam.queue_free()
		intro_cam = null


func _update_countdown(delta: float) -> void:
	count_t += delta
	var n := 3 - int(count_t / 0.7)
	if n != _count_last and n >= 1:
		_count_last = n
		hud.countdown(str(n))
		sfx.play("drum", null, -2.0, 1.0 + (3 - n) * 0.06)
	if count_t >= 2.1:
		state = "playing"
		hud.countdown("RUN!")
		sfx.play("go", null, 0.0)
		feed("The sun is setting. Keep your lantern bright.", C_INFO)


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
	_add_action("flare", [KEY_Q], [MOUSE_BUTTON_MIDDLE])
	_add_action("jump", [KEY_SPACE])
	_add_action("push", [KEY_E])
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
	if gentle:
		player.flares = 2
	hud.hide_intro()
	if shot_path == "" and not args.has("introsecs"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if intro_cam and not args.has("autostart") and (shot_path == "" or args.has("flyover")):
		_begin_flyover()
		return
	state = "playing"
	hud.show_game_ui()
	if intro_cam:
		player.cam.current = true
		intro_cam.queue_free()
		intro_cam = null
	sfx.play("toll", null, -4.0)
	feed("The sun is setting. Keep your lantern bright.", C_INFO)


## Start a new round (back to the title screen).
func restart() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().reload_current_scene()


## Click or key during the flyover: skip straight to the countdown.
func skip_flyover() -> void:
	if state == "flyover":
		_begin_countdown()


# ---------------------------------------------------------------- spawning

func _spawn_survivors() -> void:
	var c: Vector3 = world.island_center(world.START_ISLAND)
	for i in Cfg.SURVIVOR_COUNT:
		# Everyone starts in a ring on Dawn Meadow; you at the south, facing the gate.
		var a := TAU * float(i) / Cfg.SURVIVOR_COUNT + PI / 2.0
		var p := c + Vector3(cos(a) * world.SPAWN_RING, 0.3, sin(a) * world.SPAWN_RING)
		var s = PlayerScript.new() if i == 0 else BotScript.new()
		s.setup(self, Cfg.NAMES[i], Cfg.COLORS[i], p, i)
		add_child(s)
		s.face_toward(c if i != 0 else p + Vector3(0, 0, -1))
		survivors.append(s)
		if i == 0:
			player = s


func _find_item_spawn():
	for attempt in 30:
		var q = world.random_item_point()
		if q == null:
			continue
		var p: Vector3 = q
		if world.in_any_shrine(p, 1.0):
			continue
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
	if p == null and kind == "tool" and randf() < 0.5:
		var spots: Array = world.garden_gates.duplicate()
		spots.append(world.cave_door)
		var sp: Vector3 = spots.pick_random()
		var out: Vector3 = sp - (world.garden_center if sp != world.cave_door else world.cave_center)
		out.y = 0.0
		var q0: Vector3 = sp + out.normalized() * randf_range(1.6, 2.6) + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		if world.island_at(q0) >= 0 and world.is_clear(q0, 0.8):
			q0.y = world.ground_at(q0)
			p = q0
	if p == null and kind == "tool":
		var blooms := _list("bloom")
		if not blooms.is_empty() and randf() < 0.7:
			var b = blooms.pick_random()
			var a := randf() * TAU
			var q: Vector3 = b.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 6.0)
			var bi: int = world.island_at(b.global_position)
			if bi >= 0 and world.island_at(q) == bi and world.is_clear(q, 1.0) and not world.in_any_shrine(q, 1.0):
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
	elif kind == "flare":
		pk.heal = Cfg.DROP_HEAL
	else:
		pk.tool_name = Cfg.TOOL_NAMES.pick_random()
	pk.position = p
	add_child(pk)
	pickups.append(pk)


## A relic placed exactly (the fruit under the tree, the potion on the altar).
func spawn_relic(kind: String, p: Vector3) -> void:
	var pk = PickupScript.new()
	pk.kind = kind
	pk.heal = Cfg.FRUIT_HEAL if kind == "fruit" else Cfg.POTION_HEAL
	pk.position = p
	add_child(pk)
	pickups.append(pk)


## Extinguishers and Sun Wards appear on the open islands (never in the garden, the cave
## or the portal isle), mostly on Heart Rock and the meadow, near the start of the gauntlet.
func _tick_trial_spawns(delta: float) -> void:
	next_ext -= delta
	if next_ext <= 0.0:
		next_ext = randf_range(Cfg.EXT_INTERVAL.x, Cfg.EXT_INTERVAL.y)
		if _list("extinguisher").size() < Cfg.MAX_EXTINGUISHERS:
			var isl: int = [world.HEART_ISLAND, world.HEART_ISLAND, world.START_ISLAND, 1, 2].pick_random()
			var q = world.random_island_point(isl, 1.6, 1.2)
			if q != null and not world.in_any_shrine(q, 0.5):
				_spawn_pickup("extinguisher", q)
	next_ward -= delta
	if next_ward <= 0.0:
		next_ward = randf_range(Cfg.WARD_INTERVAL.x, Cfg.WARD_INTERVAL.y)
		if _list("ward").size() < Cfg.MAX_WARDS:
			var isl2: int = [world.START_ISLAND, 1, 2, world.HEART_ISLAND].pick_random()
			var q2 = world.random_island_point(isl2, 1.6, 1.2)
			if q2 != null:
				_spawn_pickup("ward", q2)


func _find_hollow_spawn():
	var min_d: float = Cfg.HOLLOW_SPAWN_MIN_DIST * (0.7 if final_phase else 1.0)
	for attempt in 40:
		var p := Vector3.ZERO
		var blooms := _list("bloom")
		if final_phase:
			# At night they gather around the gate and the islands next to it.
			var isl: int = [world.GATE_ISLAND, world.GATE_ISLAND, 3, 4, world.HEART_ISLAND].pick_random()
			var q = world.random_island_point(isl, 1.0, 0.0)
			if q == null:
				continue
			p = q
		elif not blooms.is_empty() and randf() < 0.4:
			var b = blooms.pick_random()
			var a := randf() * TAU
			p = b.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(5.0, 9.0)
		else:
			var q = world.random_island_point(-1, 1.0, 0.0)
			if q == null:
				continue
			p = q
		var g: float = world.ground_at(p)
		if g < -5.0:
			continue
		p.y = g + 1.6
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
	if _frames == 12 and args.has("cavetest"):
		var map2: RID = world.get_world_3d().navigation_map
		var inside: Vector3 = world.cave_center + world.cave_dir * 2.5
		for from2 in [world.cave_door + world.cave_dir * 3.0, world.garden_center + Vector3(0, 0, 9.0)]:
			var tgt2: Vector3 = inside if from2.distance_to(world.cave_center) < 20.0 else world.tree_pos + Vector3(3, 0, 0)
			var path2 := NavigationServer3D.map_get_path(map2, from2, tgt2, true)
			print("CAVETEST from ", from2.snapped(Vector3.ONE * 0.1), " to ", tgt2.snapped(Vector3.ONE * 0.1), " pts ", path2.size(), " end ", path2[path2.size() - 1].snapped(Vector3.ONE * 0.1) if path2.size() > 0 else Vector3.INF)
		var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
		for k in 9:
			var d: float = 12.0 - k * 1.5
			var q := PhysicsRayQueryParameters3D.create(world.cave_center + world.cave_dir * d + Vector3(0, 6, 0), world.cave_center + world.cave_dir * d + Vector3(0, -2, 0), 1 | 4)
			var hit: Dictionary = space.intersect_ray(q)
			print("  ray at d=%.1f hit y=%s" % [d, str(hit.position.y) if not hit.is_empty() else "none"])
	if _frames == 10 and args.has("navtest"):
		var nm: NavigationMesh = world.nav_region.navigation_mesh
		print("nav polys: ", nm.get_polygon_count(), " verts: ", nm.get_vertices().size())
		var map: RID = world.get_world_3d().navigation_map
		for i in world.ISLANDS.size():
			var from: Vector3 = world.island_center(i) + Vector3(2, 0, 2)
			var path := NavigationServer3D.map_get_path(map, from, world.gate_pos, true)
			var endp := path[path.size() - 1] if path.size() > 0 else Vector3.INF
			print("path from ", world.island_name(i), " -> pts ", path.size(), " end ", endp.snapped(Vector3.ONE * 0.1), " gate ", world.gate_pos)
		for b in world.bridges:
			var ys: Array = []
			for st in b["stones"]:
				ys.append(snappedf(st.y, 0.1))
			print("bridge %s->%s stones %s" % [world.island_name(b["a"]), world.island_name(b["b"]), ys])
	if args.has("wyrmtest") and state == "playing":
		var wb: int = int(args["wyrmtest"]) if args["wyrmtest"] != "1" else 6
		var st: Vector3 = world.bridges[wb]["stones"][2]
		if _frames == 20:
			var dirw: Vector3 = world.bridges[wb]["dir"]
			player.global_position = world.bridges[wb]["stones"][0] + Vector3(0, 0.2, 0)
			player.velocity = Vector3.ZERO
			player.yaw = atan2(-dirw.x, -dirw.z)
			player.pitch = -0.05
		if _frames == 40:
			wyrm.strike(wb, st, Cfg.WYRM_WARN)
	if args.has("lineup") and _frames == 6:
		# Debug view: all pilgrims in a row facing the camera (--cam=0,1.3,7,0,1.0,0).
		for k in survivors.size():
			var sv = survivors[k]
			sv.global_position = Vector3(-6.75 + k * 1.5, 0.05, 0.0)
			sv.velocity = Vector3.ZERO
			sv.face_toward(sv.global_position + Vector3(0, 0, 1))
			sv.name_label.visible = false
		for pk in pickups:
			if is_instance_valid(pk):
				pk.queue_free()
	if args.has("bridgeview") and _frames == 20:
		var bb: Dictionary = world.bridges[int(args["bridgeview"])]
		var dirb: Vector3 = bb["dir"]
		var a0: Vector3 = world.island_center(int(bb["a"]))
		player.global_position = bb["start"] - dirb * 2.5 + Vector3(0, a0.y - bb["start"].y + 0.2, 0)
		player.yaw = atan2(-dirb.x, -dirb.z)
		player.pitch = -0.32
	if _frames == 30 and args.has("demohollow"):
		var fwd: Vector3 = -player.global_position.normalized()
		var hp: Vector3 = player.global_position + fwd * 4.5 + Vector3(0.8, 1.6, 0)
		_spawn_hollow(hp)
	if _frames == 4:
		# A starter bloom a few steps in front of you, so your first goal is easy.
		var sp: Vector3 = player.global_position + Vector3(-2.5, 0, -5.0)
		var sg: float = world.ground_at(sp)
		if sg > -5.0:
			_spawn_pickup("bloom", Vector3(sp.x, sg, sp.z))
			pickups[-1].reserved_for = player
			pickups[-1].reserved_until = Time.get_ticks_msec() + 25000
		for i in 2:
			_spawn_pickup("bloom")
		for i in 2:
			_spawn_pickup("tool")
	hollows = hollows.filter(func(h): return is_instance_valid(h))
	pickups = pickups.filter(func(p): return is_instance_valid(p))
	drops = drops.filter(func(d): return is_instance_valid(d))
	if state == "countdown":
		_update_countdown(delta)
	if state != "playing":
		return
	time_left = maxf(0.0, time_left - delta)
	world.update_time(frac())
	_update_shrines()
	if not final_phase and time_left <= Cfg.FINAL_PHASE_AT:
		_start_final()
	var sec := int(ceil(time_left))
	if sec <= 10 and sec != _last_tick:
		_last_tick = sec
		sfx.play("tick", null, -2.0 + (10 - sec) * 0.4, 1.0 + (10 - sec) * 0.03)
		hud.pulse_clock()
	_tick_spawns(delta)
	_tick_trial_spawns(delta)
	_tick_drops(delta)
	_tick_wyrm(delta)
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
			if _flat(s.global_position, pk.global_position) > (2.1 if pk.kind == "potion" else 1.3):
				continue
			if absf(s.global_position.y - pk.global_position.y) > 2.2:
				continue
			if not pk.can_take(s):
				continue
			if pk.kind == "flare":
				s.add_flares(Cfg.DROP_FLARES)
				s.heal(pk.heal * heal_mult(s))
				var first: bool = not s.relic_flare
				s.relic_flare = true
				if s.is_player:
					if first:
						hud.banner("SUNFLARE RELIC  1 of 3  ✓\n+%d flares. %s" % [Cfg.DROP_FLARES, _relic_next(s)], 3.5)
					else:
						hud.toast("+%d FLARES  (%s to blast hollows and rivals)" % [Cfg.DROP_FLARES, hud.k("flare")])
					shake_near(pk.global_position, 1.0, 0.25)
				else:
					feed("%s grabbed the Sunflare." % s.display_name, C_INFO)
				_relic_check(s)
				_take(pk, Color(1.0, 0.6, 0.2), "flare_get", s.is_player)
				break
			if pk.kind == "fruit" or pk.kind == "potion":
				var is_fruit: bool = pk.kind == "fruit"
				if (is_fruit and s.relic_fruit) or (not is_fruit and s.relic_potion):
					continue
				if is_fruit:
					s.relic_fruit = true
					stats["fruit"] += 1
				else:
					s.relic_potion = true
					stats["potion"] += 1
					trials.on_potion_taken()
				s.heal(pk.heal * heal_mult(s))
				var nm := "SKY FRUIT" if is_fruit else "MOON POTION"
				if s.is_player:
					hud.banner("%s  %d of 3  ✓\n%s" % [nm, s.relic_count(), _relic_next(s)], 3.5)
					shake_near(pk.global_position, 1.0, 0.2)
				else:
					feed("%s took the %s." % [s.display_name, nm.capitalize()], Color(1.0, 0.8, 0.45) if is_fruit else Color(0.8, 0.6, 1.0))
				_relic_check(s)
				_take(pk, Color(1.0, 0.75, 0.3) if is_fruit else Color(0.7, 0.45, 1.0), "flare_get", s.is_player)
				break
			if pk.kind == "extinguisher":
				if s.extinguishers >= Cfg.EXT_MAX_HELD:
					continue
				s.extinguishers += 1
				if s.is_player:
					hud.toast("EXTINGUISHER (%d)  ·  walk into the portal's fire to put it out" % s.extinguishers)
				_take(pk, Color(0.6, 0.85, 1.0), "tool", s.is_player)
				break
			if pk.kind == "ward":
				if s.wards >= Cfg.WARD_MAX_HELD:
					continue
				s.wards += 1
				if s.is_player:
					hud.toast("SUN WARD  ·  it will take the next hit for you")
				_take(pk, Color(1.0, 0.95, 0.7), "chime2", s.is_player)
				break
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
		if _flat(s.global_position, gp) > 1.9 or s.global_position.y < gp.y - 1.0:
			continue
		if s.has_all_relics() and s.light >= Cfg.ESCAPE_LIGHT:
			s.escape()
			continue
		var out := Vector3(s.global_position.x - gp.x, 0, s.global_position.z - gp.z)
		if out.length() < 0.1:
			out = Vector3(world.portal_front.x - gp.x, 0, world.portal_front.z - gp.z)
		s.push(out.normalized() * 9.0)
		if s.is_player and s.gate_msg_cd <= 0.0:
			s.gate_msg_cd = 2.0
			sfx.play("deny")
			player.shake = 0.3
			if not s.has_all_relics():
				hud.banner("The portal rejects you\nStill missing: %s" % ", ".join(s.missing_relics()), 3.0)
			else:
				hud.banner("The portal rejects your dim light\nYou have %d%%, you need 80%%" % int(s.light), 2.5)


## What the player should go for next, in words.
func _relic_next(s) -> String:
	if s.has_all_relics():
		if s.light >= Cfg.ESCAPE_LIGHT:
			return "All three! Cross the gauntlet to the PORTAL."
		return "All three! Get to 80%% light, then the PORTAL."
	return "Still need: %s" % ", ".join(s.missing_relics())


func _relic_check(s) -> void:
	if s.has_all_relics():
		stats["ready"] += 1
		if not s.is_player:
			feed("%s holds all three relics!" % s.display_name, C_GOOD)


func _open_gate() -> void:
	gate_open = true
	world.set_gate_open()
	sfx.play("gate_open")
	sfx.play("toll", null, -3.0, 1.5)
	hud.banner("THE SUN GATE IS OPEN\nStep through with 80% light", 5.0)
	feed("The Sun Gate has opened on Sun Gate Isle.", C_GOOD)


func _start_final() -> void:
	final_phase = true
	for h in hollows:
		if is_instance_valid(h):
			h.persistent = true
	sfx.play("toll", null, 0.0, 0.6)
	hud.banner("NIGHT FALLS\nThe shrines are dark. The hollows gather at the portal.", 4.5)
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
		print("RESULT esc=%d player=%s bloom=%d shard=%d damage=%d flare=%d kills=%d blooms=%d hollows=%d fell=%d shoves=%d pushed_off=%d wyrm=%d drops=%d fruit=%d potion=%d beast=%d crawler=%d doused=%d ready=%d" % [
			escaped_names.size(), "esc" if player.escaped else ("alive" if player.lost else ("fell" if player.fell else "dead")),
			stats["bloom"], stats["shard"], stats["damage"], stats["flare"], stats["kills"], stats["blooms"], stats["hollows"],
			stats["fell"], stats["shoves"], stats["pushed_off"], stats["wyrm"], stats["drops"],
			stats["fruit"], stats["potion"], stats["beast"], stats["crawler"], stats["doused"], stats["ready"]])


func _log_status() -> void:
	var parts: Array = []
	for s in survivors:
		var tag := "esc" if s.escaped else ("%d" % int(s.light) if s.alive else ("F" if s.fell else "X"))
		var rel := ("S" if s.relic_flare else "") + ("F" if s.relic_fruit else "") + ("P" if s.relic_potion else "")
		parts.append("%s:%s%s%s%s" % [s.display_name, tag, "*" if s.tool_swings > 0 else "", "[%s]" % rel if rel != "" else "", "e%d" % s.extinguishers if s.extinguishers > 0 else ""])
	print("t=%03d fps=%d hollows=%d blooms=%d | %s" % [int(time_left), Engine.get_frames_per_second(), _active_hollows(), _list("bloom").size(), " ".join(PackedStringArray(parts))])
	if args.has("trialtrace"):
		var pot = trials.potion
		var near := INF
		var who := ""
		for s2 in survivors:
			if s2.alive and not s2.escaped and pot != null and is_instance_valid(pot):
				var d2 := _flat(s2.global_position, pot.global_position)
				if d2 < near:
					near = d2
					who = "%s y=%.1f" % [s2.display_name, s2.global_position.y]
		print("  potion=%s pos=%s nearest=%.2f %s | crawler=%d hp=%d pos=%s | beast=%d hp=%d" % [trials.potion_ready(), pot.global_position if pot != null and is_instance_valid(pot) else Vector3.ZERO, near, who, trials.crawler.state, trials.crawler.hp, trials.crawler.global_position.snapped(Vector3.ONE * 0.1), trials.beast.state, trials.beast.hp])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and (state == "ended" or (state == "playing" and (not player.alive or player.escaped))):
		restart()
	elif state == "flyover" and ((event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)):
		skip_flyover()
	elif state == "intro" and event is InputEventKey and event.pressed \
			and event.keycode in [KEY_ENTER, KEY_1, KEY_2, KEY_KP_1, KEY_KP_2, KEY_P]:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if event.keycode == KEY_P:
			player.set_autopilot(true)
		start_match(event.keycode in [KEY_1, KEY_KP_1])
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		hud.toast("Music on" if sfx.toggle_music() else "Music off")


func _process(delta: float) -> void:
	if args.has("hitch"):
		# Debug: report every frame that took longer than 40 ms (shader compiles show up here).
		_hitch_t += delta
		if delta > 0.04:
			print("HITCH %4d ms at %5.1fs state=%s hollows=%d drops=%d pickups=%d" % [int(delta * 1000.0), _hitch_t, state, hollows.size(), drops.size(), pickups.size()])
	if intro_cam:
		_update_intro_cam(delta)
	if args.has("introsecs") and state == "intro":
		# Demo recording: show the title card briefly, then let the AI play.
		if intro_t > float(args["introsecs"]):
			player.set_autopilot(true)
			start_match(args.has("gentle"))
	if intro_cam and state == "flyover" and not is_instance_valid(intro_cam):
		intro_cam = null
	if args.has("snapevery") and state == "playing":
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = float(args["snapevery"])
			var dir: String = args.get("snapdir", OS.get_user_data_dir())
			var path := "%s/snap_%03d.png" % [dir, int(Cfg.MATCH_TIME - time_left)]
			get_viewport().get_texture().get_image().save_png(path)
			print("snap ", path, " light=", int(player.light), " pos=", player.global_position.snapped(Vector3.ONE * 0.1))
	if state == "playing" and (args.has("falltest") or args.has("dietest")) and _frames >= 40 and not has_meta("tested"):
		set_meta("tested", true)
		if args.has("falltest"):
			player.global_position = world.island_center(world.START_ISLAND) + Vector3(0, 0.5, world.island_radius(world.START_ISLAND) + 1.5)
		else:
			print("DIETEST before pos=", player.global_position.snapped(Vector3.ONE * 0.1), " floor=", player.is_on_floor())
			player.lose_light(200.0)
	if args.has("outclick") and state == "playing" and hud.out_panel.visible and _quit_t < 100.0:
		_quit_t += delta
		if _quit_t > 0.8:
			_quit_t = 1000.0
			var ob: Button = hud.find_child("OutPlayAgain", true, false)
			var oat: Vector2 = get_viewport().get_final_transform() * ob.get_global_rect().get_center()
			print("OUTCLICK panel='", hud.out_title.text, "' clicking ", oat)
			print("OUTCLICK player fell=", player.fell, " cause=", player.cause, " pos=", player.global_position.snapped(Vector3.ONE * 0.1), " layer=", player.collision_layer, " mask=", player.collision_mask)
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = oat
				ev.global_position = oat
				Input.parse_input_event(ev)
	if args.has("clicktest") and state == "ended":
		# Test: click PLAY AGAIN with a real mouse event once the end screen is up.
		_quit_t += delta
		if _quit_t > 2.5 and _quit_t < 100.0:
			_quit_t = 1000.0
			var b: Button = hud.find_child("PlayAgain", true, false)
			var at: Vector2 = get_viewport().get_final_transform() * b.get_global_rect().get_center()
			print("CLICKTEST clicking ", at)
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = pressed
				ev.position = at
				ev.global_position = at
				Input.parse_input_event(ev)
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
	for g in trials.guardians():
		if not g.is_active():
			continue
		var tg: Vector3 = g.global_position - origin
		if absf(tg.y) > 2.5:
			continue
		tg.y = 0.0
		var dg: float = tg.length() - float(g.body_radius())
		if dg > reach:
			continue
		if dg > 0.6 and tg.normalized().dot(facing) < 0.2:
			continue
		if dg < bd:
			bd = dg
			best = g
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
		if want_tool != (pk.kind == "tool") or pk.kind == "flare":
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
	for g in trials.guardians():
		if g.is_active() and _flat(g.global_position, p) <= Cfg.FLARE_RADIUS + g.body_radius() and absf(g.global_position.y - p.y) < 3.0:
			g.hurt(Cfg.GUARD_FLARE_DAMAGE, p, 6.0)
	# The blast also throws other pilgrims back: a weapon out on the stones.
	for o in survivors:
		if o == s or not o.alive or o.escaped or args.has("noshove"):
			continue
		var d := _flat(o.global_position, p)
		if d > Cfg.FLARE_RADIUS * 0.6 or absf(o.global_position.y - p.y) > 2.5:
			continue
		var dir: Vector3 = o.global_position - p
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		var k := 1.0 - d / (Cfg.FLARE_RADIUS * 0.6) * 0.5
		var force: float = Cfg.FLARE_SHOVE * k * (0.35 if o.bracing and o.brace_ready else 1.0)
		o.shoved(dir * force + Vector3(0, 3.0, 0), s)
		if o.is_player:
			hud.toast("%s's flare threw you back!" % s.display_name)
			o.shake = maxf(o.shake, 0.3)


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


func on_guardian_woke(g) -> void:
	if player.alive and not player.escaped and _flat(g.global_position, player.global_position) < 30.0:
		hud.alert("THE %s AWAKES" % g.display, Color(1.0, 0.45, 0.3), 2.5)
	elif g.kind == "beast":
		feed("The Thornback is awake in the Hidden Garden.", C_BAD)


func on_guardian_down(g) -> void:
	stats[g.kind] += 1
	var near: bool = player.alive and not player.escaped and _flat(g.global_position, player.global_position) < 30.0
	if g.kind == "beast":
		trials.on_beast_down()
		feed("The Thornback has fallen! The Sky Fruit drops from the tree.", C_GOOD)
		if near:
			hud.banner("THE THORNBACK FALLS\nGrab a SKY FRUIT before the others do!", 3.0)
	else:
		feed("The Shardback shatters in the Crystal Cave.", C_GOOD)
		if near:
			hud.banner("THE SHARDBACK SHATTERS\nTake the MOON POTION from the altar!", 3.0)


func on_guardian_reformed(g) -> void:
	if g.kind == "beast":
		trials.on_beast_reformed()
		feed("The Thornback has grown back under the fruit tree.", C_DARK)
	else:
		feed("The Shardback re-forms in the Crystal Cave.", C_DARK)


func on_fruit_fell() -> void:
	sfx.play("chime3", world.tree_pos, 2.0)
	fx_burst(world.tree_pos + Vector3(0, 4.0, 0), Color(1.0, 0.75, 0.3), 40, false, 3.0)


func on_seal_doused(s) -> void:
	stats["doused"] += 1
	if s.is_player:
		hud.toast("You doused the flames! The way to the portal is open for %ds" % int(Cfg.SEAL_OUT_TIME))
	elif player.alive and not player.escaped and _flat(world.gate_pos, player.global_position) < 40.0:
		feed("%s put out part of the fire seal." % s.display_name, C_INFO)


func on_survivor_down(s) -> void:
	if args.has("log"):
		print("DOWN %s cause=%s t=%d pos=%s goal=%s shover=%s" % [s.display_name, s.cause, int(time_left), s.global_position.snapped(Vector3.ONE * 0.1),
			s.goal.snapped(Vector3.ONE * 0.1) if "goal" in s else "-", s.last_shover.display_name if s.last_shover else "-"])
	if s.cause == "fell":
		stats["fell"] += 1
		var now := Time.get_ticks_msec()
		var msg := "%s fell into the Underglow." % s.display_name
		if now - int(s.last_blade_ms) < 5000:
			msg = "A blade threw %s into the Underglow!" % ("you" if s.is_player else s.display_name)
		elif now - int(s.last_fire_ms) < 5000:
			msg = "The fire threw %s into the Underglow!" % ("you" if s.is_player else s.display_name)
		elif now - int(s.last_wyrm_ms) < 6000:
			msg = "The Devourer swept %s into the Underglow!" % ("you" if s.is_player else s.display_name)
		elif s.last_shover != null and now - int(s.last_shove_ms) < 4500:
			stats["pushed_off"] += 1
			msg = "%s knocked %s into the Underglow!" % [s.last_shover.display_name, "you" if s.is_player else s.display_name]
		feed(msg, C_BAD)
		sfx.play("fall", null if s.is_player else s.global_position, 0.0, randf_range(0.9, 1.1))
		if s.is_player:
			hud.banner("YOU FELL INTO THE UNDERGLOW\nSpectating. %s to switch." % ("Tap the screen" if touch else "Press Tab"), 4.0)
		return
	feed("Your lantern went out." if s.is_player else "%s's lantern went out." % s.display_name, C_BAD)
	fx_burst(s.global_position + Vector3(0, 1.0, 0), Color(0.12, 0.08, 0.18), 30, true, 1.5)
	sfx.play("lantern_out", null if s.is_player else s.global_position, 0.0)
	if s.is_player:
		hud.banner("YOUR LANTERN WENT OUT\nSpectating. Press Tab to switch.", 4.0)


## A fallen pilgrim reaches the glowing sea far below.
func on_hit_underglow(s) -> void:
	var p: Vector3 = s.global_position
	fx_burst(p, Color(0.35, 1.0, 0.9), 50, false, 10.0)
	fx_light(p, Color(0.35, 1.0, 0.9), 10.0, 30.0, 1.5)


# ---------------------------------------------------------------- drops, the Devourer, shoves

func _tick_drops(delta: float) -> void:
	next_drop -= delta
	if next_drop > 0.0:
		return
	var iv: Vector2 = Cfg.DROP_INTERVAL_NIGHT if final_phase else Cfg.DROP_INTERVAL
	next_drop = randf_range(iv.x, iv.y)
	var p = null
	if stats["drops"] == 0:
		# The first one lands in the middle of the meadow: everyone scrambles at once.
		var c: Vector3 = world.island_center(world.START_ISLAND)
		var a := randf() * TAU
		p = c + Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 3.0)
	else:
		for attempt in 10:
			var isl: int = world.HEART_ISLAND if randf() < 0.2 else -1
			var q = world.random_island_point(isl, 2.0, 0.5)
			if q != null and not world.in_any_shrine(q, 0.5) and not world.in_cave(q, 1.5) and world.island_at(q) != world.GATE_ISLAND:
				p = q
				break
	if p == null:
		return
	spawn_drop(p)


func spawn_drop(p: Vector3) -> void:
	stats["drops"] += 1
	var d = DropScript.new()
	d.main = self
	d.warn = Cfg.DROP_WARN
	d.place = world.place_name(p)
	d.position = p
	add_child(d)
	drops.append(d)
	var dist: float = p.distance_to(player.global_position)
	hud.alert("SUNFLARE INCOMING  ·  %s  ·  %dm" % [d.place.to_upper(), int(dist)], Color(1.0, 0.65, 0.25), 3.5)
	sfx.play("drop_warn", null, -8.0)
	hud.tip("drop", "TIP: A SUNFLARE is falling (orange on the map). Grab it first for +2 flares. Don't stand in the ring when it lands!")


func on_drop_landed(d) -> void:
	var p: Vector3 = d.global_position
	fx_ring(p + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.2), Cfg.DROP_BLAST * 2.0, 0.6)
	fx_light(p + Vector3(0, 2.0, 0), Color(1.0, 0.6, 0.25), 14.0, 22.0, 1.0)
	fx_burst(p + Vector3(0, 0.6, 0), Color(1.0, 0.65, 0.25), 70, false, 9.0)
	sfx.play("drop_impact", p, 6.0)
	shake_near(p, 28.0, 0.7)
	for s in survivors:
		if not s.alive or s.escaped:
			continue
		var dd := _flat(s.global_position, p)
		if dd < Cfg.DROP_BLAST and absf(s.global_position.y - p.y) < 3.0:
			var dir: Vector3 = s.global_position - p
			dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.05 else Vector3(1, 0, 0)
			s.shoved(dir * 8.0 + Vector3(0, 5.0, 0))
			s.lose_light(4.0)
	_spawn_pickup("flare", p)


## The most attractive Sunflare for a bot: an incoming drop or a landed one.
func best_drop(s):
	var sp: Vector3 = s.global_position
	var best = null
	var best_score := INF
	var reach: float = 18.0 + 26.0 * s.greed
	for d in drops:
		if not is_instance_valid(d):
			continue
		var dp: Vector3 = d.global_position
		var dist := _flat(sp, dp)
		if dist > reach:
			continue
		# Wait just outside the blast ring until it lands.
		var goal := dp
		if d.remaining() > 0.8:
			var off: Vector3 = sp - dp
			off.y = 0.0
			off = off.normalized() if off.length() > 0.1 else Vector3(1, 0, 0)
			goal = dp + off * (Cfg.DROP_BLAST + 0.8)
		if dist < best_score:
			best_score = dist
			best = {"pos": goal}
	for pk in pickups:
		if not is_instance_valid(pk) or pk.kind != "flare":
			continue
		var dist := _flat(sp, pk.global_position)
		if dist > reach or dist >= best_score:
			continue
		best_score = dist
		best = {"pos": pk.global_position}
	return best


## Is there something worth fighting over near p?
func contested_near(p: Vector3, r: float) -> bool:
	for d in drops:
		if is_instance_valid(d) and _flat(d.global_position, p) < r + Cfg.DROP_BLAST:
			return true
	for pk in pickups:
		if is_instance_valid(pk) and pk.kind != "shard" and _flat(pk.global_position, p) < r:
			return true
	return false


func find_shove_target(s, cone := true):
	var best = null
	var bd: float = Cfg.SHOVE_RANGE
	for o in survivors:
		if o == s or not o.alive or o.escaped:
			continue
		var to: Vector3 = o.global_position - s.global_position
		if absf(to.y) > 1.6:
			continue
		to.y = 0.0
		var d := to.length()
		if d > bd:
			continue
		if cone and d > 0.6 and to.normalized().dot(s.facing) < 0.25:
			continue
		bd = d
		best = o
	return best


func do_shove(s) -> void:
	var p: Vector3 = s.global_position
	sfx.play("swish", null if s.is_player else p, -4.0, randf_range(0.9, 1.15))
	var t = find_shove_target(s, true)
	if t == null:
		return
	stats["shoves"] += 1
	var dir: Vector3 = t.global_position - p
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else s.facing
	var force: float = Cfg.SHOVE_FORCE
	if t.bracing and t.brace_ready:
		force *= 0.3
	t.shoved(dir * force + Vector3(0, Cfg.SHOVE_LIFT, 0), s)
	sfx.play("shove", null if (s.is_player or t.is_player) else t.global_position, 0.0, randf_range(0.9, 1.1))
	fx_ring(t.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.95, 0.85), 1.4, 0.3)
	if t.is_player:
		t.shake = maxf(t.shake, 0.35)
		hud.toast("%s shoved you!" % s.display_name)
	if s.is_player:
		player.shake = maxf(player.shake, 0.12)


func shake_near(p: Vector3, radius: float, amount: float) -> void:
	if player == null or not player.alive:
		return
	var d: float = player.global_position.distance_to(p)
	if d < radius:
		player.shake = maxf(player.shake, amount * (1.0 - d / radius))


func _tick_wyrm(delta: float) -> void:
	next_wyrm -= delta
	if next_wyrm > 0.0 or wyrm.state != "idle":
		return
	# Prefer a bridge with pilgrims on it (the player counts double).
	var cands: Array = []
	for s in survivors:
		if not s.alive or s.escaped:
			continue
		var bi: int = world.bridge_at(s.global_position, 0.5)
		if bi < 0 or bi == world.GAUNTLET:
			continue
		cands.append([bi, s])
		if s.is_player:
			cands.append([bi, s])
	if cands.is_empty() and _wyrm_tries < 5:
		_wyrm_tries += 1
		next_wyrm = 2.0
		return
	_wyrm_tries = 0
	var iv: Vector2 = Cfg.WYRM_INTERVAL_NIGHT if final_phase else Cfg.WYRM_INTERVAL
	next_wyrm = randf_range(iv.x, iv.y)
	var bi := -1
	var near := Vector3.ZERO
	if cands.is_empty():
		# Nobody out on the stones: rise somewhere the player can see it anyway.
		var bd := INF
		for i in world.bridges.size():
			if i == world.GAUNTLET:
				continue
			for st in world.bridges[i]["stones"]:
				var d: float = st.distance_to(player.global_position)
				if d < bd:
					bd = d
					bi = i
					near = st
	else:
		var c: Array = cands.pick_random()
		bi = c[0]
		near = c[1].global_position
	var stone: Vector3 = world.bridges[bi]["stones"][0]
	for st in world.bridges[bi]["stones"]:
		if _flat(st, near) < _flat(stone, near):
			stone = st
	wyrm.strike(bi, stone, Cfg.WYRM_WARN * (1.3 if gentle else 1.0))
	if args.has("log"):
		var on: Array = []
		for s2 in survivors:
			if s2.alive and not s2.escaped and world.bridge_at(s2.global_position, 0.5) == bi:
				on.append(s2.display_name)
		print("WYRM t=%d bridge=%d stone=%s on_bridge=%s" % [int(time_left), bi, stone.snapped(Vector3.ONE * 0.1), on])
	var pd: float = player.global_position.distance_to(stone)
	if pd < 60.0:
		hud.alert("THE DEVOURER RISES!  GET OFF THE STONES!", Color(1.0, 0.3, 0.25), Cfg.WYRM_WARN + 0.5)
	hud.tip("wyrm", "TIP: When stones glow RED, the Devourer is about to burst up through that bridge. Get off them!")


## If p is in the Devourer's strike zone, the nearest way off the bridge; else null.
func wyrm_escape_point(p: Vector3, reaction := 0.0):
	if wyrm == null or not wyrm.is_threatening():
		return null
	if wyrm.state == "warn" and wyrm.t < reaction:
		return null
	if p.distance_to(wyrm.target) > 7.5:
		return null
	var b: Dictionary = world.bridges[wyrm.bridge]
	var mine: Vector2 = world.bridge_line_info(wyrm.bridge, p)
	var its: Vector2 = world.bridge_line_info(wyrm.bridge, wyrm.target)
	if mine.x > 4.0:
		return null
	var dir: Vector3 = b["dir"]
	if mine.y < its.y:
		var a: Vector3 = world.island_center(int(b["a"]))
		return b["start"] - dir * 2.0 + Vector3(0, a.y - b["start"].y, 0)
	var e: Vector3 = world.island_center(int(b["b"]))
	return b["end"] + dir * 2.0 + Vector3(0, e.y - b["end"].y, 0)


func on_survivor_escaped(s) -> void:
	fx_light(world.gate_pos + Vector3(0, 3.5, 0), Color(1.0, 0.85, 0.5), 12.0, 20.0, 1.2)
	world.escape_beam()
	sfx.play("escape", null if s.is_player else world.gate_pos + Vector3(0, 2, 0), 0.0)
	feed("%s stepped through the portal." % s.display_name, C_GOOD)
	if s.is_player:
		hud.banner("YOU PASSED THROUGH THE PORTAL", 4.0)


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
