extends CanvasLayer
## Screen UI: sunset clock, lantern meter, abilities, event feed, roster, intro/end.

const Cfg = preload("res://scripts/cfg.gd")
const LightMeter = preload("res://scripts/light_meter.gd")
const Indicator = preload("res://scripts/indicator.gd")

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float danger = 0.0;
uniform float hurt = 0.0;
uniform float dark = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.0, 0.85)) * 1.45;
	float v = smoothstep(0.35, 1.05, d);
	float pulse = 0.55 + 0.45 * sin(TIME * 6.5);
	float red = v * (danger * pulse * 0.9 + hurt * 0.7);
	float blk = v * dark;
	float a = clamp(red + blk, 0.0, 0.92);
	vec3 col = vec3(0.75, 0.02, 0.05) * (red / max(red + blk, 0.0001));
	COLOR = vec4(col, a);
}
"""

var main
var root: Control
var clock: Label
var phase: Label
var meter
var light_lbl: Label
var status_lbl: Label
var feed_box: VBoxContainer
var roster: RichTextLabel
var banner_lbl: Label
var banner_t := 0.0
var toast_lbl: Label
var toast_t := 0.0
var vig_mat: ShaderMaterial
var intro: Control
var endp: Control
var end_title: Label
var end_body: Label
var hurt := 0.0
var roster_t := 0.0
var indicator
var game_ui: Array = []
var objective: Label
var abil: RichTextLabel
var tip_panel: PanelContainer
var tip_lbl: Label
var tip_t := 0.0
var tips_seen := {}
var tip_queue: Array = []
var play_t := 0.0
var obj_target = null
var obj_label := ""
var obj_col := Color(1.0, 0.9, 0.6)


func setup(m) -> void:
	main = m
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	vig_mat.shader = sh
	vig.material = vig_mat
	root.add_child(vig)
	indicator = Indicator.new()
	root.add_child(indicator)

	var top := VBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 10
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	clock = _label("05:00", 54, Color(1.0, 0.92, 0.75))
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(clock)
	phase = _label("", 16, Color(1.0, 0.86, 0.72, 0.85))
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(phase)
	# The one line that always says what to do next.
	var opanel := PanelContainer.new()
	var osb := _panel_style()
	osb.bg_color = Color(0.03, 0.02, 0.06, 0.62)
	osb.border_color = Color(1.0, 0.85, 0.5, 0.45)
	osb.set_content_margin_all(10)
	osb.content_margin_left = 18
	osb.content_margin_right = 18
	opanel.add_theme_stylebox_override("panel", osb)
	opanel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	opanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(opanel)
	objective = _label("", 20, Color(1.0, 0.9, 0.6))
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opanel.add_child(objective)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 18
	panel.offset_top = -18
	panel.offset_bottom = -18
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	light_lbl = _label("LANTERN 50%", 22, Color(1.0, 0.9, 0.7))
	vb.add_child(light_lbl)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vb.add_child(spacer)
	meter = LightMeter.new()
	vb.add_child(meter)
	status_lbl = _label("", 15, Color(0.95, 0.9, 0.85))
	vb.add_child(status_lbl)
	abil = RichTextLabel.new()
	abil.bbcode_enabled = true
	abil.fit_content = true
	abil.scroll_active = false
	abil.autowrap_mode = TextServer.AUTOWRAP_OFF
	abil.custom_minimum_size = Vector2(340, 0)
	abil.add_theme_font_size_override("normal_font_size", 15)
	abil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(abil)

	tip_panel = PanelContainer.new()
	var tsb := _panel_style()
	tsb.bg_color = Color(0.05, 0.04, 0.1, 0.8)
	tsb.border_color = Color(0.6, 0.85, 1.0, 0.5)
	tsb.set_content_margin_all(12)
	tip_panel.add_theme_stylebox_override("panel", tsb)
	tip_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	tip_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tip_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	tip_panel.offset_bottom = -215
	tip_panel.offset_top = -215
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.modulate.a = 0.0
	root.add_child(tip_panel)
	tip_lbl = _label("", 18, Color(0.85, 0.95, 1.0))
	tip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip_panel.add_child(tip_lbl)

	feed_box = VBoxContainer.new()
	feed_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	feed_box.offset_left = 18
	feed_box.offset_top = 18
	feed_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed_box)

	var rpanel := PanelContainer.new()
	rpanel.add_theme_stylebox_override("panel", _panel_style())
	rpanel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rpanel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	rpanel.offset_right = -18
	rpanel.offset_left = -18
	rpanel.offset_top = 18
	rpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rpanel)
	roster = RichTextLabel.new()
	roster.bbcode_enabled = true
	roster.fit_content = true
	roster.scroll_active = false
	roster.custom_minimum_size = Vector2(165, 0)
	roster.add_theme_font_size_override("normal_font_size", 13)
	roster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rpanel.add_child(roster)

	banner_lbl = _label("", 30, Color(1.0, 0.92, 0.75))
	banner_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner_lbl.grow_vertical = Control.GROW_DIRECTION_BOTH
	banner_lbl.offset_top = -170
	banner_lbl.offset_bottom = -170
	banner_lbl.modulate.a = 0.0
	root.add_child(banner_lbl)

	toast_lbl = _label("", 18, Color(1.0, 0.95, 0.85))
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	toast_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_lbl.offset_top = 90
	toast_lbl.offset_bottom = 90
	toast_lbl.modulate.a = 0.0
	root.add_child(toast_lbl)

	_build_intro()
	_build_end()
	# Gameplay HUD stays hidden behind the title card and fades in when the match starts.
	game_ui = [top, panel, rpanel]
	for c in game_ui:
		c.modulate.a = 0.0


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.08, 0.55)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	sb.border_color = Color(1.0, 0.85, 0.6, 0.18)
	sb.set_border_width_all(1)
	return sb


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.font_color = col
	ls.outline_size = maxi(4, size / 7)
	ls.outline_color = Color(0, 0, 0, 0.75)
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _overlay(alpha := 0.6) -> Control:
	var c := ColorRect.new()
	c.color = Color(0.01, 0.01, 0.04, alpha)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	return c


func _center_label(parent: Node, text: String, size: int, col: Color) -> Label:
	var l := _label(text, size, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _build_intro() -> void:
	intro = _overlay(0.42)
	var vb: Node = intro.get_child(0).get_child(0)
	_center_label(vb, "LAST LIGHT", 72, Color(1.0, 0.85, 0.55))
	_center_label(vb, "The sun sets in 5 minutes. Your lantern is your life.", 21, Color(1, 0.92, 0.85))
	_center_label(vb, " ", 6, Color.WHITE)
	var steps := [
		["1", "Walk into PINK BEAMS (blooms) to make your lantern brighter.", Color(1.0, 0.7, 0.85)],
		["2", "Dark moths (HOLLOWS) drain your light. Run away, or %s to blast them back." % k("flare"), Color(0.8, 0.65, 1.0)],
		["3", "At 01:00 the SUN GATE opens on the hilltop. Walk in with 80% light to escape.", Color(1.0, 0.85, 0.45)],
	]
	for s in steps:
		_center_label(vb, "%s.  %s" % [s[0], s[1]], 20, s[2])
	_center_label(vb, " ", 6, Color.WHITE)
	_center_label(vb, "Don't worry about remembering this: the box at the top of the screen always says what to do next.", 16, Color(0.85, 0.95, 1.0))
	if main.touch:
		_center_label(vb, "Left side: drag to move  ·  Right side: drag to look  ·  Buttons: FLARE, HIT (with a tool), BRACE, RUN", 15, Color(1.0, 0.85, 0.6))
		_center_label(vb, "Gentle: hollows bite you softer, blooms give you more light, your flare recharges faster. Best for your first game.", 15, Color(0.8, 0.9, 1.0))
		_center_label(vb, "Tap GENTLE, NORMAL, or WATCH AI below", 22, Color(1.0, 0.95, 0.8))
		return
	_center_label(vb, "WASD move  ·  Mouse look  ·  Shift sprint  ·  Space flare  ·  Left-click hit (with a tool)  ·  P autopilot", 15, Color(1.0, 0.85, 0.6))
	_center_label(vb, " ", 10, Color.WHITE)
	_center_label(vb, "Press 1 for GENTLE (best for your first game)     ·     Click or press 2 for NORMAL", 22, Color(1.0, 0.95, 0.8))
	_center_label(vb, "Gentle: hollows bite you softer, blooms give you more light, your flare recharges faster. The other pilgrims play normally.", 15, Color(0.8, 0.9, 1.0))
	_center_label(vb, "Press P to watch the AI play a round for you (press P again any time to take over)", 16, Color(0.9, 0.9, 0.95))


func _build_end() -> void:
	endp = _overlay()
	var vb: Node = endp.get_child(0).get_child(0)
	end_title = _center_label(vb, "", 60, Color(1.0, 0.85, 0.55))
	end_body = _center_label(vb, "", 19, Color(0.95, 0.9, 0.85))
	_center_label(vb, k("again"), 22, Color(1.0, 0.95, 0.8))
	endp.visible = false


func hide_intro() -> void:
	var tw := create_tween()
	tw.tween_property(intro, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): intro.visible = false)
	var tw2 := create_tween().set_parallel(true)
	for c in game_ui:
		tw2.tween_property(c, "modulate:a", 1.0, 0.8)


func show_end(title: String, escaped: Array, lost: Array) -> void:
	end_title.text = title
	var body := "The light is gone.\n\n"
	body += "Passed through the Sun Gate:  %s\n" % (", ".join(PackedStringArray(escaped)) if not escaped.is_empty() else "no one")
	body += "Left in the dark:  %s" % (", ".join(PackedStringArray(lost)) if not lost.is_empty() else "no one")
	end_body.text = body
	endp.visible = true
	endp.modulate.a = 0.0
	create_tween().tween_property(endp, "modulate:a", 1.0, 1.5)


func feed(text: String, col: Color) -> void:
	var l := _label(text, 16, col)
	feed_box.add_child(l)
	while feed_box.get_child_count() > 6:
		var old := feed_box.get_child(0)
		feed_box.remove_child(old)
		old.queue_free()
	var tw := l.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.0)
	tw.tween_callback(l.queue_free)


func banner(text: String, dur := 3.5) -> void:
	banner_lbl.text = text
	banner_t = dur


## Names a control the way this device uses it (keyboard/mouse or on-screen buttons).
func k(id: String) -> String:
	var t: bool = main.touch != null
	match id:
		"flare":
			return "tap FLARE" if t else "press SPACE"
		"hit":
			return "tap HIT" if t else "left-click"
		"brace":
			return "hold BRACE" if t else "hold RIGHT-CLICK"
		"run":
			return "hold RUN" if t else "hold SHIFT"
		"take":
			return "Touch the screen to take over" if t else "Press P to take over"
		"again":
			return "Tap PLAY AGAIN" if t else "Press R to play again"
	return id


func kc(id: String) -> String:
	var t := k(id)
	return t[0].to_upper() + t.substr(1)


func toast(text: String) -> void:
	toast_lbl.text = text
	toast_t = 1.8


## Shows a one-time explanation the first time something happens.
func tip(id: String, text: String) -> void:
	if tips_seen.has(id):
		return
	tips_seen[id] = true
	tip_queue.append(text)


func _update_tips(delta: float, p) -> void:
	if main.state == "playing" and p.alive and not p.escaped:
		play_t += delta
		var pp: Vector3 = p.global_position
		if play_t > 1.5:
			tip("start", "TIP: Follow the box at the top and the glowing marker. They always show your next step.")
		if p.light >= Cfg.BRACE_LIGHT:
			tip("brace", "TIP: Above 70%% you can %s to brace and block one bite." % k("brace"))
		if p.light < Cfg.DIM_LIGHT:
			tip("dim", "TIP: Below 20% you move slower. Get to a pink bloom right away!")
		if p.tool_swings > 0:
			tip("tool", "TIP: You picked up a tool. %s when a hollow is close: 2 hits destroy it." % k("hit"))
		if main.world.shrine_protects(pp):
			tip("shrine", "TIP: You're inside a shrine's gold ring. Hollows can't come in, but the rings shrink as night falls.")
		var h = main.nearest_hollow(pp, 18.0)
		if h != null:
			tip("hollow", "TIP: That dark moth is a HOLLOW. Touching it drains your light. Run, or %s when it's close." % k("flare"))
	tip_t -= delta
	if tip_t <= 0.0 and not tip_queue.is_empty():
		tip_lbl.text = tip_queue.pop_front()
		tip_t = 6.5
	tip_panel.modulate.a = clampf(tip_t * 2.0, 0.0, 1.0) if tip_t < 6.0 else clampf((6.5 - tip_t) * 4.0, 0.0, 1.0)


## Works out the single most useful thing to do right now, plus where it is.
func _compute_objective(p) -> void:
	obj_target = null
	obj_label = ""
	obj_col = Color(1.0, 0.9, 0.6)
	var st: String = main.state
	if st != "playing":
		objective.text = ("The light is gone. %s." % k("again")) if st == "ended" else ""
		return
	if p.escaped:
		objective.text = "You escaped! Watching %s (Tab to switch)" % p.spectate_name()
		return
	if not p.alive:
		objective.text = "Your lantern went out. Watch how %s does it (Tab to switch)" % p.spectate_name()
		return
	var pp: Vector3 = p.global_position
	var need := int(ceil(Cfg.ESCAPE_LIGHT - p.light))
	var gate: Vector3 = main.world.gate_pos
	var threat = main.nearest_hollow(pp, 8.0)
	if threat != null:
		obj_col = Color(0.85, 0.65, 1.0)
		var sh = main.world.nearest_shrine(pp, 2.5)
		if p.tool_swings > 0 and p.light >= 30.0:
			objective.text = "HOLLOW!  Face it and %s to hit it (2 hits)" % k("hit").to_upper()
		elif p.flare_cd <= 0.0 and p.light > Cfg.FLARE_COST + 1.0:
			objective.text = "HOLLOW!  %s to blast it back, then run" % k("flare").to_upper()
		elif sh != null and pp.distance_to(sh) < 16.0:
			objective.text = "HOLLOW!  Run into the gold ring, it can't follow"
			obj_target = sh
			obj_label = "SAFE RING"
		else:
			objective.text = "HOLLOW!  Run away. %s to sprint" % kc("run")
		return
	if main.gate_open:
		if p.light >= Cfg.ESCAPE_LIGHT:
			obj_col = Color(1.0, 0.85, 0.4)
			objective.text = "GO!  Walk into the glowing SUN GATE"
			obj_target = gate
			obj_label = "SUN GATE"
			return
		var b = main.nearest_pickup(pp, ["bloom", "shard"])
		obj_col = Color(1.0, 0.6, 0.6)
		objective.text = "Gate open! You need %d%% more. Get a bloom!" % need
		if b != null:
			obj_target = b.global_position
			obj_label = "BLOOM"
		return
	if p.light >= Cfg.ESCAPE_LIGHT:
		obj_col = Color(1.0, 0.85, 0.4)
		objective.text = "Bright enough!  Wait by the SUN GATE (opens 01:00)"
		obj_target = gate
		obj_label = "SUN GATE"
		return
	# Prefer the bloom you can realistically reach first (others are racing too).
	var bloom = main.best_pickup(p, false)
	if bloom == null:
		bloom = main.nearest_pickup(pp, ["bloom", "shard"])
	if bloom != null:
		obj_col = Color(1.0, 0.72, 0.85)
		objective.text = "Walk into a PINK BLOOM  (%d%% more to escape)" % need
		obj_target = bloom.global_position
		obj_label = "BLOOM"
		return
	var tl = main.nearest_pickup(pp, ["tool"])
	if p.tool_swings == 0 and tl != null:
		obj_col = Color(1.0, 0.85, 0.45)
		objective.text = "No blooms right now. Grab a TOOL (gold beam)"
		obj_target = tl.global_position
		obj_label = "TOOL"
		return
	objective.text = "New blooms appear soon. Look for pink beams"


func flash_hurt() -> void:
	hurt = 1.0


func pulse_clock() -> void:
	clock.pivot_offset = clock.size * 0.5
	clock.scale = Vector2.ONE * 1.25
	create_tween().tween_property(clock, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _update_indicators(p) -> void:
	indicator.threats.clear()
	indicator.gate = {}
	var cam := get_viewport().get_camera_3d()
	if cam == null or main.state != "playing" or not p.alive or p.escaped:
		return
	var pp: Vector3 = p.global_position
	for h in main.hollows:
		if not is_instance_valid(h) or h.state == 3:
			continue
		var d: float = pp.distance_to(h.global_position)
		if d > 14.0:
			continue
		var m: Dictionary = indicator.project(cam, h.global_position, 60.0)
		if m["edge"]:
			m["alpha"] = clampf(1.2 - d / 14.0, 0.25, 1.0)
			indicator.threats.append(m)
	if obj_target != null:
		var tgt: Vector3 = obj_target
		var g: Dictionary = indicator.project(cam, tgt + Vector3(0, 2.2, 0), 50.0)
		g["col"] = obj_col
		g["text"] = "%s  %dm" % [obj_label, int(pp.distance_to(tgt))]
		if not g["edge"]:
			# Keep the on-screen marker clear of the clock and objective box at the top.
			var gp2: Vector2 = g["pos"]
			g["pos"] = Vector2(gp2.x, maxf(gp2.y, 190.0))
		indicator.gate = g


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var p = main.player
	var tl: float = main.time_left
	var secs := int(ceil(tl))
	clock.text = "%02d:%02d" % [floori(secs / 60.0), secs % 60]
	var st: String = main.state
	if st == "intro":
		phase.text = ""
	elif st == "ended":
		phase.text = "The light is gone"
	elif tl > Cfg.GATE_OPEN_AT:
		phase.text = "The sun is setting · the Sun Gate opens at 01:00"
	elif tl > Cfg.FINAL_PHASE_AT:
		phase.text = "The Sun Gate is OPEN · 80% light to pass"
	else:
		phase.text = "Night · the hollows gather at the gate"
	if st == "playing" and tl <= Cfg.FINAL_PHASE_AT:
		clock.label_settings.font_color = Color(1.0, 0.35, 0.3).lerp(Color(1, 0.9, 0.8), 0.5 + 0.5 * sin(tl * 6.0))
	elif tl <= Cfg.GATE_OPEN_AT:
		clock.label_settings.font_color = Color(1.0, 0.8, 0.4)
	else:
		clock.label_settings.font_color = Color(1.0, 0.92, 0.75)

	var light: float = p.light
	meter.value = light
	light_lbl.text = "LANTERN  %d%%" % int(round(light))
	if p.escaped:
		status_lbl.text = "You passed through the Sun Gate. Watching %s (Tab)" % p.spectate_name()
	elif not p.alive:
		status_lbl.text = "Your lantern went out. Watching %s (Tab)" % p.spectate_name()
	elif light >= Cfg.ESCAPE_LIGHT:
		status_lbl.text = "Bright enough for the Sun Gate (80%)"
	elif light < Cfg.DIM_LIGHT:
		status_lbl.text = "FADING. You are slowed"
	else:
		status_lbl.text = "Reach 80% to use the Sun Gate"
	# One compact row: bright = ready, grey = not available.
	var on := "[color=#ffe7a8]"
	var off := "[color=#8a8494]"
	var tch: bool = main.touch != null
	var flare_txt: String = (on + ("FLARE ready" if tch else "SPACE flare") + "[/color]") if p.flare_cd <= 0.0 else (off + "flare %ds[/color]" % int(ceil(p.flare_cd)))
	var tool_txt: String = (on + ("HIT %d/%d" if tch else "CLICK hit %d/%d") % [p.tool_swings, Cfg.TOOL_SWINGS] + "[/color]") if p.tool_swings > 0 else (off + "no tool[/color]")
	var brace_txt: String = (on + ("BRACE ready" if tch else "R-CLICK brace") + "[/color]") if (light >= Cfg.BRACE_LIGHT and p.brace_ready) else (off + "brace 70%+[/color]")
	abil.text = "%s     %s     %s" % [flare_txt, tool_txt, brace_txt]
	if p.autopilot:
		abil.text += "\n[color=#a8d8ff]AUTOPILOT is playing for you. %s[/color]" % k("take")
	elif main.gentle:
		abil.text += "\n[color=#a8d8ff]Gentle mode: softer bites, bigger blooms[/color]"

	_compute_objective(p)
	objective.label_settings.font_color = obj_col
	objective.get_parent().visible = objective.text != ""
	_update_tips(delta, p)

	hurt = maxf(0.0, hurt - delta * 2.5)
	var danger := 0.0
	if p.alive and not p.escaped:
		danger = clampf((Cfg.DIM_LIGHT - light) / 12.0, 0.0, 1.0)
	vig_mat.set_shader_parameter("danger", danger)
	vig_mat.set_shader_parameter("hurt", hurt)
	vig_mat.set_shader_parameter("dark", main.frac() * 0.4 + (0.4 if st == "ended" else 0.0))

	banner_t -= delta
	banner_lbl.modulate.a = clampf(banner_t, 0.0, 1.0)
	toast_t -= delta
	toast_lbl.modulate.a = clampf(toast_t * 2.0, 0.0, 1.0)

	_update_indicators(p)

	roster_t -= delta
	if roster_t <= 0.0:
		roster_t = 0.25
		_update_roster()


func _update_roster() -> void:
	var list: Array = main.survivors.duplicate()
	list.sort_custom(func(a, b):
		var sa: float = (300.0 if a.escaped else 0.0) + (a.light if a.alive else -100.0)
		var sb: float = (300.0 if b.escaped else 0.0) + (b.light if b.alive else -100.0)
		return sa > sb)
	var txt := "[b]PILGRIMS[/b]\n"
	for s in list:
		var col: Color = s.tint.lightened(0.25)
		var nm: String = s.display_name
		if s.is_player:
			nm = "[b]" + nm + "[/b]"
		var right := ""
		if s.escaped:
			right = "[color=#ffe6a0]escaped[/color]"
		elif not s.alive:
			right = "[color=#777788]%s[/color]" % ("lost" if s.lost else "dark")
		else:
			var lc := "#ffffff"
			if s.light >= Cfg.ESCAPE_LIGHT:
				lc = "#fff2b0"
			elif s.light < Cfg.DIM_LIGHT:
				lc = "#ff6060"
			right = "[color=%s]%d%%[/color]" % [lc, int(round(s.light))]
		txt += "[color=#%s]%s[/color]  %s\n" % [col.to_html(false), nm, right]
	roster.text = txt
