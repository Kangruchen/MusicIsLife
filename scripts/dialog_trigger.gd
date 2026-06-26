extends Area2D
class_name DialogueTrigger

@export var dialogue_lines: Array[DialogueLine]
@export var dialogue_ui: DialogueUI
@export var trigger_battle_id: int = 0
@export var start_battle_after_dialogue: bool = false
@export var battle_manager_path: NodePath = NodePath("")
@export var battle_id: int = 1
@export var prepare_battle_before_cutscene: bool = false
@export var pre_dialogue_cutscene: Node = null

@export var require_input: bool = false
@export var interact_action: StringName = &"interact"
@export var prompt_node: CanvasItem = null
@export var external_trigger_only: bool = false

var _player_in_area: bool = false
var _player_body: Node2D = null
var _has_triggered: bool = false
var _is_waiting_for_cutscene: bool = false


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

	_player_body = body
	if external_trigger_only:
		return

	if require_input:
		_player_in_area = true
		if prompt_node:
			prompt_node.show()
		return

	_try_trigger_dialogue()


func _on_body_exited(body: Node2D) -> void:
	if body.name != "Player":
		return

	_player_in_area = false
	if _player_body == body:
		_player_body = null
	if prompt_node:
		prompt_node.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not _player_in_area or not require_input:
		return
	if not event.is_action_pressed(interact_action):
		return
	if external_trigger_only:
		return

	_try_trigger_dialogue()
	get_viewport().set_input_as_handled()


func _update_prompt_text() -> void:
	if prompt_node == null:
		return

	var prompt_text: String = tr("PROMPT_PRESS") % GameConstants.get_action_key_label(String(interact_action), "E")
	if prompt_node is Label:
		(prompt_node as Label).text = prompt_text
	elif prompt_node is RichTextLabel:
		(prompt_node as RichTextLabel).text = prompt_text


func start_dialogue_externally() -> void:
	_try_trigger_dialogue()


func _try_trigger_dialogue() -> void:
	if _has_triggered or _is_waiting_for_cutscene:
		return
	if dialogue_ui == null or dialogue_ui.is_busy or dialogue_lines.is_empty():
		return

	if prompt_node:
		prompt_node.hide()

	_has_triggered = true
	if prepare_battle_before_cutscene:
		_prepare_battle_for_trigger()
	if pre_dialogue_cutscene != null and pre_dialogue_cutscene.has_method("play"):
		_is_waiting_for_cutscene = true
		if pre_dialogue_cutscene.has_method("play_for_player"):
			await pre_dialogue_cutscene.play_for_player(_player_body)
		else:
			await pre_dialogue_cutscene.play()
		_is_waiting_for_cutscene = false
		if not is_inside_tree():
			return
		if dialogue_ui == null or dialogue_ui.is_busy:
			_has_triggered = false
			return

	dialogue_ui.play_sequence(dialogue_lines)
	if start_battle_after_dialogue or trigger_battle_id > 0:
		if not dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed_start_battle):
			dialogue_ui.dialogue_closed.connect(_on_dialogue_closed_start_battle, CONNECT_ONE_SHOT)
		return

	queue_free()


func _get_battle_manager() -> TutorialBattleManager:
	if not battle_manager_path.is_empty():
		return get_node_or_null(battle_manager_path) as TutorialBattleManager

	var root: Node = get_tree().current_scene
	if root:
		return root.find_child("TutorialBattleManager", true, false) as TutorialBattleManager
	return null


func _get_battle_to_start() -> int:
	return trigger_battle_id if trigger_battle_id > 0 else battle_id


func _prepare_battle_for_trigger() -> void:
	var battle_to_prepare: int = _get_battle_to_start()
	if battle_to_prepare <= 0:
		return
	var battle_manager: TutorialBattleManager = _get_battle_manager()
	if battle_manager != null:
		battle_manager.prepare_battle(battle_to_prepare)


func _on_dialogue_closed_start_battle() -> void:
	var battle_to_start: int = _get_battle_to_start()
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
