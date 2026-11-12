extends Control
## Screen-space markers: the Sun Gate once it opens, and violet arrows at the screen
## edge for hollows close by that you cannot see (so you can react before they bite).

var gate := {}       # {pos: Vector2, edge: bool, angle: float, text: String, col: Color}
var threats: Array = [] # [{pos: Vector2, angle: float, alpha: float}]
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func project(cam: Camera3D, world_pos: Vector3, margin: float) -> Dictionary:
	var vp := get_viewport_rect().size
	var center := vp * 0.5
	var behind := cam.is_position_behind(world_pos)
	var sp := cam.unproject_position(world_pos)
	if behind:
		sp = center - (sp - center) * 100.0
	var inside := not behind and sp.x > margin and sp.x < vp.x - margin and sp.y > margin and sp.y < vp.y - margin
	if inside:
		return {"pos": sp, "edge": false, "angle": 0.0}
	var d := sp - center
	if d.length() < 0.001:
		d = Vector2(0, 1)
	var half := center - Vector2(margin, margin)
	var sx := absf(half.x / d.x) if absf(d.x) > 0.0001 else INF
	var sy := absf(half.y / d.y) if absf(d.y) > 0.0001 else INF
	return {"pos": center + d * minf(sx, sy), "edge": true, "angle": d.angle()}


func _arrow(p: Vector2, ang: float, col: Color, sz: float) -> void:
	var dir := Vector2.from_angle(ang)
	var side := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([p + dir * sz, p - dir * sz * 0.5 + side * sz * 0.75, p - dir * sz * 0.5 - side * sz * 0.75]), col)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for t in threats:
		var c := Color(0.75, 0.45, 1.0, float(t["alpha"]))
		_arrow(t["pos"], t["angle"], c, 15.0)
		_arrow(t["pos"] - Vector2.from_angle(t["angle"]) * 12.0, t["angle"], Color(c.r, c.g, c.b, c.a * 0.5), 11.0)
	if gate.is_empty():
		return
	var col: Color = gate["col"]
	var p: Vector2 = gate["pos"]
	var pulse := 0.75 + 0.25 * sin(_t * 4.0)
	if gate["edge"]:
		_arrow(p, gate["angle"], Color(col.r, col.g, col.b, pulse), 24.0)
		var tp := p - Vector2.from_angle(gate["angle"]) * 40.0
		_label(font, tp + Vector2(-90, 6), gate["text"], col)
	else:
		var s := 11.0 + 3.0 * pulse
		var dia := PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)])
		draw_colored_polygon(dia, Color(col.r, col.g, col.b, pulse))
		draw_polyline(dia + PackedVector2Array([dia[0]]), Color(0, 0, 0, 0.6), 2.0)
		_label(font, p + Vector2(-90, -22), gate["text"], col)


func _label(font: Font, pos: Vector2, text: String, col: Color) -> void:
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 180, 17, 6, Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 180, 17, col)
