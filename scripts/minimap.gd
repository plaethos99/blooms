extends Control
## Heading-up map in the corner: islands, stepping stones, the Sun Gate, incoming
## Sunflare drops (with countdown), blooms, pilgrims, nearby hollows, and the bridge the
## Devourer is about to strike.

const SIZE := 210.0
const VIEW_M := 70.0 # metres from centre to edge

var main
var _t := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _basis() -> Array:
	var p = main.player
	var cam := get_viewport().get_camera_3d()
	var yaw: float = p.yaw
	var origin: Vector3 = p.global_position
	if (not p.alive or p.escaped) and cam:
		origin = cam.global_position
		var f := -cam.global_transform.basis.z
		yaw = atan2(-f.x, -f.z)
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	return [origin, fwd, right]


func _to_map(b: Array, w: Vector3) -> Vector2:
	var o: Vector3 = b[0]
	var d := Vector2(w.x - o.x, w.z - o.z)
	var f: float = d.dot(b[1])
	var r: float = d.dot(b[2])
	var k := (SIZE * 0.5) / VIEW_M
	return Vector2(SIZE * 0.5, SIZE * 0.5) + Vector2(r, -f) * k


func _clamp_edge(p: Vector2, margin: float) -> Array:
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var d := p - c
	var lim := SIZE * 0.5 - margin
	if absf(d.x) <= lim and absf(d.y) <= lim:
		return [p, false]
	var s := lim / maxf(absf(d.x), absf(d.y))
	return [c + d * s, true]


func _draw() -> void:
	if main == null or main.player == null or main.state == "intro" or main.state == "flyover":
		return
	var w = main.world
	var b := _basis()
	var k := (SIZE * 0.5) / VIEW_M
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.02, 0.03, 0.07, 0.62))
	# The abyss shimmer.
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(0.1, 0.5, 0.6, 0.05 + 0.03 * sin(_t * 1.3)))
	for i in w.ISLANDS.size():
		var c: Vector3 = w.island_center(i)
		var mp := _to_map(b, c)
		var col := Color(0.32, 0.55, 0.42, 0.85)
		if i == w.GATE_ISLAND:
			col = Color(0.62, 0.52, 0.3, 0.9)
		draw_circle(mp, w.island_radius(i) * k, col)
		draw_arc(mp, w.island_radius(i) * k, 0.0, TAU, 32, Color(0.75, 0.95, 0.85, 0.35), 1.0, true)
	for bi in w.bridges.size():
		var br: Dictionary = w.bridges[bi]
		var warn: float = br["warn"]
		for st in br["stones"]:
			var mp := _to_map(b, st)
			var col := Color(0.5, 0.9, 1.0, 0.8).lerp(Color(1.0, 0.2, 0.1, 1.0), warn)
			draw_circle(mp, 1.4 * k + warn * 1.5, col)
	# Shrine rings.
	if w.shrine_radius > 0.3:
		for s in w.shrines:
			draw_arc(_to_map(b, s["pos"]), w.shrine_radius * k, 0.0, TAU, 24, Color(1.0, 0.82, 0.45, 0.6), 1.5, true)
	# Pickups.
	for pk in main.pickups:
		if not is_instance_valid(pk):
			continue
		var mp := _to_map(b, pk.global_position)
		match pk.kind:
			"bloom":
				draw_circle(mp, 3.2, Color(1.0, 0.5, 0.75))
			"shard":
				draw_circle(mp, 2.2, Color(0.5, 0.9, 1.0))
			"tool":
				draw_circle(mp, 2.6, Color(1.0, 0.82, 0.35))
			"flare":
				var ce := _clamp_edge(mp, 8.0)
				_star(ce[0], 6.5 + sin(_t * 8.0), Color(1.0, 0.55, 0.15))
	# Hollows close by.
	for h in main.hollows:
		if not is_instance_valid(h) or h.state == 3:
			continue
		if h.global_position.distance_to(b[0]) > 40.0:
			continue
		draw_circle(_to_map(b, h.global_position), 3.0, Color(0.95, 0.2, 0.35, 0.95))
	# Pilgrims.
	for s in main.survivors:
		if s.is_player or not s.alive or s.escaped:
			continue
		draw_circle(_to_map(b, s.global_position), 2.6, s.tint.lightened(0.2))
	# Gate (clamped to the edge when far).
	var gp := _to_map(b, w.gate_pos)
	var ge := _clamp_edge(gp, 10.0)
	var gc := Color(1.0, 0.85, 0.4) if main.gate_open else Color(1.0, 0.85, 0.4, 0.75)
	var gs := 6.0 + (1.5 * sin(_t * 4.0) if main.gate_open else 0.0)
	var dia := PackedVector2Array([ge[0] + Vector2(0, -gs), ge[0] + Vector2(gs, 0), ge[0] + Vector2(0, gs), ge[0] + Vector2(-gs, 0)])
	draw_colored_polygon(dia, gc)
	draw_string_outline(font, ge[0] + Vector2(-30, -9), "GATE", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, 4, Color(0, 0, 0, 0.8))
	draw_string(font, ge[0] + Vector2(-30, -9), "GATE", HORIZONTAL_ALIGNMENT_CENTER, 60, 11, gc)
	# Incoming Sunflares with their countdown.
	for d in main.drops:
		if not is_instance_valid(d):
			continue
		var ce := _clamp_edge(_to_map(b, d.global_position), 12.0)
		var pulse := 0.5 + 0.5 * sin(_t * 10.0)
		var pos: Vector2 = ce[0]
		draw_arc(pos, 7.0 + 4.0 * pulse, 0.0, TAU, 20, Color(1.0, 0.55, 0.15, 0.9), 2.5, true)
		_star(pos, 5.0, Color(1.0, 0.7, 0.3))
		var txt := "%d" % int(ceil(d.remaining()))
		draw_string_outline(font, pos + Vector2(-20, 20), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 13, 4, Color(0, 0, 0, 0.85))
		draw_string(font, pos + Vector2(-20, 20), txt, HORIZONTAL_ALIGNMENT_CENTER, 40, 13, Color(1.0, 0.8, 0.4))
	# The Devourer's target.
	if main.wyrm and main.wyrm.is_threatening():
		var wp := _clamp_edge(_to_map(b, main.wyrm.target), 10.0)
		var pr := 9.0 + 5.0 * (0.5 + 0.5 * sin(_t * 14.0))
		draw_arc(wp[0], pr, 0.0, TAU, 24, Color(1.0, 0.15, 0.1, 0.95), 3.0, true)
	# You: an arrow pointing up (the way you face).
	var c := Vector2(SIZE * 0.5, SIZE * 0.5)
	var p = main.player
	if p.alive and not p.escaped:
		var face: Vector3 = p.facing
		var fa: float = atan2(face.dot(Vector3(b[2].x, 0, b[2].y)), face.dot(Vector3(b[1].x, 0, b[1].y)))
		var dir := Vector2(sin(fa), -cos(fa))
		var side := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([c + dir * 8.0, c - dir * 5.0 + side * 5.0, c - dir * 2.0, c - dir * 5.0 - side * 5.0]), Color(1, 1, 1))
	draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Color(1.0, 0.85, 0.6, 0.35), false, 1.5)
	draw_string_outline(font, Vector2(6, SIZE - 6), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, 3, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(6, SIZE - 6), "MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.75, 0.7))


func _star(p: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * float(i) / 10.0 - PI / 2.0 + _t * 1.5
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(p + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, col)
