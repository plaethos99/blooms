extends CanvasLayer
## On-screen controls for phones and tablets (enabled automatically on mobile, or with
## `-- --touch` on desktop to preview the layout).
## Left half: a floating move stick. Right half: drag to look.
## Buttons: JUMP, PUSH, FLARE, HIT, BRACE (hold). Pushing the stick all the way runs.
## Title screen: GENTLE / NORMAL / WATCH AI.

const STICK_R := 85.0

var main
var move := Vector2.ZERO
var _stick_id := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_id := -1
var _look_last := Vector2.ZERO
var _held := {} # touch index -> action name
var _canvas: Control
var _glow_action := "" # Level 1: a button that pulses when its hint shows
var _glow_t := 0.0


func _ready() -> void:
	layer = 5
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_controls)
	add_child(_canvas)


func _size() -> Vector2:
	return _canvas.get_viewport_rect().size


## [action, label, center, radius]
func _buttons() -> Array:
	var s := _size()
	if main.state == "intro":
		var cx := s.x * 0.5
		var y := s.y - 58.0
		if main.is_course:
			return [
				["normal", "PLAY", Vector2(cx, y), 56.0],
				["watch", "WATCH AI", Vector2(cx + 230, y), 46.0],
				["classic", "CLASSIC", Vector2(cx - 230, y), 46.0],
			]
		return [
			["level1", "LEVEL 1", Vector2(cx, y - 120), 52.0],
			["gentle", "GENTLE", Vector2(cx - 230, y), 50.0],
			["normal", "NORMAL", Vector2(cx, y), 50.0],
			["watch", "WATCH AI", Vector2(cx + 230, y), 50.0],
		]
	if main.state == "ended":
		return [["again", "PLAY AGAIN", Vector2(s.x * 0.5, s.y - 80.0), 70.0]]
	if not main.player.alive or main.player.escaped:
		return [["again", "RESTART", Vector2(s.x * 0.5, s.y - 70.0), 52.0]]
	if main.is_course:
		var p = main.player
		var list := [["jump", "JUMP", Vector2(s.x - 110, s.y - 115), 66.0], ["push", "PUSH", Vector2(s.x - 250, s.y - 80), 42.0]]
		if p.weapon != "":
			list.append(["swing", "HIT", Vector2(s.x - 100, s.y - 265), 50.0])
		if p.weapons.size() >= 2:
			list.append(["swap", "SWAP", Vector2(s.x - 230, s.y - 200), 40.0])
		if p.has_rope and p.cphase == 4:
			list.append(["brace", "ROPE", Vector2(s.x - 250, s.y - 300), 52.0])
		return list
	return [
		["jump", "JUMP", Vector2(s.x - 110, s.y - 115), 66.0],
		["push", "PUSH", Vector2(s.x - 250, s.y - 80), 46.0],
		["flare", "FLARE", Vector2(s.x - 240, s.y - 205), 46.0],
		["swing", "HIT", Vector2(s.x - 100, s.y - 265), 42.0],
		["brace", "BRACE", Vector2(s.x - 370, s.y - 85), 40.0],
	]


func _button_at(p: Vector2) -> Array:
	for b in _buttons():
		if p.distance_to(b[2]) <= float(b[3]) + 10.0:
			return b
	return []


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _stick_id:
			_stick_pos = event.position
			var d: Vector2 = _stick_pos - _stick_origin
			move = d.limit_length(STICK_R) / STICK_R
			_canvas.queue_redraw()
		elif event.index == _look_id:
			var d: Vector2 = event.position - _look_last
			_look_last = event.position
			var p = main.player
			p.yaw -= d.x * 0.0065
			p.pitch = clampf(p.pitch - d.y * 0.005, -1.25, 0.45)
			p._cam_follow_t = 2.0
		get_viewport().set_input_as_handled()


func _on_press(idx: int, pos: Vector2) -> void:
	var b := _button_at(pos)
	if not b.is_empty():
		_press_button(idx, b[0])
		return
	if main.state == "flyover":
		main.skip_flyover()
		return
	if main.state != "playing":
		return
	main.hud.dismiss_out_panel()
	if main.player.autopilot:
		main.player.set_autopilot(false)
	if pos.x < _size().x * 0.45 and _stick_id == -1:
		_stick_id = idx
		_stick_origin = pos
		_stick_pos = pos
		move = Vector2.ZERO
	elif _look_id == -1:
		_look_id = idx
		_look_last = pos
	_canvas.queue_redraw()


func _press_button(idx: int, action: String) -> void:
	match action:
		"gentle", "normal", "watch":
			if action == "watch":
				main.player.set_autopilot(true)
			main.start_match(action == "gentle")
		"again":
			main.restart()
		"level1":
			main.go_level1()
		"classic":
			main.go_classic()
		_:
			if main.player.autopilot:
				main.player.set_autopilot(false)
			Input.action_press(action)
			_held[idx] = action
	_canvas.queue_redraw()


func _on_release(idx: int) -> void:
	if _held.has(idx):
		Input.action_release(_held[idx])
		_held.erase(idx)
	if idx == _stick_id:
		_stick_id = -1
		move = Vector2.ZERO
	if idx == _look_id:
		_look_id = -1
	_canvas.queue_redraw()


func _process(delta: float) -> void:
	_glow_t = maxf(0.0, _glow_t - delta)
	_canvas.queue_redraw()


## Level 1: make one button pulse for a few seconds (when its hint is shown).
func highlight(action: String) -> void:
	_glow_action = action
	_glow_t = 4.0


func _draw_controls() -> void:
	var font := ThemeDB.fallback_font
	var playing: bool = main.state == "playing"
	for b in _buttons():
		var c: Vector2 = b[2]
		var r: float = b[3]
		var held := _held.values().has(b[0])
		var ready := true
		if playing:
			var p = main.player
			match b[0]:
				"flare":
					ready = p.flares > 0
				"push":
					ready = p.shove_cd <= 0.0
				"swing":
					ready = p.tool_swings > 0 or main.is_course
				"brace":
					ready = p.light >= 70.0 and p.brace_ready
		var fill := Color(1.0, 0.85, 0.5, 0.42 if held else 0.22) if ready else Color(0.5, 0.48, 0.55, 0.18)
		_canvas.draw_circle(c, r, fill)
		_canvas.draw_arc(c, r, 0.0, TAU, 48, Color(1.0, 0.9, 0.7, 0.75 if ready else 0.3), 3.0, true)
		if _glow_t > 0.0 and b[0] == _glow_action:
			_canvas.draw_arc(c, r + 8.0 + 4.0 * sin(_glow_t * 8.0), 0.0, TAU, 48, Color(1.0, 0.85, 0.4, 0.8), 4.0, true)
		var fs := 20 if r > 50.0 else 16
		var lbl: String = b[1]
		if playing and b[0] == "flare":
			lbl = "FLARE %d" % main.player.flares
		_canvas.draw_string_outline(font, c + Vector2(-r, fs * 0.35), lbl, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 5, Color(0, 0, 0, 0.7))
		_canvas.draw_string(font, c + Vector2(-r, fs * 0.35), lbl, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 0.96, 0.88, 1.0 if ready else 0.5))
	if playing and _stick_id != -1:
		_canvas.draw_circle(_stick_origin, STICK_R, Color(1, 1, 1, 0.08))
		_canvas.draw_arc(_stick_origin, STICK_R, 0.0, TAU, 48, Color(1, 0.9, 0.7, 0.5), 3.0, true)
		_canvas.draw_circle(_stick_origin + move * STICK_R, 34.0, Color(1.0, 0.88, 0.6, 0.5))
	elif playing:
		var s := _size()
		_canvas.draw_string(font, Vector2(30, s.y - 230), "drag here to move", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.35))
