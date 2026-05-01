extends Control
class_name GuideMenu

# 1. 获取你在场景树中手动摆放的返回按钮
# 注意：如果按钮在某个容器里，路径可能是 $MarginContainer/BackButton
@onready var back_btn: Button = $BackButton

func _ready() -> void:
    # 2. 绑定点击信号
    if back_btn:
        back_btn.pressed.connect(_on_back_pressed)
    else:
        push_error("Guide 场景中没有找到名为 BackButton 的节点！请检查路径。")

func _on_back_pressed() -> void:
    print("[Guide] 返回主菜单...")
    # 核心跳转：切换回 main_menu.tscn 场景
    get_tree().change_scene_to_file("res://scenes/main_menu.tscn")