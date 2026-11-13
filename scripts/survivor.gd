extends CharacterBody3D
## A pilgrim. Light (health) is shown by their lantern. Subclasses provide _controller().

const Cfg = preload("res://scripts/cfg.gd")
const Arms = preload("res://scripts/arms.gd")

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
var flares: int = Cfg.FLARE_START
var flare_regen := 0.0
var want_jump := false
var air_speed := 0.0 # if > 0, horizontal speed through the air (aimed jumps)
var jump_buffer := 0.0
var coyote := 0.0
var air_jumps := 0
var shove_cd := 0.0
var fell := false
var fall_t := 0.0
var last_shover = null
var last_shove_ms := 0
var cause := ""
var last_wyrm_ms := -100000
var last_blade_ms := -100000
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

# Level 1 (the Gauntlet).
var cphase := 1 # 1 blades, 2 steps, 3 arena, 4 rope, 5 to the gate, 6 finished
var lane := 1
var checkpoint := Vector3.ZERO
var kills := 0
var has_lamp := false
var has_rope := false
var weapons := {} # kind -> true
var weapon := ""
var attack_cd := 0.0
var saw_out := false
var rope_ring := -1
var rope_state := "" # "", "zip", "hang"
var hang_t := 0.0
var invuln := 0.0
var respawn_t := 0.0
var finish_time := -1.0
var place := 0
var _hang_sway := Vector3.ZERO
var _rope_mesh: MeshInstance3D
var _weapon_nodes := {}
var _flicker_t := 0.0

var visual: Node3D
var char_index := 0
var model: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var model_meshes: Array = []
var hurt_mat: StandardMaterial3D
var _hurt_on := false
var _oneshot := ""
var _oneshot_t := 0.0
var lantern: OmniLight3D
var lantern_col := Color(1.0, 0.8, 0.55)
var bulb_mat: StandardMaterial3D
var tool_pivot: Node3D
var name_label: Label3D
var brace_ring: MeshInstance3D


func setup(p_main, p_name: String, p_tint: Color, p_spawn: Vector3, p_char := 0) -> void:
	char_index = p_char
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
	if main.is_course:
		invuln = maxf(0.0, invuln - delta)
		attack_cd = maxf(0.0, attack_cd - delta)
		if respawn_t > 0.0:
			respawn_t -= delta
			velocity = Vector3.ZERO
			if respawn_t <= 0.0:
				_reappear()
			return
	var playing: bool = main.state == "playing"
	if alive and playing:
		swing_cd = maxf(0.0, swing_cd - delta)
		flare_cd = maxf(0.0, flare_cd - delta)
		shove_cd = maxf(0.0, shove_cd - delta)
		if flares <= 0:
			flare_regen += delta
			if flare_regen >= Cfg.FLARE_RECHARGE * (0.6 if is_player and main.gentle else 1.0):
				flare_regen = 0.0
				flares = 1
				if is_player:
					main.hud.toast("Your lantern rekindled a flare")
		if not brace_ready:
			brace_recover -= delta
			if brace_recover <= 0.0:
				brace_ready = true
		_controller(delta)
	else:
		move_dir = Vector3.ZERO
		want_sprint = false
		want_jump = false
		bracing = false
	if bracing and light < Cfg.BRACE_LIGHT:
		bracing = false
	if rope_state != "":
		_rope_physics(delta)
		_update_visual()
		return

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

	var grounded := is_on_floor()
	if air_speed > 0.0 and (not grounded or jump_buffer > 0.0 or want_jump):
		speed = air_speed
	var hv := Vector3.ZERO
	if moving:
		hv = move_dir.normalized() * speed
	hv += knock
	knock = knock.lerp(Vector3.ZERO, minf(1.0, delta * (4.0 if grounded else 1.5)))
	var k := minf(1.0, delta * (12.0 if grounded else Cfg.AIR_CONTROL))
	velocity.x = lerpf(velocity.x, hv.x, k)
	velocity.z = lerpf(velocity.z, hv.z, k)
	velocity.y -= Cfg.GRAVITY * delta
	if main.is_course and not grounded:
		velocity += main.world.gust_force(global_position) * delta
	# Jumping, with a little forgiveness: a press just before landing, or just after
	# stepping off an edge, still counts.
	coyote = 0.13 if grounded else coyote - delta
	if grounded:
		air_jumps = Cfg.AIR_JUMPS
	if want_jump:
		want_jump = false
		if not grounded and coyote <= 0.0 and air_jumps > 0 and alive and playing and not escaped and not fell:
			_air_jump(hv, moving)
		else:
			jump_buffer = 0.15
	jump_buffer -= delta
	if jump_buffer > 0.0 and coyote > 0.0 and alive and playing and not escaped:
		velocity.y = Cfg.JUMP_VEL
		if moving:
			velocity.x = hv.x
			velocity.z = hv.z
		jump_buffer = 0.0
		coyote = 0.0
		main.sfx.play("jump", null if is_player else global_position, -6.0 if is_player else -10.0, randf_range(0.9, 1.15))
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
	if global_position.y < main.world.FALL_Y and not fell:
		_fall_into_abyss()
	if fell:
		fall_t += delta
		if global_position.y < main.world.UNDERWORLD_Y + 3.0 and visual.visible:
			visual.visible = false
			name_label.visible = false
			main.on_hit_underglow(self)
			set_physics_process(false)
			return
	_update_visual()


## Double jump: a second push in mid-air. Cancels any knockback so you can steer back
## to the stones after a miss, a shove or a blade.
func _air_jump(hv: Vector3, moving: bool) -> void:
	air_jumps -= 1
	velocity.y = Cfg.AIR_JUMP_VEL
	knock = Vector3.ZERO
	if moving:
		var flat := Vector3(hv.x, 0, hv.z)
		var v := move_dir.normalized() * maxf(flat.length(), Cfg.WALK_SPEED)
		velocity.x = v.x
		velocity.z = v.z
	else:
		velocity.x *= 0.3
		velocity.z *= 0.3
	jump_buffer = 0.0
	main.fx_ring(global_position + Vector3(0, 0.1, 0), lantern_col, 1.1, 0.35)
	main.sfx.play("jump", null if is_player else global_position, -4.0 if is_player else -10.0, randf_range(1.3, 1.45))


func _fall_into_abyss() -> void:
	if main.is_course and alive and cphase >= 2:
		begin_respawn()
		return
	fell = true
	if alive:
		cause = "fell"
		collapse()


func push(v: Vector3) -> void:
	knock = v


## A hard push (a shove, a bite, a blast): takes effect at once, even in mid-air.
func shoved(v: Vector3, by = null) -> void:
	if not alive or escaped or respawn_t > 0.0:
		return
	if rope_state != "":
		rope_release(false)
	knock = Vector3(v.x, 0.0, v.z)
	velocity.x = v.x
	velocity.z = v.z
	velocity.y = maxf(velocity.y, v.y)
	if by != null:
		last_shover = by
		last_shove_ms = Time.get_ticks_msec()


func try_shove() -> bool:
	if not alive or escaped or shove_cd > 0.0:
		return false
	shove_cd = Cfg.SHOVE_COOLDOWN
	play_once("push", 0.42)
	main.do_shove(self)
	return true


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
		if main.is_course and cphase >= 2:
			light = 1.0
			begin_respawn()
		else:
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
	play_once("swing", 0.5)
	if tool_swings <= 0:
		get_tree().create_timer(0.4).timeout.connect(func(): tool_pivot.visible = false)
		if is_player:
			main.hud.toast("Your %s broke." % tool_name)
		tool_name = ""


func try_flare() -> bool:
	if not alive or escaped or flare_cd > 0.0 or flares <= 0:
		return false
	flare_cd = Cfg.FLARE_COOLDOWN
	flares -= 1
	main.stats["flare"] += 1
	main.do_flare(self)
	return true


func add_flares(n: int) -> void:
	flares = mini(Cfg.FLARE_MAX, flares + n)
	flare_regen = 0.0


func collapse(silent := false) -> void:
	if not alive:
		return
	alive = false
	light = 0.0
	collision_layer = 0
	bracing = false
	brace_ring.visible = false
	var tw := create_tween()
	if cause == "fell":
		tw.tween_property(visual, "rotation:x", PI * 0.9, 1.2)
	else:
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
	brace_ring.visible = alive and bracing and brace_ready
	# A red glow over the whole character when hurt.
	var want := hurt_flash > 0.02
	if want != _hurt_on:
		_hurt_on = want
		for m in model_meshes:
			m.material_overlay = hurt_mat if want else null
	if want:
		hurt_mat.albedo_color.a = hurt_flash * 0.55
	_animate()


func p_debug_flag(n: String) -> bool:
	return main.args.has(n)


## Plays an action once (push, swing), over whatever the legs are doing.
func play_once(name: String, dur: float) -> void:
	_oneshot = name
	_oneshot_t = dur
	if anim and anim.has_animation(name):
		anim.play(name, 0.08)
		anim.speed_scale = 1.0


func _animate() -> void:
	if anim == null:
		return
	var dt := get_physics_process_delta_time()
	_oneshot_t = maxf(0.0, _oneshot_t - dt)
	var name := "idle"
	var spd := Vector2(velocity.x, velocity.z).length()
	var scale := 1.0
	if escaped:
		return
	if not alive:
		name = "fall" if fell else ""
	elif _oneshot_t > 0.0:
		return
	elif rope_state != "":
		name = "jump"
	elif not is_on_floor() and velocity.y > 1.0:
		name = "jump"
	elif not is_on_floor() and velocity.y < -4.0:
		name = "fall"
	elif bracing:
		name = "brace"
	elif spd > 5.8:
		name = "run"
		scale = spd / 7.0
	elif spd > 0.6:
		name = "walk"
		scale = clampf(spd / 4.0, 0.5, 1.4)
	if name == "":
		if anim.is_playing():
			anim.pause()
		return
	if anim.current_animation != name:
		anim.play(name, 0.18)
	anim.speed_scale = scale


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
	# The pilgrim: a rigged, animated model made in Blender
	# (3d/tests/lastlight_world/scripts/build_characters.py), one per name.
	var scene: PackedScene = load("res://models/chars/char_%d.glb" % char_index)
	model = scene.instantiate()
	visual.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for n in ["idle", "walk", "run", "fall", "brace"]:
		if anim.has_animation(n):
			anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	anim.seek(randf() * 1.5)
	if p_debug_flag("nochars"):
		model.visible = false
	if p_debug_flag("noanim"):
		anim.active = false
	var look := StandardMaterial3D.new()
	look.vertex_color_use_as_albedo = true
	look.vertex_color_is_srgb = true
	look.roughness = 0.72
	look.rim_enabled = true
	look.rim = 0.25
	look.rim_tint = 0.6
	for m in model.find_children("*", "MeshInstance3D", true, false):
		model_meshes.append(m)
		m.material_override = look
		if p_debug_flag("noshadow"):
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hurt_mat = StandardMaterial3D.new()
	hurt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hurt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hurt_mat.albedo_color = Color(1.0, 0.1, 0.08, 0.0)
	hurt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	# Lantern = health.
	lantern_col = Color(1.0, 0.8, 0.55).lerp(tint, 0.3)
	# Held in the left hand.
	var hand_l := BoneAttachment3D.new()
	hand_l.bone_name = "hand.L"
	skel.add_child(hand_l)
	var lr := Node3D.new()
	lr.position = Vector3(0, 0.12, -0.02)
	hand_l.add_child(lr)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.2, 0.17, 0.15)
	frame_mat.metallic = 0.6
	frame_mat.roughness = 0.4
	var plate := BoxMesh.new()
	plate.size = Vector3(0.2, 0.04, 0.2)
	plate.size = Vector3(0.14, 0.03, 0.14)
	_add_mesh(lr, plate, frame_mat, Vector3(0, 0.1, 0))
	_add_mesh(lr, plate, frame_mat, Vector3(0, -0.1, 0))
	bulb_mat = StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1, 0.92, 0.7)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = lantern_col
	bulb_mat.emission_energy_multiplier = 3.0
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.16
	_add_mesh(lr, bulb, bulb_mat, Vector3.ZERO)
	lantern = OmniLight3D.new()
	lantern.light_color = lantern_col
	lantern.shadow_enabled = false
	lr.add_child(lantern)

	# Tool (hidden until picked up).
	var hand_r := BoneAttachment3D.new()
	hand_r.bone_name = "hand.R"
	skel.add_child(hand_r)
	tool_pivot = Node3D.new()
	tool_pivot.position = Vector3(0, 0.06, 0)
	tool_pivot.rotation.x = PI / 2.0
	hand_r.add_child(tool_pivot)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.32, 0.22)
	var staff := CylinderMesh.new()
	staff.top_radius = 0.03
	staff.bottom_radius = 0.035
	staff.height = 1.2
	_add_mesh(tool_pivot, staff, wood, Vector3(0, 0.3, 0))
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(1.0, 0.8, 0.4)
	gold.metallic = 0.8
	gold.emission_enabled = true
	gold.emission = Color(1.0, 0.75, 0.35)
	gold.emission_energy_multiplier = 2.0
	var tip := TorusMesh.new()
	tip.inner_radius = 0.06
	tip.outer_radius = 0.12
	_add_mesh(tool_pivot, tip, gold, Vector3(0, 0.92, 0), Vector3(PI / 2.0, 0, 0))
	tool_pivot.visible = false
	# Level 1 weapons, in the same hand.
	var wp := Node3D.new()
	wp.position = Vector3(0, 0.04, 0)
	wp.rotation.x = PI / 2.0
	hand_r.add_child(wp)
	for kind in ["axe", "saw", "bow"]:
		var n := Arms.make(kind)
		n.visible = false
		wp.add_child(n)
		_weapon_nodes[kind] = n
	_rope_mesh = MeshInstance3D.new()
	var rc := CylinderMesh.new()
	rc.top_radius = 0.02
	rc.bottom_radius = 0.02
	rc.height = 1.0
	rc.radial_segments = 5
	_rope_mesh.mesh = rc
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.85, 0.72, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.75, 0.4)
	rmat.emission_energy_multiplier = 0.8
	_rope_mesh.material_override = rmat
	_rope_mesh.top_level = true
	_rope_mesh.visible = false
	_rope_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope_mesh)

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


# ---------------------------------------------------------------- Level 1

func give_weapon(kind: String) -> void:
	weapons[kind] = true
	select_weapon(kind)


func select_weapon(kind: String) -> void:
	if not weapons.has(kind) or kind == weapon:
		return
	weapon = kind
	for k in _weapon_nodes:
		_weapon_nodes[k].visible = k == kind
	tool_pivot.visible = false


func cycle_weapon(step: int) -> void:
	var order := ["bow", "axe", "saw"]
	var owned: Array = []
	for k in order:
		if weapons.has(k):
			owned.append(k)
	if owned.size() < 2:
		return
	var i := owned.find(weapon)
	select_weapon(owned[posmod(i + step, owned.size())])


## Fire the rope at ring i: zip up to it, then hang.
func rope_fire(i: int) -> void:
	if i < 0 or not has_rope or not alive:
		return
	rope_ring = i
	rope_state = "zip"
	hang_t = 0.0
	knock = Vector3.ZERO
	air_jumps = Cfg.AIR_JUMPS
	_rope_mesh.visible = true
	main.sfx.play("swish", null if is_player else global_position, -2.0, 0.6)
	main.sfx.play("jump", null if is_player else global_position, -8.0, 0.8)


## Let go of the rope; with jump, swing forward off it.
func rope_release(jump := true) -> void:
	if rope_state == "":
		return
	var rv: Vector3 = main.world.ring_vel(rope_ring)
	rope_state = ""
	rope_ring = -1
	_rope_mesh.visible = false
	air_jumps = Cfg.AIR_JUMPS
	coyote = 0.0
	if jump:
		velocity = Vector3(0, 0, -6.5) + Vector3(0, 5.0, 0) + rv * 0.5
		main.sfx.play("jump", null if is_player else global_position, -6.0, 1.1)
	else:
		velocity = rv


func _rope_physics(delta: float) -> void:
	var w = main.world
	var hang: Vector3 = w.ring_hang(rope_ring)
	var gust: Vector3 = w.gust_force(global_position)
	facing = Vector3(0, 0, -1)
	if rope_state == "zip":
		var to := hang - global_position
		var d := to.length()
		var step: float = Cfg.ROPE_SPEED * delta
		if d <= step + 0.05:
			global_position = hang
			rope_state = "hang"
			hang_t = 0.0
			_hang_sway = Vector3.ZERO
		else:
			global_position += to / d * step + gust * delta * 0.3
			velocity = to / d * Cfg.ROPE_SPEED
	else:
		hang_t += delta
		_hang_sway = (_hang_sway.lerp(Vector3.ZERO, minf(1.0, delta * 1.5)) + gust * delta * 0.25).limit_length(1.4)
		global_position = hang + _hang_sway + Vector3(0, _hang_sway.length_squared() * 0.15, 0)
		velocity = w.ring_vel(rope_ring)
	# The rope, from the hand up to the ring.
	var a := global_position + Vector3(0, 1.75, 0)
	var b: Vector3 = w.ring_pos(rope_ring) - Vector3(0, 0.45, 0)
	var dl := b - a
	var rl := maxf(0.05, dl.length())
	var y := dl / rl
	var x := y.cross(Vector3(0, 0, 1))
	if x.length() < 0.01:
		x = Vector3(1, 0, 0)
	x = x.normalized()
	_rope_mesh.global_transform = Transform3D(Basis(x, y * rl, x.cross(y)), (a + b) * 0.5)
	if global_position.y < main.world.FALL_Y:
		_fall_into_abyss()


## Fell (or burned out) after the first checkpoint: disappear, then come back there.
func begin_respawn() -> void:
	if respawn_t > 0.0:
		return
	if rope_state != "":
		rope_state = ""
		rope_ring = -1
		_rope_mesh.visible = false
	respawn_t = Cfg.RESPAWN_DELAY
	velocity = Vector3.ZERO
	knock = Vector3.ZERO
	visual.visible = false
	name_label.visible = false
	collision_layer = 0
	main.on_course_respawn(self)
	global_position = checkpoint + Vector3(0, 0.3, 0)


func _reappear() -> void:
	global_position = checkpoint + Vector3(0, 0.3, 0)
	velocity = Vector3.ZERO
	visual.visible = true
	name_label.visible = not is_player
	collision_layer = 2
	light = maxf(light, Cfg.RESPAWN_LIGHT)
	invuln = 1.5
	main.fx_ring(global_position + Vector3(0, 0.2, 0), lantern_col, 1.6, 0.5)
	main.sfx.play("bloom", null if is_player else global_position, -4.0, 0.8)
