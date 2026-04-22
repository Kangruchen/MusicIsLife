extends Control
class_name MainMenu

# === 节点引用 ===
@onready var new_game_btn: Button = $CenterContainer/MenuVBox/NewGameBtn
@onready var guide_btn: Button = $CenterContainer/MenuVBox/GuideBtn
@onready var settings_btn: Button = $CenterContainer/MenuVBox/SettingsBtn
@onready var quit_btn: Button = $CenterContainer/MenuVBox/QuitBtn

# === 导出变量 ===
@export_file("*.tscn") var game_scene_path: String = "res://scenes/Main.tscn"
@export_file("*.tscn") var guide_scene_path: String = "res://scenes/guide.tscn"

func _ready() -> void:
    # 连接所有按钮的点击信号
    new_game_btn.pressed.connect(_on_new_game_pressed)
    guide_btn.pressed.connect(_on_guide_pressed)
    settings_btn.pressed.connect(_on_settings_pressed)
    quit_btn.pressed.connect(_on_quit_pressed)

# === 信号响应 ===

func _on_new_game_pressed() -> void:
    if not game_scene_path.is_empty():
        get_tree().change_scene_to_file(game_scene_path)

func _on_guide_pressed() -> void:
    if not guide_scene_path.is_empty():
        get_tree().change_scene_to_file(guide_scene_path)

func _on_settings_pressed() -> void:
    print("Settings Menu - To be implemented")

func _on_quit_pressed() -> void:
    get_tree().quit()