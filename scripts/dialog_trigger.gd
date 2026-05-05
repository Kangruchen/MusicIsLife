extends Area2D
class_name DialogueTrigger

@export var dialogue_lines: Array[DialogueLine]
@export var dialogue_ui: DialogueUI 

# === 新增功能：手动触发控制 ===
@export var require_input: bool = false # 是否需要按键才能触发
@export var prompt_node: CanvasItem = null  # 改用 CanvasItem，以同时兼容 Label 和 Sprite2D

var _player_in_area: bool = false

func _ready() -> void:
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited) # 新增离开区域的监听
    
    # 游戏开始时默认隐藏提示
    if prompt_node:
        prompt_node.hide()

func _on_body_entered(body: Node2D) -> void:
    if body.name == "Player":
        if require_input:
            _player_in_area = true
            if prompt_node:
                prompt_node.show() # 显示按键提示
        else:
            _try_trigger_dialogue()

func _on_body_exited(body: Node2D) -> void:
    if body.name == "Player":
        _player_in_area = false
        if prompt_node:
            prompt_node.hide() # 离开区域时隐藏提示

# 监听按键输入
func _unhandled_input(event: InputEvent) -> void:
    if _player_in_area and require_input:
        # 当玩家在区域内，且按下了键盘 Y 键
        if event is InputEventKey and event.keycode == KEY_Y and event.pressed:
            _try_trigger_dialogue()
            get_viewport().set_input_as_handled() # 拦截输入，防止传给场景其他节点

func _try_trigger_dialogue() -> void:
    if dialogue_ui == null or dialogue_ui.is_busy or dialogue_lines.is_empty():
        return
        
    if prompt_node:
        prompt_node.hide()
        
    dialogue_ui.play_sequence(dialogue_lines)
    queue_free() # 触发完毕后销毁触发器