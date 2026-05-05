extends Area2D
class_name DialogueTrigger

@export var dialogue_id: int = 0
@export var dialogue_lines: Array[DialogueLine]
@export var dialogue_ui: DialogueUI 
@export var trigger_battle_id: int = 0
@export var start_battle_after_dialogue: bool = false
@export var battle_manager_path: NodePath = NodePath("")
@export var battle_id: int = 1

# === 新增功能：手动触发控制 ===
@export var require_input: bool = false # 是否需要按键才能触发
@export var prompt_node: CanvasItem = null  # 改用 CanvasItem，以同时兼容 Label 和 Sprite2D

var _player_in_area: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited) # 新增离开区域的监听
	
	# 游戏开始时默认隐藏提示
	if prompt_node:
		prompt_node.hide()

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		if require_input:
			_player_in_area = true
			if prompt_node:
				prompt_node.show() # 显示按键提示
			return
		else:
			if _use_legacy_dialogue():
				_trigger_legacy_dialogue()
			else:
				_try_trigger_dialogue()

func _on_body_exited(body: Node2D) -> void:
	if body.name == "Player":
		_player_in_area = false
		if prompt_node:
			prompt_node.hide() # 离开区域时隐藏提示

# 监听按键输入
func _unhandled_input(event: InputEvent) -> void:
	if _player_in_area and require_input:
		# 当玩家在区域内，且按下了键盘 Y 键
		if event is InputEventKey and event.keycode == KEY_Y and event.pressed:
			_try_trigger_dialogue()
			get_viewport().set_input_as_handled() # 拦截输入，防止传给场景其他节点

func _try_trigger_dialogue() -> void:
	if dialogue_ui == null or dialogue_ui.is_busy or dialogue_lines.is_empty():
		return
		
	if prompt_node:
		prompt_node.hide()
		
	dialogue_ui.play_sequence(dialogue_lines)
	if start_battle_after_dialogue:
		if not dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed_start_battle):
			dialogue_ui.dialogue_closed.connect(_on_dialogue_closed_start_battle, CONNECT_ONE_SHOT)
		return

	queue_free() # 触发完毕后销毁触发器


func _use_legacy_dialogue() -> bool:
	return dialogue_id > 0


func _trigger_legacy_dialogue() -> void:
	if dialogue_ui == null or dialogue_ui.is_busy:
		return
	if trigger_battle_id > 0 and dialogue_ui:
		if not dialogue_ui.dialogue_closed_with_id.is_connected(_on_legacy_dialogue_closed):
			dialogue_ui.dialogue_closed_with_id.connect(_on_legacy_dialogue_closed)
		var battle_manager: TutorialBattleManager = _get_battle_manager()
		if battle_manager:
			battle_manager.prepare_battle(trigger_battle_id)
	else:
		if dialogue_ui and dialogue_ui.dialogue_closed_with_id.is_connected(_on_legacy_dialogue_closed):
			dialogue_ui.dialogue_closed_with_id.disconnect(_on_legacy_dialogue_closed)
		queue_free()

	match dialogue_id:
		1:
			dialogue_ui.show_dialog1()
		2:
			dialogue_ui.show_dialog2()
		3:
			dialogue_ui.show_dialog3()
		4:
			dialogue_ui.show_dialog4()
		_:
			push_warning("未知的 Dialogue ID")


func _on_legacy_dialogue_closed(closed_id: int) -> void:
	if closed_id != dialogue_id:
		return
	if dialogue_ui and dialogue_ui.dialogue_closed_with_id.is_connected(_on_legacy_dialogue_closed):
		dialogue_ui.dialogue_closed_with_id.disconnect(_on_legacy_dialogue_closed)
	if trigger_battle_id > 0:
		var battle_manager: TutorialBattleManager = _get_battle_manager()
		if battle_manager:
			battle_manager.start_battle(trigger_battle_id)
	queue_free()


func _get_battle_manager() -> TutorialBattleManager:
	if not battle_manager_path.is_empty():
		return get_node_or_null(battle_manager_path) as TutorialBattleManager
	var root: Node = get_tree().current_scene
	if root:
		return root.find_child("TutorialBattleManager", true, false) as TutorialBattleManager
	return null


func _on_dialogue_closed_start_battle() -> void:
	if not battle_manager_path.is_empty():
		var battle_manager: TutorialBattleManager = get_node_or_null(battle_manager_path) as TutorialBattleManager
		if battle_manager:
			battle_manager.start_battle(battle_id)
	queue_free()
