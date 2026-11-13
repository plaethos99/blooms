extends Node3D
## A Duskwing: a winged shadow that circles the arena, glows red, then dives at a
## pilgrim. Hit it as it comes (axe), or shoot it while it circles (crossbow, saw).

const Cfg = preload("res://scripts/cfg.gd")

var main
var hp: int = Cfg.FLYER_HP
var state := "enter" # enter, circle, aim, dive, recover, stagger, dying
var t := 0.0
var target = null
var vel := Vector3.ZERO
var home := Vector3.ZERO # middle of the arena
var orbit_r := 10.0
var orbit_a := 0.0
var orbit_spd := 0.5
var height := 6.0
var bitten := false
var _flap := 0.0
var _wings: Array = []
var _eye_mat: StandardMaterial3D
var _glow: OmniLight3D
var _body: Node3D
var _hit_flash := 0.0
var _body_mat: StandardMaterial3D


func setup(m, centre: Vector3, from: Vector3) -> void:
	main = m
	home = centre
	position = from
	orbit_r = randf_range(7.0, 15.0)
	orbit_a = atan2(from.z - centre.z, from.x - centre.x)
	orbit_spd = randf_range(0.45, 0.75) * (1.0 if randf() < 0.5 else -1.0)
	height = randf_range(3.6, 6.2)


func _ready() -> void:
	scale = Vector3.ONE * 1.45
	_body = Node3D.new()
	add_child(_body)
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.08, 0.05, 0.12)
	_body_mat.roughness = 0.6
	_body_mat.rim_enabled = true
	_body_mat.rim = 0.6
	_body_mat.rim_tint = 0.2
	_body_mat.emission_enabled = true
	_body_mat.emission = Color(0.35, 0.1, 0.5)
	_body_mat.emission_energy_multiplier = 0.9
	var cap := CapsuleMesh.new()
	cap.radius = 0.22
	cap.height = 0.95
	var torso := MeshInstance3D.new()
	torso.mesh = cap
	torso.material_override = _body_mat
	torso.rotation.x = PI / 2.0
	_body.add_child(torso)
	var hm := SphereMesh.new()
	hm.radius = 0.19
	hm.height = 0.34
	var head := MeshInstance3D.new()
	head.mesh = hm
	head.material_override = _body_mat
	head.position = Vector3(0, 0.06, -0.5)
	_body.add_child(head)
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1.0, 0.75, 0.3)
	var em := SphereMesh.new()
	em.radius = 0.045
	em.height = 0.09
	for s in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = em
		eye.material_override = _eye_mat
		eye.position = Vector3(0.08 * s, 0.1, -0.66)
		_body.add_child(eye)
	var tail := CylinderMesh.new()
	tail.top_radius = 0.0
	tail.bottom_radius = 0.12
	tail.height = 0.8
	var tm := MeshInstance3D.new()
	tm.mesh = tail
	tm.material_override = _body_mat
	tm.rotation.x = -PI / 2.0
	tm.position = Vector3(0, 0, 0.75)
	_body.add_child(tm)
	var wing_mat := StandardMaterial3D.new()
	wing_mat.albedo_color = Color(0.12, 0.06, 0.18, 0.92)
	wing_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wing_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wing_mat.emission_enabled = true
	wing_mat.emission = Color(0.55, 0.15, 0.6)
	wing_mat.emission_energy_multiplier = 0.5
	wing_mat.rim_enabled = true
	for s in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.15 * s, 0.05, -0.1)
		_body.add_child(pivot)
		var w := MeshInstance3D.new()
		w.mesh = _wing_mesh(s)
		w.material_override = wing_mat
		pivot.add_child(w)
		_wings.append([pivot, s])
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.2, 0.15)
	_glow.light_energy = 0.0
	_glow.omni_range = 5.0
	add_child(_glow)
	main.sfx.play("hollow_form", global_position, -4.0, 1.4)


## A bat-like wing: a fan of points along the leading edge, membrane scalloped behind.
func _wing_mesh(side: float) -> ArrayMesh:
	var pts := [Vector3(0, 0, -0.15), Vector3(0.55, 0.12, -0.35), Vector3(1.15, 0.05, -0.2),
		Vector3(1.25, -0.02, 0.15), Vector3(0.85, 0, 0.25), Vector3(0.45, 0, 0.35), Vector3(0, 0, 0.3)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var root := Vector3(0, 0, 0.05)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		a.x *= side
		b.x *= side
		st.add_vertex(root)
		st.add_vertex(a)
		st.add_vertex(b)
	st.generate_normals()
	return st.commit()


func is_active() -> bool:
	return state != "dying"


## Centre of the body, for aiming and hits.
func core() -> Vector3:
	return global_position


func _orbit_point() -> Vector3:
	return home + Vector3(cos(orbit_a) * orbit_r, height, sin(orbit_a) * orbit_r)


func _steer(to: Vector3, speed: float, delta: float, turn := 3.0) -> void:
	var want := (to - global_position)
	if want.length() > 0.01:
		want = want.normalized() * minf(speed, want.length() / maxf(delta, 0.001))
	vel = vel.lerp(want, minf(1.0, delta * turn))
	global_position += vel * delta


func _physics_process(delta: float) -> void:
	if main == null or main.state == "ended":
		return
	t -= delta
	_hit_flash = maxf(0.0, _hit_flash - delta * 4.0)
	match state:
		"enter":
			orbit_a += orbit_spd * delta
			_steer(_orbit_point(), Cfg.FLYER_SPEED * 1.3, delta)
			if global_position.distance_to(_orbit_point()) < 2.0:
				state = "circle"
				t = randf_range(1.0, 2.5)
		"circle":
			orbit_a += orbit_spd * delta
			_steer(_orbit_point(), Cfg.FLYER_SPEED, delta)
			if t <= 0.0 and main.state == "playing":
				target = main.flyer_pick_target(self)
				if target != null:
					state = "aim"
					t = Cfg.FLYER_AIM_TIME
					main.sfx.play("screech", global_position, -3.0, randf_range(1.2, 1.45))
				else:
					t = 1.0
		"aim":
			# Hover and glow red: the warning before the dive.
			vel = vel.lerp(Vector3.ZERO, minf(1.0, delta * 4.0))
			global_position += vel * delta
			if not _valid(target):
				_recover()
			elif t <= 0.0:
				var aim: Vector3 = target.global_position + Vector3(0, 1.0, 0) + target.velocity * 0.2
				vel = (aim - global_position).normalized() * Cfg.FLYER_DIVE_SPEED
				state = "dive"
				bitten = false
				t = 1.6
		"dive":
			global_position += vel * delta
			if not bitten:
				for s in main.survivors:
					if not s.alive or s.escaped or s.invuln > 0.0:
						continue
					if (s.global_position + Vector3(0, 1.0, 0)).distance_to(global_position) < 1.05:
						_bite(s)
						break
			if bitten or t <= 0.0 or global_position.y < home.y - 3.0:
				_recover()
		"recover":
			_steer(_orbit_point() + Vector3(0, 1.0, 0), Cfg.FLYER_SPEED, delta, 2.0)
			orbit_a += orbit_spd * delta * 0.5
			if t <= 0.0:
				state = "circle"
				t = randf_range(1.6, 3.6)
		"stagger":
			vel = vel.lerp(Vector3.ZERO, minf(1.0, delta * 3.0))
			global_position += vel * delta
			if t <= 0.0:
				_recover()
		"dying":
			vel.y -= 14.0 * delta
			global_position += vel * delta
			_body.rotation.z += delta * 9.0
			scale = scale.lerp(Vector3.ONE * 0.05, minf(1.0, delta * 1.5))
			if t <= 0.0:
				queue_free()
	_animate(delta)


func _valid(s) -> bool:
	return s != null and is_instance_valid(s) and s.alive and not s.escaped and main.world.in_arena(s.global_position)


func _recover() -> void:
	state = "recover"
	t = 1.2
	target = null


func _bite(s) -> void:
	bitten = true
	# An axe swung just before it reaches you cuts it down instead.
	if s.weapon == "axe" and s.attack_cd > Cfg.AXE_COOLDOWN - 0.35:
		hit(Cfg.AXE_DAMAGE, s.global_position + Vector3(0, 1.3, 0), s)
		return
	var dir: Vector3 = vel
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, 1)
	s.shoved(dir * Cfg.FLYER_KNOCK + Vector3(0, 3.0, 0))
	s.lose_light(Cfg.FLYER_BITE)
	main.sfx.play("bite", null if s.is_player else s.global_position, 0.0, randf_range(0.9, 1.1))
	main.fx_burst(s.global_position + Vector3(0, 1.2, 0), Color(0.75, 0.2, 0.9), 22, false, 4.0)
	if s.is_player:
		s.shake = maxf(s.shake, 0.4)


## Struck by a weapon. Returns true if that killed it.
func hit(dmg: int, from: Vector3, by) -> bool:
	if state == "dying":
		return false
	hp -= dmg
	_hit_flash = 1.0
	var away := global_position - from
	away = away.normalized() if away.length() > 0.01 else Vector3.UP
	if hp <= 0:
		state = "dying"
		t = 1.1
		vel = away * 5.0 + Vector3(0, 2.0, 0)
		main.on_flyer_killed(self, by)
		return true
	state = "stagger"
	t = 0.45
	vel = away * 9.0
	main.sfx.play("hit", global_position, 0.0, randf_range(1.2, 1.4))
	main.fx_burst(global_position, Color(0.8, 0.4, 1.0), 14, false, 3.0)
	return false


func _animate(delta: float) -> void:
	var speed := 9.0 if state == "dive" else (16.0 if state == "aim" else 7.0)
	_flap += delta * speed
	var fold := 0.75 if state == "dive" else 0.0
	for w in _wings:
		var pv: Node3D = w[0]
		var s: float = w[1]
		pv.rotation.z = s * (sin(_flap) * 0.65 - 0.1 + fold)
	# Face where it is going (or its prey while aiming).
	var look := vel
	if state == "aim" and _valid(target):
		look = target.global_position + Vector3(0, 1.0, 0) - global_position
	if look.length() > 0.2 and absf(look.normalized().y) < 0.97:
		var b := Basis.looking_at(look.normalized(), Vector3.UP)
		_body.basis = _body.basis.slerp(b, minf(1.0, delta * 8.0)).orthonormalized()
	var red := 1.0 if state == "aim" else (0.6 if state == "dive" else 0.0)
	_glow.light_energy = lerpf(_glow.light_energy, red * 3.5, minf(1.0, delta * 10.0))
	_eye_mat.albedo_color = Color(1.0, 0.75, 0.3).lerp(Color(1.0, 0.1, 0.05), red)
	_body_mat.emission = Color(0.35, 0.1, 0.5).lerp(Color(1.0, 1.0, 1.0), _hit_flash)
	_body_mat.emission_energy_multiplier = 0.9 + _hit_flash * 3.0 + red * 0.8
