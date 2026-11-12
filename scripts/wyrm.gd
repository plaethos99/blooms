extends Node3D
## The Devourer: a vast serpent that swims in the Underglow. Every so often it picks a
## bridge with pilgrims on it, the stones glow red and the abyss roars, and a moment
## later it bursts up through the gap in a great arc, sweeping anyone it touches off
## the stones.

const Cfg = preload("res://scripts/cfg.gd")
const SEGMENTS := 36
const SPACING := 1.75
const STRIKE_TIME := 1.9
const DIVE_TIME := 1.6

const SKIN_SHADER := """
shader_type spatial;
uniform float glow = 1.0;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
void fragment() {
	float fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float sc = smoothstep(0.35, 0.5, fract(lp.z * 5.0 + sin(lp.x * 9.0) * 0.25));
	vec3 base = mix(vec3(0.02, 0.012, 0.03), vec3(0.07, 0.03, 0.08), sc);
	float spots = smoothstep(0.7, 0.92, sin(lp.x * 9.0) * sin(lp.z * 7.0 + lp.y * 5.0));
	ALBEDO = base * 0.6;
	ROUGHNESS = 0.3;
	METALLIC = 0.6;
	float rimline = smoothstep(0.55, 0.9, fr);
	EMISSION = vec3(0.9, 0.05, 0.1) * rimline * 0.9 * glow + vec3(1.0, 0.35, 0.05) * spots * 0.9 * glow + vec3(0.05, 0.6, 0.7) * rimline * 0.2;
}
"""

var main
var segs: Array = []
var radii: Array = []
var head: Node3D
var jaw: Node3D
var skin: ShaderMaterial
var head_light: OmniLight3D
var warn_light: OmniLight3D
var warn_ring: MeshInstance3D
var warn_mat: StandardMaterial3D
var state := "idle"
var t := 0.0
var idle_ang := 0.0
var bridge := -1
var target := Vector3.ZERO
var side := Vector3.ZERO
var p0 := Vector3.ZERO
var p1 := Vector3.ZERO
var p2 := Vector3.ZERO
var dive_vel := Vector3.ZERO
var hit := {}
var _burst_up := false
var _burst_down := false
var warn_time: float = Cfg.WYRM_WARN
var strikes := 0


func _ready() -> void:
	_build()
	idle_ang = randf() * TAU
	_lay_out(_idle_pos(), Vector3(1, 0, 0))


func is_threatening() -> bool:
	return state == "warn" or state == "strike"


## Begins a strike on bridge `bi` at stone `point`.
func strike(bi: int, point: Vector3, warn: float) -> void:
	state = "warn"
	t = 0.0
	warn_time = warn
	strikes += 1
	bridge = bi
	target = point
	hit.clear()
	_burst_up = false
	_burst_down = false
	var perp: Vector3 = main.world.bridges[bi]["perp"]
	side = perp * (1.0 if randf() < 0.5 else -1.0)
	p0 = point - side * 15.0 + Vector3(0, -48.0, 0)
	p2 = point + side * 15.0 + Vector3(0, -48.0, 0)
	var peak := point + Vector3(0, 2.2, 0)
	p1 = 2.0 * peak - 0.5 * (p0 + p2)
	_lay_out(p0 - Vector3(0, 6, 0), Vector3(0, -1, 0))
	warn_ring.global_position = point + Vector3(0, 0.15, 0)
	warn_ring.visible = true
	warn_light.global_position = point + Vector3(0, -10.0, 0)
	warn_light.visible = true
	main.sfx.play("roar", point + Vector3(0, -6.0, 0), 8.0, randf_range(0.9, 1.05))


func _idle_pos() -> Vector3:
	var c: Vector3 = main.world.CENTER
	return c + Vector3(cos(idle_ang) * 150.0, main.world.UNDERWORLD_Y + 1.0 + sin(t * 0.6) * 4.0, sin(idle_ang) * 150.0)


func _bezier(u: float) -> Vector3:
	var a := p0.lerp(p1, u)
	var b := p1.lerp(p2, u)
	return a.lerp(b, u)


func _process(delta: float) -> void:
	t += delta
	var prev: Vector3 = head.global_position
	match state:
		"idle":
			idle_ang += delta * 0.045
			head.global_position = _idle_pos()
			jaw.rotation.x = 0.15 + 0.1 * sin(t)
			skin.set_shader_parameter("glow", 0.8)
		"warn":
			var k := clampf(t / warn_time, 0.0, 1.0)
			main.world.set_bridge_warning(bridge, k)
			warn_mat.albedo_color.a = 0.25 + 0.55 * k * (0.6 + 0.4 * sin(t * 18.0))
			warn_ring.scale = Vector3.ONE * (1.0 + 0.15 * sin(t * 9.0))
			warn_light.light_energy = 2.0 + 14.0 * k
			warn_light.global_position = target + Vector3(0, lerpf(-14.0, -3.0, k), 0)
			head.global_position = head.global_position.lerp(p0, minf(1.0, delta * 3.0))
			if t >= warn_time:
				state = "strike"
				t = 0.0
				skin.set_shader_parameter("glow", 1.5)
				head_light.light_energy = 10.0
				main.sfx.play("wyrm_burst", target, 6.0)
		"strike":
			var u := clampf(t / STRIKE_TIME, 0.0, 1.0)
			head.global_position = _bezier(u)
			jaw.rotation.x = 0.2 + 0.8 * sin(u * PI)
			main.world.set_bridge_warning(bridge, 1.0 - u)
			warn_light.light_energy = 16.0 * (1.0 - u)
			warn_mat.albedo_color.a = 0.6 * (1.0 - u)
			var hy: float = head.global_position.y
			if not _burst_up and hy > target.y - 3.0:
				_burst_up = true
				main.fx_burst(head.global_position, Color(0.4, 1.0, 0.9), 50, false, 9.0)
				main.shake_near(target, 22.0, 0.6)
			if _burst_up and not _burst_down and u > 0.6 and hy < target.y - 2.0:
				_burst_down = true
				main.fx_burst(head.global_position, Color(1.0, 0.4, 0.6), 40, false, 7.0)
			_check_hits()
			if u >= 1.0:
				state = "dive"
				t = 0.0
				dive_vel = (p2 - p1).normalized() * 30.0
				warn_ring.visible = false
				warn_light.visible = false
				main.world.set_bridge_warning(bridge, 0.0)
		"dive":
			head.global_position += dive_vel * delta
			_check_hits()
			if t >= DIVE_TIME:
				state = "idle"
				t = 0.0
				head_light.light_energy = 0.0
				skin.set_shader_parameter("glow", 0.8)
				_lay_out(_idle_pos(), Vector3(cos(idle_ang + PI / 2.0), 0, sin(idle_ang + PI / 2.0)))
				return
	var v := head.global_position - prev
	if v.length() > 0.001:
		_face(head, head.global_position + v)
	_follow()


func _face(n: Node3D, at: Vector3) -> void:
	var d := at - n.global_position
	if d.length() < 0.001:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	n.look_at(at, up)


func _follow() -> void:
	var lead: Vector3 = head.global_position
	for i in segs.size():
		var s: Node3D = segs[i]
		var d: Vector3 = s.global_position - lead
		if d.length() > SPACING:
			s.global_position = lead + d.normalized() * SPACING
		_face(s, lead)
		lead = s.global_position


## Puts the whole body in a straight line behind the head (used when it teleports).
func _lay_out(at: Vector3, heading: Vector3) -> void:
	head.global_position = at
	_face(head, at + heading)
	for i in segs.size():
		var s: Node3D = segs[i]
		s.global_position = at - heading.normalized() * SPACING * float(i + 1)


func _check_hits() -> void:
	for s in main.survivors:
		if not s.alive or s.escaped or hit.has(s):
			continue
		var c: Vector3 = s.global_position + Vector3(0, 0.9, 0)
		var touched := head.global_position.distance_to(c) < 3.2
		if not touched:
			for i in mini(22, segs.size()):
				var seg: Node3D = segs[i]
				if seg.global_position.distance_to(c) < float(radii[i]) + 1.1:
					touched = true
					break
		if not touched:
			continue
		hit[s] = true
		if main.args.has("log"):
			print("WYRM HIT ", s.display_name)
		var away: Vector3 = side
		var flat_off: Vector3 = c - head.global_position
		flat_off.y = 0.0
		if flat_off.length() > 0.1:
			away = (side + flat_off.normalized()).normalized()
		s.last_wyrm_ms = Time.get_ticks_msec()
		s.shoved(away * 13.0 + Vector3(0, 8.0, 0))
		s.lose_light(5.0)
		main.stats["wyrm"] += 1
		main.sfx.play("bite", null if s.is_player else c, 4.0, 0.6)
		if s.is_player:
			s.shake = maxf(s.shake, 0.8)


func _build() -> void:
	skin = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKIN_SHADER
	skin.shader = sh
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.08, 0.03, 0.05)
	spike_mat.emission_enabled = true
	spike_mat.emission = Color(0.9, 0.15, 0.2)
	spike_mat.emission_energy_multiplier = 1.2
	spike_mat.roughness = 0.4
	head = Node3D.new()
	add_child(head)
	var hm := SphereMesh.new()
	hm.radius = 1.0
	hm.height = 2.0
	hm.radial_segments = 18
	hm.rings = 9
	_part(head, hm, skin, Vector3(0, 0.3, 0.4), Vector3.ZERO, Vector3(2.2, 1.5, 3.3))
	# Long upper jaw with fangs, and a lower jaw that gapes.
	var snout := SphereMesh.new()
	snout.radius = 1.0
	snout.height = 2.0
	snout.radial_segments = 14
	snout.rings = 7
	_part(head, snout, skin, Vector3(0, 0.35, -2.3), Vector3.ZERO, Vector3(1.5, 0.8, 2.6))
	jaw = Node3D.new()
	jaw.position = Vector3(0, -0.4, 0.6)
	head.add_child(jaw)
	_part(jaw, snout, skin, Vector3(0, -0.3, -2.6), Vector3.ZERO, Vector3(1.3, 0.55, 2.5))
	var maw_mat := StandardMaterial3D.new()
	maw_mat.albedo_color = Color(0.4, 0.0, 0.03)
	maw_mat.emission_enabled = true
	maw_mat.emission = Color(1.0, 0.15, 0.1)
	maw_mat.emission_energy_multiplier = 3.0
	var throat := SphereMesh.new()
	throat.radius = 1.0
	throat.height = 2.0
	_part(head, throat, maw_mat, Vector3(0, -0.25, -1.4), Vector3.ZERO, Vector3(1.1, 0.4, 2.0))
	var fang := CylinderMesh.new()
	fang.top_radius = 0.0
	fang.bottom_radius = 0.16
	fang.height = 0.9
	fang.radial_segments = 5
	fang.rings = 1
	var bone := StandardMaterial3D.new()
	bone.albedo_color = Color(0.92, 0.88, 0.8)
	bone.emission_enabled = true
	bone.emission = Color(0.5, 0.45, 0.4)
	bone.emission_energy_multiplier = 0.5
	for k in 7:
		var z := -1.0 - float(k) * 0.55
		for sx in [-1.0, 1.0]:
			var x := float(sx) * (1.05 - float(k) * 0.08)
			_part(head, fang, bone, Vector3(x, -0.25, z), Vector3(PI, 0, 0), Vector3.ONE * (1.3 if k == 1 else 1.0))
			_part(jaw, fang, bone, Vector3(x * 0.9, 0.1, z - 0.4), Vector3.ZERO, Vector3.ONE * 0.8)
	# Burning eyes and swept horns.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.8, 0.3)
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(1.0, 0.55, 0.1)
	eye_mat.emission_energy_multiplier = 12.0
	var eye := SphereMesh.new()
	eye.radius = 0.28
	eye.height = 0.4
	for row in [[0.9, -0.6], [0.6, -1.4]]:
		for sx in [-1.0, 1.0]:
			_part(head, eye, eye_mat, Vector3(float(sx) * float(row[0]) * 1.4, 0.95, float(row[1])))
	var horn := CylinderMesh.new()
	horn.top_radius = 0.0
	horn.bottom_radius = 0.45
	horn.height = 3.6
	horn.radial_segments = 6
	horn.rings = 1
	for sx in [-1.0, 1.0]:
		_part(head, horn, spike_mat, Vector3(float(sx) * 1.3, 1.6, 1.6), Vector3(1.1, 0, float(sx) * -0.5))
		_part(head, horn, spike_mat, Vector3(float(sx) * 1.9, 0.9, 2.2), Vector3(1.4, 0, float(sx) * -1.0), Vector3(0.6, 0.6, 0.6))
	head_light = OmniLight3D.new()
	head_light.light_color = Color(1.0, 0.25, 0.15)
	head_light.light_energy = 0.0
	head_light.omni_range = 20.0
	head_light.position = Vector3(0, 0, -3.0)
	head.add_child(head_light)
	# The body.
	var seg_mesh := SphereMesh.new()
	seg_mesh.radius = 1.0
	seg_mesh.height = 2.0
	seg_mesh.radial_segments = 14
	seg_mesh.rings = 7
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.35
	spike.height = 1.8
	spike.radial_segments = 5
	spike.rings = 1
	for i in SEGMENTS:
		var k := float(i) / float(SEGMENTS - 1)
		var r := lerpf(2.0, 0.35, pow(k, 1.3))
		var s := Node3D.new()
		add_child(s)
		_part(s, seg_mesh, skin, Vector3.ZERO, Vector3.ZERO, Vector3(r, r * 0.9, SPACING * 0.75))
		if i % 2 == 0 and i < SEGMENTS - 3:
			_part(s, spike, spike_mat, Vector3(0, r * 0.95, 0), Vector3(-0.5, 0, 0), Vector3.ONE * clampf(r / 1.6, 0.35, 1.2))
		segs.append(s)
		radii.append(r)
	warn_mat = StandardMaterial3D.new()
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	warn_mat.albedo_color = Color(1.0, 0.12, 0.05, 0.0)
	var tm := TorusMesh.new()
	tm.inner_radius = 3.6
	tm.outer_radius = 4.3
	tm.rings = 48
	tm.ring_segments = 6
	warn_ring = MeshInstance3D.new()
	warn_ring.mesh = tm
	warn_ring.material_override = warn_mat
	warn_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warn_ring.visible = false
	add_child(warn_ring)
	warn_light = OmniLight3D.new()
	warn_light.light_color = Color(1.0, 0.15, 0.08)
	warn_light.omni_range = 22.0
	warn_light.light_energy = 0.0
	warn_light.visible = false
	add_child(warn_light)


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
