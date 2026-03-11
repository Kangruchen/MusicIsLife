extends Node

@onready var dialogue_ui = $DialogueUI

func _ready() -> void:
	# Defer the dialogue start slightly so the rest of the scene can finish loading.
	# Use a short timer (1s) and call the DialogueUI's start_dialogue safely.
	_defer_start()

func _defer_start() -> void:
	# We use create_timer and await its timeout so we don't block other logic.
	await get_tree().create_timer(1.0).timeout

	if not dialogue_ui:
		push_warning("DialogueUI node not found at $DialogueUI; cannot start scene dialogue")
		return

	# Trigger the 'game_start' scene dialogue. This call is non-blocking from the GameManager's
	# perspective; the DialogueUI itself will pause the game when the dialogue runs.
	dialogue_ui.start_dialogue("game_start")

func _process(_delta: float) -> void:
	pass
