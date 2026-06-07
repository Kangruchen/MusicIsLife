extends Node2D

@export_file("*.tscn") var main_menu_scene_path: String = "res://scenes/main_menu.tscn"
@export_file("*.tscn") var next_scene_path: String = "res://scenes/Main.tscn"

@export_group("Elevator Areas")
@export var player: CharacterBody2D
@export var door_proximity_area: Area2D    
@export var level_end_area: Area2D         

@export_group("Elevator Visuals")
@export var left_door: Sprite2D
@export var right_door: Sprite2D
@export var left_door_open_dist: float = 64.0   # 左门需要拉开的距离
@export var right_door_open_dist: float = 64.0  # 右门需要拉开的距离
@export var mask_left_bound: Marker2D           # 绑定刚刚创建的左门框标记点
@export var mask_right_bound: Marker2D          # 绑定刚刚创建的右门框标记点
@export var player_idle_anim: String = "idle"   # 这里请严格填写你的【待机站立动画】名称（注意大小写！）

var _is_ending_tutorial: bool = false
var _door_tween: Tween
var _left_door_closed_x: float = 0.0
var _right_door_closed_x: float = 0.0

func _ready() -> void:
    if left_door and right_door:
        _left_door_closed_x = left_door.position.x
        _right_door_closed_x = right_door.position.x
        
        # 自己测量门多宽，就精准拉开多远，保证绝不露馅
        left_door_open_dist = left_door.get_rect().size.x * abs(left_door.scale.x)
        right_door_open_dist = right_door.get_rect().size.x * abs(right_door.scale.x)
        
        # 初始化基于标记点的绝对遮罩
        _setup_elevator_mask()
        
    if door_proximity_area:
        door_proximity_area.body_entered.connect(_on_door_proximity_entered)
        door_proximity_area.body_exited.connect(_on_door_proximity_exited)
        
    if level_end_area:
        level_end_area.body_entered.connect(_on_level_end_entered)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("menu"):
        get_tree().change_scene_to_file(main_menu_scene_path)

# 核心修复1：使用场景中的Marker2D作为不可逾越的绝对边界
func _setup_elevator_mask() -> void:
    if not mask_left_bound or not mask_right_bound:
        push_warning("未绑定门框边界 Marker2D，遮罩可能无法正确生效！")
        return
        
    var clip_left: float = mask_left_bound.global_position.x
    var clip_right: float = mask_right_bound.global_position.x
    
    var shader: Shader = Shader.new()
    shader.code = """
    shader_type canvas_item;
    varying float world_x;
    uniform float clip_left;
    uniform float clip_right;

    void vertex() {
        // 获取像素点的全局绝对水平坐标
        world_x = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).x;
    }

    void fragment() {
        // 超出两个 Marker2D 构成的门框范围，强制切除
        if (world_x < clip_left || world_x > clip_right) {
            COLOR.a = 0.0;
        }
    }
    """
    
    var mat: ShaderMaterial = ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("clip_left", clip_left)
    mat.set_shader_parameter("clip_right", clip_right)
    
    left_door.material = mat
    right_door.material = mat

func _on_door_proximity_entered(body: Node2D) -> void:
    if body.name == "Player" and not _is_ending_tutorial:
        _open_doors()

func _on_door_proximity_exited(body: Node2D) -> void:
    if body.name == "Player" and not _is_ending_tutorial:
        _close_doors()

func _on_level_end_entered(body: Node2D) -> void:
    if body.name == "Player" and not _is_ending_tutorial:
        _play_outro_cutscene()

func _open_doors() -> void:
    if not left_door or not right_door:
        return
    if _door_tween and _door_tween.is_running():
        _door_tween.kill()
        
    _door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _door_tween.tween_property(left_door, "position:x", _left_door_closed_x - left_door_open_dist, 0.5)
    _door_tween.tween_property(right_door, "position:x", _right_door_closed_x + right_door_open_dist, 0.5)

func _close_doors() -> void:
    if not left_door or not right_door:
        return
    if _door_tween and _door_tween.is_running():
        _door_tween.kill()
        
    _door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    _door_tween.tween_property(left_door, "position:x", _left_door_closed_x, 0.5)
    _door_tween.tween_property(right_door, "position:x", _right_door_closed_x, 0.5)

# --- 最终离场序列 ---
func _play_outro_cutscene() -> void:
    _is_ending_tutorial = true
    
    if player:
        # 彻底切断玩家的速度
        player.velocity = Vector2.ZERO
        # 执行极限状态覆写（无视玩家按键状态，强行站立）
        _enforce_absolute_idle(player)
        _clear_player_trails(player)
        
    if left_door and right_door:
        left_door.z_index = 10
        right_door.z_index = 10
        
    _close_doors()
    
    if _door_tween:
        await _door_tween.finished
        
    await get_tree().create_timer(1.5).timeout
    get_tree().change_scene_to_file(next_scene_path)

# 核心修复2：暴力接管玩家动画节点，强制定格在待机第一帧
func _enforce_absolute_idle(node: Node) -> void:
    # 封死所有代码的执行，防止玩家的 _process 代码把动作改回去
    node.set_physics_process(false)
    node.set_process(false)
    
    if node is AnimatedSprite2D:
        node.play(player_idle_anim)
        # 强行刷新回待机的第 0 帧
        node.set_frame_and_progress(0, 0.0)
        node.pause() # 时间停止
    elif node is AnimationPlayer:
        if node.has_animation(player_idle_anim):
            node.play(player_idle_anim)
            node.seek(0.0, true)
            node.pause()
    elif node.has_method("set_active"):
        # 强制关闭高级状态机 AnimationTree
        node.set("active", false) 

    # 持续向更深层挖掘动画节点
    for child: Node in node.get_children():
        _enforce_absolute_idle(child)

func _clear_player_trails(node: Node) -> void:
    for child: Node in node.get_children():
        if child is GPUParticles2D or child is CPUParticles2D:
            child.emitting = false
            child.visible = false
        elif child.get_class() == "Trail2D": 
            if child.has_method("clear_points"):
                child.call("clear_points")
            child.visible = false
            
        _clear_player_trails(child)
