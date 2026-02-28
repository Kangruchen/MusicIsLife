extends Node2D
class_name Character
## 主角控制器 - 通过 EventBus 信号播放角色动画
## 防御阶段：通过 defense_key_pressed 信号播放格挡/攻击/闪避动画
## 攻击阶段：通过 attack_performed 信号播放轻攻击/重攻击/蓄力/恢复动画

## 角色动画配置资源
@export var anim_config: CharacterAnimConfig = null

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## AnimationPlayer 引用（可选，若场景中存在则自动获取）
var _animation_player: AnimationPlayer = null


func _ready() -> void:
	# 获取 AnimationPlayer（如果存在）
	_animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer

	# 通过 EventBus 连接信号（无需硬编码节点路径）
	EventBus.defense_key_pressed.connect(_on_defense_action)
	EventBus.attack_performed.connect(_on_attack_action)

	# 动画播完后回到 idle
	if animated_sprite:
		animated_sprite.animation_finished.connect(_on_animation_finished)

	print("[Character] 初始化完成 | AnimationPlayer: ", _animation_player != null)


## 防御阶段按键回调
func _on_defense_action(track: Note.NoteType) -> void:
	if not anim_config:
		return
	var anim_name: String = anim_config.get_defense_anim(track)
	_play_anim(anim_name, true)


## 攻击阶段攻击回调
func _on_attack_action(attack_type: int) -> void:
	if not anim_config:
		return
	var anim_name: String = anim_config.get_attack_anim(attack_type)
	_play_anim(anim_name, false)


## 播放指定动画（优先 AnimatedSprite2D，若无则尝试 AnimationPlayer）
## beat_sync: 是否将播放速度同步到一个节拍间隔
func _play_anim(anim_name: String, beat_sync: bool) -> void:
	if anim_name.is_empty():
		return

	# 尝试 AnimatedSprite2D
	if animated_sprite and animated_sprite.sprite_frames \
		and animated_sprite.sprite_frames.has_animation(anim_name):
		if beat_sync:
			_apply_beat_sync_speed(anim_name)
		else:
			animated_sprite.speed_scale = 1.0
		animated_sprite.frame = 0
		animated_sprite.play(anim_name)
		return

	# 回退到 AnimationPlayer
	if _animation_player and _animation_player.has_animation(anim_name):
		if beat_sync and EventBus.beat_interval > 0.0:
			var anim_length: float = _animation_player.get_animation(anim_name).length
			if anim_length > 0.0:
				_animation_player.speed_scale = anim_length / EventBus.beat_interval
			else:
				_animation_player.speed_scale = 1.0
		else:
			_animation_player.speed_scale = 1.0
		_animation_player.play(anim_name)
		return

	push_warning("[Character] 动画 '%s' 在 AnimatedSprite2D 和 AnimationPlayer 中均未找到" % anim_name)


## 将 AnimatedSprite2D 播放速度同步到一个节拍间隔
func _apply_beat_sync_speed(anim_name: String) -> void:
	var bi: float = EventBus.beat_interval
	if bi <= 0.0:
		animated_sprite.speed_scale = 1.0
		return

	var sprite_frames: SpriteFrames = animated_sprite.sprite_frames
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0.0:
		animated_sprite.speed_scale = 1.0
		return

	# 计算原始时长，然后缩放到一个节拍
	var total_duration_weight: float = 0.0
	for i in range(frame_count):
		total_duration_weight += sprite_frames.get_frame_duration(anim_name, i)
	var original_duration: float = total_duration_weight / base_fps
	animated_sprite.speed_scale = clampf(original_duration / bi, 0.1, 10.0)


## 动画播放完毕后恢复 idle
func _on_animation_finished() -> void:
	if not anim_config:
		return
	var idle: String = anim_config.idle_anim
	if animated_sprite.animation != idle and not idle.is_empty():
		animated_sprite.speed_scale = 1.0
		animated_sprite.play(idle)
