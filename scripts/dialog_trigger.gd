extends Area2D
class_name DialogueTrigger

@export var dialogue_id: int = 1
@export var dialogue_ui: DialogueUI
@export var trigger_battle_id: int = 0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		if dialogue_ui and not dialogue_ui.is_busy:
			_trigger_dialogue()
			monitoring = false
			monitorable = false

func _trigger_dialogue() -> void:
	if trigger_battle_id > 0 and dialogue_ui:
		if not dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
			dialogue_ui.dialogue_closed.connect(_on_dialogue_closed)
		var battle_manager: TutorialBattleManager = _get_battle_manager()
		if battle_manager:
			battle_manager.prepare_battle(trigger_battle_id)
	else:
		if dialogue_ui and dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
			dialogue_ui.dialogue_closed.disconnect(_on_dialogue_closed)
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

func _on_dialogue_closed(closed_id: int) -> void:
	if closed_id != dialogue_id:
		return
	if dialogue_ui and dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
		dialogue_ui.dialogue_closed.disconnect(_on_dialogue_closed)
	if trigger_battle_id > 0:
		var battle_manager: TutorialBattleManager = _get_battle_manager()
		if battle_manager:
			battle_manager.start_battle(trigger_battle_id)
	queue_free()

func _get_battle_manager() -> TutorialBattleManager:
	var root: Node = get_tree().current_scene
	if root:
		return root.find_child("TutorialBattleManager", true, false) as TutorialBattleManager
	return null
