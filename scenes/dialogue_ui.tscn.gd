extends Control
class_name DialogueUI

signal dialogue_closed

@export var player_node: Node2D = null
@export var typing_speed: int = 12
@export var large_popup_mode: bool = false

@onready var dialog_panel: Control = $DialogPanel
@onready var name_label: Label = $DialogPanel/NameLabel
@onready var text_label: RichTextLabel = $DialogPanel/TextLabel
@onready var typing_sound: AudioStreamPlayer = $TypingSoundPlayer
@onready var avatar_rect: TextureRect = $DialogPanel/AvatarRect # 获取头像节点

var _modal_backdrop: ColorRect = null
var _modal_background: Panel = null

var is_busy: bool = false
var is_typing: bool = false
var wait_for_input: bool = false

var current_lines: Array[DialogueLine] = []
var current_index: int = 0

func _ready() -> void:
	_apply_layout_mode()
	visible = false
	dialog_panel.visible = false
	if _modal_backdrop:
		_modal_backdrop.visible = false

# 接收来自 Trigger 的整个对话数组，开始播放
func play_sequence(lines: Array[DialogueLine]) -> void:
	_start_sequence(lines)


func _start_sequence(lines: Array[DialogueLine]) -> void:
	if is_busy or lines.is_empty():
		return
	is_busy = true
	current_lines = lines
	current_index = 0

	if player_node:
		player_node.set_process_input(false)
		if player_node.has_method("freeze_movement"):
			player_node.freeze_movement()

	visible = true
	if _modal_backdrop:
		_modal_backdrop.visible = true
	dialog_panel.visible = true
	_show_current_line()

func _show_current_line() -> void:
	wait_for_input = false
	var line: DialogueLine = current_lines[current_index]

	# 更新名字和文本
	name_label.text = line.speaker_name
	text_label.text = line.content
	text_label.visible_characters = 0

	# 检查并更新头像，如果没有头像(旁白)则隐藏对应图形节点
	if line.avatar != null:
		avatar_rect.texture = line.avatar
		avatar_rect.show()
	else:
		avatar_rect.hide()

	await get_tree().create_timer(0.1).timeout 
	is_typing = true
	var total_chars: int = line.content.length()

	# 打字机效果
	while text_label.visible_characters < total_chars and is_typing:
		text_label.visible_characters += 1
		var current_char: String = line.content[text_label.visible_characters - 1]
		
		if current_char != " " and current_char != "\n":
			typing_sound.play()
			
		await get_tree().create_timer(1.0 / typing_speed).timeout

	is_typing = false
	typing_sound.stop() 
	text_label.visible_characters = total_chars
	
	await get_tree().create_timer(0.1).timeout
	wait_for_input = true

func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	
	var is_confirm: bool = event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_confirm:
		if is_typing:
			is_typing = false
		elif wait_for_input:
			_next_line()
		
		get_viewport().set_input_as_handled()

# 播放下一句或关闭
func _next_line() -> void:
	current_index += 1
	if current_index < current_lines.size():
		_show_current_line()
	else:
		_close_dialogue()

func _close_dialogue() -> void:
	visible = false
	if _modal_backdrop:
		_modal_backdrop.visible = false
	dialog_panel.visible = false
	is_busy = false
	wait_for_input = false
	dialogue_closed.emit()

	if player_node:
		var in_battle: bool = false
		if player_node.has_method("is_in_battle"):
			in_battle = player_node.is_in_battle()
		if not in_battle:
			player_node.set_process_input(true)
			if player_node.has_method("unfreeze_movement"):
				player_node.unfreeze_movement()


func _apply_layout_mode() -> void:
	if not large_popup_mode:
		return

	_build_large_popup_chrome()

	dialog_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_panel.anchor_left = 0.07
	dialog_panel.anchor_top = 0.12
	dialog_panel.anchor_right = 0.93
	dialog_panel.anchor_bottom = 0.86
	dialog_panel.offset_left = 0.0
	dialog_panel.offset_top = 0.0
	dialog_panel.offset_right = 0.0
	dialog_panel.offset_bottom = 0.0
	dialog_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dialog_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog_panel.self_modulate = Color(1.0, 1.0, 1.0, 0.0)

	name_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_label.offset_left = 34.0
	name_label.offset_top = 24.0
	name_label.offset_right = -34.0
	name_label.offset_bottom = 54.0
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35, 1.0))
	name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)

	text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_label.offset_left = 34.0
	text_label.offset_top = 72.0
	text_label.offset_right = -34.0
	text_label.offset_bottom = -32.0
	text_label.add_theme_font_size_override("normal_font_size", 22)
	text_label.add_theme_color_override("default_color", Color(0.95, 0.98, 1.0, 1.0))
	text_label.scroll_active = false

	avatar_rect.hide()


func _build_large_popup_chrome() -> void:
	_modal_backdrop = ColorRect.new()
	_modal_backdrop.name = "ModalBackdrop"
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.color = Color(0.0, 0.0, 0.0, 0.58)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal_backdrop)
	move_child(_modal_backdrop, 0)

	_modal_background = Panel.new()
	_modal_background.name = "ModalBackground"
	_modal_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.06, 0.96)
	panel_style.border_color = Color(0.26, 0.72, 0.82, 0.85)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	_modal_background.add_theme_stylebox_override("panel", panel_style)
	dialog_panel.add_child(_modal_background)
	dialog_panel.move_child(_modal_background, 0)

	var accent := ColorRect.new()
	accent.name = "ModalAccent"
	accent.set_anchors_preset(Control.PRESET_TOP_WIDE)
	accent.offset_left = 18.0
	accent.offset_top = 14.0
	accent.offset_right = -18.0
	accent.offset_bottom = 18.0
	accent.color = Color(0.18, 0.82, 0.95, 0.9)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog_panel.add_child(accent)
	dialog_panel.move_child(accent, 1)
