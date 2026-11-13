extends RefCounted
## The game's typefaces (both SIL Open Font License, see fonts/*-OFL.txt):
## Cinzel, classical Roman capitals, for titles, banners, the clock and big buttons;
## Inter, a clean modern sans, for everything else.

static var _body: FontVariation
static var _title: FontVariation


static func _tag(n: String) -> int:
	return TextServerManager.get_primary_interface().name_to_tag(n)


static func body() -> Font:
	if _body == null:
		_body = FontVariation.new()
		_body.base_font = load("res://fonts/Inter.ttf")
		_body.variation_opentype = {_tag("wght"): 600}
	return _body


static func title() -> Font:
	if _title == null:
		_title = FontVariation.new()
		_title.base_font = load("res://fonts/Cinzel.ttf")
		_title.variation_opentype = {_tag("wght"): 700}
		_title.spacing_glyph = 1
	return _title


## Makes Inter the default for every Control, Label3D and draw_string in the game.
static func install() -> void:
	ThemeDB.fallback_font = body()
