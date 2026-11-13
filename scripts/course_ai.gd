extends RefCounted
## How bots (and the player's autopilot) run Level 1: follow their lane's waypoints,
## time jumps onto moving steps and past blades, fight in the arena, swing on ropes.
## Everything that moves is driven by the match clock, so a bot can predict exactly
## where a step or ring will be when it lands.

const Cfg = preload("res://scripts/cfg.gd")


static func control(b, delta: float) -> void:
	var main = b.main
	var w = main.world
	b.think_t -= delta
	b.want_sprint = false
	if b.rope_state != "":
		_rope(b, delta)
		return
	var pos: Vector3 = b.global_position
	var grounded: bool = b.is_on_floor()
	if grounded:
		b.lane = w.lane_of(pos.x)
	# Falling with nothing below: double jump back towards the nearest step.
	if not grounded and b.air_jumps > 0 and b.velocity.y < -2.0 and not w.has_ground(pos, pos.y, 25.0):
		var land = w.nearest_landing(pos)
		if land != null and pos.y < float(land.y) + 0.2:
			var to_land: Vector3 = land - pos
			to_land.y = 0.0
			if to_land.length() > 0.3:
				b.move_dir = to_land.normalized()
				b._air_dir = b.move_dir
				b.air_speed = clampf(to_land.length() / 0.8, 2.0, Cfg.SPRINT_SPEED)
				b.want_jump = true
				return
	if not grounded and b._air_dir != Vector3.ZERO:
		b.move_dir = b._air_dir
		return
	b._air_dir = Vector3.ZERO
	b.air_speed = 0.0
	match int(b.cphase):
		3:
			_arena(b, delta)
			return
		4:
			_ledge(b)
			return
		6:
			b.move_dir = Vector3.ZERO
			return
	_follow(b)


static func _flat(a: Vector3, c: Vector3) -> float:
	return Vector2(a.x - c.x, a.z - c.z).length()


## Walk along the lane; at an edge, jump to the next step when the timing is right.
static func _follow(b) -> void:
	var main = b.main
	var w = main.world
	var pos: Vector3 = b.global_position
	var i: int = w.next_wp(b.lane, pos, b.cphase)
	var wp: Dictionary = w.routes[b.lane][i]
	var tgt: Vector3 = w.wp_pos(wp)
	var to := tgt - pos
	to.y = 0.0
	if to.length() < 0.35:
		b.move_dir = Vector3.ZERO
		return
	b.move_dir = to.normalized()
	b.want_sprint = b.stamina > 1.0 and b.cphase == 5
	if b.think_t <= 0.0:
		b.think_t = randf_range(0.2, 0.32)
		if b.cphase >= 2 and randf() < 0.25 and not main.args.has("noshove"):
			b._maybe_shove()
	var probe: Vector3 = pos + b.move_dir * 0.7
	if w.has_ground(probe, pos.y, 1.4):
		return
	# At an edge: predict where the next step will be when we land.
	var g: float = Cfg.GRAVITY
	var v: float = Cfg.JUMP_VEL
	var pred := tgt
	var tair := 0.7
	for it in 2:
		var dh := clampf(pred.y - 0.3 - pos.y, -6.0, 1.8)
		tair = (v + sqrt(maxf(0.0, v * v - 2.0 * g * dh))) / g
		pred = w.wp_pos(wp, w.sim_t + tair + 0.05)
	var d := _flat(pred, pos)
	if wp["m"] == null and String(wp["kind"]) != "stone" and d > 3.6:
		# Jumping onto an island: land just past its edge, not on the far-off waypoint.
		var dirv := Vector3(pred.x - pos.x, 0, pred.z - pos.z).normalized()
		pred = Vector3(pos.x + dirv.x * 3.6, pred.y, pos.z + dirv.z * 3.6)
		d = 3.6
	var ok: bool = pred.y <= pos.y + 1.45 and d <= 5.4 and d >= 0.5
	if ok and main.blades != null and not main.blades.path_clear(pos, pred, tair, b.blade_margin):
		ok = false
	if b.hes_t < 0.0:
		b.hes_t = randf_range(0.5, 1.7) * lerpf(1.4, 0.6, b.bravery)
	b.hes_t = maxf(0.0, b.hes_t - b.get_physics_process_delta_time())
	if not ok or b.hes_t > 0.0:
		# Wait at the edge (a moving step carries us along meanwhile).
		b.move_dir = Vector3.ZERO
		return
	b.hes_t = -1.0
	b.air_speed = clampf(d / tair, 2.0, Cfg.SPRINT_SPEED)
	b.want_jump = true
	var to2 := pred - pos
	to2.y = 0.0
	b.move_dir = to2.normalized()
	b._air_dir = b.move_dir


## The arena: bring down enough monsters, then head for your lane's gateway.
static func _arena(b, delta: float) -> void:
	var main = b.main
	var w = main.world
	var pos: Vector3 = b.global_position
	if b.kills >= Cfg.KILLS_NEEDED:
		var l: int = w.lane_of(pos.x)
		var ex := Vector3(w.lane_x(l), pos.y, w.exit_z + 1.0)
		var to := ex - pos
		to.y = 0.0
		b.move_dir = to.normalized() if to.length() > 0.3 else Vector3(0, 0, -1)
		return
	var f = main.nearest_flyer(pos, 40.0)
	if b.think_t <= 0.0:
		b.think_t = randf_range(0.18, 0.3)
		# Wander somewhere in the middle of the arena.
		if b.goal == Vector3.ZERO or _flat(pos, b.goal) < 1.0 or randf() < 0.08:
			var l2: int = w.lane_of(pos.x)
			b.goal = Vector3(w.lane_x(l2) + randf_range(-6.0, 6.0), pos.y, w.arena_z + randf_range(-6.0, 7.0))
		if f != null:
			var tp: Vector3 = f.core()
			var chest := pos + Vector3(0, 1.3, 0)
			var dist := chest.distance_to(tp)
			var pick := ""
			if b.weapons.has("axe") and dist < Cfg.AXE_REACH + 0.2:
				pick = "axe"
			elif b.weapons.has("bow"):
				pick = "bow"
			elif b.weapons.has("saw") and dist < Cfg.SAW_RANGE:
				pick = "saw"
			elif b.weapons.has("axe"):
				pick = "axe"
			if pick != "":
				b.select_weapon(pick)
			var can: bool = b.attack_cd <= 0.0 and b.weapon != ""
			if b.weapon == "axe" and dist > Cfg.AXE_REACH:
				can = false
			if b.weapon == "saw" and (b.saw_out or dist > Cfg.SAW_RANGE):
				can = false
			if b.weapon == "bow" and (dist > 16.0 or f.state == "enter"):
				can = false
			if can and randf() < lerpf(0.22, 0.55, b.bravery):
				var err := lerpf(0.12, 0.03, b.bravery)
				var aim := (tp - chest).normalized()
				aim = (aim + Vector3(randf_range(-err, err), randf_range(-err, err), randf_range(-err, err))).normalized()
				var flat := Vector3(aim.x, 0, aim.z)
				if flat.length() > 0.05:
					b.facing = flat.normalized()
					b.face_lock = 0.3
				main.course_attack(b, aim)
	# A monster diving straight at us: meet it with the axe, or dodge.
	if f != null and f.state == "dive" and f.target == b and b.weapons.has("axe") and b.attack_cd <= 0.0:
		var dv: float = (f.core() - (pos + Vector3(0, 1.3, 0))).length()
		if dv < 4.5:
			b.select_weapon("axe")
			main.course_attack(b, (f.core() - (pos + Vector3(0, 1.3, 0))).normalized())
			return
	if f != null and f.state == "dive" and f.target == b and not b.weapons.has("axe"):
		var side := Vector3(-f.vel.z, 0, f.vel.x).normalized()
		if side.dot(pos - f.global_position) < 0.0:
			side = -side
		b.move_dir = side
		b.want_sprint = true
		return
	var to_goal: Vector3 = b.goal - pos
	to_goal.y = 0.0
	b.move_dir = to_goal.normalized() if to_goal.length() > 0.8 else Vector3.ZERO
	# Never wander off the edge.
	if not w.has_ground(pos + b.move_dir * 1.2, pos.y, 1.5):
		var c := Vector3(w.lane_x(w.lane_of(pos.x)), pos.y, w.arena_z) - pos
		c.y = 0.0
		b.move_dir = c.normalized()
		b.goal = Vector3.ZERO


## On the arena's far edge with the rope: fire at the first ring.
static func _ledge(b) -> void:
	var main = b.main
	var w = main.world
	var pos: Vector3 = b.global_position
	if pos.z < w.exit_z - 1.0:
		# Out over the chasm (just let go of a ring): drift on towards the gate island.
		var to_g: Vector3 = w.gate_pos - pos
		to_g.y = 0.0
		b.move_dir = to_g.normalized()
		return
	var l: int = w.lane_of(pos.x)
	var first: int = int(w.lane_rings[l][0])
	var from := pos + Vector3(0, 1.6, 0)
	if w.ring_pos(first).distance_to(from) <= Cfg.ROPE_RANGE - 0.5 and b.is_on_floor():
		if b.think_t <= 0.0:
			b.think_t = randf_range(0.15, 0.45)
			b.move_dir = Vector3.ZERO
			b.rope_fire(first)
		return
	var ex := Vector3(w.lane_x(l), pos.y, w.exit_z + 0.6)
	var to := ex - pos
	to.y = 0.0
	b.move_dir = to.normalized() if to.length() > 0.3 else Vector3.ZERO


## Hanging from a ring: wait for the line to the next one to be clear, then fire.
## From the last ring, let go and drop onto the gate island.
static func _rope(b, _delta: float) -> void:
	b.move_dir = Vector3.ZERO
	if b.rope_state != "hang":
		return
	var main = b.main
	var w = main.world
	var cur: int = b.rope_ring
	var r: Dictionary = w.rings[cur]
	if int(r["k"]) == w.RING_COUNT - 1:
		if b.hang_t > 0.3:
			b.rope_release(true)
		return
	if b.hang_t < lerpf(2.2, 0.9, b.bravery):
		return
	var l: int = w.lane_of(w.ring_pos(cur).x)
	var nxt := -1
	var lr: Array = w.lane_rings[l]
	if not bool(r["drifter"]):
		nxt = int(lr[mini(int(r["k"]) + 1, lr.size() - 1)])
	else:
		var cz: float = w.ring_pos(cur).z
		for i in lr:
			if w.ring_pos(int(i)).z < cz - 1.0:
				nxt = int(i)
				break
	if nxt < 0 or nxt == cur:
		return
	var here: Vector3 = b.global_position
	var there: Vector3 = w.ring_hang(nxt)
	var dist := here.distance_to(there)
	if dist > Cfg.ROPE_RANGE:
		return
	var tz := dist / Cfg.ROPE_SPEED
	if main.blades != null and not main.blades.path_clear(here, w.ring_hang(nxt, w.sim_t + tz), tz, b.blade_margin):
		return
	b.rope_fire(nxt)
