extends Node2D

@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/main_menu.tscn"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		get_tree().change_scene_to_file(main_menu_scene_path)
