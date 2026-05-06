extends CanvasLayer

@export var total_boxes: int = 4
@export var box_size: Vector2 = Vector2(60, 60)
@export var box_spacing: float = 20.0
@export var empty_color: Color = Color(0.2, 0.2, 0.2, 0.8)
@export var filled_color: Color = Color(0.3, 0.74, 0.667, 1.0)
@export var battle2_offset: Vector2 = Vector2(400, -60)

var _boxes: Array[Panel] = []
var _filled_count: int = 0
var _container: HBoxContainer = null
var _base_position: Vector2 = Vector2(0, 100)

signal all_filled

func _ready() -> void:
	_setup_ui()
	hide()

func _setup_ui() -> void:
	_container = HBoxContainer.new()
	_container.name = "BoxContainer"
	_container.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_container)

	_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_base_position = Vector2(0, 100)
	_container.position = _base_position

	for i in range(total_boxes):
		var panel := Panel.new()
		panel.name = "Box%d" % i
		panel.custom_minimum_size = box_size
		var style := StyleBoxFlat.new()
		style.bg_color = empty_color
		style.set_border_width_all(2)
		style.set_border_color(Color(0.5, 0.5, 0.5, 1.0))
		style.set_corner_radius_all(4)
		panel.add_theme_stylebox_override("panel", style)
		_container.add_child(panel)
		_boxes.append(panel)

func set_progress(count: int) -> void:
	_filled_count = min(count, total_boxes)
	for i in range(total_boxes):
		var panel: Panel = _boxes[i]
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if i < _filled_count:
			style.bg_color = filled_color
		else:
			style.bg_color = empty_color
		panel.add_theme_stylebox_override("panel", style)

	if _filled_count >= total_boxes:
		all_filled.emit()

func reset() -> void:
	_filled_count = 0
	set_progress(0)

func show_ui(battle_id: int = 1) -> void:
	reset()
	visible = true
	if _container:
		if battle_id == 2:
			_container.position = _base_position + battle2_offset
		else:
			_container.position = _base_position

func hide_ui() -> void:
	visible = false
	reset()
