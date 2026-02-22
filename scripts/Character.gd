extends Node2D
## 主角控制器 - 负责根据玩家输入播放角色动画

# attack1 动画帧数（与 SpriteFrames 中定义一致）
const ATTACK1_FRAMES: int = 6
const ATTACK1_DEFAULT_FPS: float = 8.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

var _input_manager: Node = null
var _beat_manager: Node = null


func _ready() -> void:
	_input_manager = get_node_or_null("../InputManager")
	_beat_manager = get_node_or_null("../BeatManager")

	if _input_manager and _input_manager.has_signal("any_key_pressed"):
		_input_manager.any_key_pressed.connect(_on_any_key_pressed)
	else:
		push_warning("Character: 未找到 InputManager 或 any_key_pressed 信号")

	# 动画播完后回到 idle
	animated_sprite.animation_finished.connect(_on_animation_finished)


## 任意轨道按键按下时触发
func _on_any_key_pressed() -> void:
	# 根据当前 BPM 计算使动画恰好播完一拍所需的 speed_scale
	var beat_interval: float = _get_beat_interval()
	if beat_interval > 0.0:
		# speed_scale = 默认总时长 / 目标时长
		var default_duration: float = float(ATTACK1_FRAMES) / ATTACK1_DEFAULT_FPS
		animated_sprite.speed_scale = default_duration / beat_interval
	else:
		animated_sprite.speed_scale = 1.0

	# 无论当前是否正在播放 attack1，都从头重新播放（打断重置）
	animated_sprite.play("attack1")


## 动画播放完毕后恢复 idle
func _on_animation_finished() -> void:
	if animated_sprite.animation == "attack1":
		animated_sprite.play("idle")


## 获取当前节拍间隔（秒）
func _get_beat_interval() -> float:
	if _beat_manager and _beat_manager.get("beat_interval") != null:
		return _beat_manager.beat_interval
	return 0.0
