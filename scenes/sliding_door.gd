@tool
extends Node2D
class_name SlidingDoor

## 动画持续时间
@export var animation_duration: float = 0.4

## 自定义门板贴图
@export var custom_panel_texture: Texture2D:
    set(value):
        custom_panel_texture = value
        if is_node_ready():
            _update_texture()

@onready var door_panel: Sprite2D = $DoorPanel
@onready var proximity_area: Area2D = $ProximityArea

var _tween: Tween
var _closed_y: float = 0.0

func _ready() -> void:
    _update_texture()
    
    if Engine.is_editor_hint():
        return
        
    if door_panel:
        _closed_y = door_panel.position.y
        # 为门板应用世界空间坐标遮罩
        _setup_world_mask_shader()
        
    proximity_area.body_entered.connect(_on_proximity_area_body_entered)
    proximity_area.body_exited.connect(_on_proximity_area_body_exited)

func _update_texture() -> void:
    var panel: Sprite2D = get_node_or_null("DoorPanel")
    if panel and custom_panel_texture:
        panel.texture = custom_panel_texture
        # 强制关闭可能残留的区域裁剪
        panel.region_enabled = false

# ✨ 第一性原理核心：根据门板开始所在的绝对位置，建立一道“不可逾越的世界光幕”
func _setup_world_mask_shader() -> void:
    var rect: Rect2 = door_panel.get_rect()
    var top_local_y: float = rect.position.y
    
    # 计算出门的顶部边缘在整个游戏世界（屏幕）里的绝对坐标 Y 值
    var ceiling_world_y: float = (door_panel.get_global_transform() * Vector2(0.0, top_local_y)).y
    
    var shader = Shader.new()
    shader.code = """
    shader_type canvas_item;
    varying float world_y;
    uniform float ceiling_y_mask;

    void vertex() {
        world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
    }

    void fragment() {
        if (world_y < ceiling_y_mask) {
            COLOR.a = 0.0; // 让你彻底消失！
        }
    }
    """
    var mat = ShaderMaterial.new()
    mat.shader = shader
    mat.set_shader_parameter("ceiling_y_mask", ceiling_world_y)
    door_panel.material = mat

func _on_proximity_area_body_entered(body: Node2D) -> void:
    if body.name == "Player":
        _open_door()

func _on_proximity_area_body_exited(body: Node2D) -> void:
    if body.name == "Player":
        _close_door()

func _open_door() -> void:
    if _tween and _tween.is_running():
        _tween.kill()

    # 动态获取当前特定门板的真实完整高度
    var full_height: float = 0.0
    if door_panel and door_panel.texture:
        full_height = door_panel.texture.get_height() * door_panel.scale.y

    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    # 将移动距离精确设置为门的总高度，确保 100% 越过绝对遮罩，完全消失不留尾巴
    _tween.tween_property(door_panel, "position:y", _closed_y - full_height, animation_duration)

func _close_door() -> void:
    if _tween and _tween.is_running():
        _tween.kill()
        
    _tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    _tween.tween_property(door_panel, "position:y", _closed_y, animation_duration)