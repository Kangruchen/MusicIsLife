extends Node2D

@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/main_menu.tscn"

@export_group("Elevator Outro")
@export var player: CharacterBody2D
@export var walk_in_target: Marker2D
@export var elevator_interact_area: Area2D
@export var left_door: Sprite2D
@export var right_door: Sprite2D
@export var interact_prompt: CanvasItem
@export var door_open_distance: float = 64.0

var _can_use_elevator: bool = false
var _is_ending_tutorial: bool = false


func _ready() -> void:
	if interact_prompt:
		_update_interact_prompt()
		interact_prompt.visible = false

	if elevator_interact_area:
		elevator_interact_area.body_entered.connect(_on_elevator_area_entered)
		elevator_interact_area.body_exited.connect(_on_elevator_area_exited)

	var gamepad_manager: Node = get_node_or_null("/root/GamepadManager")
	if gamepad_manager != null and gamepad_manager.has_signal("input_scheme_changed"):
		gamepad_manager.connect("input_scheme_changed", func(_is_gamepad: bool) -> void:
			_update_interact_prompt()
		)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_tree().change_scene_to_file(main_menu_scene_path)


func _unhandled_input(event: InputEvent) -> void:
	if _can_use_elevator and not _is_ending_tutorial and event.is_action_pressed("interact"):
		_play_outro_cutscene()
		get_viewport().set_input_as_handled()


func _on_elevator_area_entered(body: Node2D) -> void:
	if body.name != "Player":
		return
	_can_use_elevator = true
	if interact_prompt:
		_update_interact_prompt()
		interact_prompt.visible = true


func _on_elevator_area_exited(body: Node2D) -> void:
	if body.name != "Player":
		return
	_can_use_elevator = false
	if interact_prompt:
		interact_prompt.visible = false


func _update_interact_prompt() -> void:
	if interact_prompt == null:
		return
	var prompt_text: String = GameConstants.get_action_key_label("interact", "E")
	if interact_prompt is Label:
		(interact_prompt as Label).text = prompt_text
	elif interact_prompt is RichTextLabel:
		(interact_prompt as RichTextLabel).text = prompt_text


func _play_outro_cutscene() -> void:
	if not player or not walk_in_target or not left_door or not right_door:
		push_warning("Tutorial elevator outro is missing required nodes.")
		return

	_is_ending_tutorial = true
	_can_use_elevator = false

	if interact_prompt:
		interact_prompt.visible = false

	player.set_physics_process(false)

	var open_tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	open_tween.tween_property(left_door, "position:x", left_door.position.x - door_open_distance, 0.5)
	open_tween.tween_property(right_door, "position:x", right_door.position.x + door_open_distance, 0.5)
	await open_tween.finished

	var walk_tween: Tween = create_tween()
	walk_tween.tween_property(player, "global_position:x", walk_in_target.global_position.x, 1.0)
	await walk_tween.finished

	var close_tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	close_tween.tween_property(left_door, "position:x", left_door.position.x + door_open_distance, 0.5)
	close_tween.tween_property(right_door, "position:x", right_door.position.x - door_open_distance, 0.5)
	await close_tween.finished

	get_tree().change_scene_to_file(main_menu_scene_path)
