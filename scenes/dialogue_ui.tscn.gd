extends Control
class_name DialogueUI

signal dialogue_closed
signal dialogue_closed_with_id(dialog_id: int)

@export var player_node: Node2D = null
@export var dialog_title: String = ""
@export var dialog1_text: String = ""
@export var dialog2_text: String = ""
@export var dialog3_text: String = ""
@export var dialog4_text: String = ""
@export var typing_speed: int = 12

@onready var dialog_panel: Control = $DialogPanel
@onready var name_label: Label = $DialogPanel/NameLabel
@onready var text_label: RichTextLabel = $DialogPanel/TextLabel
@onready var typing_sound: AudioStreamPlayer = $TypingSoundPlayer
@onready var avatar_rect: TextureRect = $DialogPanel/AvatarRect # 获取头像节点

var is_busy: bool = false
var is_typing: bool = false
var wait_for_input: bool = false

var current_lines: Array[DialogueLine] = []
var current_index: int = 0
var _legacy_mode: bool = false
var _legacy_dialog_id: int = 0

func _ready() -> void:
	visible = false
	dialog_panel.visible = false

# 接收来自 Trigger 的整个对话数组，开始播放
func play_sequence(lines: Array[DialogueLine]) -> void:
	_legacy_mode = false
	_legacy_dialog_id = 0
	_start_sequence(lines)


func show_dialog1() -> void:
	_open_legacy(dialog1_text, 1)


func show_dialog2() -> void:
	_open_legacy(dialog2_text, 2)


func show_dialog3() -> void:
	_open_legacy(dialog3_text, 3)


func show_dialog4() -> void:
	_open_legacy(dialog4_text, 4)


func _open_legacy(content: String, dialog_id: int) -> void:
	if content == "":
		return
	_legacy_mode = true
	_legacy_dialog_id = dialog_id
	var line := DialogueLine.new()
	line.speaker_name = dialog_title
	line.content = content
	line.avatar = null
	_start_sequence([line])


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
	dialog_panel.visible = false
	is_busy = false
	wait_for_input = false
	dialogue_closed.emit()
	if _legacy_mode:
		dialogue_closed_with_id.emit(_legacy_dialog_id)
	_legacy_mode = false
	_legacy_dialog_id = 0

	if player_node:
		var in_battle: bool = false
		if player_node.has_method("is_in_battle"):
			in_battle = player_node.is_in_battle()
		if not in_battle:
			player_node.set_process_input(true)
			if player_node.has_method("unfreeze_movement"):
				player_node.unfreeze_movement()
