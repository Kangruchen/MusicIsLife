extends Node2D
## 主角控制器 - 通过 EventBus 信号播放角色动画
## 防御阶段：通过 defense_key_pressed 信号播放格挡/攻击/闪避动画
## 攻击阶段：通过 attack_performed 信号播放轻攻击/重攻击/蓄力/恢复动画

## 角色动画配置资源
@export var anim_config: CharacterAnimConfig = null

@export_group("Attack Return")
@export var attack_return_trigger_count: int = 0
@export var attack_return_duration_beats: int = 1
@export var enable_attack_return_afterimage: bool = true
@export_range(0.01, 0.2, 0.01) var attack_return_afterimage_interval: float = 0.06
@export_range(0.05, 0.8, 0.01) var attack_return_afterimage_lifetime: float = 0.2
@export_range(0.05, 1.0, 0.01) var attack_return_afterimage_alpha: float = 0.55
@export var attack_return_afterimage_color: Color = Color(0.65, 0.95, 1.0, 1.0)

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

## AnimationPlayer 引用（可选，若场景中存在则自动获取）
var _animation_player: AnimationPlayer = null
var _spawn_position: Vector2 = Vector2.ZERO
var _attack_return_tween: Tween = null
var _attack_return_afterimage_token: int = 0
var _is_next_attack_charged: bool = false

const ATTACK_RETURN_AFTERIMAGE_GROUP: StringName = &"player_attack_return_afterimage"


func _ready() -> void:
	_spawn_position = global_position

	# 获取 AnimationPlayer（如果存在）
	_animation_player = get_node_or_null("AnimationPlayer") as AnimationPlayer

	# 通过 EventBus 连接信号（无需硬编码节点路径）
	EventBus.defense_key_pressed.connect(_on_defense_action)
	EventBus.attack_performed.connect(_on_attack_action)
	EventBus.show_return_countdown_requested.connect(_on_show_return_countdown_requested)
	EventBus.attack_phase_started.connect(_on_attack_phase_started)
	EventBus.attack_phase_ended.connect(_on_attack_phase_ended)

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
	# 蓄力（ENHANCE）只作为状态标记，不播放角色攻击动画。
	if attack_type == 3:
		_is_next_attack_charged = true
		return

	var anim_name: String = anim_config.get_attack_anim_with_charge(attack_type, _is_next_attack_charged)
	if attack_type == 0 or attack_type == 1:
		_is_next_attack_charged = false
	_play_anim(anim_name, false)


func _on_show_return_countdown_requested(count: int) -> void:
	if count != attack_return_trigger_count:
		return
	_start_attack_return_transition()


func _on_attack_phase_started() -> void:
	_is_next_attack_charged = false
	_stop_attack_return_transition()


func _on_attack_phase_ended() -> void:
	_stop_attack_return_afterimage()


func _start_attack_return_transition() -> void:
	_stop_attack_return_transition()

	var bi: float = EventBus.beat_interval
	if bi <= 0.0:
		bi = 0.5
	var duration: float = float(maxi(1, attack_return_duration_beats)) * bi

	if global_position.distance_to(_spawn_position) <= 0.001:
		return

	_start_attack_return_afterimage(duration)
	_attack_return_tween = create_tween()
	_attack_return_tween.tween_property(self, "global_position", _spawn_position, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_attack_return_tween.tween_callback(func() -> void:
		_stop_attack_return_afterimage()
	)


func _stop_attack_return_transition() -> void:
	if _attack_return_tween != null:
		_attack_return_tween.kill()
		_attack_return_tween = null
	_stop_attack_return_afterimage()


func _start_attack_return_afterimage(duration: float) -> void:
	if not enable_attack_return_afterimage:
		return
	_attack_return_afterimage_token += 1
	var token: int = _attack_return_afterimage_token
	var end_time: float = _get_now_seconds() + maxf(0.01, duration)
	_emit_attack_return_afterimage_loop(token, end_time)


func _emit_attack_return_afterimage_loop(token: int, end_time: float) -> void:
	if token != _attack_return_afterimage_token:
		return
	if _get_now_seconds() > end_time:
		return

	_spawn_attack_return_afterimage()
	var interval: float = maxf(0.01, attack_return_afterimage_interval)
	get_tree().create_timer(interval).timeout.connect(func() -> void:
		_emit_attack_return_afterimage_loop(token, end_time)
	)


func _spawn_attack_return_afterimage() -> void:
	if animated_sprite == null:
		return
	if animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(animated_sprite.animation):
		return

	var frame_texture: Texture2D = animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	if frame_texture == null:
		return

	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = frame_texture
	ghost.centered = animated_sprite.centered
	ghost.offset = animated_sprite.offset
	ghost.flip_h = animated_sprite.flip_h
	ghost.flip_v = animated_sprite.flip_v
	ghost.global_transform = animated_sprite.global_transform
	ghost.add_to_group(ATTACK_RETURN_AFTERIMAGE_GROUP)

	var color: Color = attack_return_afterimage_color
	color.a = attack_return_afterimage_alpha
	ghost.modulate = color

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	scene_root.add_child(ghost)

	var life: float = maxf(0.05, attack_return_afterimage_lifetime)
	var fade_tween: Tween = ghost.create_tween()
	fade_tween.tween_property(ghost, "modulate:a", 0.0, life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tween.tween_callback(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free()
	)


func _stop_attack_return_afterimage() -> void:
	_attack_return_afterimage_token += 1
	for node in get_tree().get_nodes_in_group(ATTACK_RETURN_AFTERIMAGE_GROUP):
		var ghost_node: Node = node as Node
		if ghost_node != null and is_instance_valid(ghost_node):
			ghost_node.queue_free()


func _get_now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


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
