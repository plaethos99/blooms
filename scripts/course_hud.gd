extends "res://scripts/hud.gd"
## Level 1's screen: kept almost free of text. The clock with four phase icons under it,
## your race place, your lantern, your weapons, a crosshair when you need to aim, and
## a small button icon the first time you need a new control. The way forward is shown
## in the world (the guide wisp, glowing pickups, the highlighted ring), not in words.

const GOLD := Color(1.0, 0.82, 0.4)
const DIM := Color(0.75, 0.72, 0.8, 0.45)

var phase_bar: Control
var weapon_bar: Control
var cross: Control
var hint_ctrl: Control
var place_lbl: Label
var rope_target := -1
var _hint := {} # {icon, key, word, t}
var _hints_done := {}
var _kill_pulse := 0.0
var _need_pulse := 0.0
var _t := 0.0
var _results: Control


func setup(m) -> void:
	super.setup(m)
	# Hide everything from the open-island HUD that Level 1 does not need.
	objective.get_parent().visible = false
	phase.visible = false
	feed_box.visible = false
	minimap.get_parent().visible = false
	tip_panel.visible = false
	status_lbl.visible = false
	abil.visible = false
	light_lbl.label_settings.font_size = 16
	meter.marks = []
	meter.custom_minimum_size = Vector2(220, 14)
	clock.text = _clock_text(Cfg.COURSE_TIME)
	var top: Control = clock.get_parent()
	phase_bar = Control.new()
	phase_bar.custom_minimum_size = Vector2(280, 58)
	phase_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phase_bar.draw.connect(_draw_phase_bar)
	top.add_child(phase_bar)
	top.move_child(phase_bar, 1)

	place_lbl = _label("", 34, Color(1.0, 0.92, 0.75))
	place_lbl.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	place_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	place_lbl.offset_right = -26
	place_lbl.offset_left = -26
	place_lbl.offset_top = 16
	place_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(place_lbl)

	weapon_bar = Control.new()
	weapon_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	weapon_bar.offset_left = -250
	weapon_bar.offset_top = -96
	weapon_bar.offset_right = -20
	weapon_bar.offset_bottom = -20
	weapon_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_bar.draw.connect(_draw_weapon_bar)
	root.add_child(weapon_bar)
	if main.touch:
		# The touch buttons live in that corner; weapons go top-left instead.
		weapon_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		weapon_bar.offset_left = 20
		weapon_bar.offset_top = 20
		weapon_bar.offset_right = 250
		weapon_bar.offset_bottom = 96

	cross = Control.new()
	cross.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross)
	root.add_child(cross)

	hint_ctrl = Control.new()
	hint_ctrl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint_ctrl.offset_top = -170
	hint_ctrl.offset_bottom = -110
	hint_ctrl.offset_left = -160
	hint_ctrl.offset_right = 160
	hint_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_ctrl.draw.connect(_draw_hint)
	root.add_child(hint_ctrl)
	game_ui.append_array([place_lbl, weapon_bar])
	place_lbl.modulate.a = 0.0
	weapon_bar.modulate.a = 0.0


# ---------------------------------------------------------------- title, caption, end

func _build_caption() -> void:
	caption = VBoxContainer.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	caption.grow_horizontal = Control.GROW_DIRECTION_BOTH
	caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	caption.offset_bottom = -90
	caption.offset_top = -90
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.modulate.a = 0.0
	root.add_child(caption)
	var a := _label("THE SUN GATE", 54, Color(1.0, 0.85, 0.5))
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(a)
	var b := _label("Reach it before sunset", 22, Color(1.0, 0.95, 0.85))
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_child(b)


func _build_intro() -> void:
	intro = _overlay(0.42)
	var vb: Node = intro.get_child(0).get_child(0)
	_center_label(vb, "LEVEL 1", 30, Color(1.0, 0.9, 0.7))
	_center_label(vb, "THE GAUNTLET", 72, Color(1.0, 0.85, 0.55))
	var icons := Control.new()
	icons.custom_minimum_size = Vector2(420, 110)
	icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icons.draw.connect(func(): _draw_phase_icons(icons, Vector2(210, 44), 0, 1.5, true))
	vb.add_child(icons)
	_center_label(vb, "Blades  ·  Steps  ·  Monsters  ·  Rope  ·  Gate", 18, Color(1, 0.92, 0.85, 0.85))
	_center_label(vb, " ", 10, Color.WHITE)
	if main.touch:
		_center_label(vb, "Tap PLAY", 24, Color(1.0, 0.95, 0.8))
		return
	_center_label(vb, "CLICK TO PLAY", 30, Color(1.0, 0.95, 0.8))
	_center_label(vb, "P  watch the AI      C  classic islands", 16, Color(0.85, 0.85, 0.9, 0.8))


func show_results() -> void:
	var p = main.player
	var title := "TIME'S UP"
	if p.place > 0:
		title = _ordinal(p.place) + " PLACE"
	elif not p.alive:
		title = "OUT OF THE RACE"
	end_title.text = title
	var lines: Array = []
	if p.place > 0:
		lines.append("%s    %s" % [_clock_text(p.finish_time), main.medal(p.finish_time)])
		lines.append("")
	for s in main.finish_order:
		lines.append("%s   %s   %s" % [_ordinal(s.place), s.display_name, _clock_text(s.finish_time)])
	if main.finish_order.is_empty():
		lines.append("Nobody reached the Sun Gate")
	end_body.text = "\n".join(PackedStringArray(lines))
	endp.visible = true
	endp.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(endp, "modulate:a", 1.0, 1.2)
	for c in game_ui:
		tw.tween_property(c, "modulate:a", 0.0, 0.8)
	if restart_btn:
		restart_btn.visible = false
	out_panel.visible = false


static func _ordinal(n: int) -> String:
	var suf := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suf = "st"
			2:
				suf = "nd"
			3:
				suf = "rd"
	return "%d%s" % [n, suf]


func _update_out_panel(delta: float, p) -> void:
	var out: bool = main.state == "playing" and (not p.alive or p.escaped)
	if not out:
		out_t = 0.0
		out_panel.visible = false
		return
	out_t += delta
	if out_dismissed or out_t < 2.0:
		return
	if not out_panel.visible:
		if p.escaped:
			out_title.text = _ordinal(p.place) + " PLACE"
			out_body.text = "%s    %s" % [_clock_text(p.finish_time), main.medal(p.finish_time)]
		elif p.fell:
			out_title.text = "YOU FELL"
			out_body.text = "Grab the lamp to unlock checkpoints"
		else:
			out_title.text = "YOUR LANTERN WENT OUT"
			out_body.text = "Grab the lamp to unlock checkpoints"
		out_panel.visible = true
		banner_t = 0.0
		out_panel.modulate.a = 0.0
		create_tween().tween_property(out_panel, "modulate:a", 1.0, 0.4)
		if main.touch == null:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ---------------------------------------------------------------- events from the game

func tip(_id: String, _text: String) -> void:
	pass # Level 1 guides with icons and the world itself, not tip text.


func feed(_text: String, _col: Color) -> void:
	pass


const PHASE_WORDS := {1: "BLADES", 2: "STEPS", 3: "ARENA", 4: "ROPE", 5: "THE GATE"}


func phase_banner(ph: int) -> void:
	if PHASE_WORDS.has(ph):
		banner(PHASE_WORDS[ph], 2.0)
	match ph:
		1:
			hint("jump")
		3:
			if main.player.weapon != "":
				hint("attack")


func weapon_taken(_kind: String) -> void:
	if main.player.weapons.size() >= 2:
		hint("swap")


func kill_pulse() -> void:
	_kill_pulse = 1.0


func need_kills() -> void:
	_need_pulse = 1.0


func rope_used() -> void:
	_hints_done["rope"] = true
	if _hint.get("id", "") == "rope":
		_hint["t"] = minf(float(_hint["t"]), 0.3)


## Show a control icon once: "jump", "attack", "swap", "rope", "letgo".
func hint(id: String) -> void:
	if _hints_done.has(id):
		return
	_hints_done[id] = true
	var t: bool = main.touch != null
	match id:
		"jump":
			_hint = {"id": id, "icon": "key", "key": "SPACE", "word": "JUMP  ·  TWICE IN THE AIR"}
			if t:
				_hint = {"id": id, "icon": "tap", "key": "JUMP", "word": "TWICE IN THE AIR"}
		"attack":
			_hint = {"id": id, "icon": "mouse_l", "key": "", "word": "ATTACK"}
			if t:
				_hint = {"id": id, "icon": "tap", "key": "HIT", "word": "ATTACK"}
		"swap":
			_hint = {"id": id, "icon": "key", "key": "1 2 3", "word": "SWITCH WEAPON"}
			if t:
				_hint = {"id": id, "icon": "tap", "key": "SWAP", "word": "SWITCH WEAPON"}
		"rope":
			_hint = {"id": id, "icon": "mouse_r", "key": "", "word": "ROPE"}
			if t:
				_hint = {"id": id, "icon": "tap", "key": "ROPE", "word": "AIM AT A RING"}
		"letgo":
			_hint = {"id": id, "icon": "key", "key": "SPACE", "word": "LET GO"}
			if t:
				_hint = {"id": id, "icon": "tap", "key": "JUMP", "word": "LET GO"}
	_hint["t"] = 4.0
	if t and main.touch.has_method("highlight"):
		main.touch.highlight({"jump": "jump", "attack": "swing", "swap": "swap", "rope": "brace", "letgo": "jump"}[id])


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	_t += delta
	var p = main.player
	var st: String = main.state
	var tl: float = main.time_left
	clock.text = _clock_text(tl)
	if st == "playing" and tl <= 20.0:
		clock.label_settings.font_color = Color(1.0, 0.35, 0.3).lerp(Color(1, 0.9, 0.8), 0.5 + 0.5 * sin(tl * 6.0))
	else:
		clock.label_settings.font_color = Color(1.0, 0.92, 0.75)
	meter.value = p.light
	light_lbl.text = "%d%%" % int(round(p.light))
	place_lbl.text = "" if st != "playing" else "%s / %d" % [_ordinal(main.race_place(p)), main.survivors.size()]
	_update_out_panel(delta, p)
	if restart_btn:
		var out: bool = st == "playing" and (not p.alive or p.escaped)
		if out and not restart_btn.visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		restart_btn.visible = out and not out_panel.visible
	# First time hanging from the last ring: how to let go.
	if p.rope_state == "hang" and p.rope_ring >= 0 and int(main.world.rings[p.rope_ring]["k"]) == main.world.RING_COUNT - 1:
		hint("letgo")
	hurt = maxf(0.0, hurt - delta * 2.5)
	var danger := 0.0
	if p.alive and not p.escaped:
		danger = clampf((Cfg.DIM_LIGHT - p.light) / 12.0, 0.0, 1.0)
	vig_mat.set_shader_parameter("danger", danger)
	vig_mat.set_shader_parameter("hurt", hurt)
	vig_mat.set_shader_parameter("dark", main.frac() * 0.3 + (0.4 if st == "ended" else 0.0))
	banner_t -= delta
	banner_lbl.modulate.a = clampf(banner_t * 1.5, 0.0, 1.0)
	alert_t -= delta
	alert_lbl.modulate.a = clampf(alert_t * 2.0, 0.0, 1.0)
	count_t -= delta
	count_lbl.modulate.a = clampf(count_t * 3.0, 0.0, 1.0)
	toast_t -= delta
	toast_lbl.modulate.a = clampf(toast_t * 2.0, 0.0, 1.0)
	_kill_pulse = maxf(0.0, _kill_pulse - delta * 2.0)
	_need_pulse = maxf(0.0, _need_pulse - delta * 1.5)
	if not _hint.is_empty():
		_hint["t"] = float(_hint["t"]) - delta
		if float(_hint["t"]) <= 0.0:
			_hint = {}
	phase_bar.queue_redraw()
	weapon_bar.queue_redraw()
	cross.queue_redraw()
	hint_ctrl.queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw_phase_bar() -> void:
	var p = main.player
	var mid := phase_bar.size.x * 0.5
	phase_bar.draw_rect(Rect2(Vector2(mid - 132, 6), Vector2(264, 48)), Color(0.03, 0.02, 0.06, 0.45))
	_draw_phase_icons(phase_bar, Vector2(phase_bar.size.x * 0.5, 30), int(p.cphase), 1.0, false)
	if int(p.cphase) == 3:
		# Kills so far, under the arena icon.
		var c := Vector2(phase_bar.size.x * 0.5 + 0.5 * 64.0, 30)
		var font := Fonts.body()
		var col := GOLD.lerp(Color.WHITE, _kill_pulse)
		if _need_pulse > 0.0:
			col = col.lerp(Color(1.0, 0.3, 0.25), _need_pulse * (0.5 + 0.5 * sin(_t * 20.0)))
		var txt := "%d/%d" % [mini(p.kills, Cfg.KILLS_NEEDED), Cfg.KILLS_NEEDED]
		var fs := 16 + int(_kill_pulse * 6.0)
		phase_bar.draw_string_outline(font, c + Vector2(-30, 32), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, fs, 4, Color(0, 0, 0, 0.8))
		phase_bar.draw_string(font, c + Vector2(-30, 32), txt, HORIZONTAL_ALIGNMENT_CENTER, 60, fs, col)


## Four icons in a row centred at c: blades, steps, monsters, rope. `cur` is the
## current phase (done ones are gold, the current one glows, later ones are dim).
func _draw_phase_icons(ci: CanvasItem, c: Vector2, cur: int, s: float, all_lit: bool) -> void:
	var gap := 64.0 * s
	for k in 4:
		var ph := k + 1
		var at := c + Vector2((float(k) - 1.5) * gap, 0)
		var col := DIM
		var r := 19.0 * s
		if all_lit:
			col = GOLD
		elif ph < cur:
			col = GOLD
		elif ph == cur:
			col = Color(1, 1, 1)
			var pulse := 0.5 + 0.5 * sin(_t * 4.0)
			ci.draw_circle(at, r + 3.0 * s, Color(1.0, 0.85, 0.5, 0.18 + 0.12 * pulse))
		ci.draw_arc(at, r, 0.0, TAU, 40, Color(col.r, col.g, col.b, col.a * 0.7), 1.6 * s, true)
		_icon(ci, k, at, s * 0.9, col)
		if k < 3:
			var lc := GOLD if (ph < cur or all_lit) else DIM
			ci.draw_line(at + Vector2(r + 5.0 * s, 0), at + Vector2(gap - r - 5.0 * s, 0), Color(lc.r, lc.g, lc.b, lc.a * 0.6), 1.5 * s, true)


func _icon(ci: CanvasItem, k: int, c: Vector2, s: float, col: Color) -> void:
	match k:
		0: # a pendulum blade
			ci.draw_line(c + Vector2(0, -12) * s, c + Vector2(4, 3) * s, col, 2.0 * s, true)
			ci.draw_arc(c + Vector2(4, 1) * s, 8.0 * s, 0.2, PI - 0.2, 16, col, 3.0 * s, true)
		1: # stepping stones at different heights
			for j in 3:
				var o := Vector2((float(j) - 1.0) * 9.0, 6.0 - float(j) * 5.0) * s
				ci.draw_rect(Rect2(c + o - Vector2(3.5, 2) * s, Vector2(7, 4) * s), col)
		2: # a winged monster
			var pts := PackedVector2Array([Vector2(-13, -4), Vector2(-6, 0), Vector2(0, -3), Vector2(6, 0), Vector2(13, -4), Vector2(8, 5), Vector2(3, 3), Vector2(0, 7), Vector2(-3, 3), Vector2(-8, 5)])
			for i in pts.size():
				pts[i] = c + pts[i] * s
			ci.draw_colored_polygon(pts, col)
		3: # a ring with a rope
			ci.draw_arc(c + Vector2(0, -5) * s, 6.0 * s, 0.0, TAU, 20, col, 2.2 * s, true)
			ci.draw_line(c + Vector2(0, 1) * s, c + Vector2(-5, 12) * s, col, 1.8 * s, true)


func _draw_weapon_bar() -> void:
	var p = main.player
	if p.weapons.is_empty():
		return
	var order := ["bow", "axe", "saw"]
	var font := Fonts.body()
	var x := weapon_bar.size.x
	for i in range(order.size() - 1, -1, -1):
		var kind: String = order[i]
		var box := Rect2(Vector2(x - 72.0 * float(order.size() - i), 6), Vector2(64, 64))
		if not p.weapons.has(kind):
			weapon_bar.draw_rect(box, Color(1, 1, 1, 0.04))
			weapon_bar.draw_rect(box, Color(1, 1, 1, 0.12), false, 1.0)
			continue
		var sel: bool = p.weapon == kind
		weapon_bar.draw_rect(box, Color(0.05, 0.03, 0.08, 0.6 if sel else 0.4))
		weapon_bar.draw_rect(box, GOLD if sel else Color(1, 1, 1, 0.3), false, 2.5 if sel else 1.0)
		var col := GOLD if sel else Color(0.95, 0.92, 0.88, 0.75)
		if kind == "saw" and p.saw_out:
			col = DIM
		_weapon_icon(weapon_bar, kind, box.get_center(), col)
		if main.touch == null:
			weapon_bar.draw_string(font, box.position + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))


func _weapon_icon(ci: CanvasItem, kind: String, c: Vector2, col: Color) -> void:
	match kind:
		"axe":
			ci.draw_line(c + Vector2(-10, 16), c + Vector2(8, -14), col, 3.0, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(2, -16), c + Vector2(16, -12), c + Vector2(14, 2), c + Vector2(4, -6)]), col)
		"bow":
			ci.draw_arc(c + Vector2(8, 0), 16.0, PI * 0.6, PI * 1.4, 16, col, 3.0, true)
			ci.draw_line(c + Vector2(-5, -15), c + Vector2(-5, 15), Color(col.r, col.g, col.b, col.a * 0.7), 1.2, true)
			ci.draw_line(c + Vector2(-14, 0), c + Vector2(16, 0), col, 2.0, true)
		"saw":
			ci.draw_circle(c, 11.0, Color(col.r, col.g, col.b, col.a * 0.35))
			ci.draw_arc(c, 11.0, 0.0, TAU, 24, col, 2.5, true)
			for j in 8:
				var a := TAU * float(j) / 8.0 + _t * (6.0 if main.player.saw_out else 0.0)
				ci.draw_line(c + Vector2(cos(a), sin(a)) * 11.0, c + Vector2(cos(a + 0.35), sin(a + 0.35)) * 16.0, col, 2.0, true)
			ci.draw_circle(c, 3.0, col)


func _draw_cross() -> void:
	var p = main.player
	if main.state != "playing" or not p.alive or p.escaped or p.respawn_t > 0.0:
		return
	var sz := cross.size
	var c := sz * 0.5
	var aiming: bool = (int(p.cphase) == 3 and p.weapon != "") or (int(p.cphase) == 4 and p.has_rope)
	if aiming:
		cross.draw_arc(c, 9.0, 0.0, TAU, 24, Color(1, 1, 1, 0.75), 1.6, true)
		cross.draw_circle(c, 1.8, Color(1, 1, 1, 0.9))
	# The ring the rope will catch: a gold circle around it.
	if rope_target >= 0 and int(p.cphase) == 4:
		var cam := get_viewport().get_camera_3d()
		var rp: Vector3 = main.world.ring_pos(rope_target)
		if cam != null and not cam.is_position_behind(rp):
			var sp := cam.unproject_position(rp)
			var pulse := 0.5 + 0.5 * sin(_t * 6.0)
			cross.draw_arc(sp, 26.0 + 4.0 * pulse, 0.0, TAU, 36, Color(1.0, 0.85, 0.45, 0.9), 3.0, true)
			cross.draw_arc(sp, 34.0 + 4.0 * pulse, 0.0, TAU, 36, Color(1.0, 0.85, 0.45, 0.3), 1.5, true)
			if p.rope_state == "" and not _hints_done.has("rope_shown"):
				hint("rope")


func _draw_hint() -> void:
	if _hint.is_empty():
		return
	var a := clampf(float(_hint["t"]) * 2.0, 0.0, 1.0) * clampf((4.0 - float(_hint["t"])) * 4.0, 0.0, 1.0)
	var font := Fonts.body()
	var word: String = _hint["word"]
	var key: String = _hint["key"]
	var col := Color(1, 0.96, 0.88, a)
	var w := hint_ctrl.size.x
	var cy := 28.0
	var icon_w := 0.0
	match String(_hint["icon"]):
		"mouse_l", "mouse_r":
			icon_w = 28.0
		_:
			icon_w = maxf(44.0, font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 22.0)
	var word_w := font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var x0 := (w - icon_w - 12.0 - word_w) * 0.5
	var bg := Rect2(Vector2(x0 - 14.0, cy - 26.0), Vector2(icon_w + 12.0 + word_w + 28.0, 52))
	hint_ctrl.draw_rect(bg, Color(0.03, 0.02, 0.06, 0.55 * a))
	match String(_hint["icon"]):
		"mouse_l", "mouse_r":
			var mr := Rect2(Vector2(x0 + 2.0, cy - 18.0), Vector2(24, 36))
			hint_ctrl.draw_rect(mr, col, false, 2.0)
			var left: bool = _hint["icon"] == "mouse_l"
			var btn := Rect2(Vector2(x0 + 2.0 + (0.0 if left else 12.0), cy - 18.0), Vector2(12, 14))
			hint_ctrl.draw_rect(btn, Color(1.0, 0.82, 0.4, a))
		_:
			var kr := Rect2(Vector2(x0, cy - 16.0), Vector2(icon_w, 32))
			hint_ctrl.draw_rect(kr, Color(1, 1, 1, 0.1 * a))
			hint_ctrl.draw_rect(kr, Color(1.0, 0.82, 0.4, a), false, 2.0)
			hint_ctrl.draw_string(font, Vector2(x0, cy + 5.0), key, HORIZONTAL_ALIGNMENT_CENTER, icon_w, 15, col)
	hint_ctrl.draw_string_outline(font, Vector2(x0 + icon_w + 12.0, cy + 6.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 4, Color(0, 0, 0, 0.6 * a))
	hint_ctrl.draw_string(font, Vector2(x0 + icon_w + 12.0, cy + 6.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
