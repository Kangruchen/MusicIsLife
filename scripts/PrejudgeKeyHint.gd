extends Node2D
class_name PrejudgeKeyHint
## 判定前按键提示：中心按键圆 + 外环收缩

var key_text: String = "J"
var duration: float = 0.5
var elapsed: float = 0.0
var core_radius: float = 20.0
var ring_start_radius: float = 56.0
var ring_end_radius: float = 24.0
var ring_width: float = 4.0

var core_color: Color = Color(0.22, 0.56, 0.98, 0.9)
var ring_color: Color = Color(1.0, 1.0, 1.0, 0.95)
var text_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var glyph_family: String = ""

var _label: Label = null


func _ready() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.size = Vector2(76.0, 50.0)
	_label.position = Vector2(-38.0, -25.0)
	_label.add_theme_color_override("font_color", text_color)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_label.add_theme_constant_override("outline_size", 4)
	add_child(_label)
	_apply_label_text()
	queue_redraw()


func setup(
	in_key_text: String,
	in_duration: float,
	in_core_color: Color,
	in_ring_color: Color,
	in_text_color: Color,
	in_glyph_family: String = ""
) -> void:
	key_text = in_key_text
	duration = maxf(0.01, in_duration)
	core_color = in_core_color
	ring_color = in_ring_color
	text_color = in_text_color
	glyph_family = in_glyph_family
	_apply_label_text()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= duration:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(elapsed / duration, 0.0, 1.0)
	var current_ring_radius: float = lerpf(ring_start_radius, ring_end_radius, t)

	draw_circle(Vector2.ZERO, core_radius, core_color)
	draw_arc(Vector2.ZERO, current_ring_radius, 0.0, TAU, 72, ring_color, ring_width, true)
	_draw_button_glyph()


func _apply_label_text() -> void:
	if _label == null:
		return
	_label.visible = not _uses_drawn_glyph()
	_label.text = key_text
	_label.add_theme_color_override("font_color", text_color)
	var prompt_length: int = key_text.length()
	var font_size: int = 22
	if prompt_length > 6:
		font_size = 12
	elif prompt_length > 3:
		font_size = 15
	_label.add_theme_font_size_override("font_size", font_size)


func _uses_drawn_glyph() -> bool:
	return glyph_family == "playstation" or glyph_family == "xbox" or glyph_family == "nintendo"


func _draw_button_glyph() -> void:
	if not _uses_drawn_glyph():
		return

	match glyph_family:
		"playstation":
			_draw_playstation_glyph()
		"xbox", "nintendo":
			_draw_letter_button_glyph()


func _draw_playstation_glyph() -> void:
	var glyph: String = _get_playstation_glyph_kind()
	var stroke: Color = _get_playstation_glyph_color(glyph)
	var width: float = 3.6

	match glyph:
		"triangle":
			var points: PackedVector2Array = PackedVector2Array([
				Vector2(0.0, -12.0),
				Vector2(11.0, 9.0),
				Vector2(-11.0, 9.0),
				Vector2(0.0, -12.0),
			])
			draw_polyline(points, stroke, width, true)
		"circle":
			draw_arc(Vector2.ZERO, 12.0, 0.0, TAU, 72, stroke, width, true)
		"square":
			draw_rect(Rect2(Vector2(-11.0, -11.0), Vector2(22.0, 22.0)), stroke, false, width)
		"cross":
			draw_line(Vector2(-9.0, -9.0), Vector2(9.0, 9.0), stroke, width, true)
			draw_line(Vector2(9.0, -9.0), Vector2(-9.0, 9.0), stroke, width, true)
		_:
			_draw_letter_button_glyph()


func _get_playstation_glyph_kind() -> String:
	var glyph: String = key_text.strip_edges().to_lower()
	match glyph:
		"triangle", "△":
			return "triangle"
		"circle", "○":
			return "circle"
		"square", "□":
			return "square"
		"cross", "x", "×", "✕":
			return "cross"
		_:
			return glyph


func _get_playstation_glyph_color(glyph: String) -> Color:
	match glyph:
		"triangle":
			return Color(0.34, 1.0, 0.55, 1.0)
		"circle":
			return Color(1.0, 0.36, 0.36, 1.0)
		"square":
			return Color(1.0, 0.45, 0.86, 1.0)
		"cross":
			return Color(0.42, 0.74, 1.0, 1.0)
		_:
			return text_color


func _draw_letter_button_glyph() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	var label_text: String = key_text
	if label_text.length() > 2:
		label_text = label_text.substr(0, 2)

	var font_size: int = 18 if label_text.length() <= 1 else 13
	var text_size: Vector2 = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	var pos: Vector2 = Vector2(-text_size.x * 0.5, text_size.y * 0.35)
	draw_string(font, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, text_color)
