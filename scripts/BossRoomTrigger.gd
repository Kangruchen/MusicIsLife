extends Area2D

# Boss room trigger: when the player enters this Area2D, start the boss_fight
# dialogue and disable the area to avoid repeated triggers.

var dialogue_ui: Node = null


func _ready() -> void:
	dialogue_ui = get_node_or_null("/root/DialogueUI")
	if not dialogue_ui:
		push_warning("DialogueUI node was not found; boss room dialogue will not start.")

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if not monitoring:
		return
	if body.name != "Player":
		return
	if not dialogue_ui:
		push_error("DialogueUI node was not found; cannot start boss dialogue.")
		return
	if not dialogue_ui.has_method("start_dialogue"):
		push_error("DialogueUI node does not implement start_dialogue(scene_name).")
		return

	dialogue_ui.start_dialogue("boss_fight")
	monitoring = false
