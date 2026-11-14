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
var blade_margin := 0.5 # how much room a bot leaves a swinging blade (careless bots get hit)
var plan := "" # which trial it is working on: "fruit", "potion", "flare", "portal"
var plan_t := 0.0
var patience := 0.5 # how long it is willing to wait for others to kill a guardian


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
	blade_margin = randf_range(-0.1, 0.7)
	patience = randf()
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
	# Falling with nothing below: double jump back towards the nearest stone.
	if not is_on_floor() and air_jumps > 0 and velocity.y < -2.0 and not main.world.has_ground(global_position, global_position.y, 25.0):
		var land = main.world.nearest_landing(global_position)
		# Only once we have dropped below it: a normal jump down to a lower stone stays above.
		if land != null and global_position.y < float(land.y) + 0.2:
			var to_land: Vector3 = land - global_position
			to_land.y = 0.0
			if to_land.length() > 0.3:
				move_dir = to_land.normalized()
				_air_dir = move_dir
				air_speed = clampf(to_land.length() / 0.8, 2.0, Cfg.SPRINT_SPEED)
				want_jump = true
				return
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
			var vent_wait: bool = main.trials != null and blade_margin > 0.05 and main.trials.jet_danger(land, dist / air_speed + 0.5)
			var on_vent: bool = main.trials != null and main.trials.jet_danger(global_position, 0.4)
			if not on_vent and (vent_wait or (main.blades != null and not main.blades.path_clear(global_position, land, dist / air_speed, blade_margin))):
				# A blade is about to sweep through this gap: wait at the edge for it to pass.
				move_dir = Vector3.ZERO
				air_speed = 0.0
				stuck_t = 0.0
				last_pos = global_position
				return
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
	var T = main.trials
	var W = main.world

	# 1. All three relics and bright enough: to the portal, through the seal of fire.
	if has_all_relics() and light >= Cfg.ESCAPE_LIGHT:
		if extinguishers > 0 or T.seal_open_toward(W.portal_front, 3.0):
			_set_goal(W.gate_pos)
			want_sprint = true
			if threat != null and tdist < 2.6:
				try_flare()
			return
		var ex = main.nearest_pickup(pos, ["extinguisher"])
		if ex != null:
			_set_goal(ex.global_position, ex)
			want_sprint = true
			return
		# No extinguisher anywhere: wait by the fire for someone to open it.
		var c: Vector3 = W.gate_pos
		var f: Vector3 = W.portal_front - c
		f.y = 0.0
		_set_goal(c + f.normalized() * (Cfg.SEAL_RADIUS + 2.5) + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
		return

	# 2. A guardian is about to strike me: get out of its way.
	for g in T.guardians():
		if not g.is_awake():
			continue
		var to_me: Vector3 = pos - g.global_position
		to_me.y = 0.0
		var gd: float = to_me.length()
		if g.is_striking() and gd < Cfg.GUARD_REACH + g.body_radius() + (5.0 if g.charging else 1.5):
			var in_arc: bool = gd < 1.0 or to_me.normalized().dot(g.atk_dir) > (0.6 if g.charging else 0.1)
			if in_arc:
				if light >= Cfg.BRACE_LIGHT and brace_ready and randf() < 0.5:
					bracing = true
				var side := Vector3(-g.atk_dir.z, 0, g.atk_dir.x)
				if side.dot(to_me) < 0.0:
					side = -side
				_set_goal(pos + (side * 2.0 + to_me.normalized()).normalized() * 4.0)
				want_sprint = true
				return

	# 3. Deal with a nearby hollow: fight, flare or flee.
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
			var sh = W.nearest_shrine(pos, 2.5)
			if sh != null and _flat_dist(pos, sh) < 14.0 and light < 70.0:
				_set_goal(sh)
			else:
				var away: Vector3 = pos - threat.global_position
				away.y = 0.0
				away = away.normalized()
				var side := Vector3(-away.z, 0, away.x) * randf_range(-0.6, 0.6)
				var tgt := pos + (away + side).normalized() * 6.0
				if W.island_at(tgt) == W.island_at(pos) and W.island_at(pos) >= 0:
					_set_goal(tgt)
				else:
					_set_goal(W.island_center(maxi(0, W.island_at(pos))))
			want_sprint = true
			return

	# 4. Very dim: light first, whatever the plan.
	if light < 30.0:
		var pk0 = main.best_pickup(self, false)
		if pk0 != null:
			_set_goal(pk0.global_position, pk0)
			want_sprint = stamina > 1.0
			return

	# 5. A Sunflare falling (or lying) close by: race for it (it is a relic too).
	if flares < Cfg.FLARE_MAX or not relic_flare:
		var dr = main.best_drop(self)
		if dr != null and (not relic_flare or _flat_dist(pos, dr["pos"]) < 16.0):
			_set_goal(dr["pos"])
			want_sprint = stamina > 0.5
			return

	# 6. The trials.
	if not relic_fruit or not relic_potion:
		if _do_trials(pos, T, W):
			return

	# 7. Light, then a weapon, then an extinguisher.
	if light < Cfg.MAX_LIGHT - 1.0:
		var pk = main.best_pickup(self, false)
		if pk != null and (light < Cfg.ESCAPE_LIGHT + 4.0 or _flat_dist(pos, pk.global_position) < 15.0):
			_set_goal(pk.global_position, pk)
			want_sprint = _flat_dist(pos, pk.global_position) < 12.0 and stamina > 1.0
			return
	if tool_swings == 0:
		var tl = main.best_pickup(self, true)
		if tl != null and _flat_dist(pos, tl.global_position) < 30.0:
			_set_goal(tl.global_position, tl)
			return
	if extinguishers == 0 and relic_count() >= 2:
		var ex2 = main.nearest_pickup(pos, ["extinguisher"])
		if ex2 != null:
			_set_goal(ex2.global_position, ex2)
			return
	if not relic_flare:
		# Wait somewhere central for the next Sunflare.
		if not has_goal or _flat_dist(pos, goal) < 1.0:
			_set_goal(W.random_island_point(W.HEART_ISLAND if randf() < 0.5 else W.START_ISLAND, 2.0, 1.0) if randf() < 0.8 else W.random_walk_point())
		return
	if not has_goal or _flat_dist(pos, goal) < 1.0:
		_set_goal(W.random_walk_point())


## Works on the Sky Fruit and the Moon Potion. Returns true if it set a goal.
func _do_trials(pos: Vector3, T, W) -> bool:
	plan_t -= 0.25
	var fruits: Array = T.fruit_on_ground()
	# Fruit lying under the tree, or the potion on the altar, and we need it: go now.
	if not relic_fruit and not fruits.is_empty():
		var best = null
		var bd := 70.0
		for f in fruits:
			var d := _flat_dist(pos, f.global_position)
			if d < bd and not is_blocked(f):
				bd = d
				best = f
		if best != null:
			_set_goal(best.global_position, best)
			want_sprint = stamina > 0.5
			return true
	# Pick which trial to work on: the nearer one, kept for a while so it doesn't dither.
	if plan_t <= 0.0 or (plan == "fruit" and relic_fruit) or (plan == "potion" and relic_potion) or plan == "":
		plan_t = randf_range(6.0, 10.0)
		var df: float = _flat_dist(pos, W.garden_center) if not relic_fruit else INF
		var dp: float = _flat_dist(pos, W.cave_center) if not relic_potion else INF
		plan = "fruit" if df < dp else "potion"
	var armed: bool = tool_swings > 0 or flares > 0
	if plan == "potion":
		var g = T.crawler
		if T.potion_ready():
			var pp: Vector3 = T.potion.global_position
			var to_pot := pos - pp
			to_pot.y = 0.0
			var near_pt: Vector3 = pp + (to_pot.normalized() if to_pot.length() > 0.1 else W.cave_dir) * 1.5
			# The Shardback is right there and we are armed: fight it first.
			if g.is_awake() and armed and _flat_dist(g.global_position, pos) < 5.0 and light >= 35.0:
				return _fight(g, pos)
			_set_goal(near_pt, T.potion)
			want_sprint = stamina > 0.5
			return true
		# Brewing: wait by the doorway (or fight the guardian if keen).
		if g.is_awake() and armed and bravery > 0.5 and light >= 45.0 and _flat_dist(g.global_position, pos) < 8.0:
			return _fight(g, pos)
		_set_goal(W.cave_door + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5)) if _flat_dist(pos, W.cave_door) > 2.5 else pos)
		return true
	# The fruit: the Thornback has to fall first.
	var b = T.beast
	if b.is_active():
		var keen: bool = armed and light >= lerpf(55.0, 35.0, bravery)
		if keen:
			return _fight(b, pos)
		if tool_swings == 0:
			var tl = main.best_pickup(self, true)
			if tl != null and _flat_dist(pos, tl.global_position) < 45.0:
				_set_goal(tl.global_position, tl)
				return true
		# Unarmed: lurk by a garden gateway and hope someone else kills it.
		if patience > 0.3:
			var gate: Vector3 = W.garden_gates[0]
			for gg in W.garden_gates:
				if _flat_dist(pos, gg) < _flat_dist(pos, gate):
					gate = gg
			var inward: Vector3 = (W.garden_center - gate)
			inward.y = 0.0
			var lurk: Vector3 = gate + inward.normalized() * 2.0
			if _flat_dist(pos, lurk) > 2.0:
				_set_goal(lurk)
			return true
		return false
	# Beast down, fruit not fallen yet (or all taken): wait near the tree if it is about to drop.
	if T.fruit_t > 0.0:
		_set_goal(W.tree_pos + (pos - W.tree_pos).normalized() * 3.0)
		return true
	# All taken: go for the potion meanwhile.
	if not relic_potion:
		plan = "potion"
		plan_t = 8.0
	return false


## Close in on a guardian and hit it; flare it when close and out of swings.
func _fight(g, pos: Vector3) -> bool:
	var to_g: Vector3 = g.global_position - pos
	to_g.y = 0.0
	var d: float = to_g.length() - float(g.body_radius())
	if to_g.length() > 0.01:
		facing = to_g.normalized()
		face_lock = 0.3
	if g.is_asleep() and tool_swings == 0 and flares > 0 and d < 3.0:
		try_flare()
	if tool_swings > 0:
		if d <= Cfg.SWING_REACH - 0.3:
			try_swing()
		_set_goal(g.global_position - to_g.normalized() * (g.body_radius() + 1.2))
	else:
		if flares > 0 and d < Cfg.FLARE_RADIUS * 0.6:
			try_flare()
		_set_goal(g.global_position - to_g.normalized() * (g.body_radius() + 2.0))
	want_sprint = d > 4.0 and stamina > 1.0
	return true


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
