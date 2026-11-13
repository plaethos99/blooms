extends Control
## Lantern-light bar with the 20 / 70 / 80 thresholds marked.

var value := 50.0
var shown := 50.0
var marks := [20, 70, 80] # Level 1 shows none


func _ready() -> void:
	custom_minimum_size = Vector2(340, 22)


func _process(delta: float) -> void:
	shown = lerpf(shown, value, minf(1.0, delta * 8.0))
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.02, 0.06, 0.8))
	var col: Color
	if shown < 20.0:
		col = Color(0.95, 0.2, 0.2)
	elif shown < 70.0:
		col = Color(1.0, 0.62, 0.25)
	elif shown < 80.0:
		col = Color(1.0, 0.82, 0.4)
	else:
		col = Color(1.0, 0.95, 0.75)
	draw_rect(Rect2(2, 2, (w - 4.0) * clampf(shown / 100.0, 0.0, 1.0), h - 4.0), col)
	var font := ThemeDB.fallback_font
	for m in marks:
		var x: float = w * float(m) / 100.0
		var key: bool = m == 80
		var mc := Color(1, 1, 1, 0.95) if key else Color(1, 1, 1, 0.45)
		draw_line(Vector2(x, -5), Vector2(x, h + 5), mc, 2.0 if key else 1.0)
		draw_string(font, Vector2(x - 9.0, -8.0), str(m), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, mc)
	draw_rect(Rect2(0, 0, w, h), Color(1, 0.9, 0.7, 0.5), false, 1.0)
