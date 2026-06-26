extends CanvasLayer

@export var total_boxes: int = 4
@export var box_size: Vector2 = Vector2(22, 22)
@export var box_spacing: float = 8.0
@export var empty_color: Color = Color(0.03, 0.04, 0.05, 0.38)
@export var filled_color: Color = Color(0.22, 0.86, 0.72, 1.0)
@export var panel_width: float = 286.0
@export var screen_center_ratio: Vector2 = Vector2(0.5, 0.44)
@export var battle2_offset: Vector2 = Vector2.ZERO

var _single_boxes: Array[Panel] = []
var _cannon_boxes: Array[Panel] = []
var _missile_boxes: Array[Panel] = []
var _filled_count: int = 0
var _filled_count_row1: int = 0
var _filled_count_row2: int = 0
var _dual_row_mode: bool = false

var _panel: VBoxContainer = null
var _single_row: HBoxContainer = null
var _dual_rows: VBoxContainer = null

signal all_filled


func _ready() -> void:
	_setup_ui()
	get_viewport().size_changed.connect(_place_panel)
	hide()


func _setup_ui() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "ProgressPrompt"
	_panel.custom_minimum_size = Vector2(panel_width, 0.0)
	_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_theme_constant_override("separation", 6)
	add_child(_panel)

	_single_row = HBoxContainer.new()
	_single_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_single_row.add_theme_constant_override("separation", int(box_spacing))
	_panel.add_child(_single_row)
	_single_boxes = _create_box_row(_single_row, "TrainingBox")

	_dual_rows = VBoxContainer.new()
	_dual_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	_dual_rows.add_theme_constant_override("separation", 5)
	_panel.add_child(_dual_rows)
	_cannon_boxes = _create_labeled_row(_dual_rows, tr("TUTORIAL_PROGRESS_CANNON"), "CannonBox")
	_missile_boxes = _create_labeled_row(_dual_rows, tr("TUTORIAL_PROGRESS_MISSILE"), "MissileBox")

	_place_panel()


func _place_panel() -> void:
	if _panel == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var width: float = maxf(panel_width, _panel.custom_minimum_size.x)
	var height: float = maxf(1.0, _panel.get_combined_minimum_size().y)
	_panel.position = Vector2(
		viewport_size.x * screen_center_ratio.x - width * 0.5,
		viewport_size.y * screen_center_ratio.y - height * 0.5
	) + battle2_offset


func _create_labeled_row(parent: VBoxContainer, label_text: String, prefix: String) -> Array[Panel]:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(box_spacing))
	parent.add_child(row)

	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(58, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.88, 0.95, 0.93, 1.0))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.82))
	row.add_child(label)

	return _create_box_row(row, prefix)


func _create_box_row(parent: HBoxContainer, prefix: String) -> Array[Panel]:
	var boxes: Array[Panel] = []
	for i in range(total_boxes):
		var panel: Panel = Panel.new()
		panel.name = "%s%d" % [prefix, i]
		panel.custom_minimum_size = box_size
		panel.add_theme_stylebox_override("panel", _make_box_style(false))
		parent.add_child(panel)
		boxes.append(panel)
	return boxes


func _make_box_style(filled: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = filled_color if filled else empty_color
	style.border_color = Color(0.75, 0.94, 0.90, 0.85) if filled else Color(0.45, 0.50, 0.55, 0.70)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style


func set_progress(count: int) -> void:
	_filled_count = mini(count, total_boxes)
	_update_box_row(_single_boxes, _filled_count)
	if _filled_count >= total_boxes:
		all_filled.emit()


func setup_dual_row_mode() -> void:
	_dual_row_mode = true


func set_dual_row_progress(cannon_count: int, missile_count: int) -> void:
	if not _dual_row_mode:
		return

	_filled_count_row1 = mini(cannon_count, total_boxes)
	_filled_count_row2 = mini(missile_count, total_boxes)
	_update_box_row(_cannon_boxes, _filled_count_row1)
	_update_box_row(_missile_boxes, _filled_count_row2)

	if _filled_count_row1 >= total_boxes and _filled_count_row2 >= total_boxes:
		all_filled.emit()


func _update_box_row(boxes: Array[Panel], filled_count: int) -> void:
	for i in range(boxes.size()):
		var panel: Panel = boxes[i]
		if panel == null or not is_instance_valid(panel):
			continue
		panel.add_theme_stylebox_override("panel", _make_box_style(i < filled_count))


func reset() -> void:
	_filled_count = 0
	_filled_count_row1 = 0
	_filled_count_row2 = 0
	_update_box_row(_single_boxes, 0)
	_update_box_row(_cannon_boxes, 0)
	_update_box_row(_missile_boxes, 0)


func show_ui(battle_id: int = 1) -> void:
	visible = true
	_dual_row_mode = battle_id == 2
	reset()

	if _single_row != null:
		_single_row.visible = not _dual_row_mode
	if _dual_rows != null:
		_dual_rows.visible = _dual_row_mode
	_place_panel()


func hide_ui() -> void:
	visible = false
	reset()
