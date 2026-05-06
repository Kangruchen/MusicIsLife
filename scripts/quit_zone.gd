extends Area2D
## 退出区域 - 玩家进入时返回主菜单

@export_file("*.tscn") var main_menu_scene: String = "res://scenes/main_menu.tscn"

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.name == "Player":
		get_tree().change_scene_to_file(main_menu_scene)
