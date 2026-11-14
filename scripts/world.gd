extends Node3D
const Cfg = preload("res://scripts/cfg.gd")
## Builds the Sky Gardens: floating islands with hanging gardens and waterfalls, linked
## by stepping stones that rise and fall over the Underglow (a glowing abyss: fall in and
## you are gone). Also answers spatial queries for the game.

const ISLANDS := [
	# [name, x, z, top height, radius]
	["Dawn Meadow", 0.0, 0.0, 0.0, 20.0],
	["Lantern Grove", -46.0, -12.0, 2.5, 14.0],
	["Ember Rocks", 46.0, -14.0, 0.0, 13.0],
	["Hidden Garden", -42.0, -64.0, 6.5, 16.0],
	["Crystal Cave", 42.0, -64.0, 5.0, 13.5],
	["Heart Rock", 0.0, -48.0, 4.0, 9.0],
	["Portal Isle", 0.0, -112.0, 10.0, 13.0],
]
const START_ISLAND := 0
const HEART_ISLAND := 5
const GATE_ISLAND := 6 # the portal
const GARDEN_ISLAND := 3
const CAVE_ISLAND := 4
const SHRINE_SPOTS := [[1, 0.0, 0.0], [2, 0.0, 0.0], [5, 0.0, 2.5]] # island, dx, dz
const BRIDGES := [[0, 1], [0, 2], [1, 3], [2, 4], [0, 5], [3, 5], [4, 5], [5, 6]]
const GAUNTLET := 7 # index in BRIDGES: the causeway of fire and knives to the portal
const GARDEN_WALL_INSET := 3.4 # the garden wall stands this far inside the island rim
const CAVE_OFFSET := 4.3 # the cave dome sits this far from its island's centre, away from the bridges
const CAVE_R := 9.2 # outer radius of the dome at the ground
const CAVE_INNER := 7.3 # walkable radius inside
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

## Curtains of hanging garden: a photo of hanging ivy (cut out), swaying, its
## little flowers glowing after sunset.
const VINE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ivy : source_color, filter_linear_mipmap, repeat_disable;
uniform float night = 0.0;
varying vec3 tint;
void vertex() {
	tint = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	VERTEX.x += sin(TIME * 0.9 + wp.x * 0.3 + wp.z * 0.2 + UV.y * 2.0) * 0.08 * UV.y * UV.y;
	VERTEX.z += sin(TIME * 0.7 + wp.z * 0.25) * 0.12 * UV.y * UV.y;
}
void fragment() {
	vec4 t = texture(ivy, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	float pink = clamp((t.r + t.b) * 0.6 - t.g * 0.9, 0.0, 1.0);
	ALBEDO = t.rgb * mix(vec3(1.0), tint * 1.3, pink);
	EMISSION = tint * pink * (0.1 + 4.0 * night) + vec3(0.1, 0.6, 0.45) * night * 0.06;
	ROUGHNESS = 0.8;
	BACKLIGHT = vec3(0.2, 0.3, 0.1);
}
"""

## Grass clumps and wildflowers: photo cut-outs on crossed cards, in the wind.
const CARD_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D card : source_color, filter_linear_mipmap, repeat_disable;
uniform float night = 0.0;
uniform float glow = 0.0;
uniform vec3 card_tint : source_color = vec3(1.0);
varying vec3 tint;
void vertex() {
	tint = COLOR.rgb;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = 1.0 - UV.y;
	float w = sin(TIME * 1.4 + wp.x * 0.25 + wp.z * 0.18) * 0.5 + sin(TIME * 2.7 + wp.x * 0.9 - wp.z * 0.6) * 0.18;
	VERTEX += (vec4(vec3(w * 0.14, 0.0, w * 0.08) * h * h, 0.0) * MODEL_MATRIX).xyz;
}
void fragment() {
	vec4 t = texture(card, UV);
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ALBEDO = t.rgb * tint * card_tint;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float bloom = clamp((t.r + t.b) * 0.6 - t.g * 0.8, 0.0, 1.0);
	EMISSION = t.rgb * bloom * glow + vec3(0.2, 0.9, 0.7) * night * 0.05 * (1.0 - UV.y);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
	BACKLIGHT = vec3(0.3, 0.35, 0.15);
}
"""

## Rock and ground: photo textures projected from three sides (no UV seams on
## the sculpted islands), with moss where the model's vertex colour says (green
## channel) or, for meadows, in patches from a noise texture.
const TERRAIN_SHADER := """
shader_type spatial;
uniform sampler2D tex_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_b : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D patches : filter_linear_mipmap, repeat_enable;
uniform float scale_a = 0.25;
uniform float scale_b = 0.4;
uniform vec3 tint_a : source_color = vec3(1.0);
uniform vec3 tint_b : source_color = vec3(1.0);
uniform float moss_amount = 1.0;
uniform float patch_amount = 0.0;
uniform float normal_strength = 1.0;
uniform float occlusion = 1.0;
varying vec3 wpos;
varying vec3 wnrm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 tri_w(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}
vec3 tri(sampler2D t, vec3 p, vec3 w) {
	return texture(t, p.zy).rgb * w.x + texture(t, p.xz).rgb * w.y + texture(t, p.xy).rgb * w.z;
}
vec3 tri_n(sampler2D t, vec3 p, vec3 n, vec3 w) {
	vec3 tx = texture(t, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, p.xy).xyz * 2.0 - 1.0;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}
void fragment() {
	vec3 n = normalize(wnrm);
	vec3 w = tri_w(n);
	vec3 pa = wpos * scale_a;
	vec3 pb = wpos * scale_b;
	vec3 ca = tri(tex_a, pa, w) * tint_a;
	vec3 cb = tri(tex_b, pb, w) * tint_b;
	float moss = COLOR.g * moss_amount;
	if (patch_amount > 0.0) {
		float pn = texture(patches, wpos.xz * 0.035).r * 0.7 + texture(patches, wpos.xz * 0.11).r * 0.3;
		moss = smoothstep(0.55, 0.75, pn) * patch_amount;
	}
	float m = smoothstep(0.3, 0.7, moss + (dot(cb, vec3(0.33)) - 0.3) * 0.5);
	ALBEDO = mix(ca, cb, m) * mix(1.0 - occlusion * 0.55, 1.0, COLOR.r);
	vec3 nw = normalize(mix(tri_n(nrm_a, pa, n, w), tri_n(nrm_b, pb, n, w), m));
	nw = normalize(mix(n, nw, normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	ROUGHNESS = 0.92;
	SPECULAR = 0.3;
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
uniform float ring = 1.0;
uniform float sparse = 0.0;
uniform float opacity = 0.95;
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
	ALPHA = smoothstep(0.32 + sparse, 0.62 + sparse, n) * mix(1.0, smoothstep(150.0, 240.0, dist), ring) * (1.0 - smoothstep(420.0, 640.0, dist)) * opacity;
}
"""

const PORTAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform float open = 1.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float r = length(uv) * 2.0; // 1.0 at the inner edge of the stone ring
	if (r > 1.0) {
		discard;
	}
	float ang = atan(uv.y, uv.x);
	float swirl = 0.5 + 0.5 * sin(ang * 3.0 + log(r + 0.05) * 7.0 - TIME * 3.0);
	float swirl2 = 0.5 + 0.5 * sin(ang * 7.0 - r * 20.0 + TIME * 1.7);
	float core = 1.0 - smoothstep(0.0, 0.35, r);
	float rim = smoothstep(0.75, 0.98, r) * (1.0 - smoothstep(0.98, 1.0, r));
	vec3 c = mix(vec3(0.95, 0.35, 0.08), vec3(1.0, 0.85, 0.5), swirl * 0.6 + swirl2 * 0.3);
	c += vec3(1.0, 0.9, 0.7) * core * 0.8 + vec3(1.0, 0.55, 0.15) * rim * 1.2;
	float a = (0.45 + 0.55 * swirl) * (1.0 - smoothstep(0.9, 1.0, r) * 0.4);
	ALBEDO = c * a * mix(0.2, 1.15, open);
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
var abyss_mats: Array = []
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
var garden_center := Vector3.ZERO
var garden_gates: Array = [] # world positions of the gateways in the garden wall
var tree_pos := Vector3.ZERO # the Sky Fruit tree
var fruit_lights: Array = [] # [mesh, light] on the tree; they glow while fruit is ripe
var fruit_mat: StandardMaterial3D
var cave_center := Vector3.ZERO # centre of the dome, on the floor
var cave_door := Vector3.ZERO # just outside the doorway
var cave_dir := Vector3.ZERO # from the dome centre out through the doorway
var altar_pos := Vector3.ZERO # top of the altar, where the potion rests
var crystal_mat: StandardMaterial3D
var portal_front := Vector3.ZERO # where you step through, on the causeway side
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
var _tex := {}
var _model_mats := {}
var _iron: StandardMaterial3D
var _foliage_mats: Array = []
var _card_mats: Array = []
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
	_build_garden()
	_build_cave()
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


## The closest stone or island top a pilgrim falling at p could still reach with a
## double jump (top no higher than `climb` above p). Returns null if none is close.
func nearest_landing(p: Vector3, reach := 6.0, climb := 1.8):
	var best = null
	var best_d := reach
	for b in bridges:
		for k in b["stones"].size():
			var s: Vector3 = b["stones"][k]
			if s.y > p.y + climb:
				continue
			var d := Vector2(s.x - p.x, s.z - p.z).length() - float(b["radii"][k]) * 0.5
			if d < best_d:
				best_d = d
				best = s
	for i in ISLANDS.size():
		var c := island_center(i)
		if c.y > p.y + climb:
			continue
		var flat := Vector2(p.x - c.x, p.z - c.z)
		var d := flat.length() - (island_radius(i) - 1.5)
		if d < best_d:
			best_d = d
			var e := flat.normalized() * (island_radius(i) - 1.5)
			best = Vector3(c.x + e.x, c.y, c.z + e.y)
	return best


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

func _tex_load(name: String) -> Texture2D:
	if not _tex.has(name):
		_tex[name] = load("res://textures/%s.png" % name)
	return _tex[name]


## Photo-textured material, projected from three sides in world space.
func _photo_mat(name: String, scale: float, rough: float, tint := Color.WHITE, normal_scale := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex_load(name)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex_load(name + "_n")
	m.normal_scale = normal_scale
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 4.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _terrain(a: String, b: String, scale_a: float, scale_b: float, tint_a: Color, tint_b: Color, moss: float, patches: float) -> ShaderMaterial:
	var m := _shader_mat(TERRAIN_SHADER)
	m.set_shader_parameter("tex_a", _tex_load(a))
	m.set_shader_parameter("nrm_a", _tex_load(a + "_n"))
	m.set_shader_parameter("tex_b", _tex_load(b))
	m.set_shader_parameter("nrm_b", _tex_load(b + "_n"))
	m.set_shader_parameter("patches", _noise_tex)
	m.set_shader_parameter("scale_a", scale_a)
	m.set_shader_parameter("scale_b", scale_b)
	m.set_shader_parameter("tint_a", tint_a)
	m.set_shader_parameter("tint_b", tint_b)
	m.set_shader_parameter("moss_amount", moss)
	m.set_shader_parameter("patch_amount", patches)
	return m


func _foliage(card: String, tint: Color, night_glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex_load(card)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.8
	m.backlight_enabled = true
	m.backlight = Color(0.35, 0.3, 0.25)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if night_glow > 0.0:
		m.emission_enabled = true
		m.emission_texture = _tex_load(card)
		m.emission = Color(1.0, 0.55, 0.75)
		m.emission_energy_multiplier = 0.0
		glow_mats.append([m, 0.0, night_glow])
	_foliage_mats.append(m)
	return m


func _make_materials() -> void:
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.seamless = true
	var fn := FastNoiseLite.new()
	fn.frequency = 0.008
	fn.fractal_octaves = 4
	_noise_tex.noise = fn
	# Photo textures (made from the Grok reference set, see 3d/tests/lastlight_world).
	_stone = _photo_mat("tex_cliff", 0.3, 0.95)
	_stone_top = _photo_mat("tex_moss_stone", 0.45, 0.95)
	_dark = _photo_mat("tex_rock_dark", 0.25, 0.95, Color(0.85, 0.85, 0.9))
	_marble = _photo_mat("tex_marble", 0.4, 0.45, Color(1.0, 0.98, 0.95), 0.6)
	_trunk = _photo_mat("tex_bark", 0.8, 0.9)
	_iron = _mat(Color(0.12, 0.11, 0.1), 0.45)
	_iron.metallic = 0.7
	_water = _mat(Color(0.05, 0.12, 0.17), 0.03)
	_water.metallic = 0.3
	_model_mats = {
		"grass": _terrain("tex_grass", "tex_moss_stone", 0.33, 0.3, Color(0.78, 0.85, 0.62), Color(0.9, 0.88, 0.8), 0.0, 0.55),
		"cliff": _terrain("tex_cliff", "tex_grass", 0.22, 0.4, Color(1, 1, 1), Color(0.45, 0.55, 0.32), 1.0, 0.0),
		"under": _terrain("tex_cliff", "tex_rock_dark", 0.18, 0.2, Color(0.78, 0.74, 0.72), Color(0.8, 0.8, 0.85), 0.0, 0.0),
		"stonetop": _terrain("tex_moss_stone", "tex_grass", 0.55, 0.5, Color(1, 1, 1), Color(0.55, 0.65, 0.4), 0.4, 0.0),
		"marble": _marble,
		"bark": _trunk,
		"blossom": _foliage("card_blossom", Color(1, 1, 1), 0.12),
		"leaves": _foliage("card_leaves", Color(0.9, 1.0, 0.9), 0.0),
		"caverock": _terrain("tex_cave_rock", "tex_rock_dark", 0.3, 0.25, Color(0.8, 0.78, 0.85), Color(0.5, 0.6, 0.5), 0.6, 0.0),
		"cavefloor": _terrain("tex_cave_rock", "tex_rock_dark", 0.4, 0.3, Color(0.55, 0.53, 0.6), Color(0.6, 0.6, 0.65), 0.0, 0.5),
		"wallstone": _terrain("tex_garden_wall", "tex_moss_stone", 0.42, 0.5, Color(1.0, 0.97, 0.92), Color(0.6, 0.72, 0.45), 1.0, 0.0),
		"iron": _iron,
		"crystal": null,
	}
	_canopies = [_model_mats["blossom"]]
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
	crystal_mat = _photo_mat("tex_crystal", 1.2, 0.15, Color(0.55, 0.35, 0.85), 0.4)
	crystal_mat.emission_enabled = true
	crystal_mat.emission = Color(0.45, 0.15, 0.9)
	crystal_mat.emission_texture = _tex_load("tex_crystal")
	crystal_mat.emission_energy_multiplier = 0.55
	crystal_mat.metallic_specular = 0.9
	glow_mats.append([crystal_mat, 0.55, 1.4])
	_model_mats["crystal"] = crystal_mat
	fruit_mat = _mat(Color(1.0, 0.75, 0.25), 0.3, Color(1.0, 0.6, 0.15), 2.5)


## Places a model made in Blender (3d/tests/lastlight_world/scripts/build_world.py)
## and gives each surface the game's material of the same name.
func _model(path: String, parent: Node, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Node3D:
	var scene: PackedScene = load(path)
	var n: Node3D = scene.instantiate()
	n.position = pos
	n.rotation = rot
	n.scale = scl
	parent.add_child(n)
	_apply_model_mats(n)
	return n


func _apply_model_mats(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var key: String = src.resource_name if src else mi.mesh.surface_get_name(i)
			key = key.to_lower()
			for k in _model_mats:
				if _model_mats[k] != null and key.begins_with(k):
					mi.set_surface_override_material(i, _model_mats[k])
					break
	for c in n.get_children():
		_apply_model_mats(c)


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
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.06
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.95
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.fog_enabled = true
	env.fog_density = 0.00045
	# Mist pools in the abyss below the islands; the islands themselves stay clear.
	env.fog_height = -14.0
	env.fog_height_density = 0.012
	env.fog_sun_scatter = 0.25
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.1
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0012
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 80.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.shadow_blur = 1.5
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
	for i in ISLANDS.size():
		var c := island_center(i)
		var r := island_radius(i)
		# The sculpted island: grass top at its height, cliffs, and the rock it floats on.
		_model("res://models/island_%d.glb" % i, self, c)
		var shape := CylinderShape3D.new()
		shape.radius = r
		shape.height = 3.0
		_static(shape, c - Vector3(0, 1.5, 0), LAYER_TERRAIN)
		# A few boulders drift around the island.
		for k in 4:
			var a := randf() * TAU
			var rr := r + randf_range(4.0, 9.0)
			var s := randf_range(0.4, 1.0)
			var node := _model("res://models/rock_%d.glb" % (randi() % 3), self, c + Vector3(cos(a) * rr, randf_range(-9.0, -3.0), sin(a) * rr), Vector3(randf(), randf() * TAU, randf()), Vector3(s, s * 0.8, s))
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
		var gauntlet := bi == GAUNTLET
		var n := maxi(1, roundi((L - STONE_GAP) / ((4.0 if gauntlet else 2.8) + STONE_GAP)))
		var radii: Array = []
		var total := 0.0
		var gap := 0.0
		var blade_gaps: Array = [] # gap k sits between stones k-1 and k; these get a knife pendulum
		while true:
			radii.clear()
			total = 0.0
			for s in n:
				var rr := randf_range(1.85, 2.15) if gauntlet else randf_range(1.2, 1.6)
				radii.append(rr)
				total += rr * 2.0
			# Pick some gaps between two stones at random (never two in a row) and widen them.
			blade_gaps.clear()
			var inner: Array = range(1, n)
			inner.shuffle()
			for k in inner:
				if blade_gaps.size() >= (2 if gauntlet else maxi(1, int(n / 2.0))):
					break
				if blade_gaps.has(k - 1) or blade_gaps.has(k + 1):
					continue
				if blade_gaps.is_empty() or randf() < 0.75:
					blade_gaps.append(k)
			gap = (L - total - Cfg.BLADE_GAP_EXTRA * blade_gaps.size()) / float(n + 1)
			if gap >= 1.0 or n <= 1:
				break
			n -= 1
		var gaps: Array = []
		for k in n:
			gaps.append(gap + (Cfg.BLADE_GAP_EXTRA if blade_gaps.has(k) else 0.0))
		var rune := _mat(RUNE_COL, 0.4, RUNE_COL, 0.8)
		var stones: Array = []
		var along := ra
		var prev_y := A.y
		var phase := randf() * TAU
		var amp := randf_range(1.0, 1.7)
		for s in n:
			var rad: float = radii[s]
			along += float(gaps[s]) + rad
			# Rise and fall from stone to stone, but never more than one jump can climb,
			# and always able to reach the far island.
			var hops_left := n - s
			var lo := maxf(prev_y - MAX_STEP, B.y - MAX_STEP * hops_left)
			var hi := minf(prev_y + MAX_STEP, B.y + MAX_STEP * hops_left)
			if lo > hi + 0.01:
				push_warning("bridge %d cannot keep steps small" % bi)
			var want := lerpf(A.y, B.y, float(s + 1) / float(n + 1)) + (sin(float(s) * 1.9 + phase) * amp + randf_range(-0.3, 0.3)) * (0.3 if gauntlet else 1.0)
			var y := clampf(want, lo, hi)
			prev_y = y
			var p := A + dir * along + perp * (0.0 if gauntlet else randf_range(-0.35, 0.35))
			p.y = y
			_build_stone(p, rad, rune, gauntlet)
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
			"a": ia, "b": ib, "stones": stones, "radii": radii, "rune": rune, "warn": 0.0, "blade_gaps": blade_gaps,
			"dir": dir, "perp": perp, "start": A + dir * ra, "end": B - dir * rb,
		})


func _build_stone(p: Vector3, r: float, rune: Material, scorched := false) -> void:
	var st := _model("res://models/stone_%d.glb" % (randi() % 6), self, p, Vector3(0, randf() * TAU, 0), Vector3(r, r * (0.6 if scorched else 0.9), r))
	if scorched:
		_set_surface_mat(st, "stonetop", _scorched_mat())
	var ring := TorusMesh.new()
	ring.inner_radius = r - 0.3
	ring.outer_radius = r - 0.16
	ring.rings = 24
	ring.ring_segments = 4
	var rm := _mesh(self, ring, rune, p + Vector3(0, 0.01, 0), Vector3.ZERO, Vector3(1, 0.12, 1))
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A few strands of hanging garden under most stones.
	if randf() < 0.7:
		for k in randi_range(1, 3):
			var a := randf() * TAU
			_add_vine(p + Vector3(cos(a) * r * 0.95, -0.15, sin(a) * r * 0.95), a, randf_range(0.7, 1.1), randf_range(1.5, 3.5))
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = STONE_H
	_static(shape, p - Vector3(0, STONE_H * 0.5, 0), LAYER_TERRAIN)


func _lamp(pos: Vector3) -> void:
	# An old iron lantern post, like the reference: a post, an arm and a hanging lantern.
	var post := CylinderMesh.new()
	post.top_radius = 0.045
	post.bottom_radius = 0.07
	post.height = 2.2
	_mesh(self, post, _iron, pos + Vector3(0, 1.1, 0))
	var arm := BoxMesh.new()
	arm.size = Vector3(0.5, 0.05, 0.05)
	_mesh(self, arm, _iron, pos + Vector3(0.2, 2.15, 0))
	var cage := CylinderMesh.new()
	cage.top_radius = 0.1
	cage.bottom_radius = 0.13
	cage.height = 0.32
	cage.radial_segments = 6
	_mesh(self, cage, _iron, pos + Vector3(0.38, 1.85, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.0)).transparency = 0.6
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.24
	_mesh(self, bulb, _lamp_bulb, pos + Vector3(0.38, 1.85, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.42)
	l.light_energy = 0.4
	l.omni_range = 7.0
	l.position = pos + Vector3(0.38, 1.85, 0)
	add_child(l)
	lamp_lights.append(l)


func _build_gate() -> void:
	# The portal: a ring of carved stone on Portal Isle, facing the causeway. A ring of fire
	# seals it (see trials.gd); the portal itself is always open.
	var c := island_center(GATE_ISLAND)
	gate_pos = c
	var to_h := island_center(HEART_ISLAND) - c
	to_h.y = 0.0
	var dir := to_h.normalized()
	var yaw := atan2(dir.x, dir.z)
	var basis := Basis(Vector3.UP, yaw)
	portal_front = c + dir * 2.0
	_model("res://models/portal_ring.glb", self, c, Vector3(0, yaw, 0))
	for sx in [-1.0, 1.0]:
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.9, 5.2, 1.0)
		_static(sh, c + basis * Vector3(3.15 * float(sx), 2.6, 0), LAYER_OBSTACLE, Vector3(0, yaw, 0))
	var gold := _mat(Color(0.95, 0.72, 0.32), 0.3, Color(1.0, 0.68, 0.3), 1.2)
	gold.metallic = 0.8
	glow_mats.append([gold, 1.2, 3.0])
	var tm := TorusMesh.new()
	tm.inner_radius = 2.62
	tm.outer_radius = 2.8
	tm.rings = 64
	tm.ring_segments = 8
	gate_ring = _mesh(self, tm, gold, c + Vector3(0, 3.55, 0))
	gate_ring.basis = basis * Basis(Vector3.RIGHT, PI / 2.0)
	gate_mat = _shader_mat(PORTAL_SHADER)
	var q := QuadMesh.new()
	q.size = Vector2(5.4, 5.4)
	var disc := _mesh(self, q, gate_mat, c + Vector3(0, 3.55, 0))
	disc.basis = basis
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gate_light = OmniLight3D.new()
	gate_light.light_color = Color(1.0, 0.75, 0.4)
	gate_light.light_energy = 3.0
	gate_light.omni_range = 16.0
	gate_light.position = c + Vector3(0, 3.5, 0) + dir * 1.0
	add_child(gate_light)
	obstacles.append([Vector2(c.x, c.z), 6.0])
	# A faint pillar of light over the portal: you can always see where the way out is.
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
	# Colonnade round the isle, outside the ring of fire.
	for k in 12:
		var a := TAU * float(k) / 12.0 + 0.15
		if _bridge_clearance(GATE_ISLAND, a) < 20.0:
			continue
		_column(c + Vector3(cos(a) * 9.8, 0, sin(a) * 9.8), 3.8, true)
	gate_open = true
	gate_mat.set_shader_parameter("open", 1.0)


func _set_surface_mat(n: Node, key: String, m: Material) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var nm: String = (src.resource_name if src else mi.mesh.surface_get_name(i)).to_lower()
			if nm.begins_with(key):
				mi.set_surface_override_material(i, m)
	for ch in n.get_children():
		_set_surface_mat(ch, key, m)


var _scorched: ShaderMaterial
func _scorched_mat() -> ShaderMaterial:
	if _scorched == null:
		_scorched = _terrain("tex_paving_scorched", "tex_rock_dark", 0.4, 0.3, Color(1.0, 0.95, 0.9), Color(0.7, 0.6, 0.55), 0.0, 0.3)
	return _scorched


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for ch in n.get_children():
		var m := _first_mesh(ch)
		if m:
			return m
	return null


## The Hidden Garden: a ring of old walls with arched gateways where the stepping stones
## arrive. Inside, hedges, roses and the Sky Fruit tree, with the Thornback asleep under it.
func _build_garden() -> void:
	var i := GARDEN_ISLAND
	var c := island_center(i)
	garden_center = c
	var r := island_radius(i)
	var rw := r - GARDEN_WALL_INSET
	var gates: Array = bridge_angles.get(i, [])
	var n := int(round(TAU * rw / 4.0))
	var step := TAU / float(n)
	var a0: float = float(gates[0]) if not gates.is_empty() else 0.0
	var hedge_mat := _photo_mat("tex_hedge", 1.1, 0.85, Color(0.75, 0.9, 0.7))
	for k in n:
		var a := a0 + step * float(k)
		var is_gate := false
		for g in gates:
			if absf(angle_difference(a, float(g))) < step * 0.55:
				is_gate = true
		var radial := Vector3(cos(a), 0, sin(a))
		var tangent := Vector3(-sin(a), 0, cos(a))
		var p := c + radial * rw
		var rot := Vector3(0, -(a + PI / 2.0), 0)
		if is_gate:
			_model("res://models/wall_gate.glb", self, p, rot)
			garden_gates.append(p)
			for sx in [-1.0, 1.0]:
				var sh := BoxShape3D.new()
				sh.size = Vector3(0.95, 4.2, 1.3)
				var pp: Vector3 = p + tangent * 1.85 * float(sx)
				_static(sh, pp + Vector3(0, 2.1, 0), LAYER_OBSTACLE, rot)
				obstacles.append([Vector2(pp.x, pp.z), 0.9])
			_lamp(p + radial * 1.4 + tangent * 2.6)
		else:
			_model("res://models/wall_seg.glb", self, p, rot)
			var sh := BoxShape3D.new()
			sh.size = Vector3(4.1, 3.7, 0.85)
			_static(sh, p + Vector3(0, 1.85, 0), LAYER_OBSTACLE, rot)
			obstacles.append([Vector2(p.x, p.z), 2.2])
			# Ivy and roses down both faces.
			for side in [1.0, -1.0]:
				for v in 2:
					var off: float = randf_range(-1.6, 1.6)
					_add_vine(p + radial * 0.46 * float(side) + tangent * off + Vector3(0, 3.45, 0), a if side > 0.0 else a + PI, randf_range(0.9, 1.4), randf_range(1.6, 3.3))
	# The Sky Fruit tree in the middle.
	tree_pos = c
	_model("res://models/tree_leaves_0.glb", self, tree_pos, Vector3(0, 0.6, 0), Vector3.ONE * 2.3)
	var tsh := CylinderShape3D.new()
	tsh.radius = 0.75
	tsh.height = 5.0
	_static(tsh, tree_pos + Vector3(0, 2.5, 0), LAYER_OBSTACLE)
	obstacles.append([Vector2(tree_pos.x, tree_pos.z), 2.0])
	for k in 9:
		var fa := TAU * float(k) / 9.0 + randf_range(-0.2, 0.2)
		var fr := randf_range(1.4, 2.9)
		var fp := tree_pos + Vector3(cos(fa) * fr, randf_range(3.6, 5.6), sin(fa) * fr)
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		var fm := _mesh(self, sm, fruit_mat, fp)
		fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fl: OmniLight3D = null
		if k % 3 == 0:
			fl = OmniLight3D.new()
			fl.light_color = Color(1.0, 0.7, 0.3)
			fl.light_energy = 0.8
			fl.omni_range = 4.0
			fl.position = fp
			add_child(fl)
		fruit_lights.append([fm, fl])
	# Low clipped hedges in a broken ring round the tree (gaps toward the gateways).
	var hr := 7.6
	for k in 12:
		var a := a0 + TAU * (float(k) + 0.5) / 12.0
		var gap := false
		for g in gates:
			if absf(angle_difference(a, float(g))) < 0.4:
				gap = true
		if gap or k % 4 == 1:
			continue
		var hp := c + Vector3(cos(a), 0, sin(a)) * hr
		var bm := BoxMesh.new()
		bm.size = Vector3(3.3, 0.95, 0.75)
		_mesh(self, bm, hedge_mat, hp + Vector3(0, 0.47, 0), Vector3(0, -(a + PI / 2.0), 0))
		var hs := BoxShape3D.new()
		hs.size = bm.size
		_static(hs, hp + Vector3(0, 0.47, 0), LAYER_OBSTACLE, Vector3(0, -(a + PI / 2.0), 0))
		obstacles.append([Vector2(hp.x, hp.z), 1.7])
	# Small blossom trees between the wall and the hedges.
	for k in 4:
		var a := a0 + TAU * (float(k) + 0.5) / 4.0
		var tp := c + Vector3(cos(a), 0, sin(a)) * 10.0
		if is_clear(tp, 1.5):
			make_tree(self, tp, 0.8, true)


## The Crystal Cave: a basalt dome on its island with the doorway facing the bridges.
## Inside, glowing crystals and the altar where the Moon Potion brews.
func _build_cave() -> void:
	var i := CAVE_ISLAND
	var c := island_center(i)
	var v := Vector2.ZERO
	for a in bridge_angles.get(i, []):
		v += Vector2(cos(float(a)), sin(float(a)))
	var door_a := atan2(v.y, v.x)
	cave_dir = Vector3(cos(door_a), 0, sin(door_a))
	cave_center = c - cave_dir * CAVE_OFFSET
	cave_door = cave_center + cave_dir * (CAVE_R + 1.0)
	var shell := _model("res://models/cave_shell.glb", self, cave_center, Vector3(0, -door_a, 0))
	var mi := _first_mesh(shell)
	if mi:
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_OBSTACLE
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.shape = mi.mesh.create_trimesh_shape()
		body.add_child(cs)
		nav_region.add_child(body)
		body.global_transform = mi.global_transform
	# Keep spawns out of the thick walls.
	for k in 28:
		var a := TAU * float(k) / 28.0
		if absf(angle_difference(a, door_a)) < 0.3:
			continue
		var wp := cave_center + Vector3(cos(a), 0, sin(a)) * (CAVE_R - 0.7)
		obstacles.append([Vector2(wp.x, wp.z), 1.3])
	_model("res://models/altar.glb", self, cave_center, Vector3(0, randf() * TAU, 0))
	var ash := CylinderShape3D.new()
	ash.radius = 1.15
	ash.height = 1.05
	_static(ash, cave_center + Vector3(0, 0.52, 0), LAYER_OBSTACLE)
	obstacles.append([Vector2(cave_center.x, cave_center.z), 1.9])
	altar_pos = cave_center + Vector3(0, 1.08, 0)
	var placed := 0
	for k in 40:
		if placed >= 11:
			break
		var a := randf() * TAU
		if absf(angle_difference(a, door_a)) < 0.75:
			continue
		var cr := randf_range(5.6, 6.9)
		var cp := cave_center + Vector3(cos(a), 0, sin(a)) * cr
		var s := randf_range(0.9, 1.8)
		_model("res://models/crystal_%d.glb" % (randi() % 3), self, cp, Vector3(randf_range(-0.2, 0.2), randf() * TAU, randf_range(-0.2, 0.2)), Vector3.ONE * s)
		obstacles.append([Vector2(cp.x, cp.z), 1.0 * s])
		var csh := CylinderShape3D.new()
		csh.radius = 0.45 * s
		csh.height = 1.6 * s
		_static(csh, cp + Vector3(0, 0.8 * s, 0), LAYER_OBSTACLE)
		if placed % 3 == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(0.65, 0.35, 1.0) if placed % 2 == 0 else Color(0.3, 0.9, 1.0)
			l.light_energy = 1.4
			l.omni_range = 7.5
			l.position = cp + Vector3(0, 1.4, 0) - Vector3(cos(a), 0, sin(a)) * 1.0
			add_child(l)
		placed += 1
	var al := OmniLight3D.new()
	al.light_color = Color(0.7, 0.4, 1.0)
	al.light_energy = 1.8
	al.omni_range = 6.0
	al.position = altar_pos + Vector3(0, 1.2, 0)
	add_child(al)
	# A crystal either side of the doorway, so you can find it from afar.
	for sx in [-1.0, 1.0]:
		var side := Vector3(-cave_dir.z, 0, cave_dir.x) * 2.9 * float(sx)
		_model("res://models/crystal_1.glb", self, cave_door + side - cave_dir * 0.6, Vector3(0, randf() * TAU, 0), Vector3.ONE * 1.3)


func in_cave(p: Vector3, pad := 0.0) -> bool:
	return Vector2(p.x - cave_center.x, p.z - cave_center.z).length() < CAVE_R + pad and absf(p.y - cave_center.y) < 6.0


func in_garden(p: Vector3) -> bool:
	return Vector2(p.x - garden_center.x, p.z - garden_center.z).length() < island_radius(GARDEN_ISLAND) - GARDEN_WALL_INSET and absf(p.y - garden_center.y) < 4.0


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
	var rot := Vector3(0, randf() * TAU, 0)
	if h >= 3.0:
		_model("res://models/column.glb", self, p, rot, Vector3(1, h / 3.8, 1))
	else:
		var k := randi() % 2
		_model("res://models/column_broken_%d.glb" % k, self, p, rot, Vector3(1, h / (2.6 - k * 0.9), 1))
	if rune:
		var band := TorusMesh.new()
		band.inner_radius = 0.37
		band.outer_radius = 0.43
		band.rings = 24
		_mesh(self, band, _rune_mat, p + Vector3(0, h * 0.62, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	var shp := CylinderShape3D.new()
	shp.radius = 0.5
	shp.height = h
	_static(shp, p + Vector3(0, h * 0.5, 0), LAYER_OBSTACLE)
	obstacles.append([Vector2(p.x, p.z), 0.8])


func make_tree(parent: Node, pos: Vector3, s: float, collide: bool) -> void:
	var path := "res://models/tree_blossom_%d.glb" % (randi() % 3)
	if randf() < 0.3:
		path = "res://models/tree_leaves_%d.glb" % (randi() % 2)
	_model(path, parent, pos, Vector3(0, randf() * TAU, 0), Vector3.ONE * s * 1.15)
	if collide:
		for k in 3:
			var orb := SphereMesh.new()
			orb.radius = 0.08
			orb.height = 0.16
			var oa := randf() * TAU
			_mesh(parent, orb, _orb_mat, pos + Vector3(cos(oa) * 1.0 * s, 2.4 * s, sin(oa) * 1.0 * s))
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
	# Crystal Cave: a few broken columns in the yard outside the doorway.
	for k in 3:
		var p = island_point(CAVE_ISLAND, 1.8, 1.8)
		if p != null and not in_cave(p, 1.5):
			_column(p, randf_range(1.0, 3.2), true)
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
	stream.size = Vector2(1.4, 2.4)
	var slen: float = stream.size.y
	var smi := _mesh(root, stream, _water, Vector3(0, 0.07, -slen * 0.5))
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for sx in [-1.0, 1.0]:
		_model("res://models/rock_%d.glb" % (randi() % 3), root, Vector3(1.3 * float(sx), 0.1, -0.4), Vector3(0, randf() * TAU, 0), Vector3(0.6, 0.45, 0.75))
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
			_model("res://models/rock_%d.glb" % (randi() % 3), self, p, Vector3(0, randf() * TAU, 0), Vector3(1.5, 0.6, 1.5))
			make_tree(self, p + Vector3(0, 0.2, 0), randf_range(0.4, 0.6), false)
			for v in 4:
				var va := a + randf_range(-0.9, 0.9)
				_add_vine(p + Vector3(cos(va) * 1.3, 0.2, sin(va) * 1.3), va, randf_range(0.8, 1.2), randf_range(2.5, 6.0))
	vine_mat = _shader_mat(VINE_SHADER)
	vine_mat.set_shader_parameter("ivy", _tex_load("tex_ivy"))
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


## Two crossed cards, `w` wide and `h` tall, standing on the ground (UV v=0 at the top).
func _card_mesh(w: float, h: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for k in 2:
		var d := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var base := verts.size()
		verts.append_array([-d * w * 0.5, d * w * 0.5, d * w * 0.5 + Vector3(0, h, 0), -d * w * 0.5 + Vector3(0, h, 0)])
		uvs.append_array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
		for i in 4:
			norms.append(Vector3.UP)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_grass() -> void:
	grass_mat = _shader_mat(CARD_SHADER)
	grass_mat.set_shader_parameter("card", _tex_load("card_grass"))
	grass_mat.set_shader_parameter("card_tint", Color(0.55, 0.85, 0.4))
	var xf: Array = []
	var cols: Array = []
	for i in ISLANDS.size():
		var c := island_center(i)
		var r := island_radius(i)
		for k in int(r * r * 3.2):
			var rr := sqrt(randf()) * (r - 0.4)
			var a := randf() * TAU
			var p := c + Vector3(cos(a) * rr, 0, sin(a) * rr)
			if _in_pool(p, 0.4):
				continue
			if i == GATE_ISLAND and rr < 5.6:
				continue
			if i == CAVE_ISLAND and in_cave(p, 0.3):
				continue
			var s := randf_range(0.6, 1.15)
			var b := Basis(Vector3.UP, randf() * TAU).scaled(Vector3(s, s * randf_range(0.7, 1.2), s))
			xf.append(Transform3D(b, p))
			var g := randf()
			cols.append(Color(0.85 + g * 0.2, 0.9 + g * 0.1, 0.8 + g * 0.15))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _card_mesh(1.2, 0.55)
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
	flower_mat = _shader_mat(CARD_SHADER)
	flower_mat.set_shader_parameter("card", _tex_load("card_flowers"))
	for i in ISLANDS.size():
		var clusters := int(island_radius(i) * island_radius(i) / 18.0) + 3
		for k in clusters:
			var center = island_point(i, 1.0, 0.5)
			if center == null:
				continue
			for f in randi_range(3, 7):
				var p: Vector3 = center + Vector3(randf_range(-1.8, 1.8), 0, randf_range(-1.8, 1.8))
				if island_at(p) != i or _in_pool(p, 0.2) or (i == CAVE_ISLAND and in_cave(p, 0.3)) or (i == GATE_ISLAND and Vector2(p.x - gate_pos.x, p.z - gate_pos.z).length() < 5.6):
					continue
				var s := randf_range(0.7, 1.2)
				_flower_xf.append(Transform3D(Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * s), p))
				_flower_cols.append(Color(1, 1, 1).lerp(FLOWER_PALETTE.pick_random(), 0.15))
	# The rim flowers from the hanging gardens were added with a little height:
	# put them back on the ground.
	for k in _flower_xf.size():
		var t: Transform3D = _flower_xf[k]
		var isl := island_at(t.origin)
		if isl >= 0:
			t.origin.y = island_center(isl).y
		_flower_xf[k] = t
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _card_mesh(1.3, 0.6)
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
	for i in 10:
		var a := TAU * i / 10.0 + randf_range(-0.25, 0.25)
		var dist := randf_range(170.0, 290.0)
		var y := randf_range(-25.0, 30.0)
		var root := Node3D.new()
		root.position = CENTER + Vector3(cos(a) * dist, y, sin(a) * dist)
		add_child(root)
		var k := randi_range(1, 5)
		var size := randf_range(5.0, 14.0)
		_model("res://models/island_%d.glb" % k, root, Vector3.ZERO, Vector3(0, randf() * TAU, 0), Vector3.ONE * size / island_radius(k))
		for t in randi_range(1, 3):
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
	# Wisps of cloud drifting through the abyss under the islands.
	for layer in [[-26.0, 0.006, 0.1], [-42.0, 0.0045, 0.06]]:
		var m := _shader_mat(CLOUD_SHADER)
		m.set_shader_parameter("noise_tex", _noise_tex)
		m.set_shader_parameter("scale", float(layer[1]))
		m.set_shader_parameter("ring", 0.0)
		m.set_shader_parameter("sparse", float(layer[2]))
		var pm := PlaneMesh.new()
		pm.size = Vector2(900, 900)
		var mi := _mesh(self, pm, m, Vector3(CENTER.x, float(layer[0]), CENTER.z))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud_mats.append(m)
		abyss_mats.append(m)


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
	env.fog_light_color = _tri_c(Color(0.62, 0.7, 0.82), Color(0.6, 0.45, 0.6), Color(0.05, 0.07, 0.15), dusk)
	env.volumetric_fog_albedo = _tri_c(Color(1.0, 0.85, 0.75), Color(0.9, 0.6, 0.65), Color(0.35, 0.4, 0.7), dusk)
	env.volumetric_fog_emission = Color(0.02, 0.02, 0.05) * night
	for m in cloud_mats:
		m.set_shader_parameter("top_col", _tri_c(Color(1.0, 0.82, 0.7), Color(1.0, 0.5, 0.45), Color(0.12, 0.12, 0.25), dusk))
		m.set_shader_parameter("shade_col", _tri_c(Color(0.65, 0.5, 0.65), Color(0.4, 0.22, 0.4), Color(0.03, 0.03, 0.08), dusk))
	grass_mat.set_shader_parameter("night", night)
	flower_mat.set_shader_parameter("night", night)
	for m in abyss_mats:
		m.set_shader_parameter("opacity", lerpf(0.7, 0.2, night))
	vine_mat.set_shader_parameter("night", night)
	underglow_mat.set_shader_parameter("night", night)
	for m in water_mats:
		m.set_shader_parameter("night", night)
	flower_mat.set_shader_parameter("glow", lerpf(0.0, 1.6, night))
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
