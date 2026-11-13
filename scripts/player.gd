extends "res://scripts/bot.gd"
## Human-controlled pilgrim with a third-person camera. Builds on the bot so that
## autopilot (P) can hand control to the AI and you can watch how a round is played.

var autopilot := false
var _cam_follow_t := 0.0
var cam_pivot: Node3D
var spring: SpringArm3D
var cam: Camera3D
var yaw := 0.0
var pitch := -0.3
var spectate_idx := 0
var _no_tool_cd := 0.0


func _init() -> void:
	is_player = true


func _ready() -> void:
	super._ready()
	bravery = 0.7
	greed = 0.8
	cam_pivot = Node3D.new()
	cam_pivot.top_level = true
	add_child(cam_pivot)
	spring = SpringArm3D.new()
	spring.spring_length = 5.0
	spring.collision_mask = 1 | 4
	spring.margin = 0.25
	cam_pivot.add_child(spring)
	spring.add_excluded_object(get_rid())
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.far = 2500.0
	spring.add_child(cam)
	cam.current = true
	yaw = atan2(spawn_point.x, spawn_point.z)
	cam_pivot.global_position = spawn_point + Vector3(0, 1.6, 0)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0028
		pitch = clampf(pitch - event.relative.y * 0.0024, -1.25, 0.45)
		_cam_follow_t = 2.0
	elif main.is_course and event is InputEventMouseButton and event.pressed 			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		cycle_weapon(1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
	elif event is InputEventMouseButton and event.pressed:
		var out: bool = main.state == "playing" and (not alive or escaped)
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and main.state != "ended" and not out:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			if main.state == "intro":
				main.start_match()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_TAB:
			spectate_idx += 1
		elif event.keycode == KEY_P:
			set_autopilot(not autopilot)
		elif main.is_course and event.keycode in [KEY_1, KEY_2, KEY_3] and main.state == "playing":
			select_weapon(["bow", "axe", "saw"][[KEY_1, KEY_2, KEY_3].find(event.keycode)])


func set_autopilot(on: bool) -> void:
	autopilot = on
	has_goal = false
	if main.hud:
		main.hud.banner("AUTOPILOT ON\nThe AI is playing for you. Press P to take over." if on else "YOU HAVE CONTROL", 3.0)


func _controller(delta: float) -> void:
	if autopilot:
		super._controller(delta)
		return
	_no_tool_cd = maxf(0.0, _no_tool_cd - delta)
	if main.is_course:
		_course_controller()
		return
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if main.touch:
		iv = (iv + main.touch.move).limit_length(1.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	move_dir = right * iv.x - fwd * iv.y
	want_sprint = Input.is_action_pressed("sprint")
	if main.touch and main.touch.move.length() > 0.92:
		want_sprint = true
	if Input.is_action_just_pressed("jump"):
		want_jump = true
	if Input.is_action_just_pressed("push"):
		facing = fwd
		face_lock = 0.3
		if not try_shove():
			main.hud.toast("Catching your breath (%.0fs)" % shove_cd)
	bracing = Input.is_action_pressed("brace") and light >= Cfg.BRACE_LIGHT
	if bracing:
		facing = fwd
		face_lock = 0.2
	if Input.is_action_just_pressed("swing") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or main.touch):
		facing = fwd
		face_lock = 0.3
		if tool_swings > 0:
			try_swing()
		elif _no_tool_cd <= 0.0:
			_no_tool_cd = 2.0
			main.hud.toast("No tool. Look for a gold beam of light.")
	if Input.is_action_just_pressed("flare"):
		if not try_flare() and flares <= 0:
			main.hud.toast("No flares! Race to a SUNFLARE drop (orange on the map)")
	if Input.is_action_just_pressed("brace") and light < Cfg.BRACE_LIGHT:
		main.hud.toast("Bracing needs 70% light")


## Level 1: move, jump (or let go of the rope), attack where the camera looks, fire the rope.
func _course_controller() -> void:
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if main.touch:
		iv = (iv + main.touch.move).limit_length(1.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	move_dir = right * iv.x - fwd * iv.y
	want_sprint = Input.is_action_pressed("sprint") or (main.touch != null and main.touch.move.length() > 0.92)
	if Input.is_action_just_pressed("jump"):
		if rope_state != "":
			rope_release(true)
		else:
			want_jump = true
	if Input.is_action_just_pressed("push"):
		facing = fwd
		face_lock = 0.3
		try_shove()
	if Input.is_action_just_pressed("swap"):
		cycle_weapon(1)
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or main.touch != null
	if Input.is_action_just_pressed("swing") and captured and weapon != "":
		var aim := aim_dir()
		var flat := Vector3(aim.x, 0, aim.z)
		if flat.length() > 0.05:
			facing = flat.normalized()
			face_lock = 0.3
		main.course_attack(self, aim)
	if Input.is_action_just_pressed("brace") and captured:
		main.course_rope(self)


## Where the crosshair points, as a direction from the chest.
func aim_dir() -> Vector3:
	var o := cam.global_position
	var f := -cam.global_transform.basis.z
	var chest := global_position + Vector3(0, 1.3, 0)
	var p := o + f * 40.0
	var target = main.nearest_flyer_on_ray(o, f, 60.0)
	if target != null:
		p = target.core()
	return (p - chest).normalized()


## Camera aim (origin and direction), for picking a rope ring.
func cam_ray() -> Array:
	return [cam.global_position, -cam.global_transform.basis.z]


func _spectate_target() -> Node3D:
	var list: Array = []
	for s in main.survivors:
		if s != self and s.alive and not s.escaped:
			list.append(s)
	if list.is_empty():
		return self
	return list[spectate_idx % list.size()]


func spectate_name() -> String:
	var t := _spectate_target()
	return "" if t == self else t.display_name


func _process(delta: float) -> void:
	var target: Node3D = self
	if (not alive or escaped) and not (fell and fall_t < 2.6):
		target = _spectate_target()
	if fell and fall_t < 2.6:
		# Watch yourself tumble into the Underglow for a moment.
		pitch = lerpf(pitch, -1.1, minf(1.0, delta * 2.0))
	var tp := target.global_position + Vector3(0, 1.6, 0)
	cam_pivot.global_position = cam_pivot.global_position.lerp(tp, minf(1.0, delta * 10.0))
	# On autopilot (or while spectating) the camera swings behind whoever we follow,
	# unless the mouse moved recently.
	_cam_follow_t = maxf(0.0, _cam_follow_t - delta)
	if (autopilot or target != self) and _cam_follow_t <= 0.0:
		var f: Vector3 = target.facing
		if f.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(-f.x, -f.z), minf(1.0, delta * 1.8))
	if main.is_course and target == self and alive:
		_course_camera(delta)
	cam_pivot.rotation = Vector3(pitch, yaw, 0)
	# Feel: hurt shake, wider view while sprinting, tighter while bracing.
	shake = maxf(0.0, shake - delta * 1.6)
	var s2 := shake * shake
	cam.h_offset = randf_range(-1.0, 1.0) * s2 * 0.6
	cam.v_offset = randf_range(-1.0, 1.0) * s2 * 0.6
	var fov_target := 68.0
	if is_sprinting:
		fov_target = 75.0
	elif bracing:
		fov_target = 62.0
	cam.fov = lerpf(cam.fov, fov_target, minf(1.0, delta * 6.0))


## Level 1: the camera follows you and, when you leave the mouse alone, turns back to
## face down the course. It sits higher on the steps, pulls back in the arena and
## looks up at the rings in the chasm.
func _course_camera(delta: float) -> void:
	var want_len := 5.8
	var want_pitch := -0.36
	match cphase:
		3:
			want_len = 6.8
			want_pitch = -0.1
		4:
			want_len = 7.0
			want_pitch = 0.1
		5, 6:
			want_len = 6.0
			want_pitch = -0.2
	spring.spring_length = lerpf(spring.spring_length, want_len, minf(1.0, delta * 2.0))
	if _cam_follow_t <= 0.0 and main.state == "playing":
		var k := minf(1.0, delta * (1.6 if move_dir.length() > 0.1 or rope_state != "" else 0.7))
		pitch = lerpf(pitch, want_pitch, k)
		# In the arena you turn freely; everywhere else the view swings back down the course.
		if cphase != 3:
			yaw = lerp_angle(yaw, 0.0, k)
