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

# 双行模式变量
var _boxes_row1: Array[Panel] = []
var _boxes_row2: Array[Panel] = []
var _filled_count_row1: int = 0
var _filled_count_row2: int = 0
var _container_vbox: VBoxContainer = null
var _dual_row_mode: bool = false

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
		if i >= _boxes.size():
			break
		var panel: Panel = _boxes[i]
		if panel == null or not is_instance_valid(panel):
			continue
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if style == null:
			continue
		if i < _filled_count:
			style.bg_color = filled_color
		else:
			style.bg_color = empty_color
		panel.add_theme_stylebox_override("panel", style)

	if _filled_count >= total_boxes:
		all_filled.emit()

## 双行进度显示模式（第二场战斗用）
func setup_dual_row_mode() -> void:
	if _dual_row_mode:
		return
	
	_dual_row_mode = true
	
	# 隐藏单行模式的容器
	if _container:
		_container.visible = false
	
	# 创建垂直容器（如果还不存在）
	if _container_vbox == null:
		_container_vbox = VBoxContainer.new()
		_container_vbox.name = "DualRowContainer"
		add_child(_container_vbox)
		_container_vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
		_container_vbox.position = _base_position
		
		# 第一行（Cannon）
		var row1_label := Label.new()
		row1_label.text = "Cannon"
		row1_label.add_theme_font_size_override("font_size", 24)
		_container_vbox.add_child(row1_label)
		
		var row1_container := HBoxContainer.new()
		row1_container.alignment = BoxContainer.ALIGNMENT_CENTER
		row1_container.add_theme_constant_override("separation", int(box_spacing))
		_container_vbox.add_child(row1_container)
		
		for i in range(total_boxes):
			var panel := Panel.new()
			panel.name = "CannonBox%d" % i
			panel.custom_minimum_size = box_size
			var style := StyleBoxFlat.new()
			style.bg_color = empty_color
			style.set_border_width_all(2)
			style.set_border_color(Color(0.5, 0.5, 0.5, 1.0))
			style.set_corner_radius_all(4)
			panel.add_theme_stylebox_override("panel", style)
			row1_container.add_child(panel)
			_boxes_row1.append(panel)
		
		# 第二行（Missile）
		var row2_label := Label.new()
		row2_label.text = "Missile"
		row2_label.add_theme_font_size_override("font_size", 24)
		_container_vbox.add_child(row2_label)
		
		var row2_container := HBoxContainer.new()
		row2_container.alignment = BoxContainer.ALIGNMENT_CENTER
		row2_container.add_theme_constant_override("separation", int(box_spacing))
		_container_vbox.add_child(row2_container)
		
		for i in range(total_boxes):
			var panel := Panel.new()
			panel.name = "MissileBox%d" % i
			panel.custom_minimum_size = box_size
			var style := StyleBoxFlat.new()
			style.bg_color = empty_color
			style.set_border_width_all(2)
			style.set_border_color(Color(0.5, 0.5, 0.5, 1.0))
			style.set_corner_radius_all(4)
			panel.add_theme_stylebox_override("panel", style)
			row2_container.add_child(panel)
			_boxes_row2.append(panel)
	else:
		_container_vbox.visible = true

## 设置双行模式的进度
func set_dual_row_progress(cannon_count: int, missile_count: int) -> void:
	if not _dual_row_mode:
		return
	
	_filled_count_row1 = min(cannon_count, total_boxes)
	_filled_count_row2 = min(missile_count, total_boxes)
	
	# 更新第一行（Cannon）
	for i in range(total_boxes):
		var panel: Panel = _boxes_row1[i]
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if i < _filled_count_row1:
			style.bg_color = filled_color
		else:
			style.bg_color = empty_color
		panel.add_theme_stylebox_override("panel", style)
	
	# 更新第二行（Missile）
	for i in range(total_boxes):
		var panel: Panel = _boxes_row2[i]
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel")
		if i < _filled_count_row2:
			style.bg_color = filled_color
		else:
			style.bg_color = empty_color
		panel.add_theme_stylebox_override("panel", style)
	
	# 两行都满时发信号
	if _filled_count_row1 >= total_boxes and _filled_count_row2 >= total_boxes:
		all_filled.emit()

func reset() -> void:
	_filled_count = 0
	_filled_count_row1 = 0
	_filled_count_row2 = 0
	if _dual_row_mode:
		set_dual_row_progress(0, 0)
	else:
		set_progress(0)

func show_ui(battle_id: int = 1) -> void:
	visible = true
	# 根据battle_id设置正确的模式
	var should_use_dual_row = (battle_id == 2)
	if should_use_dual_row and not _dual_row_mode:
		setup_dual_row_mode()
	elif not should_use_dual_row:
		_dual_row_mode = false
	
	reset()
	
	# 显示正确的容器
	if _dual_row_mode:
		if _container_vbox:
			_container_vbox.visible = true
			_container_vbox.position = _base_position + battle2_offset
		if _container:
			_container.visible = false
	else:
		if _container:
			_container.visible = true
			if battle_id == 2:
				_container.position = _base_position + battle2_offset
			else:
				_container.position = _base_position
		if _container_vbox:
			_container_vbox.visible = false

func hide_ui() -> void:
	visible = false
	if _container:
		_container.visible = false
	if _container_vbox:
		_container_vbox.visible = false
	reset()
