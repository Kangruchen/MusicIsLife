extends Node2D

@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/main_menu.tscn"

@export_group("Elevator Outro")
@export var player: CharacterBody2D
@export var walk_in_target: Marker2D       # 放在电梯内部的目标点 Marker2D
@export var elevator_interact_area: Area2D # 电梯门口用于感应交互的 Area2D
@export var left_door: Sprite2D            # 左侧门 Sprite2D
@export var right_door: Sprite2D           # 右侧门 Sprite2D
@export var interact_prompt: CanvasItem       # 绑定场景中的 "E" 按键提示节点 (Sprite 或 Label)
@export var door_open_distance: float = 64.0

var _can_use_elevator: bool = false
var _is_ending_tutorial: bool = false

func _ready() -> void:
    # 确保提示按钮初始为隐藏状态
    if interact_prompt:
        interact_prompt.visible = false
        
    # 建立电梯互动区的检测连接
    if elevator_interact_area:
        elevator_interact_area.body_entered.connect(_on_elevator_area_entered)
        elevator_interact_area.body_exited.connect(_on_elevator_area_exited)

# 基础菜单键
func _input(event: InputEvent) -> void:
    if event.is_action_pressed("menu"):
        get_tree().change_scene_to_file(main_menu_scene_path)

# 电梯交互判定
func _unhandled_input(event: InputEvent) -> void:
    # 确保你在“项目设置 -> 输入映射”里设置了 "interact" 动作键
    if _can_use_elevator and not _is_ending_tutorial and event.is_action_pressed("interact"):
        _play_outro_cutscene()
        get_viewport().set_input_as_handled()

# 玩家进入交互区，显示按键提示
func _on_elevator_area_entered(body: Node2D) -> void:
    if body.name == "Player":
        _can_use_elevator = true
        if interact_prompt:
            interact_prompt.visible = true

# 玩家离开交互区，隐藏按键提示
func _on_elevator_area_exited(body: Node2D) -> void:
    if body.name == "Player":
        _can_use_elevator = false
        if interact_prompt:
            interact_prompt.visible = false

# --- 结尾电梯离场动画序列 ---
func _play_outro_cutscene() -> void:
    if not player or not walk_in_target or not left_door or not right_door:
        push_warning("电梯离场所需的节点未完全绑定在检查器中！")
        return

    _is_ending_tutorial = true
    _can_use_elevator = false
    
    # 动画开始，立刻隐藏按键提示
    if interact_prompt:
        interact_prompt.visible = false
    
    # 1. 禁用玩家物理控制
    player.set_physics_process(false)
    
    # 2. 开门动画
    var open_tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    open_tween.tween_property(left_door, "position:x", left_door.position.x - door_open_distance, 0.5)
    open_tween.tween_property(right_door, "position:x", right_door.position.x + door_open_distance, 0.5)
    await open_tween.finished
    
    # 3. 玩家平滑走向电梯内部
    var walk_tween: Tween = create_tween()
    walk_tween.tween_property(player, "global_position:x", walk_in_target.global_position.x, 1.0)
    await walk_tween.finished
    
    # 4. 关门动画
    var close_tween: Tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    # 关门就是往反方向回退对应距离
    close_tween.tween_property(left_door, "position:x", left_door.position.x + door_open_distance, 0.5)
    close_tween.tween_property(right_door, "position:x", right_door.position.x - door_open_distance, 0.5)
    await close_tween.finished
    
    # 5. 等电梯门完全关上后，最后跳转回主菜单场景
    get_tree().change_scene_to_file(main_menu_scene_path)