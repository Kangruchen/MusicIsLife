extends Area2D
class_name DialogueTrigger

@export var dialogue_id: int = 0
@export var dialogue_lines: Array[DialogueLine]
@export var dialogue_ui: DialogueUI
@export var trigger_battle_id: int = 0
@export var start_battle_after_dialogue: bool = false
@export var battle_manager_path: NodePath = NodePath("")
@export var battle_id: int = 1

@export var require_input: bool = false
@export var interact_action: StringName = &"interact"
@export var prompt_node: CanvasItem = null

var _player_in_area: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_update_prompt_text()

	var gamepad_manager: Node = get_node_or_null("/root/GamepadManager")
	if gamepad_manager != null and gamepad_manager.has_signal("input_scheme_changed"):
		gamepad_manager.connect("input_scheme_changed", func(_is_gamepad: bool) -> void:
			_update_prompt_text()
		)

	if prompt_node:
		prompt_node.hide()


func _on_body_entered(body: Node2D) -> void:
	if body.name != "Player":
		return

	if require_input:
		_player_in_area = true
		if prompt_node:
			prompt_node.show()
		return

	if _use_legacy_dialogue():
		_trigger_legacy_dialogue()
	else:
		_try_trigger_dialogue()


func _on_body_exited(body: Node2D) -> void:
	if body.name != "Player":
		return
	_player_in_area = false
	if prompt_node:
		prompt_node.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_area or not require_input:
		return
	if not event.is_action_pressed(interact_action):
		return

	_try_trigger_dialogue()
	get_viewport().set_input_as_handled()


func _update_prompt_text() -> void:
	if prompt_node == null:
		return

	var prompt_text: String = "Press %s" % GameConstants.get_action_key_label(String(interact_action), "E")
	if prompt_node is Label:
		(prompt_node as Label).text = prompt_text
	elif prompt_node is RichTextLabel:
		(prompt_node as RichTextLabel).text = prompt_text


func _try_trigger_dialogue() -> void:
	if dialogue_ui == null or dialogue_ui.is_busy or dialogue_lines.is_empty():
		return

	if prompt_node:
		prompt_node.hide()

	dialogue_ui.play_sequence(dialogue_lines)
	if start_battle_after_dialogue or trigger_battle_id > 0:
		if not dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed_start_battle):
			dialogue_ui.dialogue_closed.connect(_on_dialogue_closed_start_battle, CONNECT_ONE_SHOT)
		return

	queue_free()


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
			push_warning("Unknown Dialogue ID")


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
	var battle_to_start: int = trigger_battle_id if trigger_battle_id > 0 else battle_id
	if battle_to_start > 0:
		if not battle_manager_path.is_empty():
			var battle_manager: TutorialBattleManager = get_node_or_null(battle_manager_path) as TutorialBattleManager
			if battle_manager:
				battle_manager.start_battle(battle_to_start)
		else:
			var battle_manager: TutorialBattleManager = _get_battle_manager()
			if battle_manager:
				battle_manager.start_battle(battle_to_start)
	queue_free()
