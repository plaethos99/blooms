extends Node3D
## The three trials and the road to the portal (v0.9):
## - the Thornback and the Sky Fruit (Hidden Garden),
## - the Shardback and the Moon Potion (Crystal Cave),
## - the gauntlet: fire vents that burst on the causeway stones and launchers that
##   shoot knives across it,
## - the fire seal: four walls of flame round the portal. Walk into one carrying an
##   extinguisher and it goes out for a while; without one it burns you and throws you back.

const Cfg = preload("res://scripts/cfg.gd")
const GuardianScript = preload("res://scripts/guardian.gd")

var main
var world
var beast
var crawler
var jets: Array = [] # Dictionary per fire vent
var launchers: Array = [] # Dictionary per knife launcher
var knives: Array = [] # Dictionary per knife in flight
var seal: Array = [] # Dictionary per section of the fire seal
var potion_t := 2.0 # brewing: a potion appears when this reaches 0
var potion = null
var fruit_t := -1.0
var fruit_left := 0
var _burn_ms := {} # survivor -> last time the fire hurt them
var _flame_tex: Texture2D
var _knife_mesh: Mesh
var _knife_mat: StandardMaterial3D
var _ember_mat: StandardMaterial3D


func build(p_main) -> void:
	main = p_main
	world = main.world
	_flame_tex = _make_flame_tex()
	_build_guardians()
	_build_gauntlet()
	_build_seal()


# ---------------------------------------------------------------- guardians and relics

func _build_guardians() -> void:
	beast = GuardianScript.new()
	var g_leash: float = world.island_radius(world.GARDEN_ISLAND) - world.GARDEN_WALL_INSET - 1.8
	beast.setup(main, "beast", world.tree_pos + Vector3(2.6, 0, 1.2), g_leash, [[Vector2(world.tree_pos.x, world.tree_pos.z), 1.4]])
	beast.arena = world.garden_center
	add_child(beast)
	crawler = GuardianScript.new()
	crawler.setup(main, "crawler", world.cave_center + world.cave_dir * 3.2, world.CAVE_INNER - 1.3, [[Vector2(world.cave_center.x, world.cave_center.z), 1.5]])
	crawler.arena = world.cave_center
	add_child(crawler)


func guardians() -> Array:
	return [beast, crawler]


## The Thornback fell: the tree lets its fruit go a moment later.
func on_beast_down() -> void:
	fruit_t = Cfg.FRUIT_RIPEN
	for fl in world.fruit_lights:
		var tw := create_tween()
		tw.tween_property(fl[0], "scale", Vector3.ONE * 0.01, 1.2)
		if fl[1] != null:
			tw.parallel().tween_property(fl[1], "light_energy", 0.0, 1.2)


func on_beast_reformed() -> void:
	for fl in world.fruit_lights:
		var tw := create_tween()
		tw.tween_property(fl[0], "scale", Vector3.ONE, 1.5)
		if fl[1] != null:
			tw.parallel().tween_property(fl[1], "light_energy", 0.8, 1.5)


func _drop_fruit() -> void:
	for k in Cfg.BEAST_FRUITS:
		var a := TAU * float(k) / float(Cfg.BEAST_FRUITS) + randf_range(-0.4, 0.4)
		var p: Vector3 = world.tree_pos + Vector3(cos(a), 0, sin(a)) * randf_range(2.6, 3.6)
		var from: Vector3 = world.tree_pos + Vector3(cos(a) * 1.8, 4.5, sin(a) * 1.8)
		main.spawn_relic("fruit", p)
		var pk = main.pickups[-1]
		pk.global_position = from
		create_tween().tween_property(pk, "global_position", p, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	main.on_fruit_fell()


func fruit_on_ground() -> Array:
	return main.pickups.filter(func(pk): return is_instance_valid(pk) and pk.kind == "fruit")


func potion_ready() -> bool:
	return potion != null and is_instance_valid(potion)


func on_potion_taken() -> void:
	potion = null
	potion_t = Cfg.POTION_BREW


# ---------------------------------------------------------------- the gauntlet

func _build_gauntlet() -> void:
	var b: Dictionary = world.bridges[world.GAUNTLET]
	var stones: Array = b["stones"]
	var dir: Vector3 = b["dir"]
	var perp: Vector3 = b["perp"]
	_knife_mesh = _make_knife_mesh()
	_knife_mat = StandardMaterial3D.new()
	_knife_mat.albedo_color = Color(0.85, 0.87, 0.9)
	_knife_mat.metallic = 0.95
	_knife_mat.roughness = 0.2
	_knife_mat.emission_enabled = true
	_knife_mat.emission = Color(1.0, 0.5, 0.3)
	_knife_mat.emission_energy_multiplier = 0.4
	var side := 1.0
	var bgaps: Array = b["blade_gaps"]
	for k in stones.size():
		var st: Vector3 = stones[k]
		var r: float = b["radii"][k]
		# Fire vents on every other stone, but never right before or after a blade's gap,
		# so you never have to wait for a blade while standing on a vent.
		if k % 2 == 0 and k > 0 and not bgaps.has(k) and not bgaps.has(k + 1):
			_add_jet(st, -dir)
		elif k % 2 == 1:
			_add_launcher(st, r, perp * side, dir)
			side = -side
	# A launcher on each side of the last stretch, firing alternately.
	if stones.size() >= 2:
		var last: Vector3 = stones[stones.size() - 1]
		_add_launcher(last, float(b["radii"][stones.size() - 1]), perp * side, dir)


func _add_jet(p: Vector3, back: Vector3) -> void:
	var grate := CylinderMesh.new()
	grate.top_radius = 0.75
	grate.bottom_radius = 0.8
	grate.height = 0.08
	grate.radial_segments = 16
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.08, 0.07, 0.06)
	gm.metallic = 0.7
	gm.roughness = 0.5
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.35, 0.05)
	gm.emission_energy_multiplier = 0.2
	var gi := MeshInstance3D.new()
	gi.mesh = grate
	gi.material_override = gm
	gi.position = p + Vector3(0, 0.04, 0)
	add_child(gi)
	var fire := _flames(Vector3(1.1, 0.4, 1.1), 3.4, 90, 1.0)
	fire.position = p + Vector3(0, 0.1, 0)
	add_child(fire)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.5, 0.15)
	l.light_energy = 0.0
	l.omni_range = 9.0
	l.position = p + Vector3(0, 1.5, 0)
	add_child(l)
	var period := randf_range(Cfg.JET_CYCLE.x, Cfg.JET_CYCLE.y)
	jets.append({"pos": p, "t": randf() * period, "period": period, "fire": fire, "light": l, "grate": gm, "state": 0, "back": back})


func _add_launcher(st: Vector3, r: float, out: Vector3, dir: Vector3) -> void:
	# A pillar on its own small floating stone beside the causeway, firing across it.
	var base := st + out * (r + 2.1) + Vector3(0, -0.4, 0)
	world._model("res://models/stone_%d.glb" % (randi() % 6), self, base, Vector3(0, randf() * TAU, 0), Vector3(1.1, 1.0, 1.1))
	var aim := -out
	var yaw := atan2(aim.x, aim.z)
	var pillar: Node3D = world._model("res://models/launcher.glb", self, base, Vector3(0, yaw, 0))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.3, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.25, 0.05)
	glow.emission_energy_multiplier = 0.0
	var eye := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	eye.mesh = sm
	eye.material_override = glow
	eye.position = base + Vector3(0, 2.95, 0) + aim * 0.72
	add_child(eye)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.3, 0.1)
	l.light_energy = 0.0
	l.omni_range = 5.0
	l.position = eye.position
	add_child(l)
	var iv := randf_range(Cfg.KNIFE_INTERVAL.x, Cfg.KNIFE_INTERVAL.y)
	launchers.append({
		"muzzle": base + Vector3(0, 2.95, 0) + aim * 0.8, "aim": aim, "along": dir, "t": randf() * iv, "iv": iv,
		"glow": glow, "light": l, "target_y": st.y + 1.0, "span": (r + 2.1) * 2.0 + 2.0, "node": pillar,
	})


func _build_seal() -> void:
	var c: Vector3 = world.gate_pos
	var front: Vector3 = world.portal_front - c
	front.y = 0.0
	var a_front := atan2(front.z, front.x)
	var n: int = Cfg.SEAL_SEGMENTS
	for k in n:
		var a_mid := a_front + TAU * float(k) / float(n)
		var a0 := a_mid - PI / float(n)
		var a1 := a_mid + PI / float(n)
		# Braziers at the ends, a wall of flame between.
		var br: Node3D = world._model("res://models/brazier.glb", self, c + Vector3(cos(a0), 0, sin(a0)) * Cfg.SEAL_RADIUS)
		br.scale = Vector3.ONE * 1.2
		var fires: Array = []
		var steps := 4
		for j in steps:
			var a := lerpf(a0, a1, (float(j) + 0.5) / float(steps))
			var f := _flames(Vector3(1.3, 0.3, 0.4), 2.9, 48, 1.0)
			f.position = c + Vector3(cos(a), 0, sin(a)) * Cfg.SEAL_RADIUS + Vector3(0, 0.05, 0)
			f.rotation.y = -a
			f.emitting = true
			add_child(f)
			fires.append(f)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.5, 0.15)
		l.light_energy = 2.0
		l.omni_range = 8.0
		l.position = c + Vector3(cos(a_mid), 0, sin(a_mid)) * Cfg.SEAL_RADIUS + Vector3(0, 1.5, 0)
		add_child(l)
		var brazier_fire := _flames(Vector3(0.4, 0.2, 0.4), 1.6, 30, 0.8)
		brazier_fire.position = c + Vector3(cos(a0), 0, sin(a0)) * Cfg.SEAL_RADIUS + Vector3(0, 1.4, 0)
		add_child(brazier_fire)
		seal.append({"mid": a_mid, "out": 0.0, "fires": fires, "light": l})


# ---------------------------------------------------------------- queries for the AI and HUD

func seal_index(p: Vector3) -> int:
	var c: Vector3 = world.gate_pos
	var a := atan2(p.z - c.z, p.x - c.x)
	var best := 0
	var bd := INF
	for k in seal.size():
		var d := absf(angle_difference(a, float(seal[k]["mid"])))
		if d < bd:
			bd = d
			best = k
	return best


func seal_burning(k: int) -> bool:
	return float(seal[k]["out"]) <= 0.0


## Is the stretch of the seal facing p open (put out) right now, for at least `margin` more seconds?
func seal_open_toward(p: Vector3, margin := 2.0) -> bool:
	return float(seal[seal_index(p)]["out"]) > margin


## Will the vent at (or right by) p be burning within the next `ahead` seconds?
func jet_danger(p: Vector3, ahead: float) -> bool:
	for j in jets:
		var jp: Vector3 = j["pos"]
		if Vector2(p.x - jp.x, p.z - jp.z).length() > 2.2 or absf(p.y - jp.y) > 2.0:
			continue
		var tt: float = j["t"]
		var per: float = j["period"]
		# Burning now, or the next burst starts (warn included) within `ahead`.
		if j["state"] == 2:
			return true
		var until_warn := per - Cfg.JET_BURN - Cfg.JET_WARN - tt
		if until_warn < ahead + 0.2:
			return true
	return false


# ---------------------------------------------------------------- loop

func _physics_process(delta: float) -> void:
	if main == null or main.state != "playing":
		return
	_tick_relics(delta)
	_tick_jets(delta)
	_tick_launchers(delta)
	_tick_knives(delta)
	_tick_seal(delta)


func _tick_relics(delta: float) -> void:
	if fruit_t > 0.0:
		fruit_t -= delta
		if fruit_t <= 0.0:
			_drop_fruit()
	if not potion_ready():
		potion_t -= delta
		if potion_t <= 0.0:
			main.spawn_relic("potion", world.altar_pos)
			potion = main.pickups[-1]
			main.fx_burst(world.altar_pos + Vector3(0, 0.6, 0), Color(0.7, 0.45, 1.0), 30, false, 2.0)


func _tick_jets(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for j in jets:
		j["t"] = float(j["t"]) + delta
		var per: float = j["period"]
		var tt: float = j["t"]
		if tt >= per:
			j["t"] = 0.0
			tt = 0.0
		var st := 0
		if tt > per - Cfg.JET_BURN:
			st = 2
		elif tt > per - Cfg.JET_BURN - Cfg.JET_WARN:
			st = 1
		if st != int(j["state"]):
			j["state"] = st
			var f: GPUParticles3D = j["fire"]
			f.emitting = st == 2
			if st == 1:
				main.sfx.play("hiss", j["pos"], -2.0, 1.3)
			elif st == 2:
				main.sfx.play("flare", j["pos"], -4.0, 0.6)
		var gm: StandardMaterial3D = j["grate"]
		gm.emission_energy_multiplier = [0.2, 2.0 + 2.0 * sin(tt * 30.0), 4.0][st]
		var l: OmniLight3D = j["light"]
		l.light_energy = [0.0, 0.8, 4.0][st]
		if st != 2:
			continue
		var jp: Vector3 = j["pos"]
		for s in main.survivors:
			if not s.alive or s.escaped:
				continue
			var sp: Vector3 = s.global_position
			if Vector2(sp.x - jp.x, sp.z - jp.z).length() > 1.2 or sp.y - jp.y > 3.2 or sp.y < jp.y - 0.6:
				continue
			if now - int(_burn_ms.get(s, 0)) < 700:
				continue
			_burn_ms[s] = now
			# Thrown back along the causeway (toward Heart Rock), not off the side.
			_burn(s, Cfg.FIRE_DAMAGE, j["back"], "The fire vent burned you!")


func _burn(s, dmg: float, away: Vector3, msg: String) -> void:
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	s.lose_light(dmg * main.bite_mult(s))
	s.shoved(away.normalized() * Cfg.FIRE_KNOCK + Vector3(0, 4.5, 0), null)
	s.last_fire_ms = Time.get_ticks_msec()
	main.fx_burst(s.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.1), 16, false, 3.0)
	if s.is_player:
		main.hud.toast(msg)
		s.shake = maxf(s.shake, 0.35)


func _tick_launchers(delta: float) -> void:
	for L in launchers:
		L["t"] = float(L["t"]) + delta
		var iv: float = L["iv"]
		var tt: float = L["t"]
		var warn: float = Cfg.KNIFE_WARN * (1.4 if main.gentle else 1.0)
		var k := clampf((tt - (iv - warn)) / warn, 0.0, 1.0)
		var gm: StandardMaterial3D = L["glow"]
		gm.emission_energy_multiplier = k * 6.0 * (0.7 + 0.3 * sin(tt * 40.0))
		L["light"].light_energy = k * 2.5
		if tt >= iv:
			L["t"] = 0.0
			L["iv"] = randf_range(Cfg.KNIFE_INTERVAL.x, Cfg.KNIFE_INTERVAL.y)
			_fire_knife(L)


func _fire_knife(L: Dictionary) -> void:
	var m := MeshInstance3D.new()
	m.mesh = _knife_mesh
	m.material_override = _knife_mat
	add_child(m)
	var from: Vector3 = L["muzzle"]
	var aim: Vector3 = L["aim"]
	# Aim down at chest height over the stone, slightly ahead or behind at random.
	var tgt: Vector3 = from + aim * float(L["span"]) * 0.5
	tgt.y = float(L["target_y"]) + randf_range(-0.1, 0.4)
	tgt += Vector3(L["along"]) * randf_range(-0.8, 0.8)
	var d := (tgt - from).normalized()
	m.global_position = from
	m.look_at(from + d, Vector3.UP)
	knives.append({"node": m, "pos": from, "dir": d, "left": float(L["span"]) + 2.0, "hit": {}, "back": -Vector3(L["along"])})
	main.sfx.play("swish", from, 2.0, randf_range(1.2, 1.4))


func _tick_knives(delta: float) -> void:
	var keep: Array = []
	for kn in knives:
		var step: float = Cfg.KNIFE_SPEED * delta
		var p0: Vector3 = kn["pos"]
		var d: Vector3 = kn["dir"]
		var p1 := p0 + d * step
		kn["pos"] = p1
		kn["left"] = float(kn["left"]) - step
		var node: MeshInstance3D = kn["node"]
		node.global_position = p1
		for s in main.survivors:
			if not s.alive or s.escaped or kn["hit"].has(s):
				continue
			var c: Vector3 = s.global_position + Vector3(0, 1.0, 0)
			# Distance from the body (a vertical segment) to this step of the knife.
			var q := Geometry3D.get_closest_points_between_segments(p0, p1, s.global_position + Vector3(0, 0.2, 0), s.global_position + Vector3(0, 1.7, 0))
			if q[0].distance_to(q[1]) > Cfg.KNIFE_HIT_RADIUS:
				continue
			kn["hit"][s] = true
			s.lose_light(Cfg.KNIFE_DAMAGE * main.bite_mult(s))
			var push := (Vector3(d.x, 0, d.z).normalized() * 0.6 + Vector3(kn["back"])).normalized()
			var braced: bool = s.bracing and s.brace_ready
			s.shoved(push * Cfg.KNIFE_KNOCK * (0.3 if braced else 1.0) + Vector3(0, 2.5, 0), null)
			s.last_blade_ms = Time.get_ticks_msec()
			main.fx_burst(c, Color(1.0, 0.8, 0.6), 12, false, 3.0)
			main.sfx.play("hit", c, 0.0, 1.4)
			if s.is_player:
				main.hud.toast("A flying knife hit you!")
				s.shake = maxf(s.shake, 0.3)
		if float(kn["left"]) <= 0.0:
			node.queue_free()
		else:
			keep.append(kn)
	knives = keep


func _tick_seal(delta: float) -> void:
	var c: Vector3 = world.gate_pos
	var now := Time.get_ticks_msec()
	for k in seal.size():
		var sg: Dictionary = seal[k]
		if float(sg["out"]) > 0.0:
			sg["out"] = float(sg["out"]) - delta
			if float(sg["out"]) <= 0.0:
				_relight(k)
	for s in main.survivors:
		if not s.alive or s.escaped:
			continue
		var sp: Vector3 = s.global_position
		if absf(sp.y - c.y) > 3.0:
			continue
		var d := Vector2(sp.x - c.x, sp.z - c.z).length()
		if d > Cfg.SEAL_RADIUS + 0.7 or d < Cfg.SEAL_RADIUS - 0.9:
			continue
		var k := seal_index(sp)
		if not seal_burning(k):
			continue
		if s.extinguishers > 0:
			s.extinguishers -= 1
			_extinguish(k, s)
			continue
		if now - int(_burn_ms.get(s, 0)) < 600:
			continue
		_burn_ms[s] = now
		_burn(s, Cfg.SEAL_DAMAGE, sp - c, "The flames throw you back! Bring an EXTINGUISHER.")


func _extinguish(k: int, by) -> void:
	var sg: Dictionary = seal[k]
	sg["out"] = Cfg.SEAL_OUT_TIME
	for f in sg["fires"]:
		f.emitting = false
		main.fx_burst(f.global_position + Vector3(0, 0.8, 0), Color(0.85, 0.9, 1.0), 26, true, 2.5)
	create_tween().tween_property(sg["light"], "light_energy", 0.0, 0.5)
	main.sfx.play("hiss", by.global_position, 4.0, 0.8)
	main.sfx.play("water", by.global_position, 0.0, 1.4)
	main.on_seal_doused(by)


func _relight(k: int) -> void:
	var sg: Dictionary = seal[k]
	for f in sg["fires"]:
		f.emitting = true
	create_tween().tween_property(sg["light"], "light_energy", 2.0, 0.5)
	main.sfx.play("flare", sg["fires"][0].global_position, -4.0, 0.5)


# ---------------------------------------------------------------- effects

func _make_flame_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	return gt


## A column of fire: additive billboards rising and fading from yellow to red to smoke.
func _flames(box: Vector3, height: float, amount: int, size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.7
	p.explosiveness = 0.0
	p.randomness = 0.4
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = height * 1.1
	pm.initial_velocity_max = height * 1.6
	pm.gravity = Vector3(0, 1.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.6))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1.0, 0.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cr := Gradient.new()
	cr.set_color(0, Color(1.0, 0.8, 0.4, 0.75))
	cr.set_color(1, Color(0.25, 0.04, 0.02, 0.0))
	cr.add_point(0.2, Color(1.0, 0.45, 0.08, 0.7))
	cr.add_point(0.55, Color(0.8, 0.12, 0.02, 0.4))
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 0.9) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _flame_tex
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.draw_pass_1 = q
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, height * 2.5, 6))
	return p


func _make_knife_mesh() -> Mesh:
	# A long thin blade pointing along -Z (look_at's forward), with a short hilt.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 0.9
	var w := 0.09
	var pts := [Vector3(0, 0, -L), Vector3(w, 0, 0), Vector3(0, 0.02, 0), Vector3(-w, 0, 0), Vector3(0, -0.02, 0)]
	for i in 4:
		var a: Vector3 = pts[1 + i]
		var b: Vector3 = pts[1 + (i + 1) % 4]
		st.add_vertex(pts[0])
		st.add_vertex(a)
		st.add_vertex(b)
	var hilt := [Vector3(0, 0, 0.35), Vector3(0.03, 0, 0), Vector3(0, 0.03, 0), Vector3(-0.03, 0, 0), Vector3(0, -0.03, 0)]
	for i in 4:
		st.add_vertex(hilt[0])
		st.add_vertex(hilt[1 + (i + 1) % 4])
		st.add_vertex(hilt[1 + i])
	st.generate_normals()
	return st.commit()
