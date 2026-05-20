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
	in_text_color: Color
) -> void:
	key_text = in_key_text
	duration = maxf(0.01, in_duration)
	core_color = in_core_color
	ring_color = in_ring_color
	text_color = in_text_color
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


func _apply_label_text() -> void:
	if _label == null:
		return
	_label.text = key_text
	_label.add_theme_color_override("font_color", text_color)
	var prompt_length: int = key_text.length()
	var font_size: int = 22
	if prompt_length > 6:
		font_size = 12
	elif prompt_length > 3:
		font_size = 15
	_label.add_theme_font_size_override("font_size", font_size)
