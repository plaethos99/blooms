extends Node3D
## A Hollow: a moth-like shadow that eats light. It forms over 2 s, hunts the nearest
## exposed pilgrim for a while, then fades (unless night has fallen).

const Cfg = preload("res://scripts/cfg.gd")

const RIM_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 rim_col : source_color = vec3(0.55, 0.3, 1.0);
uniform float energy = 2.5;
void fragment() {
	float fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.2);
	ALBEDO = vec3(0.01, 0.0, 0.025);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = rim_col * fr * energy;
}
"""

const WING_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 rim_col : source_color = vec3(0.55, 0.3, 1.0);
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float e = length(uv * vec2(1.0, 1.7));
	float tatter = 0.46 + 0.04 * sin(UV.x * 40.0);
	if (e > tatter) {
		discard;
	}
	ALBEDO = vec3(0.01, 0.0, 0.02);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = rim_col * smoothstep(tatter - 0.1, tatter, e) * 2.5;
}
"""

enum { TELEGRAPH, HUNT, STAGGER, DYING }

static var _shaders := {}

var main
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

var body_root: Node3D
var wing_l: Node3D
var wing_r: Node3D
var eye_mat: StandardMaterial3D
var dark_light: OmniLight3D
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
	body_root.scale = Vector3.ONE * 0.01
	trail.emitting = false
	# Sound is the first warning: a swelling hiss, then a whisper that follows the hollow.
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
	t += delta
	life += delta
	var flap := sin(life * 9.0)
	wing_l.rotation.z = 0.55 + flap * 0.5
	wing_r.rotation.z = -0.55 - flap * 0.5
	lunge = maxf(0.0, lunge - delta * 4.0)
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
				tw.tween_property(body_root, "scale", Vector3.ONE * 1.3, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				var tw2 := create_tween().set_parallel(true)
				tw2.tween_property(swirl, "scale", Vector3.ONE * 2.2, 0.4)
				tw2.tween_property(swirl_mat, "albedo_color:a", 0.0, 0.4)
		HUNT:
			if not persistent:
				hunt_left -= delta
				if hunt_left <= 0.0:
					_fade(false)
					return
			target = main.nearest_target(global_position)
			var want := Vector3.ZERO
			if target != null:
				var to: Vector3 = target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.35:
					var spd: float = main.hollow_speed()
					want = to.normalized() * spd
			vel = vel.lerp(want, minf(1.0, delta * 3.0))
			_move(vel * delta, delta)
			_contact(delta)
		STAGGER:
			stagger_left -= delta
			knock = knock.lerp(Vector3.ZERO, minf(1.0, delta * 3.0))
			_move(knock * delta, delta)
			body_root.rotation.z = sin(life * 25.0) * 0.35 * clampf(stagger_left, 0.0, 1.0)
			if stagger_left <= 0.0:
				state = HUNT
				body_root.rotation.z = 0.0
				eye_mat.emission_energy_multiplier = 6.0


func _move(step: Vector3, delta: float) -> void:
	var p := global_position + step
	p = main.world.push_out_of_shrines(p, 0.7)
	var g: float = main.world.ground_at(p)
	if g < -20.0:
		g = global_position.y - 1.4
	var bob := sin(life * 2.2) * 0.15
	p.y = lerpf(global_position.y, g + 1.4 + bob, minf(1.0, delta * 4.0))
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
	if d < Cfg.HOLLOW_REACH and absf(tp.y - global_position.y) < 2.2:
		if not in_contact:
			in_contact = true
			bite_timer = 0.3
		bite_timer -= delta
		if bite_timer <= 0.0:
			bite_timer = Cfg.HOLLOW_BITE_INTERVAL
			lunge = 1.0
			var braced: bool = target.bracing and target.brace_ready
			if not braced:
				main.sfx.play("bite", null if target.is_player else tp, 0.0 if target.is_player else -3.0, randf_range(0.85, 1.15))
			target.receive_bite(self, randf_range(Cfg.HOLLOW_BITE.x, Cfg.HOLLOW_BITE.y) * main.bite_mult(target))
	else:
		in_contact = false


func hit(from_pos: Vector3, force: float) -> bool:
	if not is_active():
		return false
	hp -= 1
	main.fx_light(global_position, Color(0.85, 0.75, 1.0), 5.0, 6.0, 0.25)
	main.sfx.play("hit", global_position, 2.0, randf_range(0.9, 1.1))
	rim_mat.set_shader_parameter("energy", 14.0)
	create_tween().tween_method(func(v: float): rim_mat.set_shader_parameter("energy", v), 14.0, 2.5, 0.35)
	if hp <= 0:
		_fade(true)
		return true
	stagger(from_pos, force)
	return true


func stagger(from_pos: Vector3, force: float) -> void:
	if not is_active():
		return
	state = STAGGER
	stagger_left = Cfg.STAGGER_TIME
	var k := global_position - from_pos
	k.y = 0.0
	if k.length() < 0.01:
		k = Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0))
	knock = k.normalized() * force
	vel = Vector3.ZERO
	in_contact = false
	eye_mat.emission_energy_multiplier = 1.0


func _fade(killed: bool) -> void:
	if state == DYING:
		return
	state = DYING
	trail.emitting = false
	create_tween().tween_property(hum, "volume_db", -60.0, 0.5)
	if killed:
		main.on_hollow_killed(self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(body_root, "scale", Vector3.ONE * (1.6 if killed else 0.01), 0.18 if killed else 0.8)
	tw.tween_property(dark_light, "light_energy", 0.0, 0.6)
	tw.chain().tween_property(body_root, "scale", Vector3.ONE * 0.01, 0.2)
	tw.chain().tween_callback(queue_free)


func _build() -> void:
	body_root = Node3D.new()
	add_child(body_root)
	var rim := ShaderMaterial.new()
	rim.shader = _get_shader("rim")
	rim_mat = rim
	var body := SphereMesh.new()
	body.radius = 0.34
	body.height = 0.95
	body.radial_segments = 16
	body.rings = 8
	var bmi := MeshInstance3D.new()
	bmi.mesh = body
	bmi.material_override = rim
	bmi.rotation.x = 0.35
	body_root.add_child(bmi)
	var head := SphereMesh.new()
	head.radius = 0.24
	head.height = 0.44
	var hmi := MeshInstance3D.new()
	hmi.mesh = head
	hmi.material_override = rim
	hmi.position = Vector3(0, 0.38, 0.14)
	body_root.add_child(hmi)
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.8, 1.0, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.7, 1.0, 1.0)
	eye_mat.emission_energy_multiplier = 6.0
	for sx in [-1.0, 1.0]:
		var e := SphereMesh.new()
		e.radius = 0.05
		e.height = 0.08
		var emi := MeshInstance3D.new()
		emi.mesh = e
		emi.material_override = eye_mat
		emi.position = Vector3(0.09 * float(sx), 0.42, 0.34)
		body_root.add_child(emi)
	var wing_mat := ShaderMaterial.new()
	wing_mat.shader = _get_shader("wing")
	wing_l = _wing(wing_mat, 1.0)
	wing_r = _wing(wing_mat, -1.0)

	dark_light = OmniLight3D.new()
	dark_light.light_negative = true
	dark_light.light_color = Color(0.8, 0.7, 1.0)
	dark_light.light_energy = 0.0
	dark_light.omni_range = 5.0
	add_child(dark_light)

	swirl_mat = StandardMaterial3D.new()
	swirl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	swirl_mat.albedo_color = Color(0.04, 0.0, 0.08, 0.0)
	swirl_mat.emission_enabled = true
	swirl_mat.emission = Color(0.45, 0.15, 0.8)
	swirl_mat.emission_energy_multiplier = 1.2
	var tm := TorusMesh.new()
	tm.inner_radius = 0.55
	tm.outer_radius = 1.0
	tm.rings = 32
	swirl = MeshInstance3D.new()
	swirl.mesh = tm
	swirl.material_override = swirl_mat
	swirl.position.y = -1.3
	swirl.scale = Vector3(1, 0.3, 1)
	add_child(swirl)

	trail = GPUParticles3D.new()
	trail.amount = 24
	trail.lifetime = 0.9
	trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, 0.6, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.3
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	trail.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	sm.radial_segments = 8
	sm.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.25, 0.08, 0.4)
	sm.material = mat
	trail.draw_pass_1 = sm
	add_child(trail)


func _wing(mat: Material, side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(0.12 * side, 0.12, -0.05)
	pivot.rotation.y = -0.4 * side
	body_root.add_child(pivot)
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.position = Vector3(0.8 * side, 0, 0)
	mi.rotation.x = -PI / 2.0
	pivot.add_child(mi)
	return pivot
