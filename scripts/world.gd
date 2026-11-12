extends Node3D
## Builds the Lumen Terraces procedurally: terraces, ramps, shrines, the Sun Gate,
## flora, sky and lighting. Also answers spatial queries for the game.

const TIERS := [[40.0, 0.0], [27.0, 2.5], [15.0, 5.0], [6.5, 7.5]] # [radius, top height]
const RAMPS := [[1, [0.0, 120.0, 240.0]], [2, [60.0, 180.0, 300.0]], [3, [30.0, 210.0]]]
const RAMP_RUN := 6.5
const RAMP_WIDTH := 4.0
const SHRINE_SPOTS := [[33.0, 45.0], [33.0, 225.0], [21.0, 135.0], [21.0, 315.0]]
const SHRINE_MAX_RADIUS := 6.0
const POND_SPOT := [21.0, 270.0]
const POND_RADIUS := 3.4
const SUN_AZIMUTH := 240.0
const LAYER_TERRAIN := 1
const LAYER_OBSTACLE := 4

const SKY_SHADER := """
shader_type sky;
uniform float dusk = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.3, -1.0);
uniform vec3 moon_dir = vec3(0.0, 0.6, 1.0);

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}
vec3 tri(vec3 a, vec3 b, vec3 c, float t) {
	return t < 0.5 ? mix(a, b, t * 2.0) : mix(b, c, t * 2.0 - 1.0);
}
void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 zen = tri(vec3(0.20, 0.32, 0.62), vec3(0.17, 0.12, 0.36), vec3(0.008, 0.012, 0.045), dusk);
	vec3 hor = tri(vec3(1.00, 0.66, 0.42), vec3(0.98, 0.38, 0.34), vec3(0.07, 0.05, 0.15), dusk);
	vec3 low = tri(vec3(0.62, 0.45, 0.52), vec3(0.32, 0.17, 0.30), vec3(0.01, 0.01, 0.03), dusk);
	vec3 col = mix(hor, zen, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(hor, low, smoothstep(0.0, 0.35, -h));
	}
	vec3 sd = normalize(sun_dir);
	float sun_amt = clamp(dot(d, sd), 0.0, 1.0);
	float sun_vis = smoothstep(-0.2, 0.04, sd.y);
	vec3 sun_col = tri(vec3(1.0, 0.82, 0.55), vec3(1.0, 0.45, 0.2), vec3(0.7, 0.18, 0.12), dusk);
	col += sun_col * pow(sun_amt, 8.0) * 0.7 * sun_vis;
	col += sun_col * pow(sun_amt, 90.0) * 1.5 * sun_vis;
	float az = clamp(dot(normalize(d.xz + vec2(0.0001)), normalize(sd.xz + vec2(0.0001))), 0.0, 1.0);
	col += sun_col * pow(az, 4.0) * exp(-abs(h) * 7.0) * 0.55 * (1.0 - dusk * 0.5);
	col += sun_col * smoothstep(0.9990, 0.9995, sun_amt) * 10.0 * sun_vis;
	if (!AT_CUBEMAP_PASS) {
		float night = smoothstep(0.5, 1.0, dusk);
		vec3 sp = d * 180.0;
		vec3 cell = floor(sp);
		float r = hash13(cell);
		float star = step(0.9962, r);
		star *= 1.0 - smoothstep(0.0, 0.38, length(fract(sp) - 0.5));
		float tw = 0.6 + 0.4 * sin(TIME * (2.0 + r * 5.0) + r * 50.0);
		col += vec3(0.85, 0.9, 1.0) * star * tw * night * smoothstep(0.0, 0.25, h) * 2.5;
		float a1 = sin(d.x * 5.0 + TIME * 0.12 + sin(d.z * 4.0 + TIME * 0.08) * 1.5);
		float band = exp(-pow((h - 0.42 - a1 * 0.08) * 6.0, 2.0));
		float curtain = 0.5 + 0.5 * sin(d.x * 38.0 + d.z * 23.0 + TIME * 0.5);
		vec3 aur = mix(vec3(0.1, 0.95, 0.6), vec3(0.65, 0.3, 1.0), 0.5 + 0.5 * a1);
		col += aur * band * (0.35 + 0.65 * curtain) * night * 0.55;
	}
	vec3 md = normalize(moon_dir);
	float mamt = dot(d, md);
	float mvis = smoothstep(0.3, 0.8, dusk);
	col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9988, 0.9992, mamt) * 3.0 * mvis;
	col += vec3(0.35, 0.45, 0.9) * pow(clamp(mamt, 0.0, 1.0), 40.0) * 0.3 * mvis;
	COLOR = col;
}
"""

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col : source_color = vec3(0.05, 0.14, 0.12);
uniform vec3 tip_col : source_color = vec3(0.45, 0.70, 0.48);
uniform vec3 glow_col : source_color = vec3(0.3, 1.0, 0.85);
uniform float night = 0.0;
varying float hgt;
varying vec3 tint;
void vertex() {
	hgt = UV.y;
	tint = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 1.4 + wp.x * 0.25 + wp.z * 0.18) * 0.5 + sin(TIME * 2.7 + wp.x * 0.9 - wp.z * 0.6) * 0.18;
	vec3 wind = vec3(w * 0.22, 0.0, w * 0.12) * hgt * hgt;
	VERTEX += (vec4(wind, 0.0) * MODEL_MATRIX).xyz;
}
void fragment() {
	ALBEDO = mix(base_col, tip_col * tint, hgt);
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
	EMISSION = glow_col * tint * night * hgt * hgt * 0.35;
}
"""

const FLOWER_SHADER := """
shader_type spatial;
uniform float glow = 0.6;
varying vec3 tint;
void vertex() {
	tint = COLOR.rgb;
}
void fragment() {
	ALBEDO = tint * 0.5;
	EMISSION = tint * glow;
	ROUGHNESS = 0.5;
}
"""

const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 top_col : source_color = vec3(1.0, 0.75, 0.65);
uniform vec3 shade_col : source_color = vec3(0.5, 0.4, 0.6);
uniform float scale = 0.0025;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wp.xz;
	float n = texture(noise_tex, uv * scale + vec2(TIME * 0.002, 0.0)).r * 0.65
		+ texture(noise_tex, uv * scale * 3.6 - vec2(0.0, TIME * 0.004)).r * 0.35;
	float dist = length(wp.xz);
	ALBEDO = mix(shade_col, top_col, smoothstep(0.35, 0.8, n));
	ALPHA = smoothstep(0.32, 0.62, n) * (1.0 - smoothstep(250.0, 520.0, dist)) * 0.95;
}
"""

const PORTAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float open = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv * vec2(1.0, 0.7));
	float ang = atan(uv.y, uv.x);
	float swirl = 0.5 + 0.5 * sin(ang * 5.0 + r * 18.0 - TIME * 2.5);
	float edge = 1.0 - smoothstep(0.22, 0.5, r);
	vec3 c = mix(vec3(1.0, 0.5, 0.2), vec3(1.0, 0.95, 0.75), swirl);
	float a = edge * mix(0.1, 1.0, open) * (0.55 + 0.45 * swirl);
	ALBEDO = c * a * mix(0.8, 3.0, open);
	ALPHA = a;
}
"""

var nav_region: NavigationRegion3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var cloud_mats: Array = []
var grass_mat: ShaderMaterial
var flower_mat: ShaderMaterial
var glow_mats: Array = [] # [material, day energy, night energy]
var lamp_lights: Array = []
var fireflies: GPUParticles3D
var shrines: Array = []
var shrine_radius := SHRINE_MAX_RADIUS
var gate_pos := Vector3(0, 7.5, 0)
var gate_mat: ShaderMaterial
var gate_light: OmniLight3D
var gate_ring: MeshInstance3D
var gate_open := false
var obstacles: Array = [] # [Vector2 xz, radius]
var ramp_centers: Array = []
var floaters: Array = []
var pond_pos := Vector3.ZERO
var lights_out_mode := false
var _t := 0.0

var _stone: StandardMaterial3D
var _marble: StandardMaterial3D
var _trunk: StandardMaterial3D
var _canopies: Array = []
var _orb_mat: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _lamp_bulb: StandardMaterial3D


func build() -> void:
	_make_materials()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	_build_terrain()
	_build_ramps()
	_build_balustrade()
	_build_gate()
	_build_shrines()
	_build_pond()
	_build_colonnade()
	_build_trees()
	_build_ruins()
	_build_grass()
	_build_flowers()
	_build_fireflies()
	_build_distant()
	_build_clouds()
	_bake_nav()


# ---------------------------------------------------------------- helpers

func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _mat(col: Color, rough := 0.85, emis := Color.BLACK, emis_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m


func _mesh(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _static(shape: Shape3D, pos: Vector3, layer: int, rot := Vector3.ZERO) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	b.collision_mask = 0
	b.position = pos
	b.rotation = rot
	var cs := CollisionShape3D.new()
	cs.shape = shape
	b.add_child(cs)
	nav_region.add_child(b)
	return b


func _tri_c(a: Color, b: Color, c: Color, t: float) -> Color:
	if t < 0.5:
		return a.lerp(b, t * 2.0)
	return b.lerp(c, t * 2.0 - 1.0)


func tier_height(r: float) -> float:
	for i in range(TIERS.size() - 1, -1, -1):
		if r <= float(TIERS[i][0]):
			return float(TIERS[i][1])
	return -50.0


func _clear_of_ramps(p: Vector3, d: float) -> bool:
	var q := Vector2(p.x, p.z)
	for c in ramp_centers:
		if q.distance_to(c) < d:
			return false
	return true


func is_clear(p: Vector3, rad: float) -> bool:
	var q := Vector2(p.x, p.z)
	for o in obstacles:
		if q.distance_to(o[0]) < float(o[1]) + rad:
			return false
	return true


func _pick_tier(max_tier: int) -> int:
	var w := randf()
	var t := 0
	if w < 0.5:
		t = 0
	elif w < 0.82:
		t = 1
	elif w < 0.97:
		t = 2
	else:
		t = 3
	return mini(t, max_tier)


func _random_decor_point(clear: float, max_tier := 3):
	for attempt in 50:
		var i := _pick_tier(max_tier)
		var inner: float = (float(TIERS[i + 1][0]) + 1.2) if i < 3 else 3.5
		var outer: float = float(TIERS[i][0]) - 1.2
		if outer <= inner:
			continue
		var r := sqrt(lerpf(inner * inner, outer * outer, randf()))
		var a := randf() * TAU
		var p := Vector3(cos(a) * r, float(TIERS[i][1]), sin(a) * r)
		if not _clear_of_ramps(p, 6.5):
			continue
		if not is_clear(p, clear):
			continue
		return p
	return null


# ---------------------------------------------------------------- queries

func ground_at(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 30.0, p.z), Vector3(p.x, -40.0, p.z), LAYER_TERRAIN)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -50.0
	return hit.position.y


func random_island_point(max_r: float) -> Vector3:
	var r := sqrt(randf()) * max_r
	var a := randf() * TAU
	return Vector3(cos(a) * r, 0.0, sin(a) * r)


func random_walk_point() -> Vector3:
	var p = _random_decor_point(1.0, 3)
	if p == null:
		return Vector3(20, 0, 0)
	return p


func shrine_protects(p: Vector3) -> bool:
	if shrine_radius <= 0.3:
		return false
	for s in shrines:
		var c: Vector3 = s["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < shrine_radius - 0.3:
			return true
	return false


func in_any_shrine(p: Vector3, pad := 0.0) -> bool:
	if shrine_radius <= 0.05:
		return false
	for s in shrines:
		var c: Vector3 = s["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < shrine_radius + pad:
			return true
	return false


func push_out_of_shrines(p: Vector3, pad: float) -> Vector3:
	if shrine_radius <= 0.05:
		return p
	for s in shrines:
		var c: Vector3 = s["pos"]
		var d := Vector2(p.x - c.x, p.z - c.z)
		var lim := shrine_radius + pad
		if d.length() < lim:
			if d.length() < 0.01:
				d = Vector2(1, 0)
			d = d.normalized() * lim
			p.x = c.x + d.x
			p.z = c.z + d.y
	return p


func nearest_shrine(p: Vector3, min_radius: float):
	if shrine_radius < min_radius:
		return null
	var best = null
	var bd := INF
	for s in shrines:
		var c: Vector3 = s["pos"]
		var d := c.distance_to(p)
		if d < bd:
			bd = d
			best = c
	return best


# ---------------------------------------------------------------- build steps

func _make_materials() -> void:
	_stone = _mat(Color(0.6, 0.54, 0.57), 0.95)
	_marble = _mat(Color(0.93, 0.9, 0.85), 0.5)
	_trunk = _mat(Color(0.3, 0.22, 0.25), 0.9)
	for c in [Color(1.0, 0.62, 0.78), Color(0.78, 0.62, 1.0), Color(0.45, 0.92, 0.85), Color(1.0, 0.78, 0.55)]:
		var m := _mat(c, 0.8, c, 0.05)
		_canopies.append(m)
		glow_mats.append([m, 0.05, 0.45])
	_orb_mat = _mat(Color(1.0, 0.85, 0.5), 0.4, Color(1.0, 0.75, 0.35), 1.0)
	glow_mats.append([_orb_mat, 1.0, 5.0])
	_rune_mat = _mat(Color(0.4, 0.9, 1.0), 0.4, Color(0.35, 0.85, 1.0), 0.6)
	glow_mats.append([_rune_mat, 0.6, 4.0])
	_lamp_bulb = _mat(Color(1.0, 0.85, 0.6), 0.4, Color(1.0, 0.7, 0.4), 2.0)
	glow_mats.append([_lamp_bulb, 2.0, 6.0])


func _build_environment() -> void:
	sky_mat = _shader_mat(SKY_SHADER)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.12
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0035
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.light_volumetric_fog_energy = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)


func _build_terrain() -> void:
	var grass_cap := _mat(Color(0.2, 0.36, 0.3), 0.95)
	for i in TIERS.size():
		var r: float = TIERS[i][0]
		var top: float = TIERS[i][1]
		var depth: float = 6.0 if i == 0 else top - float(TIERS[i - 1][1]) + 0.5
		var cm := CylinderMesh.new()
		cm.top_radius = r
		cm.bottom_radius = r
		cm.height = depth
		cm.radial_segments = 72
		cm.rings = 1
		_mesh(self, cm, _stone, Vector3(0, top - depth * 0.5, 0))
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = depth
		_static(shape, Vector3(0, top - depth * 0.5, 0), LAYER_TERRAIN)
		var cap := CylinderMesh.new()
		cap.top_radius = r - 0.25
		cap.bottom_radius = r - 0.25
		cap.height = 0.1
		cap.radial_segments = 72
		_mesh(self, cap, grass_cap, Vector3(0, top - 0.03, 0))
	# The rocky root of the floating island.
	var dark := _mat(Color(0.33, 0.28, 0.34), 1.0)
	var root := CylinderMesh.new()
	root.top_radius = 40.0
	root.bottom_radius = 4.0
	root.height = 30.0
	root.radial_segments = 20
	root.rings = 5
	_mesh(self, root, dark, Vector3(0, -6.0 - 15.0, 0))
	for k in 9:
		var a := randf() * TAU
		var rr := randf_range(18.0, 34.0)
		var sz := randf_range(2.0, 5.0)
		var cone := CylinderMesh.new()
		cone.top_radius = sz
		cone.bottom_radius = 0.2
		cone.height = sz * 3.0
		cone.radial_segments = 7
		_mesh(self, cone, dark, Vector3(cos(a) * rr, -6.0 - sz * 1.5 - randf() * 4.0, sin(a) * rr))


func _build_ramps() -> void:
	var mat := _mat(Color(0.72, 0.66, 0.62), 0.9)
	for entry in RAMPS:
		var inner: int = entry[0]
		for ang in entry[1]:
			var a := deg_to_rad(float(ang))
			var r_in: float = TIERS[inner][0]
			var y_low: float = TIERS[inner - 1][1]
			var y_high: float = TIERS[inner][1]
			var h := y_high - y_low
			var dir := Vector3(cos(a), 0, sin(a))
			# A mound: walkable top slope plus gently sloped sides (no side walls to snag on).
			var origin := dir * (r_in - 0.05) + Vector3(0, y_low, 0)
			var rot := Vector3(0, -a, 0)
			var pts := _ramp_points(h)
			_mesh(self, _ramp_mesh(pts), mat, origin, rot)
			var shape := ConvexPolygonShape3D.new()
			shape.points = PackedVector3Array(pts)
			_static(shape, origin, LAYER_TERRAIN, rot)
			var center := dir * (r_in + RAMP_RUN * 0.5)
			ramp_centers.append(Vector2(center.x, center.z))
			# A lamp post at the top of each stair guides players at night.
			var side := Vector3(-dir.z, 0, dir.x) * (RAMP_WIDTH * 0.5 + 0.35)
			_ramp_lamp(dir * (r_in - 0.4) + side + Vector3(0, y_high, 0))


## Local space: +x points outward (down the slope), y up. x=0 is the upper tier's wall.
func _ramp_points(h: float) -> Array:
	var hw := RAMP_WIDTH * 0.5
	var side := h * 2.0 # side slopes ~26 degrees
	return [
		Vector3(0, h, -hw), Vector3(0, h, hw), # top edge at the upper tier
		Vector3(0, 0, -hw - side), Vector3(0, 0, hw + side), # base at the wall
		Vector3(RAMP_RUN, 0, -hw - side * 0.35), Vector3(RAMP_RUN, 0, hw + side * 0.35), # foot
	]


func _ramp_mesh(p: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := [
		[0, 4, 1], [1, 4, 5], # top slope
		[0, 2, 4], # side -z
		[1, 5, 3], # side +z
		[0, 1, 2], [1, 3, 2], # wall face (hidden)
	]
	var centroid := Vector3.ZERO
	for v in p:
		centroid += v
	centroid /= p.size()
	for t in tris:
		var a: Vector3 = p[t[0]]
		var b: Vector3 = p[t[1]]
		var c: Vector3 = p[t[2]]
		var n := (b - a).cross(c - a).normalized()
		var out := (a + b + c) / 3.0 - centroid
		# Godot front faces are clockwise: the cross product must point inward.
		if n.dot(out) > 0.0:
			var tmp := b
			b = c
			c = tmp
			n = -n
		for v in [a, b, c]:
			st.set_normal(-n)
			st.add_vertex(v)
	return st.commit()


func _ramp_lamp(pos: Vector3) -> void:
	var post := CylinderMesh.new()
	post.top_radius = 0.05
	post.bottom_radius = 0.08
	post.height = 1.8
	_mesh(self, post, _trunk, pos + Vector3(0, 0.9, 0))
	var bulb := SphereMesh.new()
	bulb.radius = 0.15
	bulb.height = 0.3
	_mesh(self, bulb, _lamp_bulb, pos + Vector3(0, 1.9, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.42)
	l.light_energy = 0.4
	l.omni_range = 6.0
	l.position = pos + Vector3(0, 1.9, 0)
	add_child(l)
	lamp_lights.append(l)


func _build_balustrade() -> void:
	var n := 60
	var r := 39.4
	var seg_len := TAU * r / n
	var rail := BoxMesh.new()
	rail.size = Vector3(seg_len * 0.98, 0.16, 0.32)
	var post := BoxMesh.new()
	post.size = Vector3(0.34, 0.9, 0.34)
	var cap := SphereMesh.new()
	cap.radius = 0.2
	cap.height = 0.4
	for i in n:
		var a := TAU * i / n
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var tangent := Vector3(-sin(a), 0, cos(a))
		var rot := Vector3(0, atan2(-tangent.z, tangent.x), 0)
		_mesh(self, rail, _marble, p + Vector3(0, 0.85, 0), rot)
		_mesh(self, post, _marble, p + Vector3(0, 0.45, 0), rot)
		if i % 6 == 0:
			_mesh(self, cap, _lamp_bulb, p + Vector3(0, 1.1, 0))
		var shape := BoxShape3D.new()
		shape.size = Vector3(seg_len, 1.4, 0.5)
		_static(shape, p + Vector3(0, 0.7, 0), LAYER_OBSTACLE, rot)


func _build_gate() -> void:
	var top: float = TIERS[3][1]
	gate_pos = Vector3(0, top, 0)
	var gold := _mat(Color(0.95, 0.72, 0.32), 0.3, Color(1.0, 0.68, 0.3), 1.2)
	gold.metallic = 0.8
	glow_mats.append([gold, 1.2, 3.0])
	var plinth := CylinderMesh.new()
	plinth.top_radius = 3.4
	plinth.bottom_radius = 3.6
	plinth.height = 0.1
	plinth.radial_segments = 48
	_mesh(self, plinth, _marble, Vector3(0, top + 0.02, 0))
	for sx in [-1.0, 1.0]:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 5.0, 0.7)
		var pp := Vector3(1.95 * float(sx), top + 2.5, 0)
		_mesh(self, bm, _marble, pp)
		var sh := BoxShape3D.new()
		sh.size = bm.size
		_static(sh, pp, LAYER_OBSTACLE)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.9, 0.45, 0.9)
	_mesh(self, lintel, _marble, Vector3(0, top + 5.1, 0))
	var tm := TorusMesh.new()
	tm.inner_radius = 1.9
	tm.outer_radius = 2.35
	tm.rings = 48
	tm.ring_segments = 12
	gate_ring = _mesh(self, tm, gold, Vector3(0, top + 7.0, 0), Vector3(PI / 2.0, 0, 0))
	gate_mat = _shader_mat(PORTAL_SHADER)
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 4.85)
	_mesh(self, q, gate_mat, Vector3(0, top + 2.45, 0))
	gate_light = OmniLight3D.new()
	gate_light.light_color = Color(1.0, 0.75, 0.4)
	gate_light.light_energy = 0.6
	gate_light.omni_range = 12.0
	gate_light.position = Vector3(0, top + 3.0, 0)
	add_child(gate_light)
	obstacles.append([Vector2.ZERO, 3.2])


func _build_shrines() -> void:
	for spot in SHRINE_SPOTS:
		var a := deg_to_rad(float(spot[1]))
		var r: float = spot[0]
		var p := Vector3(cos(a) * r, tier_height(r), sin(a) * r)
		var base := BoxMesh.new()
		base.size = Vector3(1.4, 0.4, 1.4)
		_mesh(self, base, _stone, p + Vector3(0, 0.2, 0))
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.45, 1.7, 0.45)
		_mesh(self, pillar, _stone, p + Vector3(0, 1.25, 0))
		var house := BoxMesh.new()
		house.size = Vector3(0.85, 0.65, 0.85)
		_mesh(self, house, _stone, p + Vector3(0, 2.4, 0), Vector3.ZERO, Vector3(1, 1, 1))
		var roof := PrismMesh.new()
		roof.size = Vector3(1.4, 0.55, 1.4)
		_mesh(self, roof, _marble, p + Vector3(0, 3.0, 0))
		var core_mat := _mat(Color(1.0, 0.85, 0.55), 0.3, Color(1.0, 0.7, 0.35), 4.0)
		var core := SphereMesh.new()
		core.radius = 0.3
		core.height = 0.6
		_mesh(self, core, core_mat, p + Vector3(0, 2.4, 0))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.75, 0.45)
		light.light_energy = 2.5
		light.omni_range = 9.0
		light.position = p + Vector3(0, 2.4, 0)
		add_child(light)
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.albedo_color = Color(1.0, 0.8, 0.45, 0.6)
		var tm := TorusMesh.new()
		tm.inner_radius = SHRINE_MAX_RADIUS - 0.12
		tm.outer_radius = SHRINE_MAX_RADIUS
		tm.rings = 64
		tm.ring_segments = 6
		var ring := _mesh(self, tm, ring_mat, p + Vector3(0, 0.12, 0))
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.0, 3.0, 1.0)
		_static(shape, p + Vector3(0, 1.5, 0), LAYER_OBSTACLE)
		obstacles.append([Vector2(p.x, p.z), 1.6])
		shrines.append({"pos": p, "light": light, "ring": ring, "core": core_mat})


func _build_pond() -> void:
	var a := deg_to_rad(float(POND_SPOT[1]))
	var r: float = POND_SPOT[0]
	pond_pos = Vector3(cos(a) * r, tier_height(r), sin(a) * r)
	var water := _mat(Color(0.04, 0.1, 0.14), 0.03)
	water.metallic = 0.2
	var disc := CylinderMesh.new()
	disc.top_radius = POND_RADIUS
	disc.bottom_radius = POND_RADIUS
	disc.height = 0.06
	disc.radial_segments = 48
	_mesh(self, disc, water, pond_pos + Vector3(0, 0.06, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = POND_RADIUS - 0.1
	rim.outer_radius = POND_RADIUS + 0.4
	rim.rings = 48
	_mesh(self, rim, _marble, pond_pos + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	var pad_mat := _mat(Color(0.2, 0.45, 0.3), 0.7)
	var bud_mat := _mat(Color(1.0, 0.7, 0.85), 0.4, Color(1.0, 0.45, 0.7), 2.0)
	glow_mats.append([bud_mat, 1.0, 5.0])
	for k in 8:
		var pa := randf() * TAU
		var pr := randf_range(0.6, POND_RADIUS - 0.6)
		var pos := pond_pos + Vector3(cos(pa) * pr, 0.1, sin(pa) * pr)
		var pad := CylinderMesh.new()
		pad.top_radius = randf_range(0.22, 0.38)
		pad.bottom_radius = pad.top_radius
		pad.height = 0.02
		pad.radial_segments = 12
		_mesh(self, pad, pad_mat, pos)
		if k % 2 == 0:
			var bud := SphereMesh.new()
			bud.radius = 0.08
			bud.height = 0.14
			_mesh(self, bud, bud_mat, pos + Vector3(0, 0.08, 0))
	obstacles.append([Vector2(pond_pos.x, pond_pos.z), POND_RADIUS + 0.5])


func _column(p: Vector3, h: float, rune: bool) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.4
	cm.bottom_radius = 0.46
	cm.height = h
	cm.radial_segments = 12
	_mesh(self, cm, _marble, p + Vector3(0, h * 0.5, 0))
	var base := BoxMesh.new()
	base.size = Vector3(1.15, 0.3, 1.15)
	_mesh(self, base, _marble, p + Vector3(0, 0.15, 0))
	if h > 3.0:
		var capital := BoxMesh.new()
		capital.size = Vector3(1.05, 0.28, 1.05)
		_mesh(self, capital, _marble, p + Vector3(0, h + 0.1, 0))
	if rune:
		var band := TorusMesh.new()
		band.inner_radius = 0.42
		band.outer_radius = 0.5
		band.rings = 24
		_mesh(self, band, _rune_mat, p + Vector3(0, h * 0.62, 0))
	var shp := CylinderShape3D.new()
	shp.radius = 0.5
	shp.height = h
	_static(shp, p + Vector3(0, h * 0.5, 0), LAYER_OBSTACLE)
	obstacles.append([Vector2(p.x, p.z), 0.8])


func _build_colonnade() -> void:
	var top: float = TIERS[3][1]
	for deg in [75.0, 120.0, 165.0, 255.0, 300.0, 345.0]:
		var a := deg_to_rad(float(deg))
		_column(Vector3(cos(a) * 5.4, top, sin(a) * 5.4), 3.6, true)


func _build_ruins() -> void:
	for i in 14:
		var p = _random_decor_point(2.0, 2)
		if p == null:
			continue
		_column(p, randf_range(1.0, 4.2), randf() < 0.35)


func make_tree(parent: Node, pos: Vector3, s: float, collide: bool) -> void:
	var cmat: Material = _canopies.pick_random()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16 * s
	trunk.bottom_radius = 0.32 * s
	trunk.height = 3.2 * s
	trunk.radial_segments = 8
	_mesh(parent, trunk, _trunk, pos + Vector3(0, 1.6 * s, 0), Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.08, 0.08)))
	for k in 4:
		var sm := SphereMesh.new()
		var rr := randf_range(0.9, 1.5) * s
		sm.radius = rr
		sm.height = rr * 1.5
		sm.radial_segments = 12
		sm.rings = 6
		var off := Vector3(randf_range(-1.0, 1.0) * s, (3.2 + randf_range(-0.2, 0.9)) * s, randf_range(-1.0, 1.0) * s)
		_mesh(parent, sm, cmat, pos + off)
	if collide:
		for k in 3:
			var orb := SphereMesh.new()
			orb.radius = 0.09
			orb.height = 0.18
			var oa := randf() * TAU
			_mesh(parent, orb, _orb_mat, pos + Vector3(cos(oa) * 1.1 * s, 2.3 * s, sin(oa) * 1.1 * s))
		var shp := CylinderShape3D.new()
		shp.radius = 0.35 * s
		shp.height = 3.0 * s
		_static(shp, pos + Vector3(0, 1.5 * s, 0), LAYER_OBSTACLE)
		obstacles.append([Vector2(pos.x, pos.z), 0.9 * s])


func _build_trees() -> void:
	# Keep pilgrim spawn points (ring at r=35, see main._spawn_survivors) free of trees,
	# so the starting camera is not buried in a canopy.
	for i in 10:
		var a := TAU * float(i) / 10.0 + 0.3
		obstacles.append([Vector2(cos(a) * 35.0, sin(a) * 35.0), 5.0])
	for i in 24:
		var p = _random_decor_point(2.6, 2)
		if p == null:
			continue
		make_tree(self, p, randf_range(0.8, 1.35), true)


func _tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	for b in 5:
		var ang := TAU * b / 5.0 + randf() * 0.5
		var dir := Vector3(cos(ang), 0, sin(ang))
		var side := Vector3(-dir.z, 0, dir.x) * 0.055
		var base := dir * 0.06
		var tip := dir * 0.16 + Vector3(0, 0.28 + randf() * 0.14, 0)
		verts.append(base - side)
		verts.append(base + side)
		verts.append(tip)
		uvs.append(Vector2(0, 0))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(0.5, 1))
		for k in 3:
			norms.append(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = norms
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_grass() -> void:
	grass_mat = _shader_mat(GRASS_SHADER)
	var xf: Array = []
	var cols: Array = []
	var target := 15000
	var tries := 0
	var pond_q := Vector2(pond_pos.x, pond_pos.z)
	while xf.size() < target and tries < target * 2:
		tries += 1
		var r := sqrt(randf()) * 39.0
		if r < 3.4:
			continue
		var a := randf() * TAU
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		if not _clear_of_ramps(p, 4.3):
			continue
		if Vector2(p.x, p.z).distance_to(pond_q) < POND_RADIUS + 0.4:
			continue
		p.y = tier_height(r)
		var s := randf_range(0.7, 1.2)
		var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * randf_range(0.8, 1.3), s))
		xf.append(Transform3D(b, p))
		var g := randf()
		cols.append(Color(0.75 + g * 0.35, 0.9 + g * 0.15, 0.75 + (1.0 - g) * 0.3))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tuft_mesh()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_flowers() -> void:
	flower_mat = _shader_mat(FLOWER_SHADER)
	var palette := [Color(0.3, 0.9, 1.0), Color(1.0, 0.4, 0.8), Color(1.0, 0.8, 0.35), Color(0.65, 0.45, 1.0)]
	var xf: Array = []
	var cols: Array = []
	for c in 70:
		var center = _random_decor_point(0.5, 2)
		if center == null:
			continue
		var col: Color = palette.pick_random()
		for k in randi_range(8, 22):
			var p: Vector3 = center + Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
			if not _clear_of_ramps(p, 4.2):
				continue
			p.y = tier_height(Vector2(p.x, p.z).length()) + randf_range(0.3, 0.55)
			xf.append(Transform3D(Basis().scaled(Vector3.ONE * randf_range(0.7, 1.3)), p))
			cols.append(col.lerp(Color.WHITE, randf() * 0.25))
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 8
	sm.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = flower_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_fireflies() -> void:
	fireflies = GPUParticles3D.new()
	fireflies.amount = 320
	fireflies.lifetime = 8.0
	fireflies.preprocess = 8.0
	fireflies.visibility_aabb = AABB(Vector3(-50, -10, -50), Vector3(100, 30, 100))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(38, 3, 38)
	pm.gravity = Vector3(0, 0.05, 0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.5
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.0
	pm.turbulence_noise_scale = 6.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	fireflies.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.035
	dm.height = 0.07
	dm.radial_segments = 6
	dm.rings = 3
	var fm := StandardMaterial3D.new()
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	fm.albedo_color = Color(0, 0, 0)
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.85, 0.4)
	fm.emission_energy_multiplier = 6.0
	dm.material = fm
	fireflies.draw_pass_1 = dm
	fireflies.position = Vector3(0, 4, 0)
	add_child(fireflies)


func _build_distant() -> void:
	var dark := _mat(Color(0.33, 0.28, 0.34), 1.0)
	var cap_mat := _mat(Color(0.25, 0.42, 0.32), 0.95)
	for i in 8:
		var a := TAU * i / 8.0 + randf_range(-0.3, 0.3)
		var dist := randf_range(85.0, 170.0)
		var y := randf_range(-14.0, 16.0)
		var root := Node3D.new()
		root.position = Vector3(cos(a) * dist, y, sin(a) * dist)
		add_child(root)
		var size := randf_range(4.0, 12.0)
		var cone := CylinderMesh.new()
		cone.top_radius = size
		cone.bottom_radius = size * 0.12
		cone.height = size * 1.8
		cone.radial_segments = 10
		_mesh(root, cone, dark, Vector3(0, -size * 0.9, 0))
		var cap := CylinderMesh.new()
		cap.top_radius = size - 0.2
		cap.bottom_radius = size - 0.2
		cap.height = 0.2
		cap.radial_segments = 24
		_mesh(root, cap, cap_mat, Vector3(0, 0.05, 0))
		for k in randi_range(1, 3):
			var ta := randf() * TAU
			var tr := randf() * size * 0.5
			make_tree(root, Vector3(cos(ta) * tr, 0.0, sin(ta) * tr), randf_range(0.9, 1.6), false)
		floaters.append([root, y, randf() * TAU])


func _build_clouds() -> void:
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.008
	fn.fractal_octaves = 4
	nt.noise = fn
	for layer in [[-32.0, 0.0025], [-24.0, 0.0034]]:
		var m := _shader_mat(CLOUD_SHADER)
		m.set_shader_parameter("noise_tex", nt)
		m.set_shader_parameter("scale", float(layer[1]))
		var pm := PlaneMesh.new()
		pm.size = Vector2(1100, 1100)
		var mi := _mesh(self, pm, m, Vector3(0, float(layer[0]), 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud_mats.append(m)


func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = LAYER_TERRAIN | LAYER_OBSTACLE
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 35.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


# ---------------------------------------------------------------- runtime

func update_time(dusk: float) -> void:
	if lights_out_mode:
		return
	dusk = clampf(dusk, 0.0, 1.0)
	var night := smoothstep(0.5, 1.0, dusk)
	var elev := lerpf(22.0, -9.0, dusk)
	sun.rotation = Vector3(deg_to_rad(-elev), deg_to_rad(SUN_AZIMUTH), 0.0)
	var vis := smoothstep(-3.0, 8.0, elev)
	sun.light_energy = 1.35 * vis
	sun.visible = vis > 0.001
	sun.light_color = _tri_c(Color(1.0, 0.86, 0.68), Color(1.0, 0.55, 0.32), Color(0.9, 0.3, 0.2), dusk)
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(SUN_AZIMUTH + 150.0), 0.0)
	moon.light_energy = 0.45 * smoothstep(0.35, 0.9, dusk)
	sky_mat.set_shader_parameter("dusk", dusk)
	sky_mat.set_shader_parameter("sun_dir", sun.global_transform.basis.z)
	sky_mat.set_shader_parameter("moon_dir", moon.global_transform.basis.z)
	env.ambient_light_color = _tri_c(Color(0.75, 0.68, 0.7), Color(0.5, 0.38, 0.5), Color(0.16, 0.18, 0.34), dusk)
	env.ambient_light_energy = lerpf(1.0, 1.25, night)
	env.fog_light_color = _tri_c(Color(0.95, 0.72, 0.6), Color(0.72, 0.38, 0.45), Color(0.06, 0.07, 0.16), dusk)
	env.volumetric_fog_albedo = _tri_c(Color(1.0, 0.85, 0.75), Color(0.9, 0.6, 0.65), Color(0.35, 0.4, 0.7), dusk)
	env.volumetric_fog_emission = Color(0.02, 0.02, 0.05) * night
	for m in cloud_mats:
		m.set_shader_parameter("top_col", _tri_c(Color(1.0, 0.82, 0.7), Color(1.0, 0.5, 0.45), Color(0.12, 0.12, 0.25), dusk))
		m.set_shader_parameter("shade_col", _tri_c(Color(0.65, 0.5, 0.65), Color(0.4, 0.22, 0.4), Color(0.03, 0.03, 0.08), dusk))
	grass_mat.set_shader_parameter("night", night)
	flower_mat.set_shader_parameter("glow", lerpf(0.5, 4.0, night))
	for g in glow_mats:
		g[0].emission_energy_multiplier = lerpf(float(g[1]), float(g[2]), night)
	for l in lamp_lights:
		l.light_energy = lerpf(0.3, 1.6, night)
	fireflies.amount_ratio = lerpf(0.15, 1.0, night)


func set_shrine_radius(rr: float) -> void:
	shrine_radius = rr
	var k := rr / SHRINE_MAX_RADIUS
	for s in shrines:
		var ring: MeshInstance3D = s["ring"]
		ring.visible = k > 0.01
		ring.scale = Vector3(maxf(k, 0.01), 1.0, maxf(k, 0.01))
		s["light"].light_energy = 0.15 + 2.4 * k
		s["core"].emission_energy_multiplier = 0.3 + 4.0 * k


func set_gate_open() -> void:
	gate_open = true
	var tw := create_tween().set_parallel(true)
	tw.tween_method(func(v: float): gate_mat.set_shader_parameter("open", v), 0.0, 1.0, 1.5)
	tw.tween_property(gate_light, "light_energy", 5.0, 1.5)
	tw.tween_property(gate_light, "omni_range", 18.0, 1.5)


func lights_out() -> void:
	lights_out_mode = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sun, "light_energy", 0.0, 2.0)
	tw.tween_property(moon, "light_energy", 0.12, 3.0)
	tw.tween_property(gate_light, "light_energy", 0.0, 2.5)
	tw.tween_property(env, "ambient_light_energy", 0.35, 3.0)
	for s in shrines:
		tw.tween_property(s["light"], "light_energy", 0.0, 2.0)
	for l in lamp_lights:
		tw.tween_property(l, "light_energy", 0.0, 2.5)
	tw.tween_method(func(v: float): gate_mat.set_shader_parameter("open", v), 1.0 if gate_open else 0.1, 0.0, 2.0)


## A pillar of light from the Sun Gate into the sky whenever someone escapes.
## Visible from anywhere on the island.
func escape_beam() -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 1.6
	cm.bottom_radius = 1.1
	cm.height = 120.0
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.0)
	var beam := _mesh(self, cm, m, gate_pos + Vector3(0, 62.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.scale = Vector3(0.2, 1.0, 0.2)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "albedo_color:a", 0.75, 0.25)
	tw.tween_property(beam, "scale", Vector3(1.0, 1.0, 1.0), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(m, "albedo_color:a", 0.0, 2.2)
	tw.parallel().tween_property(beam, "scale", Vector3(0.05, 1.0, 0.05), 2.2)
	tw.chain().tween_callback(beam.queue_free)


func _process(delta: float) -> void:
	_t += delta
	for f in floaters:
		var n: Node3D = f[0]
		n.position.y = float(f[1]) + sin(_t * 0.35 + float(f[2])) * 1.2
	if gate_ring:
		gate_ring.rotation.y = sin(_t * 0.4) * 0.15
