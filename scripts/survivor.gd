extends CharacterBody3D
## A pilgrim. Light (health) is shown by their lantern. Subclasses provide _controller().

const Cfg = preload("res://scripts/cfg.gd")

var main
var display_name := "Pilgrim"
var tint := Color.WHITE
var is_player := false

var light: float = Cfg.START_LIGHT
var alive := true
var escaped := false
var lost := false

var tool_name := ""
var tool_swings := 0
var swing_cd := 0.0
var flare_cd := 0.0
var bracing := false
var brace_ready := true
var brace_recover := 0.0
var stamina: float = Cfg.STAMINA_MAX
var move_dir := Vector3.ZERO
var want_sprint := false
var facing := Vector3(0, 0, 1)
var face_lock := 0.0
var knock := Vector3.ZERO
var spawn_point := Vector3.ZERO
var hurt_flash := 0.0
var gate_msg_cd := 0.0
var shake := 0.0
var is_sprinting := false
var _step_acc := 0.0
var _flicker_t := 0.0

var visual: Node3D
var body_mat: StandardMaterial3D
var lantern: OmniLight3D
var lantern_col := Color(1.0, 0.8, 0.55)
var bulb_mat: StandardMaterial3D
var tool_pivot: Node3D
var name_label: Label3D
var brace_ring: MeshInstance3D


func setup(p_main, p_name: String, p_tint: Color, p_spawn: Vector3) -> void:
	main = p_main
	display_name = p_name
	tint = p_tint
	spawn_point = p_spawn
	position = p_spawn


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	floor_snap_length = 0.6
	floor_max_angle = deg_to_rad(40.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_build_visual()


func _controller(_delta: float) -> void:
	pass


func face_toward(p: Vector3) -> void:
	var d := p - global_position
	d.y = 0.0
	if d.length() > 0.01:
		facing = d.normalized()
		visual.rotation.y = atan2(facing.x, facing.z)


func _physics_process(delta: float) -> void:
	_flicker_t += delta
	hurt_flash = maxf(0.0, hurt_flash - delta * 3.0)
	gate_msg_cd = maxf(0.0, gate_msg_cd - delta)
	face_lock = maxf(0.0, face_lock - delta)
	if escaped:
		return
	var playing: bool = main.state == "playing"
	if alive and playing:
		swing_cd = maxf(0.0, swing_cd - delta)
		flare_cd = maxf(0.0, flare_cd - delta)
		if not brace_ready:
			brace_recover -= delta
			if brace_recover <= 0.0:
				brace_ready = true
		_controller(delta)
	else:
		move_dir = Vector3.ZERO
		want_sprint = false
		bracing = false
	if bracing and light < Cfg.BRACE_LIGHT:
		bracing = false

	var speed: float = Cfg.WALK_SPEED
	var moving := move_dir.length() > 0.1
	is_sprinting = false
	if light < Cfg.DIM_LIGHT:
		speed = Cfg.DIM_SPEED
		stamina = minf(Cfg.STAMINA_MAX, stamina + delta * 0.5)
	elif want_sprint and moving and stamina > 0.0:
		speed = Cfg.SPRINT_SPEED
		stamina = maxf(0.0, stamina - delta)
		is_sprinting = true
	else:
		stamina = minf(Cfg.STAMINA_MAX, stamina + delta * 0.5)
	if bracing:
		speed *= Cfg.BRACE_SPEED_MULT

	var hv := Vector3.ZERO
	if moving:
		hv = move_dir.normalized() * speed
	hv += knock
	knock = knock.lerp(Vector3.ZERO, minf(1.0, delta * 4.0))
	var k := minf(1.0, delta * 12.0)
	velocity.x = lerpf(velocity.x, hv.x, k)
	velocity.z = lerpf(velocity.z, hv.z, k)
	velocity.y -= 22.0 * delta
	move_and_slide()
	if is_player and alive and is_on_floor():
		_step_acc += Vector2(velocity.x, velocity.z).length() * delta
		if _step_acc > (2.1 if is_sprinting else 1.6):
			_step_acc = 0.0
			main.sfx.play("step", null, -15.0 if not is_sprinting else -12.0, randf_range(0.8, 1.2))

	if alive:
		if moving and face_lock <= 0.0:
			facing = Vector3(move_dir.x, 0, move_dir.z).normalized()
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), minf(1.0, delta * 12.0))
	if global_position.y < -12.0:
		_fell()
	_update_visual()


func _fell() -> void:
	global_position = spawn_point + Vector3(0, 1.0, 0)
	velocity = Vector3.ZERO
	if alive:
		main.feed("%s fell from the terraces" % display_name, Color(0.8, 0.8, 0.9))
		lose_light(10.0)


func push(v: Vector3) -> void:
	knock = v


func heal(amount: float) -> bool:
	if not alive or escaped or light >= Cfg.MAX_LIGHT:
		return false
	light = minf(Cfg.MAX_LIGHT, light + amount)
	return true


func lose_light(amount: float) -> void:
	if not alive or escaped:
		return
	main.stats["damage"] += minf(amount, light)
	light = maxf(0.0, light - amount)
	hurt_flash = 1.0
	if is_player:
		main.hud.flash_hurt()
		main.sfx.play("hurt", null, -2.0, randf_range(0.9, 1.1))
		shake = maxf(shake, 0.35)
	if light <= 0.0:
		collapse()


func receive_bite(h, dmg: float) -> void:
	if not alive or escaped:
		return
	if bracing and brace_ready:
		brace_ready = false
		brace_recover = Cfg.BRACE_RECOVER
		main.fx_ring(global_position + Vector3(0, 0.15, 0), Color(1.0, 0.85, 0.4), 2.2, 0.4)
		main.sfx.play("brace", null if is_player else global_position, 0.0, randf_range(0.95, 1.05))
		if is_player:
			shake = maxf(shake, 0.2)
		if tool_swings > 0:
			_use_swing()
			h.hit(global_position, 7.0)
		if is_player:
			main.hud.toast("Braced! The bite glances off.")
		return
	lose_light(dmg)


func give_tool(n: String) -> void:
	tool_name = n
	tool_swings = Cfg.TOOL_SWINGS
	tool_pivot.visible = true


func try_swing() -> bool:
	if not alive or tool_swings <= 0 or swing_cd > 0.0:
		return false
	var h = main.find_hollow_in_arc(global_position, facing, Cfg.SWING_REACH)
	_use_swing()
	if h != null:
		h.hit(global_position, 7.0)
		if is_player:
			shake = maxf(shake, 0.15)
	return true


func _use_swing() -> void:
	tool_swings -= 1
	swing_cd = Cfg.SWING_COOLDOWN
	main.sfx.play("swing", null if is_player else global_position, -2.0, randf_range(0.9, 1.15))
	var tw := create_tween()
	tw.tween_property(tool_pivot, "rotation:x", 1.7, 0.1)
	tw.tween_property(tool_pivot, "rotation:x", -0.25, 0.25)
	if tool_swings <= 0:
		tw.tween_callback(func(): tool_pivot.visible = false)
		if is_player:
			main.hud.toast("Your %s broke." % tool_name)
		tool_name = ""


func try_flare() -> bool:
	if not alive or flare_cd > 0.0 or light <= Cfg.FLARE_COST + 1.0:
		return false
	flare_cd = Cfg.FLARE_COOLDOWN * (0.6 if is_player and main.gentle else 1.0)
	light -= Cfg.FLARE_COST
	main.stats["flare"] += Cfg.FLARE_COST
	main.do_flare(self)
	return true


func collapse(silent := false) -> void:
	if not alive:
		return
	alive = false
	light = 0.0
	collision_layer = 0
	bracing = false
	brace_ring.visible = false
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", PI * 0.5, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	name_label.modulate = Color(0.5, 0.5, 0.55, 0.6)
	if not silent:
		main.on_survivor_down(self)


func escape() -> void:
	escaped = true
	collision_layer = 0
	collision_mask = 0
	velocity = Vector3.ZERO
	brace_ring.visible = false
	var tw := create_tween().set_parallel(true)
	tw.tween_property(visual, "scale", Vector3.ONE * 0.01, 1.0)
	tw.tween_property(visual, "position:y", 2.5, 1.0)
	tw.tween_property(name_label, "modulate:a", 0.0, 1.0)
	main.on_survivor_escaped(self)


func _update_visual() -> void:
	var lf := light / 100.0
	var flick := 1.0
	if alive and light < Cfg.DIM_LIGHT:
		flick = 0.55 + 0.45 * absf(sin(_flicker_t * 13.0) * sin(_flicker_t * 5.3))
	lantern.light_energy = (0.25 + 2.3 * lf) * flick if alive else 0.0
	lantern.omni_range = 2.5 + 7.5 * lf
	bulb_mat.emission_energy_multiplier = (0.4 + 6.0 * lf) * flick if alive else 0.0
	body_mat.emission_energy_multiplier = hurt_flash * 2.0
	brace_ring.visible = alive and bracing and brace_ready


func _add_mesh(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	body_mat = StandardMaterial3D.new()
	body_mat.albedo_color = tint
	body_mat.roughness = 0.75
	body_mat.emission_enabled = true
	body_mat.emission = Color(1.0, 0.1, 0.1)
	body_mat.emission_energy_multiplier = 0.0
	var robe := CylinderMesh.new()
	robe.top_radius = 0.22
	robe.bottom_radius = 0.48
	robe.height = 1.25
	robe.radial_segments = 12
	_add_mesh(visual, robe, body_mat, Vector3(0, 0.62, 0))
	var chest := SphereMesh.new()
	chest.radius = 0.3
	chest.height = 0.55
	_add_mesh(visual, chest, body_mat, Vector3(0, 1.25, 0))
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.96, 0.84, 0.72)
	skin.roughness = 0.6
	var head := SphereMesh.new()
	head.radius = 0.19
	head.height = 0.38
	_add_mesh(visual, head, skin, Vector3(0, 1.62, 0.04))
	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = tint.darkened(0.35)
	hood_mat.roughness = 0.9
	var hood := SphereMesh.new()
	hood.radius = 0.24
	hood.height = 0.5
	_add_mesh(visual, hood, hood_mat, Vector3(0, 1.68, -0.07))

	# Lantern = health.
	lantern_col = Color(1.0, 0.8, 0.55).lerp(tint, 0.3)
	var lr := Node3D.new()
	lr.position = Vector3(0.38, 1.0, 0.3)
	visual.add_child(lr)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.2, 0.17, 0.15)
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.4
	var plate := BoxMesh.new()
	plate.size = Vector3(0.2, 0.04, 0.2)
	_add_mesh(lr, plate, frame_mat, Vector3(0, 0.14, 0))
	_add_mesh(lr, plate, frame_mat, Vector3(0, -0.14, 0))
	bulb_mat = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1, 0.92, 0.7)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = lantern_col
	bulb_mat.emission_energy_multiplier = 3.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.1
	bulb.height = 0.22
	_add_mesh(lr, bulb, bulb_mat, Vector3.ZERO)
	lantern = OmniLight3D.new()
	lantern.light_color = lantern_col
	lantern.shadow_enabled = false
	lr.add_child(lantern)

	# Tool (hidden until picked up).
	tool_pivot = Node3D.new()
	tool_pivot.position = Vector3(-0.36, 1.0, 0.15)
	tool_pivot.rotation.x = -0.25
	visual.add_child(tool_pivot)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.22)
	var staff := CylinderMesh.new()
	staff.top_radius = 0.035
	staff.bottom_radius = 0.045
	staff.height = 1.4
	_add_mesh(tool_pivot, staff, wood, Vector3(0, 0.35, 0))
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.4)
	gold.metallic = 0.8
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.75, 0.35)
	gold.emission_energy_multiplier = 2.0
	var tip := TorusMesh.new()
	tip.inner_radius = 0.08
	tip.outer_radius = 0.15
	_add_mesh(tool_pivot, tip, gold, Vector3(0, 1.05, 0), Vector3(PI / 2.0, 0, 0))
	tool_pivot.visible = false

	var tm := TorusMesh.new()
	tm.inner_radius = 0.7
	tm.outer_radius = 0.8
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(1.0, 0.85, 0.4, 0.75)
	brace_ring = _add_mesh(self, tm, bm, Vector3(0, 0.1, 0))
	brace_ring.visible = false

	name_label = Label3D.new()
	name_label.text = display_name
	name_label.position = Vector3(0, 2.3, 0)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.font_size = 40
	name_label.pixel_size = 0.005
	name_label.outline_size = 10
	name_label.modulate = tint.lightened(0.35)
	add_child(name_label)
	if is_player:
		name_label.visible = false
