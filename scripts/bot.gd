extends "res://scripts/survivor.gd"
## AI pilgrim. Same rules as the player; navigates with a NavigationAgent3D, jumps the
## gaps between stepping stones, races for Sunflare drops and shoves rivals.

var agent: NavigationAgent3D
var think_t := 0.0
var goal := Vector3.ZERO
var has_goal := false
var bravery := 0.5
var greed := 0.5
var ruthless := 0.5
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var wander_t := 0.0
var goal_obj_id := 0
var blocked := {} # pickup instance id -> time (msec) until which we ignore it
var stuck_count := 0
var _air_dir := Vector3.ZERO


func autopilot_flag() -> bool:
	return false


func is_blocked(obj) -> bool:
	var id: int = obj.get_instance_id()
	return blocked.has(id) and Time.get_ticks_msec() < int(blocked[id])


func _ready() -> void:
	super._ready()
	bravery = randf()
	greed = randf()
	ruthless = randf()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 1.1
	agent.target_desired_distance = 1.0
	agent.radius = 0.5
	agent.height = 1.8
	agent.path_max_distance = 6.0
	add_child(agent)
	think_t = randf() * 0.3
	last_pos = position


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _set_goal(p: Vector3, obj = null) -> void:
	if not has_goal or p.distance_to(goal) > 0.75:
		goal = p
		agent.target_position = p
	has_goal = true
	goal_obj_id = obj.get_instance_id() if obj != null else 0


func _controller(delta: float) -> void:
	think_t -= delta
	if think_t <= 0.0:
		think_t = randf_range(0.18, 0.32)
		_think()
	if not is_on_floor() and _air_dir != Vector3.ZERO:
		# Mid-jump: keep heading for the stone we aimed at.
		move_dir = _air_dir
		return
	_air_dir = Vector3.ZERO
	air_speed = 0.0
	if not has_goal:
		move_dir = Vector3.ZERO
		return
	var to_goal := goal - global_position
	to_goal.y = 0.0
	if to_goal.length() < 0.6:
		move_dir = Vector3.ZERO
		return
	var nxt := agent.get_next_path_position()
	var d := nxt - global_position
	d.y = 0.0
	if d.length() < 0.05:
		d = to_goal
	move_dir = d.normalized()
	if main.args.has("jtrace") and (display_name == main.args["jtrace"] or main.args["jtrace"] == "all") and main.world.bridge_at(global_position, 2.5) >= 0 and Engine.get_physics_frames() % 2 == 0:
		print("J %s %d pos=%s floor=%s vel=%s nxt=%s goal=%s" % [display_name, Engine.get_physics_frames(), global_position.snapped(Vector3.ONE * 0.01), is_on_floor(), velocity.snapped(Vector3.ONE * 0.1), nxt.snapped(Vector3.ONE * 0.1), goal.snapped(Vector3.ONE * 0.1)])
	# Out on the stones: keep moving fast and jump every gap.
	var probe := global_position + move_dir * 0.7
	if not main.world.has_ground(probe, global_position.y, 1.4):
		var land: Vector3 = nxt if d.length() > 1.0 else goal
		var dist := _flat_dist(land, global_position)
		if dist > 0.9:
			# Aim the jump: pick the run-up speed that lands on the middle of the next stone.
			var dh := clampf(land.y - 0.5 - global_position.y, -6.0, 1.8)
			var v: float = Cfg.JUMP_VEL
			var g: float = Cfg.GRAVITY
			var tair := (v + sqrt(maxf(0.0, v * v - 2.0 * g * dh))) / g
			air_speed = clampf(dist / tair, 2.0, Cfg.SPRINT_SPEED)
			want_jump = true
			var to_land := land - global_position
			to_land.y = 0.0
			move_dir = to_land.normalized()
			_air_dir = move_dir
	elif main.world.bridge_at(global_position, 0.3) >= 0:
		want_sprint = stamina > 1.0
	stuck_t += delta
	if stuck_t > 1.4:
		if global_position.distance_to(last_pos) < 0.6:
			# Stuck: give up on this goal for a while and walk somewhere reachable.
			stuck_count += 1
			if goal_obj_id != 0:
				blocked[goal_obj_id] = Time.get_ticks_msec() + 12000
			wander_t = 1.5
			if stuck_count >= 2:
				_set_goal(main.world.random_walk_point())
			else:
				var a := randf() * TAU
				_set_goal(global_position + Vector3(cos(a), 0, sin(a)) * 4.0)
		else:
			stuck_count = 0
		stuck_t = 0.0
		last_pos = global_position


func _think() -> void:
	bracing = false
	want_sprint = false
	var pos := global_position
	# 0. The Devourer is rising under this bridge: get off it, now.
	# Bots notice the red glow after a moment's delay (different each time).
	var react := 0.0
	if not is_player or autopilot_flag():
		react = fposmod(sin(float(get_instance_id() % 997) * 12.9898 + float(main.wyrm.strikes) * 78.233) * 43758.5453, 1.0) * 2.6 + 0.3
	var esc = main.wyrm_escape_point(pos, react)
	if esc != null:
		_set_goal(esc)
		want_sprint = true
		wander_t = 0.0
		return
	if wander_t > 0.0:
		wander_t -= 0.25
		return
	var threat = main.nearest_hollow(pos, 9.0)
	var tdist := 999.0
	if threat != null:
		tdist = _flat_dist(pos, threat.global_position)

	_maybe_shove()

	# 1. Bright enough and the gate is open: go.
	if main.gate_open and light >= Cfg.ESCAPE_LIGHT:
		_set_goal(main.world.gate_pos)
		want_sprint = true
		if threat != null and tdist < 2.6:
			try_flare()
		return

	# 2. Deal with a nearby hollow: fight, flare or flee.
	if threat != null:
		var can_fight: bool = tool_swings > 0 and light >= lerpf(65.0, 30.0, bravery)
		if tdist < 2.8 and (not can_fight or light < 40.0):
			try_flare()
		if can_fight:
			var to_t: Vector3 = threat.global_position - pos
			to_t.y = 0.0
			if to_t.length() > 0.01:
				facing = to_t.normalized()
				face_lock = 0.3
			if light >= Cfg.BRACE_LIGHT and tdist < 2.4 and brace_ready:
				bracing = true
			if tdist <= Cfg.SWING_REACH - 0.2:
				try_swing()
			_set_goal(threat.global_position)
			return
		if tdist < 7.5:
			var sh = main.world.nearest_shrine(pos, 2.5)
			if sh != null and _flat_dist(pos, sh) < 14.0 and light < 70.0:
				_set_goal(sh)
			else:
				var away: Vector3 = pos - threat.global_position
				away.y = 0.0
				away = away.normalized()
				var side := Vector3(-away.z, 0, away.x) * randf_range(-0.6, 0.6)
				var tgt := pos + (away + side).normalized() * 6.0
				# Do not flee off a cliff.
				if main.world.island_at(tgt) == main.world.island_at(pos) and main.world.island_at(pos) >= 0:
					_set_goal(tgt)
				else:
					_set_goal(main.world.island_center(maxi(0, main.world.island_at(pos))))
			want_sprint = true
			return

	# 3. A Sunflare is falling (or lying) close by: race for it.
	if flares < Cfg.FLARE_MAX:
		var dr = main.best_drop(self)
		if dr != null:
			_set_goal(dr["pos"])
			want_sprint = stamina > 0.5
			return

	# 4. Gather light, then a tool.
	if light < Cfg.MAX_LIGHT - 1.0:
		var pk = main.best_pickup(self, false)
		if pk != null:
			_set_goal(pk.global_position, pk)
			want_sprint = _flat_dist(pos, pk.global_position) < 12.0 and stamina > 1.0
			return
	if tool_swings == 0:
		var tl = main.best_pickup(self, true)
		if tl != null:
			_set_goal(tl.global_position, tl)
			return

	# 5. Bright enough (or late): wait on the gate island. Otherwise wander.
	if light >= Cfg.ESCAPE_LIGHT or (main.time_left < 80.0 and light >= 65.0):
		_set_goal(main.world.gate_wait_point(get_instance_id()))
		return
	if not has_goal or _flat_dist(pos, goal) < 1.0:
		_set_goal(main.world.random_walk_point())


## Shove a rival who stands near a drop, or (if ruthless) near an edge.
func _maybe_shove() -> void:
	if shove_cd > 0.0 or not is_on_floor() or main.args.has("noshove"):
		return
	var t = main.find_shove_target(self)
	if t == null:
		return
	if main.gentle and t.is_player and ruthless < 0.75:
		return
	var dir: Vector3 = t.global_position - global_position
	dir.y = 0.0
	dir = dir.normalized()
	var over_edge: bool = not main.world.has_ground(t.global_position + dir * 2.2, t.global_position.y, 3.0)
	var contest: bool = main.contested_near(global_position, 5.0)
	var chance := 0.0
	if over_edge:
		chance = lerpf(0.03, 0.4, ruthless)
	elif contest:
		chance = lerpf(0.1, 0.4, ruthless)
	if randf() < chance:
		facing = dir
		face_lock = 0.3
		try_shove()
