extends Node3D
## A guardian of one of the trials, built from jointed parts made in Blender
## (3d/tests/lastlight_world/scripts/build_creatures.py) and animated here by turning them.
##   kind "beast":   the THORNBACK sleeps under the Sky Fruit tree in the Hidden Garden.
##                   Wake it, kill it, and the tree lets its fruit fall. It re-forms later.
##   kind "crawler": the SHARDBACK prowls round the Moon Potion's altar in the Crystal Cave
##                   and attacks anyone who comes in. Kill it to grab the potion in peace.
## Every attack has a clear tell: it rears up, its eyes blaze and a red arc shows where
## it will hit. Step out of the arc, brace, or blast it with a flare.

const Cfg = preload("res://scripts/cfg.gd")

enum {SLEEP, PROWL, CHASE, WINDUP, ATTACK, RECOVER, STAGGER, DEAD, REFORM}

var main
var kind := "beast"
var display := "THORNBACK"
var home := Vector3.ZERO
var arena := Vector3.ZERO # the leash is measured from here (the garden, the cave)
var leash := 9.0
var avoid: Array = [] # [Vector2 centre, radius] it walks around (the tree, the altar)
var state := SLEEP
var t := 0.0
var hp := 1
var max_hp := 1
var target = null
var facing := Vector3(0, 0, 1)
var speed := 4.0
var knock := Vector3.ZERO
var cd := 1.0
var charging := false
var atk_dir := Vector3.FORWARD
var hit_done := {}
var reform_t := 0.0
var awake_t := 0.0 # time with nobody around; it settles down again after a while
var gait := 0.0
var move_k := 0.0
var flash := 0.0
var kills := 0 # times it has been slain

var model: Node3D
var parts := {} # name -> Node3D
var rest := {} # name -> Transform3D
var eye_mat: StandardMaterial3D
var eye_light: OmniLight3D
var warn_ring: MeshInstance3D
var warn_mat: StandardMaterial3D
var overlay: StandardMaterial3D
var _mats := {}


func setup(p_main, p_kind: String, p_home: Vector3, p_leash: float, p_avoid: Array) -> void:
	main = p_main
	kind = p_kind
	home = p_home
	arena = p_home
	leash = p_leash
	avoid = p_avoid
	display = "THORNBACK" if kind == "beast" else "SHARDBACK"
	max_hp = Cfg.BEAST_HP if kind == "beast" else Cfg.CRAWLER_HP
	hp = max_hp
	speed = Cfg.BEAST_SPEED if kind == "beast" else Cfg.CRAWLER_SPEED
	state = SLEEP if kind == "beast" else PROWL
	position = home


func _ready() -> void:
	_build()
	if state == SLEEP:
		_pose_sleep(1.0)


func is_active() -> bool:
	return state != DEAD and state != REFORM


func is_awake() -> bool:
	return is_active() and state != SLEEP


func is_striking() -> bool:
	return state == WINDUP or state == ATTACK


func is_asleep() -> bool:
	return state == SLEEP


func body_radius() -> float:
	return 1.3 if kind == "beast" else 1.1


# ---------------------------------------------------------------- damage

## A weapon blow (also called when a braced pilgrim with a weapon counters a bite).
func hit(from_pos: Vector3, force: float) -> bool:
	return hurt(1, from_pos, force * 0.25)


func hurt(dmg: int, from_pos: Vector3, push: float) -> bool:
	if not is_active():
		return false
	hp -= dmg
	flash = 1.0
	main.sfx.play("hit", global_position, 3.0, randf_range(0.7, 0.85))
	main.fx_burst(global_position + Vector3(0, 1.3, 0), Color(0.9, 0.75, 0.4) if kind == "beast" else Color(0.75, 0.5, 1.0), 18, false, 4.0)
	if state == SLEEP:
		_wake()
	if hp <= 0:
		_die()
		return true
	var k := global_position - from_pos
	k.y = 0.0
	if k.length() > 0.01:
		knock = k.normalized() * push
	# Big blows (flares) interrupt an attack; small ones only if it was not mid-strike.
	if dmg >= 2 or state != ATTACK:
		state = STAGGER
		t = 0.0
		charging = false
		warn_ring.visible = false
	return true


func _die() -> void:
	state = DEAD
	t = 0.0
	kills += 1
	charging = false
	warn_ring.visible = false
	eye_light.light_energy = 0.0
	main.sfx.play("hollow_die", global_position, 6.0, 0.55)
	main.fx_burst(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.45) if kind == "beast" else Color(0.7, 0.45, 1.0), 60, false, 6.0)
	main.shake_near(global_position, 14.0, 0.4)
	reform_t = Cfg.BEAST_REFORM if kind == "beast" else Cfg.CRAWLER_REFORM
	main.on_guardian_down(self)


func _wake() -> void:
	if state != SLEEP:
		return
	state = CHASE
	t = 0.0
	cd = 0.9
	awake_t = 0.0
	main.sfx.play("roar", global_position, 4.0, 0.8)
	main.shake_near(global_position, 18.0, 0.35)
	main.on_guardian_woke(self)


# ---------------------------------------------------------------- brain

func _pick_target():
	var best = null
	var bd := INF
	for s in main.survivors:
		if not s.alive or s.escaped:
			continue
		var sp: Vector3 = s.global_position
		if absf(sp.y - home.y) > 3.0:
			continue
		if _flat(sp, arena) > leash + 1.5:
			continue
		var d := _flat(sp, global_position)
		if main.gentle and s.is_player:
			d += 5.0
		if d < bd:
			bd = d
			best = s
	return best


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _physics_process(delta: float) -> void:
	if main == null or main.state != "playing" and main.state != "ended":
		_animate(delta, 0.0)
		return
	if main.state == "ended":
		_animate(delta, 0.0)
		return
	t += delta
	cd = maxf(0.0, cd - delta)
	flash = maxf(0.0, flash - delta * 4.0)
	knock = knock.lerp(Vector3.ZERO, minf(1.0, delta * 5.0))
	var want := Vector3.ZERO
	var spd := 0.0
	match state:
		SLEEP:
			var tg = _pick_target()
			if tg != null and _flat(tg.global_position, global_position) < (7.5 if kind == "beast" else 99.0):
				_wake()
		PROWL:
			# Pace round the altar / tree.
			var a := t * 0.35
			var p := home + Vector3(cos(a), 0, sin(a)) * minf(leash * 0.55, 3.6)
			want = p - global_position
			spd = speed * 0.4
			var tg = _pick_target()
			if tg != null:
				target = tg
				state = CHASE
				t = 0.0
				if kind == "crawler":
					main.sfx.play("screech", global_position, 2.0, 0.55)
		CHASE:
			target = _pick_target()
			if target == null:
				awake_t += delta
				want = home - global_position
				spd = speed * 0.6
				if awake_t > 6.0 and _flat(global_position, home) < 1.5:
					state = SLEEP if kind == "beast" else PROWL
					t = 0.0
			else:
				awake_t = 0.0
				var to: Vector3 = target.global_position - global_position
				to.y = 0.0
				var d := to.length()
				want = to
				spd = speed
				var reach: float = Cfg.GUARD_REACH + body_radius() * 0.5
				if cd <= 0.0 and d < reach:
					_begin_windup(to, false)
				elif cd <= 0.0 and d > 4.5 and d < 9.0 and randf() < delta * 0.9:
					_begin_windup(to, true)
		WINDUP:
			if target != null and is_instance_valid(target) and not charging:
				var to: Vector3 = target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.1:
					atk_dir = atk_dir.slerp(to.normalized(), minf(1.0, delta * 3.0)).normalized()
			facing = atk_dir
			_show_warn()
			if t >= Cfg.GUARD_WINDUP * (1.25 if charging else 1.0) * (1.3 if main.gentle else 1.0):
				state = ATTACK
				t = 0.0
				hit_done.clear()
				warn_ring.visible = false
				main.sfx.play("swing", global_position, 4.0, 0.5 if kind == "beast" else 0.7)
		ATTACK:
			if charging:
				want = atk_dir
				spd = Cfg.BEAST_CHARGE_SPEED if kind == "beast" else Cfg.BEAST_CHARGE_SPEED * 0.8
				_strike(1.4, 0.0)
				if t > 0.75:
					_end_attack()
			else:
				if t > 0.08 and t < 0.3:
					_strike(Cfg.GUARD_REACH + body_radius() * 0.5, 0.25)
				if t > 0.35:
					_end_attack()
		RECOVER:
			if t > 0.55:
				state = CHASE
				t = 0.0
		STAGGER:
			if t > 0.55:
				state = CHASE
				t = 0.0
				cd = maxf(cd, 0.6)
		DEAD:
			if t > 2.4 and visible:
				visible = false
			reform_t -= delta
			if reform_t <= 0.0:
				_reform()
		REFORM:
			if t > 2.0:
				state = SLEEP if kind == "beast" else PROWL
				t = 0.0
				hp = max_hp
				eye_light.light_energy = 1.2
				main.on_guardian_reformed(self)
	_move(want, spd, delta)
	_animate(delta, spd)


func _begin_windup(to: Vector3, charge: bool) -> void:
	state = WINDUP
	t = 0.0
	charging = charge
	atk_dir = to.normalized() if to.length() > 0.01 else facing
	main.sfx.play("screech", global_position, 3.0, 0.45 if kind == "beast" else 0.6)


func _end_attack() -> void:
	state = RECOVER
	t = 0.0
	charging = false
	cd = Cfg.GUARD_COOLDOWN * randf_range(0.8, 1.3)


## Hurts every pilgrim in front (a swipe: `cone` > 0) or in its path (a charge).
func _strike(reach: float, cone: float) -> void:
	var dmg: float = Cfg.BEAST_DAMAGE if kind == "beast" else Cfg.CRAWLER_DAMAGE
	var force: float = Cfg.BEAST_KNOCK if kind == "beast" else Cfg.CRAWLER_KNOCK
	for s in main.survivors:
		if not s.alive or s.escaped or hit_done.has(s):
			continue
		var to: Vector3 = s.global_position - global_position
		if absf(to.y) > 2.5:
			continue
		to.y = 0.0
		var d := to.length()
		if d > reach + 0.4:
			continue
		if cone > 0.0 and d > 0.8 and to.normalized().dot(atk_dir) < cone:
			continue
		hit_done[s] = true
		var braced: bool = s.bracing and s.brace_ready
		s.receive_bite(self, dmg * main.bite_mult(s))
		var dir := to.normalized() if d > 0.05 else atk_dir
		dir = (dir + atk_dir * 0.5).normalized()
		s.shoved(dir * force * (0.35 if braced else 1.0) + Vector3(0, 4.0, 0), null)
		if s.is_player:
			s.shake = maxf(s.shake, 0.5)
			main.hud.toast("The %s %s you!" % [display, "gored" if kind == "beast" else "slashed"])
		main.sfx.play("bite", s.global_position, 2.0, 0.6)


func _show_warn() -> void:
	warn_ring.visible = true
	var k := clampf(t / Cfg.GUARD_WINDUP, 0.0, 1.0)
	warn_mat.albedo_color = Color(1.0, 0.15, 0.08, 0.25 + 0.45 * k)
	warn_ring.global_position = global_position + Vector3(0, 0.06, 0) + atk_dir * (3.0 if charging else 1.4)
	warn_ring.scale = Vector3(1.6, 1.0, 4.2) if charging else Vector3(1.0, 1.0, 1.0) * (Cfg.GUARD_REACH + body_radius() * 0.5) * 0.62
	warn_ring.rotation.y = atan2(atk_dir.x, atk_dir.z)


func _move(want: Vector3, spd: float, delta: float) -> void:
	var v := Vector3.ZERO
	want.y = 0.0
	if want.length() > 0.3 and spd > 0.0:
		v = want.normalized() * spd
		if state != WINDUP and state != ATTACK:
			facing = facing.slerp(want.normalized(), minf(1.0, delta * 6.0)).normalized()
	v += knock
	var p := global_position + v * delta
	# Stay in its arena and out of the tree / altar.
	var off := Vector2(p.x - arena.x, p.z - arena.z)
	if off.length() > leash:
		off = off.normalized() * leash
		p.x = arena.x + off.x
		p.z = arena.z + off.y
		if charging:
			_end_attack()
	for a in avoid:
		var c: Vector2 = a[0]
		var r: float = float(a[1]) + body_radius() * 0.6
		var q := Vector2(p.x, p.z) - c
		if q.length() < r:
			q = q.normalized() * r if q.length() > 0.01 else Vector2(r, 0)
			p.x = c.x + q.x
			p.z = c.y + q.y
	p.y = home.y
	move_k = lerpf(move_k, (Vector2(p.x, p.z) - Vector2(global_position.x, global_position.z)).length() / maxf(delta, 0.001), minf(1.0, delta * 8.0))
	global_position = p
	rotation.y = lerp_angle(rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 10.0))


func _reform() -> void:
	state = REFORM
	t = 0.0
	visible = true
	global_position = home
	model.scale = Vector3.ONE * 0.05
	model.rotation = Vector3.ZERO
	model.position = Vector3.ZERO
	create_tween().tween_property(model, "scale", Vector3.ONE, 1.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	main.fx_burst(home + Vector3(0, 0.6, 0), Color(0.5, 1.0, 0.5) if kind == "beast" else Color(0.7, 0.45, 1.0), 50, false, 3.0)
	main.sfx.play("screech", home, 0.0, 0.5)


# ---------------------------------------------------------------- animation

func _p(n: String) -> Node3D:
	return parts.get(n)


func _pose_sleep(k: float) -> void:
	if kind != "beast":
		return
	model.position.y = lerpf(model.position.y, -0.75, k)
	for n in ["leg_fl", "leg_fr"]:
		_p(n).basis = rest[n].basis * Basis(Vector3.RIGHT, -1.25 * k)
	for n in ["leg_bl", "leg_br"]:
		_p(n).basis = rest[n].basis * Basis(Vector3.RIGHT, 1.2 * k)
	_p("head").basis = rest["head"].basis * Basis(Vector3.RIGHT, 0.35 * k)


func _animate(delta: float, _spd: float) -> void:
	if model == null:
		return
	var moving := clampf(move_k / maxf(speed, 0.1), 0.0, 2.0)
	gait += delta * (2.2 + move_k * (1.3 if kind == "beast" else 2.0))
	overlay.albedo_color = Color(1.0, 0.25, 0.15, 0.6 * flash)
	var glow := 1.2
	if state == WINDUP:
		glow = 3.0 + 4.0 * clampf(t / Cfg.GUARD_WINDUP, 0.0, 1.0)
	elif state == SLEEP:
		glow = 0.15
	eye_mat.emission_energy_multiplier = glow * 2.0
	if state != DEAD:
		eye_light.light_energy = glow * 0.5
	if state == DEAD:
		model.rotation.z = lerpf(model.rotation.z, PI * 0.5, minf(1.0, delta * 3.0))
		model.position.y = lerpf(model.position.y, -0.6 - maxf(0.0, t - 1.2), minf(1.0, delta * 3.0))
		return
	if state == SLEEP:
		_pose_sleep(minf(1.0, delta * 3.0))
		model.scale.y = 1.0 + 0.02 * sin(gait * 0.8)
		return
	model.scale.y = 1.0
	var bob := 0.0
	var head_x := 0.0
	var jaw_x := 0.0
	var lean := 0.0
	if state == WINDUP:
		var k := clampf(t / Cfg.GUARD_WINDUP, 0.0, 1.0)
		head_x = -0.45 * k
		jaw_x = 0.5 * k
		lean = -0.12 * k
	elif state == ATTACK:
		head_x = 0.35
		jaw_x = 0.6
		lean = 0.12
	elif state == STAGGER:
		head_x = -0.3
		lean = -0.2 * (1.0 - t / 0.55)
	model.position.y = lerpf(model.position.y, bob, minf(1.0, delta * 6.0))
	model.rotation.x = lerpf(model.rotation.x, lean, minf(1.0, delta * 8.0))
	var swing := clampf(moving, 0.0, 1.2) * (0.55 if kind == "beast" else 0.45)
	if kind == "beast":
		var ph := {"leg_fl": 0.0, "leg_br": 0.0, "leg_fr": PI, "leg_bl": PI}
		for n in ph:
			var leg := _p(n)
			leg.basis = rest[n].basis * Basis(Vector3.RIGHT, sin(gait + float(ph[n])) * swing)
		model.position.y += absf(sin(gait)) * 0.06 * moving
		_p("tail").basis = rest["tail"].basis * Basis(Vector3.UP, sin(gait * 0.7) * 0.35) * Basis(Vector3.RIGHT, -0.2 * moving)
	else:
		for i in 6:
			var n := "leg_%d" % i
			var leg := _p(n)
			var side := -1.0 if i % 2 == 0 else 1.0
			var ph := 0.0 if (i == 0 or i == 3 or i == 4) else PI
			var lift := maxf(0.0, cos(gait * 1.4 + ph)) * 0.35 * minf(1.0, moving + 0.15)
			leg.basis = rest[n].basis * Basis(Vector3.UP, sin(gait * 1.4 + ph) * swing) * Basis(Vector3.FORWARD, lift * side)
		model.position.y += sin(gait * 2.8) * 0.03 * moving
	var head := _p("head")
	head.basis = head.basis.slerp(rest["head"].basis * Basis(Vector3.RIGHT, head_x + sin(gait * 0.5) * 0.05), minf(1.0, delta * 10.0))
	var jaw := _p("jaw")
	jaw.basis = jaw.basis.slerp(rest["jaw"].basis * Basis(Vector3.RIGHT, jaw_x), minf(1.0, delta * 12.0))


# ---------------------------------------------------------------- build

func _tri_mat(tex: String, scale: float, tint: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/%s.png" % tex)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://textures/%s_n.png" % tex)
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 3.0
	m.vertex_color_use_as_albedo = false
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.rim_enabled = true
	m.rim = 0.25
	m.rim_tint = 0.6
	return m


func _build() -> void:
	model = main.world._model("res://models/%s.glb" % kind, self, Vector3.ZERO)
	_collect(model)
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(1.0, 0.7, 0.2) if kind == "beast" else Color(0.75, 0.4, 1.0)
	eye_mat.emission_enabled = true
	eye_mat.emission = eye_mat.albedo_color
	eye_mat.emission_energy_multiplier = 2.0
	_mats = {
		"beasthide": _tri_mat("tex_beast_hide", 1.4, Color(0.95, 0.9, 0.85), 0.9),
		"thorn": _tri_mat("tex_bark", 2.5, Color(0.7, 0.62, 0.55), 0.85),
		"horn": _tri_mat("tex_bark", 2.0, Color(0.55, 0.5, 0.45), 0.6),
		"bloomlet": main.world._mat(Color(1.0, 0.7, 0.9), 0.6, Color(1.0, 0.45, 0.75), 1.2),
		"eye": eye_mat,
		"caverock": _tri_mat("tex_cave_rock", 1.2, Color(0.6, 0.58, 0.66), 0.75),
		"crystal": main.world.crystal_mat,
	}
	overlay = StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.albedo_color = Color(1, 0.3, 0.2, 0.0)
	_apply_mats(model)
	eye_light = OmniLight3D.new()
	eye_light.light_color = eye_mat.albedo_color
	eye_light.light_energy = 1.2
	eye_light.omni_range = 5.0
	eye_light.position = Vector3(0, 1.8 if kind == "beast" else 1.2, 1.8)
	add_child(eye_light)
	# The tell: a red area on the ground showing where the next blow lands.
	warn_mat = StandardMaterial3D.new()
	warn_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warn_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warn_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	warn_mat.no_depth_test = false
	warn_mat.albedo_color = Color(1.0, 0.15, 0.08, 0.4)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	warn_ring = MeshInstance3D.new()
	warn_ring.mesh = disc
	warn_ring.material_override = warn_mat
	warn_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warn_ring.top_level = true
	warn_ring.visible = false
	add_child(warn_ring)


func _collect(n: Node) -> void:
	for ch in n.get_children():
		if ch is Node3D:
			var nm := String(ch.name).to_lower()
			for key in ["body", "head", "jaw", "tail", "leg_fl", "leg_fr", "leg_bl", "leg_br", "leg_0", "leg_1", "leg_2", "leg_3", "leg_4", "leg_5"]:
				if nm == key and not parts.has(key):
					parts[key] = ch
					rest[key] = ch.transform
		_collect(ch)


func _apply_mats(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		mi.material_overlay = overlay
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			var key: String = (src.resource_name if src else mi.mesh.surface_get_name(i)).to_lower()
			for k in _mats:
				if key.begins_with(k):
					mi.set_surface_override_material(i, _mats[k])
					break
	for ch in n.get_children():
		_apply_mats(ch)
