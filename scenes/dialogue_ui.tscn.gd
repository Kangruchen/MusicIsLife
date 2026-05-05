extends Control
class_name DialogueUI

signal dialogue_closed(dialog_id: int)

@export var player_node: Node2D = null
@export var dialog_title: String = ""
@export var dialog1_text: String = ""
@export var dialog2_text: String = ""
@export var dialog3_text: String = ""
@export var dialog4_text: String = ""
@export var typing_speed: int = 8

@onready var dialog_panel: Panel = $DialogPanel
@onready var name_label: Label = $DialogPanel/NameLabel
@onready var text_label: RichTextLabel = $DialogPanel/TextLabel
@onready var typing_sound: AudioStreamPlayer = $TypingSoundPlayer

var is_busy: bool = false
var is_typing: bool = false
var wait_for_close: bool = false
var _current_dialog_id: int = 0

func _ready() -> void:
	visible = false
	dialog_panel.visible = false

func show_dialog1() -> void: _open(dialog1_text, 1)
func show_dialog2() -> void: _open(dialog2_text, 2)
func show_dialog3() -> void: _open(dialog3_text, 3)
func show_dialog4() -> void: _open(dialog4_text, 4)

func _open(content: String, dialog_id: int = 0) -> void:
	_current_dialog_id = dialog_id
	if is_busy or content == "": return
	is_busy = true
	wait_for_close = false

	# 锁定玩家输入与移动
	if player_node:
		player_node.set_process_input(false)
		player_node.set_physics_process(false)

	visible = true
	dialog_panel.visible = true
	name_label.text = dialog_title
	
	# 初始化文本内容，起始可见字符设为0
	text_label.text = content
	text_label.visible_characters = 0

	# 0.1秒缓冲，避免玩家触发对话前一瞬间的按键被错误识别
	await get_tree().create_timer(0.1).timeout 

	is_typing = true
	var total_chars: int = content.length()

	# 逐字展示：只要还没展示完，并且玩家没有跳过(is_typing==true)，就一直打字
	while text_label.visible_characters < total_chars and is_typing:
		text_label.visible_characters += 1
		var current_char: String = content[text_label.visible_characters - 1]
		
		# 遇到空格或换行时不播放音效，更加自然
		if current_char != " " and current_char != "\n":
			typing_sound.play()
			
		await get_tree().create_timer(1.0 / typing_speed).timeout

	# === 循环结束（自动打完或被玩家按空格跳过） ===
	
	is_typing = false
	typing_sound.stop() 
	
	# 强制让所有文字立刻呈现，应对跳过中途断掉的情况
	text_label.visible_characters = total_chars
	
	#加入0.1秒的“冷却硬直”，避免玩家因为“长按”空格导致刚跳过打字就立刻关闭了对话
	await get_tree().create_timer(0.1).timeout
	wait_for_close = true

# 统一处理点击/按空格输入交互
func _unhandled_input(event: InputEvent) -> void:
	# UI未显示时不拦截输入
	if not visible: return
	
	# 匹配空格、回车，或者鼠标左键
	var is_confirm: bool = event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	
	if is_confirm:
		if is_typing:
			# 阶段1：还在打字时按了确认 -> 立刻终止打字状态，全量展示文字
			is_typing = false
		elif wait_for_close:
			# 阶段2：早已打完且度过了防连点冷却 -> 执行彻底关闭，进而解锁角色
			_close_dialogue()
		
		# 吞掉这次按键输入，阻止向下传递，防止角色在背景里跟着起跳或攻击
		get_viewport().set_input_as_handled()

func _close_dialogue() -> void:
	var closed_id: int = _current_dialog_id
	visible = false
	dialog_panel.visible = false
	is_busy = false
	wait_for_close = false
	_current_dialog_id = 0

	if player_node:
		player_node.set_process_input(true)
		player_node.set_physics_process(true)

	dialogue_closed.emit(closed_id)
