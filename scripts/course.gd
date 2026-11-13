extends "res://scripts/world.gd"
## Level 1, THE GAUNTLET: a straight race in parallel lanes, built from the same sky
## gardens as the open-island game. Every lane has the same layout (fair racing, and
## ready for online play later: everything that moves is driven by the match clock).
##
##   start pads -> (1) FIRE BLADES -> lamp islet -> (2) MOVING STEPS (weapons)
##   -> (3) the shared ARENA (flying monsters) -> (4) ROPE CHASM -> the Sun Gate.

const Arms = preload("res://scripts/arms.gd")

const PAD_R := 6.0
const LAMP_R := 4.5
const ARENA_R := 14.0
const GATE_R := 16.0
const STEP_R := 1.3
const START_Y := 0.0
const LAMP_Y := 1.5
const ARENA_Y := 3.0
const GATE_Y := 6.0
const RING_Y := 10.2
const RING_COUNT := 8
const RING_STEP := 10.0
const RING_FIRST := 7.0
# Phase 1: gaps (rim to rim) before, between and after ten stones; blades hang in the odd gaps.
const STONES_1 := 10
const GAPS_1 := [1.4, 2.6, 1.4, 2.6, 1.4, 2.6, 1.4, 2.6, 1.4, 2.6, 1.4]
const BLADE_GAPS_1 := [1, 3, 5, 7, 9]
# Phase 2: twelve moving steps; gaps 4 and 8 are wide, with a lane-crossing step in the middle.
const STEPS_2 := 12
const GAPS_2 := [1.6, 1.6, 1.6, 1.6, 3.2, 1.6, 1.6, 1.6, 3.2, 1.6, 1.6, 1.6, 1.6]
const FERRY_GAPS := [4, 8]
const WEAPON_STEPS := {2: "bow", 6: "axe", 10: "saw"}

var isles: Array = [] # [name, x, z, top y, radius, model index]
var lane_xs: Array = []
var arena_isles: Array = []
var gate_isle := -1
var lamp_z := 0.0
var arena_z := 0.0 # centre of the arena circles
var entry_z := 0.0 # arena rim on the way in
var exit_z := 0.0 # arena rim on the way out
var gate_z := 0.0
var chasm_z0 := 0.0
var chasm_z1 := 0.0
var sim_t := 0.0 # match clock for everything that moves (physics time)

var movers: Array = [] # moving steps, see _mover
var rings: Array = [] # rope rings, see _ring
var lane_rings: Array = [] # lane -> Array of ring indices, in order
var routes: Array = [] # lane -> Array of waypoints (see _wp)
var seg: Array = [] # lane -> {phase: [first, last]} indices into its route
var lamps: Array = [] # lane -> {pos, bulb, light, beam}
var weapon_spots: Array = [] # {kind, mover, node, lane}
var barriers: Array = [] # lane -> {mat, x}
var extra_blades: Array = [] # read by blades.gd: [mid, dir, period, phase]
var guide: Node3D
var _guide_target = null
var _guide_light: OmniLight3D
var _ring_hl := -1

var gust_state := "idle"
var gust_dir := 1.0
var gust_t := 4.0
var _gust_fx: GPUParticles3D
var _gust_pm: ParticleProcessMaterial


# ---------------------------------------------------------------- island table

func _isle(i: int) -> Array:
	return isles[i]


func isle_count() -> int:
	return isles.size()


func _gate_spot() -> Vector3:
	return Vector3(0.0, GATE_Y, gate_z - 3.0)


func _gate_isle() -> int:
	return gate_isle


func lane_x(l: int) -> float:
	return float(lane_xs[l])


func lane_of(x: float) -> int:
	var best := 0
	for l in lane_xs.size():
		if absf(x - float(lane_xs[l])) < absf(x - float(lane_xs[best])):
			best = l
	return best


# ---------------------------------------------------------------- layout

func _plan() -> void:
	var n: int = Cfg.LANES
	for l in n:
		lane_xs.append((float(l) - float(n - 1) * 0.5) * Cfg.LANE_W)
	var len1 := float(STONES_1) * STEP_R * 2.0
	for g in GAPS_1:
		len1 += float(g)
	lamp_z = -PAD_R - len1 - LAMP_R
	var len2 := float(STEPS_2) * STEP_R * 2.0
	for g in GAPS_2:
		len2 += float(g)
	entry_z = lamp_z - LAMP_R - len2
	arena_z = entry_z - ARENA_R
	exit_z = arena_z - ARENA_R
	chasm_z0 = exit_z
	var last_ring_z := exit_z - RING_FIRST - RING_STEP * float(RING_COUNT - 1)
	gate_z = last_ring_z - 3.0 - GATE_R
	chasm_z1 = last_ring_z - 3.0
	for l in n:
		isles.append(["Dawn Steps", lane_x(l), 0.0, START_Y, PAD_R, 5])
	for l in n:
		isles.append(["Lamp Rock", lane_x(l), lamp_z, LAMP_Y, LAMP_R, 5])
	var arena_models := [1, 2, 4, 3, 1]
	for l in n:
		arena_isles.append(isles.size())
		isles.append(["The Arena", lane_x(l), arena_z, ARENA_Y, ARENA_R, arena_models[l % arena_models.size()]])
	gate_isle = isles.size()
	isles.append(["Sun Gate Isle", 0.0, gate_z, GATE_Y, GATE_R, 0])
	area_mid = Vector3(0.0, 0.0, gate_z * 0.5)
	# Where paths leave each island (keeps cliff gardens and columns out of the way).
	for i in isles.size():
		bridge_angles[i] = [-PI / 2.0, PI / 2.0]
	for i in arena_isles:
		bridge_angles[i].append_array([0.0, PI])
	bridge_angles[gate_isle] = []
	for l in n:
		var land := Vector3(lane_x(l) * 0.5, 0, chasm_z1)
		bridge_angles[gate_isle].append(atan2(land.z - gate_z, land.x))


func build() -> void:
	_plan()
	_make_materials()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	_build_islands()
	for l in Cfg.LANES:
		routes.append([])
		seg.append({})
		lane_rings.append([])
	_build_phase1()
	_build_lamps()
	_build_phase2()
	_build_arena()
	_build_chasm()
	_build_gate()
	_build_island_features()
	_build_waterfalls()
	_build_hanging_gardens()
	_build_grass()
	_build_flowers()
	_build_fireflies()
	_build_petals()
	_build_distant()
	_build_clouds()
	_build_underworld()
	_build_guide()
	_build_routes()


func _build_islands() -> void:
	for i in isles.size():
		var c := island_center(i)
		var r := island_radius(i)
		var mi: int = int(isles[i][5])
		var s := r / float(ISLANDS[mi][4])
		_model("res://models/island_%d.glb" % mi, self, c, Vector3(0, randf() * TAU, 0), Vector3(s, clampf(s * 1.2, 0.45, 1.0), s))
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = 3.0
		_static(shape, c - Vector3(0, 1.5, 0), LAYER_TERRAIN)
		for k in 3:
			var a := randf() * TAU
			var rr := r + randf_range(4.0, 8.0)
			var sc := randf_range(0.4, 0.9)
			var node := _model("res://models/rock_%d.glb" % (randi() % 3), self, c + Vector3(cos(a) * rr, randf_range(-9.0, -3.0), sin(a) * rr), Vector3(randf(), randf() * TAU, randf()), Vector3(sc, sc * 0.8, sc))
			floaters.append([node, node.position.y, randf() * TAU, 0.7])


## (1) Fire blades: six still stones per lane, a burning pendulum over every other gap.
func _build_phase1() -> void:
	var ys: Array = []
	var jit: Array = []
	var prev := START_Y
	for k in STONES_1:
		var want := lerpf(START_Y, LAMP_Y, float(k + 1) / float(STONES_1 + 1)) + randf_range(-0.4, 0.4)
		prev = clampf(want, prev - 0.9, prev + 0.9)
		ys.append(prev)
		jit.append(randf_range(-0.3, 0.3))
	var swing := {}
	var first_ph := randf() * TAU
	for g in BLADE_GAPS_1:
		swing[g] = [randf_range(Cfg.BLADE_PERIOD.x, Cfg.BLADE_PERIOD.y), randf() * TAU]
	# The last two swing against each other: time both at once.
	swing[9] = [float(swing[7][0]), float(swing[7][1]) + PI]
	swing[1] = [float(swing[1][0]), first_ph]
	for l in Cfg.LANES:
		var x := lane_x(l)
		var rune := _mat(RUNE_COL, 0.4, RUNE_COL, 0.8)
		var stones: Array = []
		var radii: Array = []
		var along := PAD_R
		for k in STONES_1:
			along += float(GAPS_1[k]) + STEP_R
			var p := Vector3(x + float(jit[k]), float(ys[k]), -along)
			_build_stone(p, STEP_R, rune)
			stones.append(p)
			radii.append(STEP_R)
			along += STEP_R
		_lamp(Vector3(x + 2.4, START_Y, -PAD_R + 0.8))
		bridges.append({
			"a": l, "b": Cfg.LANES + l, "stones": stones, "radii": radii, "rune": rune, "warn": 0.0,
			"blade_gaps": BLADE_GAPS_1, "blade_swing": swing, "fire": true,
			"dir": Vector3(0, 0, -1), "perp": Vector3(1, 0, 0),
			"start": Vector3(x, START_Y, -PAD_R), "end": Vector3(x, LAMP_Y, lamp_z + LAMP_R),
		})


## The lamp you must pick up at the end of the blades: one pedestal per lane.
func _build_lamps() -> void:
	var gold := _mat(Color(0.95, 0.72, 0.32), 0.3, Color(1.0, 0.68, 0.3), 1.4)
	gold.metallic = 0.8
	for l in Cfg.LANES:
		var c := Vector3(lane_x(l), LAMP_Y, lamp_z)
		var col := CylinderMesh.new()
		col.top_radius = 0.42
		col.bottom_radius = 0.55
		col.height = 1.0
		_mesh(self, col, _marble, c + Vector3(0, 0.5, 0))
		var top := CylinderMesh.new()
		top.top_radius = 0.6
		top.bottom_radius = 0.5
		top.height = 0.12
		_mesh(self, top, gold, c + Vector3(0, 1.06, 0))
		var root := Node3D.new()
		root.position = c + Vector3(0, 1.75, 0)
		add_child(root)
		var cage := CylinderMesh.new()
		cage.top_radius = 0.2
		cage.bottom_radius = 0.26
		cage.height = 0.55
		cage.radial_segments = 6
		var cm := _mesh(root, cage, _iron, Vector3.ZERO)
		cm.transparency = 0.55
		var cap := CylinderMesh.new()
		cap.top_radius = 0.05
		cap.bottom_radius = 0.28
		cap.height = 0.16
		_mesh(root, cap, gold, Vector3(0, 0.35, 0))
		var bulb_mat := _mat(Color(1.0, 0.9, 0.6), 0.3, Color(1.0, 0.75, 0.35), 6.0)
		var bulb := SphereMesh.new()
		bulb.radius = 0.17
		bulb.height = 0.34
		_mesh(root, bulb, bulb_mat, Vector3.ZERO)
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.75, 0.4)
		lt.light_energy = 2.5
		lt.omni_range = 7.0
		root.add_child(lt)
		var beam_mat := StandardMaterial3D.new()
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		beam_mat.albedo_color = Color(1.0, 0.8, 0.4, 0.16)
		var bm := CylinderMesh.new()
		bm.top_radius = 0.7
		bm.bottom_radius = 0.35
		bm.height = 30.0
		bm.cap_top = false
		bm.cap_bottom = false
		var beam := _mesh(self, bm, beam_mat, c + Vector3(0, 16.0, 0))
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		obstacles.append([Vector2(c.x, c.z), 0.8])
		var shp := CylinderShape3D.new()
		shp.radius = 0.5
		shp.height = 1.1
		_static(shp, c + Vector3(0, 0.55, 0), LAYER_OBSTACLE)
		lamps.append({"pos": c + Vector3(0, 1.0, 0), "root": root, "bulb": bulb_mat, "light": lt, "beam": beam_mat})
		_lamp(c + Vector3(2.8, 0, -LAMP_R + 1.0))


## Dim a lane's lamp once the player has taken theirs (they still shine for the others).
func set_lamp_taken(l: int) -> void:
	var d: Dictionary = lamps[l]
	var tw := create_tween().set_parallel(true)
	tw.tween_property(d["light"], "light_energy", 0.3, 0.6)
	tw.tween_property(d["bulb"], "emission_energy_multiplier", 0.6, 0.6)
	tw.tween_property(d["beam"], "albedo_color:a", 0.0, 0.6)


## (2) Moving steps: they rise and fall, slide side to side, or both. The pattern is the
## same in every lane; two wide gaps have a step that ferries you between lanes.
func _build_phase2() -> void:
	var plan: Array = []
	var start_z := lamp_z - LAMP_R
	var along := 0.0
	for k in STEPS_2:
		along += float(GAPS_2[k]) + STEP_R
		var kind := "bob"
		if k > 0:
			if k % 2 == 0:
				kind = "bob" if randf() < 0.6 else "zig"
			else:
				kind = "sway" if randf() < 0.65 else "zig"
		var y := lerpf(LAMP_Y, ARENA_Y, float(k + 1) / float(STEPS_2 + 1))
		plan.append({"z": start_z - along, "y": y, "kind": kind,
			"w": TAU / randf_range(Cfg.STEP_PERIOD.x, Cfg.STEP_PERIOD.y), "ph": randf() * TAU})
		along += STEP_R
	for l in Cfg.LANES:
		var x := lane_x(l)
		for k in STEPS_2:
			var p: Dictionary = plan[k]
			var m := _mover(Vector3(x, float(p["y"]), float(p["z"])), STEP_R, String(p["kind"]), float(p["w"]), float(p["ph"]))
			m["lane"] = l
			m["idx"] = k
			if WEAPON_STEPS.has(k):
				var kind_w: String = WEAPON_STEPS[k]
				var holder := Node3D.new()
				holder.position = Vector3(0, 1.35, 0)
				m["body"].add_child(holder)
				var w := Arms.make(kind_w)
				w.scale = Vector3.ONE * 1.6
				holder.add_child(w)
				_pickup_glow(holder)
				weapon_spots.append({"kind": kind_w, "mover": m, "node": holder, "lane": l})
	# Lane-crossing steps in the two wide gaps (opposite timing).
	var fi := 0
	for g in FERRY_GAPS:
		var k0: int = int(g) - 1
		var z := (float(plan[k0]["z"]) + float(plan[k0 + 1]["z"])) * 0.5
		var y := (float(plan[k0]["y"]) + float(plan[k0 + 1]["y"])) * 0.5 - 0.15
		var cycle := 4.0 * (Cfg.FERRY_DWELL + Cfg.FERRY_MOVE)
		var m := _mover(Vector3(0, y, z), 1.25, "ferry", 0.0, cycle * 0.5 * float(fi))
		m["lane"] = -1
		m["idx"] = -1
		fi += 1


func _mover(base: Vector3, r: float, kind: String, w: float, ph: float) -> Dictionary:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = true
	body.collision_layer = LAYER_TERRAIN
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = STONE_H
	cs.shape = shape
	cs.position = Vector3(0, -STONE_H * 0.5, 0)
	body.add_child(cs)
	add_child(body)
	_model("res://models/stone_%d.glb" % (randi() % 6), body, Vector3.ZERO, Vector3(0, randf() * TAU, 0), Vector3(r, r * 0.9, r))
	var col: Color = {"bob": Color(0.45, 1.0, 0.75), "sway": Color(0.55, 0.75, 1.0), "zig": Color(0.85, 0.6, 1.0), "ferry": Color(1.0, 0.8, 0.4)}[kind]
	var rune := _mat(col, 0.4, col, 1.2)
	glow_mats.append([rune, 1.2, 4.0])
	var ring := TorusMesh.new()
	ring.inner_radius = r - 0.3
	ring.outer_radius = r - 0.16
	ring.rings = 24
	ring.ring_segments = 4
	var rm := _mesh(body, ring, rune, Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1, 0.12, 1))
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in 2:
		var a := randf() * TAU
		var vine := _model("res://models/rock_%d.glb" % (randi() % 3), body, Vector3(cos(a) * r * 0.5, -0.9, sin(a) * r * 0.5), Vector3(randf(), randf() * TAU, randf()), Vector3(0.45, 0.6, 0.45))
		vine.scale *= r / 1.3
	var m := {"body": body, "base": base, "kind": kind, "w": w, "ph": ph, "r": r}
	body.position = mover_pos(m, 0.0)
	movers.append(m)
	return m


func _ferry_x(t: float, ph: float, xs: Array) -> float:
	var span: float = Cfg.FERRY_DWELL + Cfg.FERRY_MOVE
	var order: Array = [0, 1, 2, 1]
	if xs.size() != 3:
		order = range(xs.size()) + range(xs.size() - 2, 0, -1)
	var cycle := span * float(order.size())
	var tt := fposmod(t + ph, cycle)
	var s := int(tt / span)
	var local := tt - float(s) * span
	var a := float(xs[int(order[s])])
	var b := float(xs[int(order[(s + 1) % order.size()])])
	if local < Cfg.FERRY_DWELL:
		return a
	return lerpf(a, b, smoothstep(0.0, 1.0, (local - Cfg.FERRY_DWELL) / Cfg.FERRY_MOVE))


## Where a moving step is at time t.
func mover_pos(m: Dictionary, t: float) -> Vector3:
	var b: Vector3 = m["base"]
	var s := sin(t * float(m["w"]) + float(m["ph"]))
	match String(m["kind"]):
		"bob":
			return b + Vector3(0, Cfg.STEP_BOB * s, 0)
		"sway":
			return b + Vector3(Cfg.STEP_SWAY * s, 0, 0)
		"zig":
			return b + Vector3(Cfg.STEP_SWAY * 0.8 * s, Cfg.STEP_BOB * 0.7 * s, 0)
		"ferry":
			return Vector3(_ferry_x(t, float(m["ph"]), lane_xs), b.y, b.z)
	return b


## A soft gold glow and a beam over something to pick up.
func _pickup_glow(parent: Node3D) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.45)
	l.light_energy = 1.2
	l.omni_range = 3.5
	parent.add_child(l)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.82, 0.4, 0.13)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.3
	cm.height = 6.0
	cm.cap_top = false
	cm.cap_bottom = false
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = Vector3(0, 2.2, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Beam"
	parent.add_child(mi)


## (3) The arena: the lanes meet on one wide island. A gate of light at each lane's far
## side lets you through once you have brought down enough monsters.
func _build_arena() -> void:
	for l in Cfg.LANES:
		var x := lane_x(l)
		var gp := Vector3(x, ARENA_Y, exit_z + 2.0)
		for sx in [-1.0, 1.0]:
			_column(gp + Vector3(3.3 * float(sx), 0, 0), 4.2, true)
		var lintel := BoxMesh.new()
		lintel.size = Vector3(7.6, 0.5, 0.9)
		_mesh(self, lintel, _marble, gp + Vector3(0, 4.35, 0))
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.albedo_color = Color(1.0, 0.3, 0.25, 0.28)
		var q := QuadMesh.new()
		q.size = Vector2(6.0, 4.0)
		var cur := _mesh(self, q, mat, gp + Vector3(0, 2.0, 0))
		cur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The rope launcher waits in the gateway.
		var holder := Node3D.new()
		holder.position = gp + Vector3(0, 1.4, 0.6)
		add_child(holder)
		var rope := Arms.make("rope")
		rope.scale = Vector3.ONE * 1.5
		holder.add_child(rope)
		barriers.append({"mat": mat, "pos": gp, "item": holder})
		_lamp(Vector3(x - 2.6, ARENA_Y, entry_z - 1.2))
	# Broken columns and amber crystals around the outside of the arena.
	var half := float(Cfg.LANES - 1) * 0.5 * Cfg.LANE_W
	for s in [-1.0, 1.0]:
		var cx := float(s) * (half + ARENA_R - 4.0)
		_amber_cluster(Vector3(cx, ARENA_Y, arena_z + 4.0))
		_column(Vector3(cx + float(s) * -2.0, ARENA_Y, arena_z - 5.0), randf_range(1.4, 3.2), true)
		make_tree(self, Vector3(cx + float(s) * 1.5, ARENA_Y, arena_z - 1.0), 1.2, true)
	for l in Cfg.LANES - 1:
		var mx := (lane_x(l) + lane_x(l + 1)) * 0.5
		_column(Vector3(mx, ARENA_Y, arena_z + 7.5), randf_range(1.0, 2.2), false)


## Show the gateway as open (gold) or closed (red) for the player.
func set_barrier_open(l: int, open: bool) -> void:
	var m: StandardMaterial3D = barriers[l]["mat"]
	m.albedo_color = Color(1.0, 0.82, 0.4, 0.22) if open else Color(1.0, 0.3, 0.25, 0.28)


func take_rope_visual(l: int) -> void:
	var it: Node3D = barriers[l]["item"]
	it.visible = false


## (4) The rope chasm: rings float over the abyss, sliding side to side; two more drift
## between the lanes. Burning blades swing across the line, and gusts blow through.
func _build_chasm() -> void:
	var gold := _mat(Color(1.0, 0.8, 0.4), 0.3, Color(1.0, 0.7, 0.3), 2.5)
	gold.metallic = 0.7
	var ring_plan: Array = []
	for k in RING_COUNT:
		ring_plan.append({"w": TAU / randf_range(4.2, 5.6), "ph": randf() * TAU})
	for l in Cfg.LANES:
		for k in RING_COUNT:
			var f := lerpf(1.0, 0.5, float(k) / float(RING_COUNT - 1))
			var base := Vector3(lane_x(l) * f, RING_Y, exit_z - RING_FIRST - RING_STEP * float(k))
			var i := _ring(base, float(ring_plan[k]["w"]), float(ring_plan[k]["ph"]), l, k, false)
			lane_rings[l].append(i)
	# Two drifting rings that carry you from lane to lane.
	for d in 3:
		var k := 1 + d * 2
		var z := exit_z - RING_FIRST - RING_STEP * (float(k) + 0.5)
		var cycle := 4.0 * (Cfg.FERRY_DWELL + Cfg.FERRY_MOVE)
		_ring(Vector3(0, RING_Y + 0.8, z), 0.0, cycle * 0.5 * float(d), -1, -1, true)
	# Burning blades across the rope line, between rings 0-1 and 2-3 (same in every lane).
	for k in [0, 2, 4, 6]:
		var per := randf_range(2.6, 3.4)
		var ph := randf() * TAU
		for l in Cfg.LANES:
			var a: Vector3 = rings[int(lane_rings[l][k])]["base"]
			var b: Vector3 = rings[int(lane_rings[l][k + 1])]["base"]
			var mid := (a + b) * 0.5 - Vector3(0, Cfg.ROPE_HANG + 0.55, 0)
			extra_blades.append([mid, Vector3(0, 0, -1), per, ph])
	_build_gust_fx()


func _ring(base: Vector3, w: float, ph: float, lane: int, k: int, drifter: bool) -> int:
	var root := Node3D.new()
	add_child(root)
	var mat := _mat(Color(1.0, 0.8, 0.4), 0.3, Color(1.0, 0.7, 0.3), 2.0)
	mat.metallic = 0.7
	if drifter:
		mat.emission = Color(0.5, 0.85, 1.0)
		mat.albedo_color = Color(0.6, 0.9, 1.0)
	var tm := TorusMesh.new()
	tm.inner_radius = 0.48
	tm.outer_radius = 0.66
	tm.rings = 32
	tm.ring_segments = 10
	_mesh(root, tm, mat, Vector3.ZERO, Vector3(PI / 2.0, 0, 0))
	var chain := CylinderMesh.new()
	chain.top_radius = 0.03
	chain.bottom_radius = 0.03
	chain.height = 2.2
	_mesh(root, chain, _iron, Vector3(0, 1.75, 0))
	var rock := _model("res://models/rock_%d.glb" % (randi() % 3), root, Vector3(0, 3.0, 0), Vector3(randf(), randf() * TAU, randf()), Vector3(0.7, 0.5, 0.7))
	rock.name = "Rock"
	var lt := OmniLight3D.new()
	lt.light_color = Color(1.0, 0.75, 0.4) if not drifter else Color(0.5, 0.85, 1.0)
	lt.light_energy = 0.8
	lt.omni_range = 4.0
	root.add_child(lt)
	var r := {"node": root, "base": base, "w": w, "ph": ph, "lane": lane, "k": k, "drifter": drifter, "mat": mat, "light": lt}
	rings.append(r)
	root.position = ring_pos(rings.size() - 1, 0.0)
	return rings.size() - 1


## Centre of ring i at time t (default: now).
func ring_pos(i: int, t := -1.0) -> Vector3:
	if t < 0.0:
		t = sim_t
	var r: Dictionary = rings[i]
	var b: Vector3 = r["base"]
	if bool(r["drifter"]):
		var xs: Array = []
		for x in lane_xs:
			xs.append(float(x) * 0.75)
		return Vector3(_ferry_x(t, float(r["ph"]), xs), b.y + 0.25 * sin(t * 1.3 + float(r["ph"])), b.z)
	var s := sin(t * float(r["w"]) + float(r["ph"]))
	return b + Vector3(Cfg.RING_SWAY * s, 0.25 * sin(t * 1.7 + float(r["ph"])), 0)


## Where a pilgrim's feet hang from ring i.
func ring_hang(i: int, t := -1.0) -> Vector3:
	return ring_pos(i, t) - Vector3(0, Cfg.ROPE_HANG, 0)


func ring_vel(i: int) -> Vector3:
	return (ring_pos(i, sim_t + 0.05) - ring_pos(i, sim_t)) / 0.05


## The ring a rope fired from `from` along `aim` would latch onto (-1 if none):
## the one nearest the aim, else the next one ahead in your lane.
func pick_ring(from: Vector3, aim: Vector3, cur := -1) -> int:
	var best := -1
	var best_s := INF
	var cur_z: float = INF if cur < 0 else ring_pos(cur).z
	for i in rings.size():
		if i == cur:
			continue
		var rp := ring_pos(i)
		if rp.z > cur_z - 1.0 or rp.z > from.z + 1.0:
			continue
		var to := rp - from
		var d := to.length()
		if d > Cfg.ROPE_RANGE or d < 1.0:
			continue
		var ang := aim.angle_to(to / d)
		if ang > 0.6:
			continue
		var s := ang + d * 0.012
		if s < best_s:
			best_s = s
			best = i
	if best >= 0:
		return best
	# Nothing near the aim: the next ring ahead in this lane, if it is in reach.
	var l := lane_of(from.x)
	for i in lane_rings[l]:
		var rp := ring_pos(int(i))
		if int(i) != cur and rp.z < minf(cur_z - 1.0, from.z + 1.0) and rp.distance_to(from) <= Cfg.ROPE_RANGE:
			return int(i)
	return -1


func highlight_ring(i: int) -> void:
	if i == _ring_hl:
		return
	if _ring_hl >= 0:
		rings[_ring_hl]["mat"].emission_energy_multiplier = 2.0
		rings[_ring_hl]["light"].light_energy = 0.8
	_ring_hl = i
	if i >= 0:
		rings[i]["mat"].emission_energy_multiplier = 7.0
		rings[i]["light"].light_energy = 2.4


func _build_gust_fx() -> void:
	_gust_fx = GPUParticles3D.new()
	_gust_fx.amount = 140
	_gust_fx.lifetime = 2.0
	_gust_fx.emitting = false
	_gust_fx.visibility_aabb = AABB(Vector3(-60, -15, -40), Vector3(120, 30, 80))
	_gust_pm = ParticleProcessMaterial.new()
	_gust_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_gust_pm.emission_box_extents = Vector3(4.0, 4.0, (chasm_z0 - chasm_z1) * 0.5)
	_gust_pm.direction = Vector3(1, 0, 0)
	_gust_pm.spread = 4.0
	_gust_pm.initial_velocity_min = 22.0
	_gust_pm.initial_velocity_max = 30.0
	_gust_pm.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_gust_pm.color_ramp = gt
	_gust_fx.process_material = _gust_pm
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 0.035, 0.035)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.9, 0.95, 1.0)
	bm.material = m
	_gust_fx.draw_pass_1 = bm
	add_child(_gust_fx)
	_gust_fx.position = Vector3(0, RING_Y - 2.0, (chasm_z0 + chasm_z1) * 0.5)


## Sideways push from a gust on someone at p (zero outside the chasm or between gusts).
func gust_force(p: Vector3) -> Vector3:
	if gust_state != "blow" or p.z > chasm_z0 - 1.0 or p.z < chasm_z1:
		return Vector3.ZERO
	return Vector3(gust_dir * Cfg.GUST_PUSH, 0, 0)


func _tick_gusts(delta: float) -> void:
	gust_t -= delta
	if gust_t > 0.0:
		return
	match gust_state:
		"idle":
			gust_state = "warn"
			gust_t = Cfg.GUST_WARN
			gust_dir = 1.0 if randf() < 0.5 else -1.0
			_gust_pm.direction = Vector3(gust_dir, 0, 0)
			var half := float(Cfg.LANES - 1) * 0.5 * Cfg.LANE_W + 10.0
			_gust_fx.position.x = -gust_dir * half
			_gust_fx.emitting = true
		"warn":
			gust_state = "blow"
			gust_t = Cfg.GUST_TIME
		_:
			gust_state = "idle"
			gust_t = randf_range(Cfg.GUST_EVERY.x, Cfg.GUST_EVERY.y)
			_gust_fx.emitting = false


# ---------------------------------------------------------------- routes (bots + the guide)

## A waypoint: something to stand on (or hang from) next.
func _wp(kind: String, phase: int, pos: Vector3, r: float, m = null, ring := -1) -> Dictionary:
	return {"kind": kind, "phase": phase, "pos": pos, "r": r, "m": m, "ring": ring}


func _build_routes() -> void:
	for l in Cfg.LANES:
		var x := lane_x(l)
		var rt: Array = routes[l]
		var s: Dictionary = seg[l]
		s[1] = [rt.size(), 0]
		for st in bridges[l]["stones"]:
			rt.append(_wp("stone", 1, st, STEP_R - 0.35))
		rt.append(_wp("lamp", 1, Vector3(x + 1.3, LAMP_Y, lamp_z + 0.2), 0.9))
		s[1][1] = rt.size() - 1
		s[2] = [rt.size(), 0]
		for m in movers:
			if int(m["lane"]) == l:
				rt.append(_wp("mover", 2, m["base"], STEP_R - 0.35, m))
		rt.append(_wp("pt", 2, Vector3(x, ARENA_Y, entry_z - 2.5), 1.5))
		s[2][1] = rt.size() - 1
		s[3] = [rt.size(), rt.size()]
		rt.append(_wp("exit", 3, Vector3(x, ARENA_Y, exit_z + 2.0), 1.2))
		s[4] = [rt.size(), 0]
		for i in lane_rings[l]:
			rt.append(_wp("ring", 4, ring_hang(int(i), 0.0), 0.8, null, int(i)))
		s[4][1] = rt.size() - 1
		s[5] = [rt.size(), rt.size()]
		rt.append(_wp("gate", 5, gate_pos, 1.2))


## Where a waypoint is at time t (default: now).
func wp_pos(wp: Dictionary, t := -1.0) -> Vector3:
	if t < 0.0:
		t = sim_t
	if wp["m"] != null:
		return mover_pos(wp["m"], t)
	if int(wp["ring"]) >= 0:
		return ring_hang(int(wp["ring"]), t)
	return wp["pos"]


## Index (in lane l's route) of the next thing ahead of p in phase `ph`.
func next_wp(l: int, p: Vector3, ph: int) -> int:
	var s: Array = seg[l].get(clampi(ph, 1, 5), [0, 0])
	var rt: Array = routes[l]
	for i in range(int(s[0]), int(s[1]) + 1):
		var wp: Dictionary = rt[i]
		var q := wp_pos(wp)
		if q.z < p.z - 0.45:
			return i
		# Standing on it already counts as passed, unless it is the end of the phase.
		if i == int(s[1]):
			return i
	return int(s[1])


## Respawn spot for someone who fell in `ph`, in lane l.
func checkpoint(ph: int, l: int) -> Vector3:
	var x := lane_x(l)
	match ph:
		2:
			return Vector3(x - 1.6, LAMP_Y, lamp_z - 1.2)
		3:
			return Vector3(x, ARENA_Y, entry_z - 3.0)
		4:
			return Vector3(x, ARENA_Y, exit_z + 0.8)
		_:
			return Vector3(x * 0.5, GATE_Y, chasm_z1 - 3.0)


func in_arena(p: Vector3) -> bool:
	return p.y > ARENA_Y - 1.5 and p.y < ARENA_Y + 4.0 and arena_isles.has(island_at(p))


func on_gate_isle(p: Vector3) -> bool:
	return island_at(p) == gate_isle and p.y > GATE_Y - 1.0


## Closest place a falling pilgrim at p could still double-jump back onto.
func nearest_landing(p: Vector3, reach := 6.0, climb := 1.8):
	var best = super.nearest_landing(p, reach, climb)
	var best_d: float = reach if best == null else Vector2(p.x - best.x, p.z - best.z).length() - 0.6
	for m in movers:
		var s := mover_pos(m, sim_t)
		if s.y > p.y + climb:
			continue
		var d := Vector2(s.x - p.x, s.z - p.z).length() - float(m["r"]) * 0.5
		if d < best_d:
			best_d = d
			best = s
	return best


# ---------------------------------------------------------------- the guide

## A little wisp of light that floats to wherever you should go next.
func _build_guide() -> void:
	guide = Node3D.new()
	add_child(guide)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.75)
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	_mesh(guide, sm, m, Vector3.ZERO)
	var halo := StandardMaterial3D.new()
	halo.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo.albedo_color = Color(1.0, 0.8, 0.45, 0.25)
	var hm := SphereMesh.new()
	hm.radius = 0.4
	hm.height = 0.8
	_mesh(guide, hm, halo, Vector3.ZERO).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_guide_light = OmniLight3D.new()
	_guide_light.light_color = Color(1.0, 0.85, 0.5)
	_guide_light.light_energy = 1.6
	_guide_light.omni_range = 4.0
	guide.add_child(_guide_light)
	var ps := GPUParticles3D.new()
	ps.amount = 40
	ps.lifetime = 0.9
	ps.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, 0.4, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.6, 0.9), Color(1.0, 0.7, 0.3, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	ps.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.04
	dm.height = 0.08
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	dm.material = fm
	ps.draw_pass_1 = dm
	guide.add_child(ps)
	guide.visible = false


## Point the guide at p (null hides it).
func set_guide(p) -> void:
	_guide_target = p
	if p == null:
		guide.visible = false
		return
	var q: Vector3 = p + Vector3(0, 1.3, 0)
	if not guide.visible:
		guide.visible = true
		guide.global_position = q


# ---------------------------------------------------------------- decoration

func _build_island_features() -> void:
	# Trees behind the gate, a few columns on the gate isle.
	var c := island_center(gate_isle)
	for k in 5:
		var a := -PI / 2.0 + randf_range(-1.1, 1.1)
		make_tree(self, c + Vector3(cos(a) * randf_range(9.0, 13.0), 0, sin(a) * randf_range(9.0, 13.0)), randf_range(0.9, 1.3), true)


func _build_waterfalls() -> void:
	if not arena_isles.is_empty():
		_waterfall(int(arena_isles[0]), PI + 0.4)
		_waterfall(int(arena_isles[-1]), -0.4)
	_waterfall(gate_isle, -PI / 2.0 + 0.9)
	_waterfall(gate_isle, -PI / 2.0 - 0.9)


# ---------------------------------------------------------------- runtime

func _physics_process(delta: float) -> void:
	sim_t += delta
	for m in movers:
		var body: AnimatableBody3D = m["body"]
		body.global_position = mover_pos(m, sim_t)
	for i in rings.size():
		var n: Node3D = rings[i]["node"]
		n.global_position = ring_pos(i, sim_t)
	_tick_gusts(delta)


func _process(delta: float) -> void:
	super._process(delta)
	for w in weapon_spots:
		var n: Node3D = w["node"]
		n.rotation.y += delta * 1.6
		n.position.y = 1.35 + sin(_t * 2.2) * 0.12
	for b in barriers:
		var it: Node3D = b["item"]
		it.rotation.y += delta * 1.2
	for d in lamps:
		var r: Node3D = d["root"]
		r.position.y = float(d["pos"].y) + 0.75 + sin(_t * 1.8) * 0.08
		r.rotation.y += delta * 0.6
	if guide.visible and _guide_target != null:
		var q: Vector3 = _guide_target + Vector3(0, 1.3 + sin(_t * 3.0) * 0.15, 0)
		guide.global_position = guide.global_position.lerp(q, minf(1.0, delta * 5.0))
		_guide_light.light_energy = 1.3 + 0.5 * sin(_t * 4.0)
