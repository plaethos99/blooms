extends Node3D
## Builds the Sky Gardens: floating islands with hanging gardens and waterfalls, linked
## by stepping stones that rise and fall over the Underglow (a glowing abyss: fall in and
## you are gone). Also answers spatial queries for the game.

const ISLANDS := [
	# [name, x, z, top height, radius]
	["Dawn Meadow", 0.0, 0.0, 0.0, 20.0],
	["Lantern Grove", -46.0, -12.0, 2.5, 14.0],
	["Ember Rocks", 46.0, -14.0, 0.0, 13.0],
	["Mirror Pond", -32.0, -60.0, 7.0, 13.0],
	["Bell Ruins", 32.0, -62.0, 5.5, 12.0],
	["Heart Rock", 0.0, -50.0, 4.0, 6.5],
	["Sun Gate Isle", 0.0, -100.0, 10.0, 13.0],
]
const START_ISLAND := 0
const HEART_ISLAND := 5
const GATE_ISLAND := 6
const SHRINE_SPOTS := [[1, 0.0, 0.0], [2, 0.0, 0.0], [3, 4.0, -3.0], [4, 0.0, 0.0]] # island, dx, dz
const BRIDGES := [[0, 1], [0, 2], [1, 3], [2, 4], [3, 6], [4, 6], [0, 5], [5, 6]]
const WATERFALLS := [[0, 2], [1, 1], [3, 1], [4, 1], [6, 2]] # island, count
const STONE_H := 0.7
const STONE_GAP := 1.45
const MAX_STEP := 1.2 # biggest height change between neighbouring stones
const UNDERWORLD_Y := -70.0
const FALL_Y := -12.0
const CENTER := Vector3(0, 0, -50)
const SHRINE_MAX_RADIUS := 6.0
const POND_RADIUS := 3.0
const SUN_AZIMUTH := 240.0
const LAYER_TERRAIN := 1
const LAYER_OBSTACLE := 4
const SPAWN_RING := 12.0
const RUNE_COL := Color(0.35, 0.9, 1.0)
const WARN_COL := Color(1.0, 0.15, 0.08)

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
	vec3 low = tri(vec3(0.30, 0.22, 0.40), vec3(0.16, 0.08, 0.22), vec3(0.01, 0.02, 0.05), dusk);
	vec3 col = mix(hor, zen, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(hor, low, smoothstep(0.0, 0.25, -h));
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

## Curtains of hanging garden: leafy strands with flowers that glow after sunset.
const VINE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform float night = 0.0;
varying vec3 tint;
void vertex() {
	tint = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.x += sin(TIME * 0.9 + wp.x * 0.3 + wp.z * 0.2 + UV.y * 2.0) * 0.12 * UV.y * UV.y;
	VERTEX.z += sin(TIME * 0.7 + wp.z * 0.25) * 0.15 * UV.y * UV.y;
}
void fragment() {
	float x = UV.x * 7.0;
	float cell = floor(x);
	float fx = fract(x) - 0.5;
	float rnd = fract(sin(cell * 91.3 + tint.r * 17.0 + tint.b * 5.0) * 4375.5);
	float len = 0.4 + 0.6 * rnd;
	float wob = sin(UV.y * 18.0 + cell * 2.0) * 0.12;
	float leaf = 0.12 + 0.14 * (0.5 + 0.5 * sin(UV.y * 70.0 + cell * 3.0));
	if (abs(fx + wob) > leaf || UV.y > len) {
		discard;
	}
	float fl = step(0.84, fract(sin(floor(UV.y * 26.0) * 13.7 + cell * 7.1) * 951.3));
	vec3 leafc = mix(vec3(0.16, 0.42, 0.24), vec3(0.08, 0.26, 0.2), UV.y / len);
	ALBEDO = mix(leafc, tint, fl);
	EMISSION = tint * fl * (0.25 + 3.5 * night) + vec3(0.1, 0.6, 0.45) * night * 0.12;
	ROUGHNESS = 0.8;
}
"""

## A curtain of water that arcs off an island edge and falls into the Underglow.
const WATERFALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float fall_len = 70.0;
uniform float night = 0.0;
varying float d;
void vertex() {
	d = -VERTEX.y;
	float k = clamp(d / fall_len, 0.0, 1.0);
	VERTEX.z += 1.3 * sqrt(max(d, 0.0));
	VERTEX.x *= 1.0 + k * 1.6;
}
void fragment() {
	float n = texture(noise_tex, vec2(UV.x * 2.5, d * 0.035 - TIME * 0.7)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 6.0 + 0.3, d * 0.08 - TIME * 1.4)).r;
	float streak = smoothstep(0.35, 0.8, n * 0.55 + n2 * 0.55);
	float edge = smoothstep(0.0, 0.2, UV.x) * smoothstep(1.0, 0.8, UV.x);
	float fade = 1.0 - smoothstep(fall_len * 0.3, fall_len, d);
	float foam = 1.0 - smoothstep(0.0, 2.0, d);
	vec3 c = mix(vec3(0.62, 0.8, 0.95), vec3(0.3, 0.85, 1.0), night) * (0.55 + 0.6 * streak) + foam * 0.5;
	ALBEDO = c * mix(0.9, 1.5, night);
	ALPHA = clamp((0.2 + 0.6 * streak + foam) * edge * fade, 0.0, 1.0);
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
	float dist = length(wp.xz - vec2(0.0, -50.0));
	ALBEDO = mix(shade_col, top_col, smoothstep(0.35, 0.8, n));
	// A ring of cloud far out; the abyss right below the islands stays clear.
	ALPHA = smoothstep(0.32, 0.62, n) * smoothstep(150.0, 240.0, dist) * (1.0 - smoothstep(420.0, 640.0, dist)) * 0.95;
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

## The Underglow: a sea of luminous mist far below, veined with glowing rivers.
const UNDERGLOW_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float night = 0.0;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = wp.xz * 0.003;
	float n1 = texture(noise_tex, uv + vec2(TIME * 0.003, TIME * 0.0015)).r;
	float n2 = texture(noise_tex, uv * 2.3 - vec2(TIME * 0.004, -TIME * 0.002)).r;
	float mask = texture(noise_tex, uv * 0.6 + vec2(0.37, 0.11)).r;
	float n = n1 * 0.65 + n2 * 0.35;
	float breathe = 0.65 + 0.35 * sin(TIME * 0.7 + n * 16.0);
	// Thin glowing rivers that wander through dark mist, only in some places.
	float river = (1.0 - smoothstep(0.0, 0.012, abs(n - 0.5))) * smoothstep(0.42, 0.6, mask);
	float river2 = (1.0 - smoothstep(0.0, 0.008, abs(n2 - 0.56))) * smoothstep(0.55, 0.7, 1.0 - mask);
	float pools = smoothstep(0.62, 0.8, n1) * 0.5;
	vec3 deep = vec3(0.004, 0.008, 0.03);
	vec3 mist = mix(vec3(0.01, 0.06, 0.12), vec3(0.06, 0.02, 0.12), n2);
	vec3 col = mix(deep, mist, smoothstep(0.35, 0.75, n));
	col += vec3(0.1, 0.9, 1.0) * pools * 0.35;
	col += vec3(0.25, 2.4, 2.2) * river * breathe;
	col += vec3(1.6, 0.4, 1.4) * river2 * breathe;
	float d = length(wp.xz - vec2(0.0, -50.0));
	col *= (1.0 - smoothstep(220.0, 700.0, d) * 0.85) * (0.8 + 0.5 * night);
	ALBEDO = col;
}
"""

const MIST_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.25, 0.7, 0.9);
uniform float strength = 0.35;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = texture(noise_tex, wp.xz * 0.006 + vec2(TIME * 0.006, 0.0)).r;
	n *= texture(noise_tex, wp.xz * 0.017 - vec2(0.0, TIME * 0.009)).r * 1.6;
	float d = length(wp.xz - vec2(0.0, -50.0));
	float a = smoothstep(0.25, 0.75, n) * (1.0 - smoothstep(200.0, 600.0, d)) * strength;
	ALBEDO = tint * a;
	ALPHA = a;
}
"""

const CRYSTAL_SHADER := """
shader_type spatial;
render_mode unshaded;
uniform vec3 col_a : source_color = vec3(0.2, 0.95, 1.0);
uniform vec3 col_b : source_color = vec3(0.55, 0.2, 1.0);
instance uniform float height = 30.0;
varying float h;
void vertex() {
	h = VERTEX.y;
}
void fragment() {
	float k = clamp(h / height + 0.5, 0.0, 1.0);
	float fr = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	vec3 c = mix(col_b, col_a, k);
	float pulse = 0.85 + 0.15 * sin(TIME * 1.3 + h * 0.3);
	ALBEDO = c * (0.12 + 0.7 * fr + 1.6 * pow(k, 4.0)) * pulse;
}
"""

var nav_region: NavigationRegion3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var uplight: DirectionalLight3D
var cloud_mats: Array = []
var grass_mat: ShaderMaterial
var flower_mat: ShaderMaterial
var vine_mat: ShaderMaterial
var water_mats: Array = []
var underglow_mat: ShaderMaterial
var glow_mats: Array = [] # [material, day energy, night energy]
var lamp_lights: Array = []
var fireflies: GPUParticles3D
var shrines: Array = []
var shrine_radius := SHRINE_MAX_RADIUS
var gate_pos := Vector3.ZERO
var gate_mat: ShaderMaterial
var gate_light: OmniLight3D
var gate_ring: MeshInstance3D
var beacon_mat: StandardMaterial3D
var gate_open := false
var obstacles: Array = [] # [Vector2 xz, radius]
var floaters: Array = [] # [node, base y, phase, amplitude]
var jellies: Array = [] # [node, orbit radius, angle, speed, base y, phase]
var bridges: Array = [] # see _build_bridges
var bridge_angles := {} # island -> Array of angles (radians) where bridges leave it
var waterfalls: Array = [] # lip positions, for sound
var pools: Array = [] # [Vector3 pos, radius] of water on island tops
var pond_pos := Vector3.ZERO
var lights_out_mode := false
var _night := 0.0
var _t := 0.0

var _noise_tex: NoiseTexture2D
var _stone: StandardMaterial3D
var _stone_top: StandardMaterial3D
var _dark: StandardMaterial3D
var _marble: StandardMaterial3D
var _trunk: StandardMaterial3D
var _water: StandardMaterial3D
var _canopies: Array = []
var _orb_mat: StandardMaterial3D
var _rune_mat: StandardMaterial3D
var _lamp_bulb: StandardMaterial3D
var _under_crystal: StandardMaterial3D
var _amber: StandardMaterial3D
var _vine_xf: Array = []
var _vine_cols: Array = []
var _flower_xf: Array = []
var _flower_cols: Array = []
const FLOWER_PALETTE := [Color(0.3, 0.9, 1.0), Color(1.0, 0.4, 0.8), Color(1.0, 0.8, 0.35), Color(0.65, 0.45, 1.0), Color(1.0, 0.55, 0.45)]


func build() -> void:
	_make_materials()
	_build_environment()
	nav_region = NavigationRegion3D.new()
	add_child(nav_region)
	_plan_bridges()
	_build_islands()
	_build_bridges()
	_build_gate()
	_build_shrines()
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


func island_center(i: int) -> Vector3:
	return Vector3(float(ISLANDS[i][1]), float(ISLANDS[i][3]), float(ISLANDS[i][2]))


func island_radius(i: int) -> float:
	return float(ISLANDS[i][4])


func island_name(i: int) -> String:
	return String(ISLANDS[i][0])


func is_clear(p: Vector3, rad: float) -> bool:
	var q := Vector2(p.x, p.z)
	for o in obstacles:
		if q.distance_to(o[0]) < float(o[1]) + rad:
			return false
	return true


## Smallest angular distance (degrees) from `ang` to any bridge leaving island i.
func _bridge_clearance(i: int, ang: float) -> float:
	var best := 180.0
	for b in bridge_angles.get(i, []):
		best = minf(best, absf(rad_to_deg(angle_difference(ang, float(b)))))
	return best


func island_point(i: int, margin := 1.5, clear := 1.0):
	var c := island_center(i)
	var r := island_radius(i) - margin
	for attempt in 40:
		var rr := sqrt(randf()) * r
		var a := randf() * TAU
		var p := c + Vector3(cos(a) * rr, 0.0, sin(a) * rr)
		if not is_clear(p, clear):
			continue
		if _in_pool(p, 0.6):
			continue
		return p
	return null


func _in_pool(p: Vector3, pad: float) -> bool:
	for pl in pools:
		var c: Vector3 = pl[0]
		if Vector2(p.x - c.x, p.z - c.z).length() < float(pl[1]) + pad and absf(p.y - c.y) < 2.0:
			return true
	return false


# ---------------------------------------------------------------- queries

func ground_at(p: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, 40.0, p.z), Vector3(p.x, -40.0, p.z), LAYER_TERRAIN)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -50.0
	return hit.position.y


## Is there something to stand on at p, between a little above and `depth` below feet_y?
func has_ground(p: Vector3, feet_y: float, depth := 1.6) -> bool:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, feet_y + 1.3, p.z), Vector3(p.x, feet_y - depth, p.z), LAYER_TERRAIN)
	return not space.intersect_ray(q).is_empty()


func island_at(p: Vector3) -> int:
	for i in ISLANDS.size():
		var c := island_center(i)
		if Vector2(p.x - c.x, p.z - c.z).length() < island_radius(i) + 0.4 and p.y > c.y - 3.0 and p.y < c.y + 5.0:
			return i
	return -1


## Index of the bridge whose stones p is on or right next to (-1 if none).
func bridge_at(p: Vector3, pad := 0.6) -> int:
	for bi in bridges.size():
		var b: Dictionary = bridges[bi]
		for k in b["stones"].size():
			var s: Vector3 = b["stones"][k]
			if Vector2(p.x - s.x, p.z - s.z).length() < float(b["radii"][k]) + pad and absf(p.y - s.y) < 3.0:
				return bi
	return -1


## How far p is from a bridge's line (flat), and where along it (0..1).
func bridge_line_info(bi: int, p: Vector3) -> Vector2:
	var b: Dictionary = bridges[bi]
	var a: Vector3 = b["start"]
	var e: Vector3 = b["end"]
	var ab := Vector2(e.x - a.x, e.z - a.z)
	var ap := Vector2(p.x - a.x, p.z - a.z)
	var t := clampf(ap.dot(ab) / ab.length_squared(), 0.0, 1.0)
	var closest := ab * t
	return Vector2(ap.distance_to(closest), t)


func place_name(p: Vector3) -> String:
	var i := island_at(p)
	if i >= 0:
		return island_name(i)
	var bi := bridge_at(p, 2.0)
	if bi >= 0:
		return "the stones to %s" % island_name(int(bridges[bi]["b"]))
	return "the sky"


func _pick_island(include_gate: bool) -> int:
	var total := 0.0
	var w: Array = []
	for i in ISLANDS.size():
		var x := island_radius(i) * island_radius(i)
		if i == GATE_ISLAND:
			x *= 0.35 if include_gate else 0.0
		w.append(x)
		total += x
	var r := randf() * total
	for i in w.size():
		r -= float(w[i])
		if r <= 0.0:
			return i
	return 0


func random_island_point(i := -1, margin := 1.5, clear := 1.0):
	for attempt in 6:
		var isl := i if i >= 0 else _pick_island(true)
		var p = island_point(isl, margin, clear)
		if p != null:
			return p
	return null


## Somewhere to put a bloom or tool: mostly on islands, sometimes out on a stone.
func random_item_point():
	if randf() < 0.15 and not bridges.is_empty():
		var b: Dictionary = bridges.pick_random()
		var s: Vector3 = b["stones"].pick_random()
		return s
	return random_island_point(-1, 1.5, 1.2)


func random_walk_point() -> Vector3:
	var p = random_island_point(_pick_island(false), 2.0, 1.0)
	if p == null:
		return island_center(START_ISLAND) + Vector3(5, 0, 0)
	return p


## Where a bright pilgrim waits for the gate: around the gate, spread out.
func gate_wait_point(seed_id: int) -> Vector3:
	var a := float(seed_id % 8) / 8.0 * TAU
	var c := island_center(GATE_ISLAND)
	return c + Vector3(cos(a), 0.0, sin(a)) * 6.0


func shrine_protects(p: Vector3) -> bool:
	if shrine_radius <= 0.3:
		return false
	for s in shrines:
		var c: Vector3 = s["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < shrine_radius - 0.3 and absf(p.y - c.y) < 3.0:
			return true
	return false


func in_any_shrine(p: Vector3, pad := 0.0) -> bool:
	if shrine_radius <= 0.05:
		return false
	for s in shrines:
		var c: Vector3 = s["pos"]
		if Vector2(p.x - c.x, p.z - c.z).length() < shrine_radius + pad and absf(p.y - c.y) < 4.0:
			return true
	return false


func push_out_of_shrines(p: Vector3, pad: float) -> Vector3:
	if shrine_radius <= 0.05:
		return p
	for s in shrines:
		var c: Vector3 = s["pos"]
		if absf(p.y - c.y) > 5.0:
			continue
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
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.008
	fn.fractal_octaves = 4
	_noise_tex.noise = fn
	_stone = _mat(Color(0.6, 0.54, 0.57), 0.95)
	_stone_top = _mat(Color(0.55, 0.58, 0.52), 0.95)
	_dark = _mat(Color(0.3, 0.25, 0.32), 1.0)
	_marble = _mat(Color(0.93, 0.9, 0.85), 0.5)
	_trunk = _mat(Color(0.3, 0.22, 0.25), 0.9)
	_water = _mat(Color(0.05, 0.12, 0.17), 0.03)
	_water.metallic = 0.3
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
	_under_crystal = _mat(Color(0.5, 0.95, 1.0), 0.3, Color(0.3, 0.9, 1.0), 2.0)
	glow_mats.append([_under_crystal, 2.0, 6.0])
	_amber = _mat(Color(1.0, 0.65, 0.3), 0.25, Color(1.0, 0.5, 0.15), 1.5)
	glow_mats.append([_amber, 1.5, 4.5])


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
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.1
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0018
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.light_volumetric_fog_energy = 1.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)
	# Light from the Underglow below: paints the undersides of islands teal.
	uplight = DirectionalLight3D.new()
	uplight.rotation = Vector3(PI / 2.0, 0.0, 0.0)
	uplight.light_color = Color(0.35, 0.85, 1.0)
	uplight.light_energy = 0.3
	uplight.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(uplight)


func _plan_bridges() -> void:
	for b in BRIDGES:
		var ia: int = b[0]
		var ib: int = b[1]
		var A := island_center(ia)
		var B := island_center(ib)
		var ang_a := atan2(B.z - A.z, B.x - A.x)
		var ang_b := atan2(A.z - B.z, A.x - B.x)
		if not bridge_angles.has(ia):
			bridge_angles[ia] = []
		if not bridge_angles.has(ib):
			bridge_angles[ib] = []
		bridge_angles[ia].append(ang_a)
		bridge_angles[ib].append(ang_b)
		for pair in [[A, ang_a, island_radius(ia)], [B, ang_b, island_radius(ib)]]:
			var c: Vector3 = pair[0]
			var a: float = pair[1]
			var r: float = pair[2]
			obstacles.append([Vector2(c.x + cos(a) * (r - 2.0), c.z + sin(a) * (r - 2.0)), 2.6])
	# Keep the spawn ring and the middle of the meadow open.
	var c0 := island_center(START_ISLAND)
	for k in 10:
		var a := TAU * float(k) / 10.0 + PI / 2.0
		obstacles.append([Vector2(c0.x + cos(a) * SPAWN_RING, c0.z + sin(a) * SPAWN_RING), 2.2])
	obstacles.append([Vector2(c0.x, c0.z), 4.5])


func _build_islands() -> void:
	var grass_cap := _mat(Color(0.2, 0.36, 0.3), 0.95)
	for i in ISLANDS.size():
		var c := island_center(i)
		var r := island_radius(i)
		var body := CylinderMesh.new()
		body.top_radius = r
		body.bottom_radius = r * 0.93
		body.height = 3.0
		body.radial_segments = 64
		body.rings = 1
		_mesh(self, body, _stone, c - Vector3(0, 1.5, 0))
		var cap := CylinderMesh.new()
		cap.top_radius = r - 0.12
		cap.bottom_radius = r - 0.12
		cap.height = 0.1
		cap.radial_segments = 64
		_mesh(self, cap, grass_cap, c - Vector3(0, 0.03, 0))
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = 3.0
		_static(shape, c - Vector3(0, 1.5, 0), LAYER_TERRAIN)
		# The rocky root that the island floats on.
		var rh := r * 1.4
		var root := CylinderMesh.new()
		root.top_radius = r * 0.93
		root.bottom_radius = r * 0.1
		root.height = rh
		root.radial_segments = 14
		root.rings = 4
		_mesh(self, root, _dark, c - Vector3(0, 3.0 + rh * 0.5, 0), Vector3(0, randf() * TAU, 0))
		for k in int(r / 2.5) + 2:
			var a := randf() * TAU
			var rr := randf_range(r * 0.25, r * 0.75)
			var sz := randf_range(1.5, r * 0.28)
			var cone := CylinderMesh.new()
			cone.top_radius = sz
			cone.bottom_radius = 0.15
			cone.height = sz * 3.0
			cone.radial_segments = 7
			_mesh(self, cone, _dark, c + Vector3(cos(a) * rr, -3.0 - sz * 1.5 - randf() * r * 0.3, sin(a) * rr))
		# Glowing crystals hang from the underside.
		for k in 5:
			var a := randf() * TAU
			var rr := randf_range(r * 0.2, r * 0.6)
			var h := randf_range(1.0, 2.6)
			var cr := CylinderMesh.new()
			cr.top_radius = randf_range(0.2, 0.4)
			cr.bottom_radius = 0.02
			cr.height = h
			cr.radial_segments = 5
			cr.rings = 1
			var y := -3.0 - (1.0 - rr / r) * rh * 0.55 - h * 0.5
			_mesh(self, cr, _under_crystal, c + Vector3(cos(a) * rr, y, sin(a) * rr), Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
		# A few pebbles drift around the island.
		for k in 4:
			var a := randf() * TAU
			var rr := r + randf_range(4.0, 9.0)
			var sm := SphereMesh.new()
			var s := randf_range(0.3, 0.9)
			sm.radius = s
			sm.height = s * 1.4
			sm.radial_segments = 7
			sm.rings = 4
			var node := _mesh(self, sm, _dark, c + Vector3(cos(a) * rr, randf_range(-9.0, -3.0), sin(a) * rr), Vector3(randf(), randf(), randf()))
			floaters.append([node, node.position.y, randf() * TAU, 0.7])


func _build_bridges() -> void:
	for bi in BRIDGES.size():
		var ia: int = BRIDGES[bi][0]
		var ib: int = BRIDGES[bi][1]
		var A := island_center(ia)
		var B := island_center(ib)
		var ra := island_radius(ia)
		var rb := island_radius(ib)
		var flat := Vector3(B.x - A.x, 0, B.z - A.z)
		var dist := flat.length()
		var dir := flat / dist
		var perp := Vector3(-dir.z, 0, dir.x)
		var L := dist - ra - rb
		var n := maxi(1, roundi((L - STONE_GAP) / (2.8 + STONE_GAP)))
		var radii: Array = []
		var total := 0.0
		for s in n:
			var rr := randf_range(1.2, 1.6)
			radii.append(rr)
			total += rr * 2.0
		var gap := (L - total) / float(n + 1)
		var rune := _mat(RUNE_COL, 0.4, RUNE_COL, 0.8)
		var stones: Array = []
		var along := ra
		var prev_y := A.y
		var phase := randf() * TAU
		var amp := randf_range(1.0, 1.7)
		for s in n:
			var rad: float = radii[s]
			along += gap + rad
			# Rise and fall from stone to stone, but never more than one jump can climb,
			# and always able to reach the far island.
			var hops_left := n - s
			var lo := maxf(prev_y - MAX_STEP, B.y - MAX_STEP * hops_left)
			var hi := minf(prev_y + MAX_STEP, B.y + MAX_STEP * hops_left)
			if lo > hi + 0.01:
				push_warning("bridge %d cannot keep steps small" % bi)
			var want := lerpf(A.y, B.y, float(s + 1) / float(n + 1)) + sin(float(s) * 1.9 + phase) * amp + randf_range(-0.3, 0.3)
			var y := clampf(want, lo, hi)
			prev_y = y
			var p := A + dir * along + perp * randf_range(-0.35, 0.35)
			p.y = y
			_build_stone(p, rad, rune)
			stones.append(p)
			along += rad
		var head_a := A + dir * (ra - 1.3)
		var head_b := B - dir * (rb - 1.3)
		var chain: Array = [head_a]
		chain.append_array(stones)
		chain.append(head_b)
		for j in chain.size() - 1:
			var link := NavigationLink3D.new()
			link.bidirectional = true
			link.start_position = chain[j]
			link.end_position = chain[j + 1]
			add_child(link)
		_lamp(A + dir * (ra - 0.7) + perp * 1.9)
		_lamp(B - dir * (rb - 0.7) - perp * 1.9)
		bridges.append({
			"a": ia, "b": ib, "stones": stones, "radii": radii, "rune": rune, "warn": 0.0,
			"dir": dir, "perp": perp, "start": A + dir * ra, "end": B - dir * rb,
		})


func _build_stone(p: Vector3, r: float, rune: Material) -> void:
	var top := CylinderMesh.new()
	top.top_radius = r
	top.bottom_radius = r * 0.82
	top.height = STONE_H
	top.radial_segments = 9
	top.rings = 1
	_mesh(self, top, _stone_top, p - Vector3(0, STONE_H * 0.5, 0), Vector3(0, randf() * TAU, 0))
	var hh := randf_range(1.8, 3.4)
	var under := CylinderMesh.new()
	under.top_radius = r * 0.82
	under.bottom_radius = 0.08
	under.height = hh
	under.radial_segments = 7
	under.rings = 1
	_mesh(self, under, _dark, p - Vector3(0, STONE_H + hh * 0.5, 0), Vector3(0, randf() * TAU, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = r - 0.3
	ring.outer_radius = r - 0.14
	ring.rings = 24
	ring.ring_segments = 4
	var rm := _mesh(self, ring, rune, p, Vector3.ZERO, Vector3(1, 0.25, 1))
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A few strands of hanging garden under most stones.
	if randf() < 0.7:
		for k in randi_range(1, 3):
			var a := randf() * TAU
			_add_vine(p + Vector3(cos(a) * r * 0.9, -0.15, sin(a) * r * 0.9), a, randf_range(0.6, 1.0), randf_range(1.2, 3.0))
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = STONE_H
	_static(shape, p - Vector3(0, STONE_H * 0.5, 0), LAYER_TERRAIN)


func _lamp(pos: Vector3) -> void:
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
	l.omni_range = 7.0
	l.position = pos + Vector3(0, 1.9, 0)
	add_child(l)
	lamp_lights.append(l)


func _build_gate() -> void:
	var c := island_center(GATE_ISLAND)
	var top := c.y
	gate_pos = c
	var gold := _mat(Color(0.95, 0.72, 0.32), 0.3, Color(1.0, 0.68, 0.3), 1.2)
	gold.metallic = 0.8
	glow_mats.append([gold, 1.2, 3.0])
	var plinth := CylinderMesh.new()
	plinth.top_radius = 3.4
	plinth.bottom_radius = 3.6
	plinth.height = 0.1
	plinth.radial_segments = 48
	_mesh(self, plinth, _marble, c + Vector3(0, 0.02, 0))
	for sx in [-1.0, 1.0]:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 5.0, 0.7)
		var pp := c + Vector3(1.95 * float(sx), 2.5, 0)
		_mesh(self, bm, _marble, pp)
		var sh := BoxShape3D.new()
		sh.size = bm.size
		_static(sh, pp, LAYER_OBSTACLE)
	var lintel := BoxMesh.new()
	lintel.size = Vector3(4.9, 0.45, 0.9)
	_mesh(self, lintel, _marble, c + Vector3(0, 5.1, 0))
	var tm := TorusMesh.new()
	tm.inner_radius = 1.9
	tm.outer_radius = 2.35
	tm.rings = 48
	tm.ring_segments = 12
	gate_ring = _mesh(self, tm, gold, c + Vector3(0, 7.0, 0), Vector3(PI / 2.0, 0, 0))
	gate_mat = _shader_mat(PORTAL_SHADER)
	var q := QuadMesh.new()
	q.size = Vector2(3.2, 4.85)
	_mesh(self, q, gate_mat, c + Vector3(0, 2.45, 0))
	gate_light = OmniLight3D.new()
	gate_light.light_color = Color(1.0, 0.75, 0.4)
	gate_light.light_energy = 0.6
	gate_light.omni_range = 12.0
	gate_light.position = c + Vector3(0, 3.0, 0)
	add_child(gate_light)
	obstacles.append([Vector2(c.x, c.z), 3.4])
	# A faint pillar of light over the gate: you can always see where the way out is.
	var cm := CylinderMesh.new()
	cm.top_radius = 2.5
	cm.bottom_radius = 0.9
	cm.height = 260.0
	cm.radial_segments = 20
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	beacon_mat = StandardMaterial3D.new()
	beacon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beacon_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	beacon_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	beacon_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beacon_mat.albedo_color = Color(1.0, 0.75, 0.4, 0.07)
	var beam := _mesh(self, cm, beacon_mat, c + Vector3(0, 138.0, 0))
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Colonnade around the gate.
	for k in 10:
		var a := TAU * float(k) / 10.0 + 0.15
		if _bridge_clearance(GATE_ISLAND, a) < 22.0:
			continue
		_column(c + Vector3(cos(a) * 8.5, 0, sin(a) * 8.5), 3.8, true)


func _build_shrines() -> void:
	for spot in SHRINE_SPOTS:
		var p := island_center(int(spot[0])) + Vector3(float(spot[1]), 0, float(spot[2]))
		var base := BoxMesh.new()
		base.size = Vector3(1.4, 0.4, 1.4)
		_mesh(self, base, _stone, p + Vector3(0, 0.2, 0))
		var pillar := BoxMesh.new()
		pillar.size = Vector3(0.45, 1.7, 0.45)
		_mesh(self, pillar, _stone, p + Vector3(0, 1.25, 0))
		var house := BoxMesh.new()
		house.size = Vector3(0.85, 0.65, 0.85)
		_mesh(self, house, _stone, p + Vector3(0, 2.4, 0))
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


func _pond(center: Vector3, radius: float) -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.06
	disc.radial_segments = 40
	_mesh(self, disc, _water, center + Vector3(0, 0.06, 0))
	var rim := TorusMesh.new()
	rim.inner_radius = radius - 0.1
	rim.outer_radius = radius + 0.4
	rim.rings = 40
	_mesh(self, rim, _marble, center + Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	var pad_mat := _mat(Color(0.2, 0.45, 0.3), 0.7)
	var bud_mat := _mat(Color(1.0, 0.7, 0.85), 0.4, Color(1.0, 0.45, 0.7), 2.0)
	glow_mats.append([bud_mat, 1.0, 5.0])
	for k in int(radius * 2.5):
		var pa := randf() * TAU
		var pr := randf_range(0.5, radius - 0.5)
		var pos := center + Vector3(cos(pa) * pr, 0.1, sin(pa) * pr)
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
	obstacles.append([Vector2(center.x, center.z), radius + 0.5])
	pools.append([center, radius])


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


func _amber_cluster(p: Vector3) -> void:
	for k in randi_range(3, 5):
		var h := randf_range(0.8, 2.6)
		var cr := CylinderMesh.new()
		cr.top_radius = 0.02
		cr.bottom_radius = randf_range(0.2, 0.45)
		cr.height = h
		cr.radial_segments = 6
		cr.rings = 1
		var off := Vector3(randf_range(-0.6, 0.6), h * 0.4, randf_range(-0.6, 0.6))
		_mesh(self, cr, _amber, p + off, Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 0.8
	l.omni_range = 5.0
	l.position = p + Vector3(0, 1.2, 0)
	add_child(l)
	lamp_lights.append(l)
	var shp := CylinderShape3D.new()
	shp.radius = 0.8
	shp.height = 2.0
	_static(shp, p + Vector3(0, 1.0, 0), LAYER_OBSTACLE)
	obstacles.append([Vector2(p.x, p.z), 1.3])


func _trees_on(i: int, count: int, min_r := 0.0) -> void:
	var c := island_center(i)
	for k in count:
		for attempt in 12:
			var p = island_point(i, 2.2, 2.6)
			if p == null:
				break
			var q: Vector3 = p
			if Vector2(q.x - c.x, q.z - c.z).length() < min_r:
				continue
			make_tree(self, q, randf_range(0.85, 1.35), true)
			break


func _build_island_features() -> void:
	# Dawn Meadow: open middle, trees around the rim, a few old columns.
	_trees_on(START_ISLAND, 7, 15.0)
	for k in 3:
		var p = island_point(START_ISLAND, 3.0, 2.0)
		if p != null:
			_column(p, randf_range(1.2, 3.6), randf() < 0.5)
	# Lantern Grove: dense blossom trees.
	_trees_on(1, 10)
	# Ember Rocks: glowing amber crystals and ruins.
	for k in 5:
		var p = island_point(2, 2.0, 2.0)
		if p != null:
			_amber_cluster(p)
	for k in 2:
		var p = island_point(2, 2.0, 2.0)
		if p != null:
			_column(p, randf_range(1.0, 3.0), false)
	# Mirror Pond.
	pond_pos = island_center(3) + Vector3(-4.0, 0, 3.0)
	_pond(pond_pos, POND_RADIUS)
	_trees_on(3, 4)
	# Bell Ruins.
	for k in 8:
		var p = island_point(4, 1.8, 1.8)
		if p != null:
			_column(p, randf_range(1.0, 4.2), randf() < 0.4)
	_trees_on(4, 2)
	# Heart Rock: two amber spires either side of the path.
	var hc := island_center(HEART_ISLAND)
	_amber_cluster(hc + Vector3(4.0, 0, 0))
	_amber_cluster(hc + Vector3(-4.0, 0, 0))
	# Sun Gate Isle.
	_trees_on(GATE_ISLAND, 2)


func _build_waterfalls() -> void:
	for wf in WATERFALLS:
		var i: int = wf[0]
		var c := island_center(i)
		var r := island_radius(i)
		var placed: Array = []
		for n in int(wf[1]):
			var best_a := 0.0
			var best_s := -1.0
			for attempt in 40:
				var a := randf() * TAU
				if i == 3:
					# Mirror Pond's pond spills over the nearest edge.
					a = atan2(pond_pos.z - c.z, pond_pos.x - c.x) + randf_range(-0.25, 0.25)
				var s := _bridge_clearance(i, a)
				for pa in placed:
					s = minf(s, absf(rad_to_deg(angle_difference(a, float(pa)))))
				if s > best_s:
					best_s = s
					best_a = a
			placed.append(best_a)
			_waterfall(i, best_a)


func _waterfall(i: int, a: float) -> void:
	var c := island_center(i)
	var r := island_radius(i)
	var dir := Vector3(cos(a), 0, sin(a))
	var lip := c + dir * (r - 0.05)
	var root := Node3D.new()
	root.position = lip
	root.rotation.y = atan2(dir.x, dir.z)
	add_child(root)
	var fall_len := 75.0
	var m := _shader_mat(WATERFALL_SHADER)
	m.set_shader_parameter("noise_tex", _noise_tex)
	m.set_shader_parameter("fall_len", fall_len)
	m.render_priority = 1
	water_mats.append(m)
	var pm := PlaneMesh.new()
	pm.orientation = PlaneMesh.FACE_Z
	pm.size = Vector2(2.2, fall_len)
	pm.subdivide_depth = 40
	pm.subdivide_width = 2
	pm.center_offset = Vector3(0, -fall_len * 0.5, 0)
	var wmi := _mesh(root, pm, m, Vector3(0, 0.02, 0))
	wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wmi.extra_cull_margin = 40.0
	# The spring: a little pool feeding a stream to the edge, rocks either side.
	if i != 3:
		var pool_c := c + dir * (r - 3.4)
		_pond(pool_c, 1.5)
	var stream := PlaneMesh.new()
	stream.size = Vector2(1.4, 2.4 if i != 3 else maxf(0.5, r - 0.2 - (pond_pos - c).length() - POND_RADIUS))
	var slen: float = stream.size.y
	var smi := _mesh(root, stream, _water, Vector3(0, 0.07, -slen * 0.5))
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		var rock := SphereMesh.new()
		rock.radius = 0.55
		rock.height = 0.8
		rock.radial_segments = 8
		rock.rings = 4
		_mesh(root, rock, _stone, Vector3(1.25 * float(sx), 0.15, -0.4), Vector3(0, randf(), 0), Vector3(1.0, 0.8, 1.3))
	# Spray drifting off the lip.
	var spray := GPUParticles3D.new()
	spray.amount = 40
	spray.lifetime = 2.5
	spray.preprocess = 2.5
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ppm.emission_box_extents = Vector3(1.0, 0.2, 0.2)
	ppm.direction = Vector3(0, -1, 1)
	ppm.spread = 25.0
	ppm.initial_velocity_min = 1.0
	ppm.initial_velocity_max = 2.5
	ppm.gravity = Vector3(0, -2.0, 0)
	ppm.scale_min = 1.0
	ppm.scale_max = 2.5
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 0.35), Color(1, 1, 1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	ppm.color_ramp = gt
	spray.process_material = ppm
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 6
	sm.rings = 3
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color(0.85, 0.95, 1.0)
	sm.material = smat
	spray.draw_pass_1 = sm
	spray.position = Vector3(0, -0.6, 0.5)
	root.add_child(spray)
	waterfalls.append(lip)


func _add_vine(top: Vector3, ang: float, width: float, length: float) -> void:
	var b := Basis(Vector3.UP, atan2(cos(ang), sin(ang))).scaled(Vector3(width, length, 1.0))
	_vine_xf.append(Transform3D(b, top))
	var col: Color = FLOWER_PALETTE.pick_random()
	_vine_cols.append(col.lerp(Color.WHITE, randf() * 0.2))


func _build_hanging_gardens() -> void:
	for i in ISLANDS.size():
		var c := island_center(i)
		var r := island_radius(i)
		var steps := int(TAU * r / 0.85)
		for k in steps:
			var a := TAU * float(k) / float(steps) + randf_range(-0.02, 0.02)
			if randf() < 0.22:
				continue
			var near_fall := false
			for w in waterfalls:
				var wp: Vector3 = w
				if Vector2(c.x + cos(a) * r - wp.x, c.z + sin(a) * r - wp.z).length() < 2.0:
					near_fall = true
			if near_fall:
				continue
			var length := randf_range(2.0, 7.5)
			if randf() < 0.15:
				length = randf_range(9.0, 14.0)
			_add_vine(c + Vector3(cos(a) * (r + 0.03), -0.05, sin(a) * (r + 0.03)), a, randf_range(0.9, 1.6), length)
			# Flowers spill over the rim.
			if randf() < 0.6:
				for f in 3:
					var fr := r - randf_range(0.15, 0.7)
					var fa := a + randf_range(-0.03, 0.03)
					_flower_xf.append(Transform3D(Basis().scaled(Vector3.ONE * randf_range(0.8, 1.4)), c + Vector3(cos(fa) * fr, randf_range(0.25, 0.45), sin(fa) * fr)))
					_flower_cols.append(_vine_cols[-1])
		# Garden ledges on the cliff: little terraces of bushes with more vines.
		for k in int(r / 4.0) + 1:
			var a := randf() * TAU
			if _bridge_clearance(i, a) < 25.0:
				continue
			var dir := Vector3(cos(a), 0, sin(a))
			var p := c + dir * (r * 0.92) + Vector3(0, -randf_range(3.5, 5.5), 0)
			var shelf := CylinderMesh.new()
			shelf.top_radius = 1.4
			shelf.bottom_radius = 0.9
			shelf.height = 0.5
			shelf.radial_segments = 10
			_mesh(self, shelf, _stone, p)
			for b in 3:
				var sm := SphereMesh.new()
				var br := randf_range(0.45, 0.8)
				sm.radius = br
				sm.height = br * 1.4
				sm.radial_segments = 10
				sm.rings = 5
				_mesh(self, sm, _canopies.pick_random(), p + Vector3(randf_range(-0.7, 0.7), 0.4 + br * 0.4, randf_range(-0.7, 0.7)))
			for v in 4:
				var va := a + randf_range(-0.9, 0.9)
				_add_vine(p + Vector3(cos(va) * 1.3, 0.2, sin(va) * 1.3), va, randf_range(0.8, 1.2), randf_range(2.5, 6.0))
	vine_mat = _shader_mat(VINE_SHADER)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.center_offset = Vector3(0, -0.5, 0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = _vine_xf.size()
	for k in _vine_xf.size():
		mm.set_instance_transform(k, _vine_xf[k])
		mm.set_instance_color(k, _vine_cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = vine_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


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
	for i in ISLANDS.size():
		var c := island_center(i)
		var r := island_radius(i)
		var target := int(r * r * 9.0)
		for k in target:
			var rr := sqrt(randf()) * (r - 0.3)
			var a := randf() * TAU
			var p := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			if _in_pool(p, 0.3):
				continue
			if i == GATE_ISLAND and rr < 3.7:
				continue
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
	for k in xf.size():
		mm.set_instance_transform(k, xf[k])
		mm.set_instance_color(k, cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_flowers() -> void:
	flower_mat = _shader_mat(FLOWER_SHADER)
	for i in ISLANDS.size():
		var clusters := int(island_radius(i) * island_radius(i) / 20.0) + 2
		for k in clusters:
			var center = island_point(i, 1.0, 0.5)
			if center == null:
				continue
			var col: Color = FLOWER_PALETTE.pick_random()
			for f in randi_range(8, 20):
				var p: Vector3 = center + Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
				if island_at(p) != i or _in_pool(p, 0.2):
					continue
				p.y += randf_range(0.3, 0.55)
				_flower_xf.append(Transform3D(Basis().scaled(Vector3.ONE * randf_range(0.7, 1.3)), p))
				_flower_cols.append(col.lerp(Color.WHITE, randf() * 0.25))
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	sm.radial_segments = 8
	sm.rings = 4
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = sm
	mm.instance_count = _flower_xf.size()
	for k in _flower_xf.size():
		mm.set_instance_transform(k, _flower_xf[k])
		mm.set_instance_color(k, _flower_cols[k])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = flower_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _build_fireflies() -> void:
	fireflies = GPUParticles3D.new()
	fireflies.amount = 380
	fireflies.lifetime = 8.0
	fireflies.preprocess = 8.0
	fireflies.visibility_aabb = AABB(Vector3(-80, -15, -90), Vector3(160, 40, 180))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(60, 5, 70)
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
	fireflies.position = CENTER + Vector3(0, 7, 0)
	add_child(fireflies)


## Blossom petals blowing across the gardens.
func _build_petals() -> void:
	var ps := GPUParticles3D.new()
	ps.amount = 260
	ps.lifetime = 14.0
	ps.preprocess = 14.0
	ps.visibility_aabb = AABB(Vector3(-100, -40, -100), Vector3(200, 70, 200))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(65, 6, 70)
	pm.direction = Vector3(1, 0, 0.4)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.0
	pm.gravity = Vector3(0, -0.35, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.5
	pm.turbulence_noise_scale = 5.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.85, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	ps.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.08)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.72, 0.85)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = Color(1.0, 0.5, 0.7)
	m.emission_energy_multiplier = 0.3
	q.material = m
	ps.draw_pass_1 = q
	ps.position = CENTER + Vector3(0, 9, 0)
	add_child(ps)


func _build_distant() -> void:
	var cap_mat := _mat(Color(0.25, 0.42, 0.32), 0.95)
	for i in 10:
		var a := TAU * i / 10.0 + randf_range(-0.25, 0.25)
		var dist := randf_range(170.0, 290.0)
		var y := randf_range(-25.0, 30.0)
		var root := Node3D.new()
		root.position = CENTER + Vector3(cos(a) * dist, y, sin(a) * dist)
		add_child(root)
		var size := randf_range(5.0, 14.0)
		var cone := CylinderMesh.new()
		cone.top_radius = size
		cone.bottom_radius = size * 0.12
		cone.height = size * 1.8
		cone.radial_segments = 10
		_mesh(root, cone, _dark, Vector3(0, -size * 0.9, 0))
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
		floaters.append([root, y, randf() * TAU, 1.2])


func _build_clouds() -> void:
	for layer in [[-38.0, 0.0025], [-47.0, 0.0034]]:
		var m := _shader_mat(CLOUD_SHADER)
		m.set_shader_parameter("noise_tex", _noise_tex)
		m.set_shader_parameter("scale", float(layer[1]))
		var pm := PlaneMesh.new()
		pm.size = Vector2(1300, 1300)
		var mi := _mesh(self, pm, m, Vector3(CENTER.x, float(layer[0]), CENTER.z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud_mats.append(m)


func _build_underworld() -> void:
	underglow_mat = _shader_mat(UNDERGLOW_SHADER)
	underglow_mat.set_shader_parameter("noise_tex", _noise_tex)
	var sea := PlaneMesh.new()
	sea.size = Vector2(1600, 1600)
	var smi := _mesh(self, sea, underglow_mat, Vector3(CENTER.x, UNDERWORLD_Y, CENTER.z))
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for layer in [[-60.0, Color(0.15, 0.6, 0.85), 0.16], [-50.0, Color(0.45, 0.25, 0.9), 0.08]]:
		var mm := _shader_mat(MIST_SHADER)
		mm.set_shader_parameter("noise_tex", _noise_tex)
		mm.set_shader_parameter("tint", layer[1])
		mm.set_shader_parameter("strength", layer[2])
		var pm := PlaneMesh.new()
		pm.size = Vector2(1200, 1200)
		var mi := _mesh(self, pm, mm, Vector3(CENTER.x, float(layer[0]), CENTER.z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Crystal spires rising out of the glow.
	var cmats: Array = []
	for pair in [[Color(0.2, 0.95, 1.0), Color(0.45, 0.2, 1.0)], [Color(1.0, 0.45, 0.85), Color(0.35, 0.15, 0.8)]]:
		var m := _shader_mat(CRYSTAL_SHADER)
		m.set_shader_parameter("col_a", pair[0])
		m.set_shader_parameter("col_b", pair[1])
		cmats.append(m)
	for k in 46:
		var a := randf() * TAU
		var d := randf_range(25.0, 260.0)
		var base := CENTER + Vector3(cos(a) * d, UNDERWORLD_Y - 6.0, sin(a) * d)
		for j in randi_range(1, 3):
			var h := randf_range(14.0, 42.0) * (1.0 if j == 0 else 0.55)
			var rad := randf_range(1.5, 4.5) * (1.0 if j == 0 else 0.6)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.0
			cm.bottom_radius = rad
			cm.height = h
			cm.radial_segments = 6
			cm.rings = 1
			var off := Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)) if j > 0 else Vector3.ZERO
			var mi := _mesh(self, cm, cmats.pick_random(), base + off + Vector3(0, h * 0.5, 0), Vector3(randf_range(-0.25, 0.25), randf() * TAU, randf_range(-0.25, 0.25)))
			mi.set_instance_shader_parameter("height", h)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lumen jellies drifting in the deep.
	var jm := StandardMaterial3D.new()
	jm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	jm.cull_mode = BaseMaterial3D.CULL_DISABLED
	jm.albedo_color = Color(0.35, 0.85, 1.0, 0.45)
	var jm2 := jm.duplicate()
	jm2.albedo_color = Color(1.0, 0.45, 0.85, 0.45)
	for k in 16:
		var root := Node3D.new()
		var s := randf_range(1.5, 4.5)
		var mat: Material = jm if randf() < 0.6 else jm2
		var dome := SphereMesh.new()
		dome.radius = 1.0
		dome.height = 1.0
		dome.is_hemisphere = true
		dome.radial_segments = 16
		dome.rings = 6
		_mesh(root, dome, mat, Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.8, 1))
		for t in 7:
			var ta := TAU * float(t) / 7.0
			var tl := randf_range(2.0, 4.0)
			var cm := CylinderMesh.new()
			cm.top_radius = 0.04
			cm.bottom_radius = 0.01
			cm.height = tl
			cm.radial_segments = 4
			cm.rings = 1
			_mesh(root, cm, mat, Vector3(cos(ta) * 0.6, -tl * 0.5, sin(ta) * 0.6))
		root.scale = Vector3.ONE * s
		add_child(root)
		var orbit := randf_range(30.0, 200.0)
		var ang := randf() * TAU
		var by := randf_range(-60.0, -34.0)
		root.position = CENTER + Vector3(cos(ang) * orbit, by, sin(ang) * orbit)
		jellies.append([root, orbit, ang, randf_range(0.004, 0.012) * (1.0 if randf() < 0.5 else -1.0), by, randf() * TAU])
	# Spores rising from the glow.
	var sp := GPUParticles3D.new()
	sp.amount = 800
	sp.lifetime = 16.0
	sp.preprocess = 16.0
	sp.visibility_aabb = AABB(Vector3(-200, -10, -200), Vector3(400, 70, 400))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(170, 2, 170)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 20.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, 0.05, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 9.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var cg := Gradient.new()
	cg.colors = PackedColorArray([Color(0.4, 2.2, 2.0), Color(2.0, 0.6, 1.6)])
	var cgt := GradientTexture1D.new()
	cgt.gradient = cg
	pm.color_initial_ramp = cgt
	var ag := Gradient.new()
	ag.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ag.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var agt := GradientTexture1D.new()
	agt.gradient = ag
	pm.color_ramp = agt
	sp.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.12
	dm.height = 0.24
	dm.radial_segments = 6
	dm.rings = 3
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true
	dm.material = fm
	sp.draw_pass_1 = dm
	sp.position = Vector3(CENTER.x, UNDERWORLD_Y + 3.0, CENTER.z)
	add_child(sp)


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
	nm.region_min_size = 0.5
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


# ---------------------------------------------------------------- runtime

func update_time(dusk: float) -> void:
	if lights_out_mode:
		return
	dusk = clampf(dusk, 0.0, 1.0)
	var night := smoothstep(0.5, 1.0, dusk)
	_night = night
	var elev := lerpf(22.0, -9.0, dusk)
	sun.rotation = Vector3(deg_to_rad(-elev), deg_to_rad(SUN_AZIMUTH), 0.0)
	var vis := smoothstep(-3.0, 8.0, elev)
	sun.light_energy = 1.35 * vis
	sun.visible = vis > 0.001
	sun.light_color = _tri_c(Color(1.0, 0.86, 0.68), Color(1.0, 0.55, 0.32), Color(0.9, 0.3, 0.2), dusk)
	moon.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(SUN_AZIMUTH + 150.0), 0.0)
	moon.light_energy = 0.45 * smoothstep(0.35, 0.9, dusk)
	uplight.light_energy = lerpf(0.25, 0.7, night)
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
	vine_mat.set_shader_parameter("night", night)
	underglow_mat.set_shader_parameter("night", night)
	for m in water_mats:
		m.set_shader_parameter("night", night)
	flower_mat.set_shader_parameter("glow", lerpf(0.5, 2.4, night))
	for g in glow_mats:
		g[0].emission_energy_multiplier = lerpf(float(g[1]), float(g[2]), night)
	for l in lamp_lights:
		l.light_energy = lerpf(0.3, 1.6, night)
	fireflies.amount_ratio = lerpf(0.15, 1.0, night)
	beacon_mat.albedo_color.a = lerpf(0.05, 0.12, night) * (2.2 if gate_open else 1.0)
	_update_runes()


## 0..1 warning glow on one bridge's stones (the Devourer is about to strike there).
func set_bridge_warning(bi: int, k: float) -> void:
	bridges[bi]["warn"] = k
	_update_runes()


func _update_runes() -> void:
	var pulse := 0.6 + 0.4 * sin(_t * 14.0)
	for b in bridges:
		var w: float = b["warn"]
		var m: StandardMaterial3D = b["rune"]
		m.emission = RUNE_COL.lerp(WARN_COL, w)
		m.albedo_color = RUNE_COL.lerp(WARN_COL, w)
		m.emission_energy_multiplier = lerpf(0.8, 4.0, _night) + w * 7.0 * pulse


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
	tw.tween_property(beacon_mat, "albedo_color:a", 0.0, 2.0)
	for s in shrines:
		tw.tween_property(s["light"], "light_energy", 0.0, 2.0)
	for l in lamp_lights:
		tw.tween_property(l, "light_energy", 0.0, 2.5)
	tw.tween_method(func(v: float): gate_mat.set_shader_parameter("open", v), 1.0 if gate_open else 0.1, 0.0, 2.0)


## A pillar of light from the Sun Gate into the sky whenever someone escapes.
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
		n.position.y = float(f[1]) + sin(_t * 0.35 + float(f[2])) * float(f[3])
	for j in jellies:
		var n: Node3D = j[0]
		j[2] = float(j[2]) + float(j[3]) * delta
		var ang: float = j[2]
		var orbit: float = j[1]
		var ph: float = j[5]
		n.position = CENTER + Vector3(cos(ang) * orbit, float(j[4]) + sin(_t * 0.4 + ph) * 2.0, sin(ang) * orbit)
		var pulse := 1.0 + 0.12 * sin(_t * 1.6 + ph)
		var base_s := n.scale.x / maxf(0.001, float(n.get_meta("pulse", 1.0)))
		n.set_meta("pulse", pulse)
		n.scale = Vector3.ONE * base_s * pulse
	if gate_ring:
		gate_ring.rotation.y = sin(_t * 0.4) * 0.15
	var warned := false
	for b in bridges:
		if float(b["warn"]) > 0.0:
			warned = true
	if warned:
		_update_runes()
