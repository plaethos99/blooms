extends Node3D
## Knife pendulums: crescent blades that swing across the gaps between stepping stones.
## Each hangs from a small floating rock; time your jump for when the blade is off to
## one side. A hit costs a little light and throws you sideways, often into the Underglow.

const Cfg = preload("res://scripts/cfg.gd")

const ARC_R := 0.72 # crescent: radius of the cutting edge
const ARC_CY := 0.38 # crescent: height of that circle's centre above the blade origin
const ARC_FROM := -2.70526 # -155 degrees
const ARC_TO := -0.436332 # -25 degrees
const INNER_Y := 0.12 # the back of the blade pulls towards this height

var main
var blades: Array = [] # Dictionary per blade, see _add_blade
var _t := 0.0 # simulation clock (physics)
var _vt := 0.0 # visual clock
var _steel: StandardMaterial3D
var _iron: StandardMaterial3D
var _rune: StandardMaterial3D
var _blade_mesh: ArrayMesh
var _fire_steel: StandardMaterial3D
var _flame_mat: StandardMaterial3D
var _samples: Array[Vector2] = [] # points along the blade (blade-local) used for hits


func build(world) -> void:
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.78, 0.8, 0.84)
	_steel.metallic = 0.9
	_steel.roughness = 0.22
	_steel.emission_enabled = true
	_steel.emission = Color(1.0, 0.35, 0.25)
	_steel.emission_energy_multiplier = 0.18
	_steel.cull_mode = BaseMaterial3D.CULL_DISABLED
	_iron = StandardMaterial3D.new()
	_iron.albedo_color = Color(0.13, 0.12, 0.11)
	_iron.metallic = 0.6
	_iron.roughness = 0.5
	_rune = StandardMaterial3D.new()
	_rune.albedo_color = Color(1.0, 0.3, 0.15)
	_rune.emission_enabled = true
	_rune.emission = Color(1.0, 0.3, 0.15)
	_rune.emission_energy_multiplier = 1.6
	_blade_mesh = _make_blade_mesh()
	# Level 1's blades are on fire: a glowing edge and a trail of flame.
	_fire_steel = _steel.duplicate()
	_fire_steel.albedo_color = Color(0.55, 0.42, 0.36)
	_fire_steel.emission = Color(1.0, 0.42, 0.12)
	_fire_steel.emission_energy_multiplier = 2.2
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.vertex_color_use_as_albedo = true
	_flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	for k in 9:
		var x := lerpf(-0.62, 0.62, float(k) / 8.0)
		var oy := ARC_CY - sqrt(maxf(0.0, ARC_R * ARC_R - x * x))
		var iy := oy + 0.6 * (INNER_Y - oy)
		_samples.append(Vector2(x, (oy + iy) * 0.5) * Cfg.BLADE_SIZE)
	for bi in world.bridges.size():
		var b: Dictionary = world.bridges[bi]
		var stones: Array = b["stones"]
		var radii: Array = b["radii"]
		# The world widened a few random gaps between stones for us; hang a blade in each.
		# Level 1 gives every gap its own swing (the same in every lane, so racing is fair).
		var sw: Dictionary = b.get("blade_swing", {})
		for g in b.get("blade_gaps", []):
			var k: int = int(g) - 1
			if k < 0 or k + 1 >= stones.size():
				continue
			var s0: Vector3 = stones[k]
			var s1: Vector3 = stones[k + 1]
			# Middle of the open air between the two stone rims.
			var d := Vector3(s1.x - s0.x, 0, s1.z - s0.z)
			var dl := d.length()
			var dir := d / dl
			var r0: float = radii[k]
			var r1: float = radii[k + 1]
			var mid := s0 + dir * (r0 + (dl - r0 - r1) * 0.5)
			mid.y = maxf(s0.y, s1.y)
			var per := randf_range(Cfg.BLADE_PERIOD.x, Cfg.BLADE_PERIOD.y)
			var ph := randf() * TAU
			if sw.has(g):
				per = float(sw[g][0])
				ph = float(sw[g][1])
			_add_blade(bi, mid, dir, world, per, ph, bool(b.get("fire", false)))
	# Free-hanging blades (Level 1's rope chasm): [mid, dir, period, phase].
	var extra = world.get("extra_blades")
	if extra != null:
		for eb in extra:
			_add_blade(-1, eb[0], eb[1], world, float(eb[2]), float(eb[3]), true)
	if main != null and main.args.has("log"):
		print("BLADES built %d" % blades.size())


## A blade over `mid` (top of the higher stone), swinging across the path `dir`.
func _add_blade(bi: int, mid: Vector3, dir: Vector3, world, period: float, phase: float, fire := false) -> void:
	var perp := Vector3(-dir.z, 0, dir.x)
	var arm: float = Cfg.BLADE_ARM
	# The blade's middle sweeps through where a jumping pilgrim's body is.
	var pivot_pos := mid + Vector3(0, Cfg.BLADE_HEIGHT + arm - _samples[4].y, 0)
	var base := Basis(perp, Vector3.UP, -dir)
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.position = pivot_pos
	pivot.basis = base
	# Hung from a small floating rock with an iron axle and a warning rune.
	world._model("res://models/rock_%d.glb" % (randi() % 3), self, pivot_pos + Vector3(0, 0.55, 0),
		Vector3(randf() * 0.4, randf() * TAU, randf() * 0.4), Vector3(0.55, 0.4, 0.55))
	var axle := CylinderMesh.new()
	axle.top_radius = 0.07
	axle.bottom_radius = 0.07
	axle.height = 0.7
	_mesh(self, axle, _iron, pivot_pos, _axis_basis(dir))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.24
	_mesh(self, ring, _rune, pivot_pos, _axis_basis(dir))
	# The arm and blade swing with the pivot.
	var rod := CylinderMesh.new()
	rod.top_radius = 0.035
	rod.bottom_radius = 0.035
	rod.height = arm
	rod.radial_segments = 6
	_mesh(pivot, rod, _iron, Vector3(0, -arm * 0.5, 0), Basis())
	var collar := CylinderMesh.new()
	collar.top_radius = 0.07
	collar.bottom_radius = 0.09
	collar.height = 0.18
	_mesh(pivot, collar, _iron, Vector3(0, -arm + 0.12, 0), Basis())
	var blade := MeshInstance3D.new()
	blade.mesh = _blade_mesh
	blade.material_override = _fire_steel if fire else _steel
	blade.position = Vector3(0, -arm, 0)
	blade.scale = Vector3.ONE * Cfg.BLADE_SIZE
	pivot.add_child(blade)
	if fire:
		_add_flames(pivot, arm)
	blades.append({
		"bridge": bi, "pivot": pivot, "pos": pivot_pos, "base": base, "perp": perp, "dir": dir,
		"mid": mid, "w": TAU / period, "phase": phase, "last_s": 0.0, "fire": fire,
	})


## Flames streaming off a blade's edge (world-space particles, so they trail the swing).
func _add_flames(pivot: Node3D, arm: float) -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 70
	ps.lifetime = 0.55
	ps.local_coords = false
	ps.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.75 * Cfg.BLADE_SIZE, 0.12, 0.05)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, 2.5, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(3.0, 2.2, 0.8, 1.0), Color(2.6, 0.9, 0.2, 0.8), Color(0.6, 0.1, 0.05, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	ps.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.28, 0.28)
	q.material = _flame_mat
	ps.draw_pass_1 = q
	ps.position = Vector3(0, -arm - 0.1 * Cfg.BLADE_SIZE, 0)
	pivot.add_child(ps)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.2)
	l.light_energy = 1.4
	l.omni_range = 4.5
	l.position = Vector3(0, -arm, 0)
	pivot.add_child(l)


func _axis_basis(dir: Vector3) -> Basis:
	# Cylinders and tori are built around Y; turn that to lie along the bridge.
	var y := dir
	var x := Vector3.UP.cross(y).normalized()
	return Basis(x, y, x.cross(y))


func _mesh(parent: Node, m: Mesh, mat: Material, pos: Vector3, b: Basis) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	mi.transform = Transform3D(b, pos)
	return mi


## A crescent axe head in the XY plane: sharp along the bottom arc, thick along the back.
func _make_blade_mesh() -> ArrayMesh:
	var n := 14
	var outer: Array = []
	var inner: Array = []
	for i in n + 1:
		var a := lerpf(ARC_FROM, ARC_TO, float(i) / float(n))
		var o := Vector2(cos(a) * ARC_R, ARC_CY + sin(a) * ARC_R)
		outer.append(o)
		inner.append(Vector2(o.x, o.y + 0.6 * (INNER_Y - o.y)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge_z := 0.004
	var back_z := 0.035
	for side in [1.0, -1.0]:
		for i in n:
			var o0 := Vector3(outer[i].x, outer[i].y, edge_z * side)
			var o1 := Vector3(outer[i + 1].x, outer[i + 1].y, edge_z * side)
			var i0 := Vector3(inner[i].x, inner[i].y, back_z * side)
			var i1 := Vector3(inner[i + 1].x, inner[i + 1].y, back_z * side)
			if side > 0.0:
				_tri(st, o0, i0, o1)
				_tri(st, o1, i0, i1)
			else:
				_tri(st, o0, o1, i0)
				_tri(st, o1, i1, i0)
	# The flat back of the blade, joining both faces.
	for i in n:
		var a0 := Vector3(inner[i].x, inner[i].y, back_z)
		var a1 := Vector3(inner[i + 1].x, inner[i + 1].y, back_z)
		var b0 := Vector3(inner[i].x, inner[i].y, -back_z)
		var b1 := Vector3(inner[i + 1].x, inner[i + 1].y, -back_z)
		_tri(st, a0, b0, a1)
		_tri(st, a1, b0, b1)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _angle(bl: Dictionary, t: float) -> float:
	return deg_to_rad(Cfg.BLADE_ARC) * sin(t * float(bl["w"]) + float(bl["phase"]))


func _swing_basis(bl: Dictionary, t: float) -> Basis:
	return Basis(bl["base"]) * Basis(Vector3(0, 0, 1), _angle(bl, t))


## World positions of the blade's hit points at time t.
func _points(bl: Dictionary, t: float) -> Array:
	var b := _swing_basis(bl, t)
	var p: Vector3 = bl["pos"]
	var out: Array = []
	for s in _samples:
		out.append(p + b * Vector3(s.x, s.y - Cfg.BLADE_ARM, 0.0))
	return out


## Does blade point q touch a pilgrim with feet at f? Generous in height, so a blade
## that visibly passes through someone always counts, standing or mid-jump.
static func _touches(q: Vector3, f: Vector3) -> bool:
	if q.y < f.y - 0.45 or q.y > f.y + 2.1:
		return false
	return Vector2(q.x - f.x, q.z - f.z).length() < Cfg.BLADE_HIT_RADIUS


func _process(delta: float) -> void:
	_vt += delta
	for bl in blades:
		var pv: Node3D = bl["pivot"]
		pv.basis = _swing_basis(bl, _vt)


func _physics_process(delta: float) -> void:
	_t += delta
	if main == null:
		return
	var playing: bool = main.state == "playing"
	var now := Time.get_ticks_msec()
	var player = main.player
	for bl in blades:
		var s := sin(_angle(bl, _t))
		var crossed := float(bl["last_s"]) != 0.0 and signf(s) != signf(float(bl["last_s"]))
		bl["last_s"] = s
		var pos: Vector3 = bl["pos"]
		# A whoosh as the blade sweeps through the bottom near you.
		if crossed and player != null and is_instance_valid(player):
			var d: float = player.global_position.distance_to(bl["mid"])
			if d < 11.0:
				main.sfx.play("swish", bl["mid"] + Vector3(0, 1.0, 0), -4.0, randf_range(0.75, 0.95))
			if playing and d < 9.0 and player.alive and not player.escaped:
				main.hud.tip("blades", "TIP: Knife pendulums swing between the stones. Wait for the blade to pass, then jump!")
		if not playing:
			continue
		var pts: Array = []
		for sv in main.survivors:
			if not sv.alive or sv.escaped or sv.fell:
				continue
			var f: Vector3 = sv.global_position
			if Vector2(f.x - pos.x, f.z - pos.z).length() > Cfg.BLADE_ARM + 1.5:
				continue
			if now - int(sv.last_blade_ms) < int(Cfg.BLADE_HIT_COOLDOWN * 1000.0):
				continue
			if pts.is_empty():
				pts = _points(bl, _t)
			var hit := false
			for q in pts:
				if _touches(q, f):
					hit = true
					break
			if hit:
				_hit(bl, sv, now)


func _hit(bl: Dictionary, sv, now: int) -> void:
	sv.last_blade_ms = now
	if main.args.has("log"):
		print("BLADE hit %s bridge=%d t=%d" % [sv.display_name, int(bl["bridge"]), int(main.time_left)])
	# Thrown the way the blade is moving.
	var vel := cos(_t * float(bl["w"]) + float(bl["phase"]))
	var side: Vector3 = bl["perp"] * (1.0 if vel >= 0.0 else -1.0)
	var k: float = Cfg.BLADE_KNOCK * (0.4 if sv.bracing and sv.brace_ready else 1.0)
	sv.shoved(side * k + Vector3(0, Cfg.BLADE_LIFT, 0))
	var fire: bool = bl.get("fire", false)
	sv.lose_light(Cfg.COURSE_BLADE_DAMAGE if fire else Cfg.BLADE_DAMAGE)
	var p: Vector3 = sv.global_position + Vector3(0, 1.0, 0)
	main.fx_burst(p, Color(1.0, 0.55, 0.15) if fire else Color(1.0, 0.45, 0.3), 26 if fire else 18, false, 4.0)
	main.sfx.play("hit", null if sv.is_player else p, 0.0, randf_range(1.1, 1.3))
	if sv.is_player:
		sv.shake = maxf(sv.shake, 0.45)
		if not main.is_course:
			main.hud.toast("A swinging blade caught you!")


## Bots: is it safe to jump from `from` to `to` (taking t_air seconds) right now?
func path_clear(from: Vector3, to: Vector3, t_air: float, margin: float) -> bool:
	var a2 := Vector2(from.x, from.z)
	var b2 := Vector2(to.x, to.z)
	var ab := b2 - a2
	for bl in blades:
		var m: Vector3 = bl["mid"]
		var m2 := Vector2(m.x, m.z)
		var u := clampf((m2 - a2).dot(ab) / maxf(0.001, ab.length_squared()), 0.0, 1.0)
		if (a2 + ab * u).distance_to(m2) > 1.5:
			continue
		# Walk the jump forward in time and see if the blade is there when we are.
		var t := 0.0
		while t <= t_air + 0.15:
			var k := clampf(t / maxf(0.01, t_air), 0.0, 1.0)
			var me := Vector2(from.x, from.z).lerp(b2, k)
			for q in _points(bl, _t + t):
				if Vector2(q.x, q.z).distance_to(me) < Cfg.BLADE_HIT_RADIUS + margin:
					return false
			t += 0.05
	return true
