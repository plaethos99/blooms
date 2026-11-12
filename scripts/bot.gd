extends "res://scripts/survivor.gd"
## AI pilgrim. Same rules as the player; navigates with a NavigationAgent3D.

var agent: NavigationAgent3D
var think_t := 0.0
var goal := Vector3.ZERO
var has_goal := false
var bravery := 0.5
var greed := 0.5
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var wander_t := 0.0
var goal_obj_id := 0
var blocked := {} # pickup instance id -> time (msec) until which we ignore it
var stuck_count := 0


func is_blocked(obj) -> bool:
	var id: int = obj.get_instance_id()
	return blocked.has(id) and Time.get_ticks_msec() < int(blocked[id])


func _ready() -> void:
	super._ready()
	bravery = randf()
	greed = randf()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 0.8
	agent.radius = 0.5
	agent.height = 1.8
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
	stuck_t += delta
	if stuck_t > 1.2:
		if global_position.distance_to(last_pos) < 0.6:
			# Stuck: give up on this pickup for a while and walk somewhere reachable.
			stuck_count += 1
			if goal_obj_id != 0:
				blocked[goal_obj_id] = Time.get_ticks_msec() + 12000
			wander_t = 1.5
			if stuck_count >= 2:
				_set_goal(main.world.random_walk_point())
			else:
				var a := randf() * TAU
				_set_goal(global_position + Vector3(cos(a), 0, sin(a)) * 5.0)
		else:
			stuck_count = 0
		stuck_t = 0.0
		last_pos = global_position


func _think() -> void:
	bracing = false
	want_sprint = false
	if wander_t > 0.0:
		wander_t -= 0.25
		return
	var pos := global_position
	var threat = main.nearest_hollow(pos, 9.0)
	var tdist := 999.0
	if threat != null:
		tdist = _flat_dist(pos, threat.global_position)

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
				_set_goal(pos + (away + side).normalized() * 7.0)
			want_sprint = true
			return

	# 3. Gather light, then a tool.
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

	# 4. Bright enough (or late): wait near the summit stairs. Otherwise wander.
	if light >= Cfg.ESCAPE_LIGHT or (main.time_left < 80.0 and light >= 65.0):
		var a := deg_to_rad(30.0 if (get_instance_id() % 2 == 0) else 210.0)
		_set_goal(Vector3(cos(a) * 10.5, 5.0, sin(a) * 10.5))
		return
	if not has_goal or _flat_dist(pos, goal) < 1.0:
		_set_goal(main.world.random_walk_point())
