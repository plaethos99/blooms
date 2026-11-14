extends Node3D
## A Hollow: a winged shadow-wraith with a crown of horns, six burning eyes and a jaw
## that splits open. It forms over 2 s, screeches when it picks a victim, then hunts:
## it closes in, winds up and lunges. Its bite drains light and knocks you back, which
## out on the stepping stones can mean a fall into the Underglow.

const Cfg = preload("res://scripts/cfg.gd")

const RIM_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 rim_col : source_color = vec3(0.75, 0.04, 0.18);
uniform float energy = 1.3;
void fragment() {
	float fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.008, 0.0, 0.012);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = rim_col * fr * energy;
}
"""

const WING_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 rim_col : source_color = vec3(0.8, 0.06, 0.2);
float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float e = length(uv * vec2(1.0, 1.6));
	// Ragged, torn membrane: scalloped edge plus holes.
	float tatter = 0.44 + 0.05 * sin(UV.x * 34.0) + 0.03 * sin(UV.x * 71.0 + 1.3);
	float holes = step(0.93, h(floor(UV * 14.0))) * step(0.15, e);
	if (e > tatter || holes > 0.5) {
		discard;
	}
	float veins = smoothstep(0.92, 1.0, sin(atan(uv.y, uv.x) * 9.0) * 0.5 + 0.5);
	ALBEDO = vec3(0.012, 0.0, 0.02);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = rim_col * (smoothstep(tatter - 0.07, tatter, e) * 2.0 + veins * 0.5);
}
"""

enum { TELEGRAPH, HUNT, STAGGER, DYING }

static var _shaders := {}

var main
var warm := false # an inert copy shown once on the title screen, so its shaders compile there
var state := TELEGRAPH
var t := 0.0
var life := 0.0
var hunt_left: float = Cfg.HOLLOW_HUNT_TIME
var hp: int = Cfg.HOLLOW_HITS
var persistent := false
var stagger_left := 0.0
var knock := Vector3.ZERO
var vel := Vector3.ZERO
var bite_timer := 0.3
var in_contact := false
var target = null
var lunge := 0.0
var lunge_state := 0 # 0 none, 1 winding up, 2 dashing
var lunge_t := 0.0
var lunge_cd := 1.5
var lunge_dir := Vector3.ZERO
var screeched := false

var body_root: Node3D
var wing_l: Node3D
var wing_r: Node3D
var jaw: Node3D
var tendrils: Array = []
var eye_mat: StandardMaterial3D
var maw_mat: StandardMaterial3D
var dark_light: OmniLight3D
var eye_light: OmniLight3D
var swirl: MeshInstance3D
var swirl_mat: StandardMaterial3D
var trail: GPUParticles3D
var rim_mat: ShaderMaterial
var hum: AudioStreamPlayer3D


static func _get_shader(key: String) -> Shader:
	if not _shaders.has(key):
		var s := Shader.new()
		s.code = RIM_SHADER if key == "rim" else WING_SHADER
		_shaders[key] = s
	return _shaders[key]


func _ready() -> void:
	_build()
	if warm:
		trail.emitting = true
		return
	body_root.scale = Vector3.ONE * 0.01
	trail.emitting = false
	main.sfx.play("hollow_form", global_position - Vector3(0, 1.0, 0), 2.0, randf_range(0.9, 1.1))
	hum = AudioStreamPlayer3D.new()
	hum.bus = "SFX"
	hum.unit_size = 4.0
	hum.max_distance = 32.0
	hum.volume_db = -30.0
	hum.pitch_scale = randf_range(0.85, 1.15)
	add_child(hum)
	main.sfx.attach_loop(hum, "hollow_loop")
	create_tween().tween_property(hum, "volume_db", -4.0, Cfg.HOLLOW_TELEGRAPH)


func is_active() -> bool:
	return state == HUNT or state == STAGGER


func _physics_process(delta: float) -> void:
	if warm:
		return
	t += delta
	life += delta
	var flap_speed := 14.0 if lunge_state == 2 else 8.0
	var flap := sin(life * flap_speed)
	wing_l.rotation.z = 0.35 + flap * 0.45
	wing_r.rotation.z = -0.35 - flap * 0.45
	for i in tendrils.size():
		var td: Node3D = tendrils[i]
		td.rotation.x = 0.25 + sin(life * 3.0 + i * 1.3) * 0.35 - vel.length() * 0.06
		td.rotation.z = sin(life * 2.3 + i * 2.1) * 0.25
	lunge = maxf(0.0, lunge - delta * 4.0)
	var open := clampf(lunge + (0.6 if lunge_state > 0 else 0.0), 0.0, 1.0)
	jaw.rotation.x = 0.1 + open * 0.75
	maw_mat.emission_energy_multiplier = 1.0 + open * 6.0
	body_root.position.z = lunge * 0.35
	match state:
		TELEGRAPH:
			var k := clampf(t / Cfg.HOLLOW_TELEGRAPH, 0.0, 1.0)
			swirl.rotation.y += delta * (2.0 + k * 6.0)
			swirl.scale = Vector3.ONE * (0.3 + 1.1 * k)
			swirl_mat.albedo_color.a = 0.85 * k
			dark_light.light_energy = 2.0 * k
			if t >= Cfg.HOLLOW_TELEGRAPH:
				state = HUNT
				t = 0.0
				trail.emitting = true
				var tw := create_tween()
				tw.tween_property(body_root, "scale", Vector3.ONE * 1.45, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				var tw2 := create_tween().set_parallel(true)
				tw2.tween_property(swirl, "scale", Vector3.ONE * 2.2, 0.4)
				tw2.tween_property(swirl_mat, "albedo_color:a", 0.0, 0.4)
		HUNT:
			if not persistent and lunge_state == 0:
				hunt_left -= delta
				if hunt_left <= 0.0:
					_fade(false)
					return
			if lunge_state == 0:
				target = main.nearest_target(global_position)
			_hunt(delta)
			_contact(delta)
		STAGGER:
			stagger_left -= delta
			knock = knock.lerp(Vector3.ZERO, minf(1.0, delta * 3.0))
			_move(knock * delta, delta)
			body_root.rotation.z = sin(life * 25.0) * 0.35 * clampf(stagger_left, 0.0, 1.0)
			if stagger_left <= 0.0:
				state = HUNT
				body_root.rotation.z = 0.0
				eye_mat.emission_energy_multiplier = 7.0


func _hunt(delta: float) -> void:
	lunge_cd = maxf(0.0, lunge_cd - delta)
	if target == null:
		vel = vel.lerp(Vector3.ZERO, minf(1.0, delta * 3.0))
		_move(vel * delta, delta)
		return
	var to: Vector3 = target.global_position - global_position
	to.y = 0.0
	var dist := to.length()
	if not screeched and dist < 13.0:
		screeched = true
		main.sfx.play("screech", global_position, 3.0, randf_range(0.85, 1.15))
		if target.is_player:
			target.shake = maxf(target.shake, 0.2)
	match lunge_state:
		0:
			var want := Vector3.ZERO
			if dist > 0.35:
				want = to.normalized() * main.hollow_speed()
			vel = vel.lerp(want, minf(1.0, delta * 3.0))
			if lunge_cd <= 0.0 and dist < Cfg.LUNGE_RANGE and dist > 1.4:
				lunge_state = 1
				lunge_t = Cfg.LUNGE_WINDUP
				eye_mat.emission_energy_multiplier = 18.0
				eye_light.light_energy = 3.0
				main.sfx.play("hiss", global_position, 0.0, randf_range(0.9, 1.2))
		1:
			# Rear back, eyes blazing: the tell for the lunge.
			vel = vel.lerp(-to.normalized() * 1.2, minf(1.0, delta * 6.0))
			lunge_t -= delta
			if lunge_t <= 0.0:
				lunge_state = 2
				lunge_t = Cfg.LUNGE_TIME
				lunge_dir = to.normalized() if dist > 0.01 else Vector3.FORWARD
				vel = lunge_dir * Cfg.LUNGE_SPEED
		2:
			lunge_t -= delta
			if lunge_t <= 0.0:
				lunge_state = 0
				lunge_cd = Cfg.LUNGE_COOLDOWN
				eye_mat.emission_energy_multiplier = 7.0
				eye_light.light_energy = 0.6
	_move(vel * delta, delta)


func _move(step: Vector3, delta: float) -> void:
	var p := global_position + step
	p = main.world.push_out_of_shrines(p, 0.7)
	var g: float = main.world.ground_at(p)
	if g < -20.0:
		g = global_position.y - 1.6
	var bob := sin(life * 2.2) * 0.15
	p.y = lerpf(global_position.y, g + 1.6 + bob, minf(1.0, delta * 4.0))
	global_position = p
	var flat := Vector3(vel.x, 0, vel.z)
	if flat.length() > 0.3:
		rotation.y = lerp_angle(rotation.y, atan2(flat.x, flat.z), minf(1.0, delta * 6.0))


func _contact(delta: float) -> void:
	if target == null:
		in_contact = false
		return
	var tp: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var d := Vector2(tp.x - global_position.x, tp.z - global_position.z).length()
	if d < Cfg.HOLLOW_REACH and absf(tp.y - global_position.y) < 2.4:
		if not in_contact:
			in_contact = true
			bite_timer = 0.3
		bite_timer -= delta
		if lunge_state == 2 or bite_timer <= 0.0:
			var lunging := lunge_state == 2
			bite_timer = Cfg.HOLLOW_BITE_INTERVAL
			lunge = 1.0
			if lunging:
				lunge_state = 0
				lunge_cd = Cfg.LUNGE_COOLDOWN
				eye_mat.emission_energy_multiplier = 7.0
				eye_light.light_energy = 0.6
				vel = -vel * 0.3
			var braced: bool = target.bracing and target.brace_ready
			if not braced:
				main.sfx.play("bite", null if target.is_player else tp, 0.0 if target.is_player else -3.0, randf_range(0.85, 1.15))
				var away: Vector3 = target.global_position - global_position
				away.y = 0.0
				away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
				var force: float = Cfg.LUNGE_KNOCK if lunging else Cfg.BITE_KNOCK
				target.shoved(away * force * main.bite_mult(target) + Vector3(0, 2.0 if lunging else 0.5, 0))
			var dmg: float = randf_range(Cfg.HOLLOW_BITE.x, Cfg.HOLLOW_BITE.y) * (1.4 if lunging else 1.0)
			target.receive_bite(self, dmg * main.bite_mult(target))
	else:
		in_contact = false


func hit(from_pos: Vector3, force: float) -> bool:
	if not is_active():
		return false
	hp -= 1
	main.fx_light(global_position, Color(1.0, 0.6, 0.7), 5.0, 6.0, 0.25)
	main.sfx.play("hit", global_position, 2.0, randf_range(0.9, 1.1))
	rim_mat.set_shader_parameter("energy", 14.0)
	create_tween().tween_method(func(v: float): rim_mat.set_shader_parameter("energy", v), 14.0, 1.3, 0.35)
	if hp <= 0:
		_fade(true)
		return true
	stagger(from_pos, force)
	return true


func stagger(from_pos: Vector3, force: float) -> void:
	if not is_active():
		return
	state = STAGGER
	lunge_state = 0
	lunge_cd = maxf(lunge_cd, 1.0)
	stagger_left = Cfg.STAGGER_TIME
	var k := global_position - from_pos
	k.y = 0.0
	if k.length() < 0.01:
		k = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	knock = k.normalized() * force
	vel = Vector3.ZERO
	in_contact = false
	eye_mat.emission_energy_multiplier = 1.0
	eye_light.light_energy = 0.1


func _fade(killed: bool) -> void:
	if state == DYING:
		return
	state = DYING
	trail.emitting = false
	create_tween().tween_property(hum, "volume_db", -60.0, 0.5)
	if killed:
		main.on_hollow_killed(self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body_root, "scale", Vector3.ONE * (1.9 if killed else 0.01), 0.18 if killed else 0.8)
	tw.tween_property(dark_light, "light_energy", 0.0, 0.6)
	tw.tween_property(eye_light, "light_energy", 0.0, 0.4)
	tw.chain().tween_property(body_root, "scale", Vector3.ONE * 0.01, 0.2)
	tw.chain().tween_callback(queue_free)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _build() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	var rim := ShaderMaterial.new()
	rim.shader = _get_shader("rim")
	rim_mat = rim
	# Hunched, ribbed torso.
	var body := SphereMesh.new()
	body.radius = 0.32
	body.height = 1.1
	body.radial_segments = 14
	body.rings = 8
	_part(body_root, body, rim, Vector3(0, 0, -0.05), Vector3(0.55, 0, 0))
	var rib := TorusMesh.new()
	rib.inner_radius = 0.26
	rib.outer_radius = 0.31
	rib.rings = 16
	rib.ring_segments = 4
	for k in 3:
		_part(body_root, rib, rim, Vector3(0, 0.12 - k * 0.2, -0.02 - k * 0.08), Vector3(0.55 + PI / 2.0, 0, 0), Vector3(1.0 - k * 0.12, 1, 1.0 - k * 0.12))
	# Long skull.
	var skull := SphereMesh.new()
	skull.radius = 0.22
	skull.height = 0.5
	skull.radial_segments = 14
	skull.rings = 7
	var head := Node3D.new()
	head.position = Vector3(0, 0.45, 0.22)
	body_root.add_child(head)
	_part(head, skull, rim, Vector3.ZERO, Vector3(1.2, 0, 0), Vector3(1.0, 1.0, 1.25))
	# Crown of horns sweeping back.
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.05
	horn.height = 0.55
	horn.radial_segments = 5
	horn.rings = 1
	for k in 5:
		var a := (float(k) - 2.0) * 0.38
		_part(head, horn, rim, Vector3(sin(a) * 0.15, 0.17, -0.08 + absf(a) * 0.05), Vector3(-0.9, 0, -a * 0.8))
	# Six burning eyes in two rows.
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.35, 0.2)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.25, 0.1)
	eye_mat.emission_energy_multiplier = 7.0
	var eye := SphereMesh.new()
	eye.radius = 0.035
	eye.height = 0.06
	eye.radial_segments = 6
	eye.rings = 3
	for row in [[0.06, 0.07, 1.0], [0.0, 0.12, 0.75], [-0.05, 0.05, 0.6]]:
		for sx in [-1.0, 1.0]:
			_part(head, eye, eye_mat, Vector3(float(row[1]) * float(sx), float(row[0]), 0.26), Vector3.ZERO, Vector3.ONE * float(row[2]))
	eye_light = OmniLight3D.new()
	eye_light.light_color = Color(1.0, 0.2, 0.1)
	eye_light.light_energy = 0.6
	eye_light.omni_range = 2.5
	eye_light.position = Vector3(0, 0.0, 0.4)
	head.add_child(eye_light)
	# A jaw that splits open, red inside, ringed with teeth.
	maw_mat = StandardMaterial3D.new()
	maw_mat.albedo_color = Color(0.3, 0.0, 0.02)
	maw_mat.emission_enabled = true
	maw_mat.emission = Color(1.0, 0.1, 0.12)
	maw_mat.emission_energy_multiplier = 1.0
	var maw := SphereMesh.new()
	maw.radius = 0.12
	maw.height = 0.12
	_part(head, maw, maw_mat, Vector3(0, -0.11, 0.2), Vector3.ZERO, Vector3(1.0, 0.5, 1.0))
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.1, 0.06)
	head.add_child(jaw)
	var jm := BoxMesh.new()
	jm.size = Vector3(0.24, 0.05, 0.32)
	_part(jaw, jm, rim, Vector3(0, -0.03, 0.15))
	var tooth := CylinderMesh.new()
	tooth.top_radius = 0.0
	tooth.bottom_radius = 0.018
	tooth.height = 0.09
	tooth.radial_segments = 4
	tooth.rings = 1
	var tooth_mat := StandardMaterial3D.new()
	tooth_mat.albedo_color = Color(0.9, 0.85, 0.8)
	tooth_mat.emission_enabled = true
	tooth_mat.emission = Color(0.6, 0.5, 0.5)
	tooth_mat.emission_energy_multiplier = 0.4
	for k in 6:
		var x := (float(k) - 2.5) * 0.04
		_part(jaw, tooth, tooth_mat, Vector3(x, 0.03, 0.29))
		_part(head, tooth, tooth_mat, Vector3(x, -0.1, 0.33), Vector3(PI, 0, 0))
	# Clawed arms and trailing tendrils.
	var limb := CylinderMesh.new()
	limb.top_radius = 0.04
	limb.bottom_radius = 0.005
	limb.height = 1.0
	limb.radial_segments = 5
	limb.rings = 1
	for k in 6:
		var td := Node3D.new()
		var a := TAU * float(k) / 6.0
		td.position = Vector3(cos(a) * 0.14, -0.35, sin(a) * 0.1 - 0.05)
		body_root.add_child(td)
		var lng := randf_range(0.8, 1.4) if k > 1 else 0.7
		_part(td, limb, rim, Vector3(0, -0.5 * lng, 0), Vector3.ZERO, Vector3(1, lng, 1))
		tendrils.append(td)
	var wing_mat := ShaderMaterial.new()
	wing_mat.shader = _get_shader("wing")
	wing_l = _wing(wing_mat, 1.0)
	wing_r = _wing(wing_mat, -1.0)

	dark_light = OmniLight3D.new()
	dark_light.light_negative = true
	dark_light.light_color = Color(0.8, 0.7, 1.0)
	dark_light.light_energy = 0.0
	dark_light.omni_range = 5.5
	add_child(dark_light)

	swirl_mat = StandardMaterial3D.new()
	swirl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	swirl_mat.albedo_color = Color(0.06, 0.0, 0.03, 0.0)
	swirl_mat.emission_enabled = true
	swirl_mat.emission = Color(0.8, 0.1, 0.3)
	swirl_mat.emission_energy_multiplier = 1.3
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 1.0
	tm.rings = 32
	swirl = MeshInstance3D.new()
	swirl.mesh = tm
	swirl.material_override = swirl_mat
	swirl.position.y = -1.5
	swirl.scale = Vector3(1, 0.3, 1)
	add_child(swirl)

	trail = GPUParticles3D.new()
	trail.amount = 28
	trail.lifetime = 1.0
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, 0.6, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	trail.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.22, 0.03, 0.1)
	sm.material = mat
	trail.draw_pass_1 = sm
	add_child(trail)


func _wing(mat: Material, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.14 * side, 0.18, -0.12)
	pivot.rotation.y = -0.45 * side
	body_root.add_child(pivot)
	var q := QuadMesh.new()
	q.size = Vector2(2.3, 1.4)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = Vector3(1.1 * side, 0.25, -0.1)
	# Swept up and back so the wings read from the front and behind, not edge-on.
	mi.rotation.x = -0.55
	pivot.add_child(mi)
	return pivot
