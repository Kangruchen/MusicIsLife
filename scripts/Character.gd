extends Node2D
## 玩家控制器（阶段状态机 + 动作状态机 + 按动画帧控制判定框）

enum PlayerState {
	DEFENSE,
	ATTACK,
}

enum ActionState {
	IDLE,
	MOVE,
	ATTACK,
}

const ATTACK_TYPE_LIGHT: int = 0
const ATTACK_TYPE_HEAVY: int = 1
const ATTACK_TYPE_HEAL: int = 2
const ATTACK_TYPE_ENHANCE: int = 3

@export var anim_config: CharacterAnimConfig = null

@export_group("Movement")
@export var attack_move_speed: float = 280.0
@export var move_action_left: StringName = &"move_left"
@export var move_action_right: StringName = &"move_right"
@export var move_action_up: StringName = &"move_up"
@export var move_action_down: StringName = &"move_down"
@export var lock_movement_during_attack: bool = true

@export_group("Hitbox Timing")
@export var attack_hitbox_enabled: bool = true
@export_range(0, 60, 1) var light_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var light_hitbox_close_frame: int = 3
@export_range(0, 60, 1) var heavy_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var heavy_hitbox_close_frame: int = 4
@export_range(0, 60, 1) var charged_light_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var charged_light_hitbox_close_frame: int = 3
@export_range(0, 60, 1) var charged_heavy_hitbox_open_frame: int = 1
@export_range(0, 60, 1) var charged_heavy_hitbox_close_frame: int = 4

@export_group("Hitbox Presets")
@export var light_hitbox_preset_name: StringName = &"Light"
@export var heavy_hitbox_preset_name: StringName = &"Heavy"
@export var charged_light_hitbox_preset_name: StringName = &""
@export var charged_heavy_hitbox_preset_name: StringName = &""

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var attack_hitbox_shape: CollisionShape2D = $AttackHitbox/CollisionShape2D
@onready var hitbox_presets_root: Node2D = get_node_or_null("HitboxPresets") as Node2D

var _state: PlayerState = PlayerState.DEFENSE
var _action_state: ActionState = ActionState.IDLE

var _is_next_attack_charged: bool = false
var _is_attack_anim_playing: bool = false
var _facing_sign: float = -1.0
var _prep_movement_enabled: bool = false
var _attack_movement_enabled: bool = true

var _is_attack_hitbox_active: bool = false
var _attack_hitbox_attack_type: int = -1
var _attack_hit_targets: Dictionary = {}

var _current_attack_type: int = -1
var _current_attack_charged: bool = false
var _current_hitbox_open_frame: int = 0
var _current_hitbox_close_frame: int = 0
var _current_hitbox_size: Vector2 = Vector2(120.0, 90.0)
var _current_hitbox_offset: Vector2 = Vector2(90.0, 0.0)

var velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	if not EventBus.defense_key_pressed.is_connected(_on_defense_action):
		EventBus.defense_key_pressed.connect(_on_defense_action)
	if not EventBus.attack_performed.is_connected(_on_attack_action):
		EventBus.attack_performed.connect(_on_attack_action)
	if not EventBus.attack_phase_started.is_connected(_on_attack_phase_started):
		EventBus.attack_phase_started.connect(_on_attack_phase_started)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not EventBus.attack_movement_enabled_changed.is_connected(_on_attack_movement_enabled_changed):
		EventBus.attack_movement_enabled_changed.connect(_on_attack_movement_enabled_changed)

	if attack_hitbox != null and not attack_hitbox.area_entered.is_connected(_on_attack_hitbox_area_entered):
		attack_hitbox.area_entered.connect(_on_attack_hitbox_area_entered)

	if animated_sprite != null and not animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.connect(_on_animation_finished)
	if animated_sprite != null and not animated_sprite.frame_changed.is_connected(_on_animation_frame_changed):
		animated_sprite.frame_changed.connect(_on_animation_frame_changed)

	_set_attack_hitbox_enabled(false)
	_enter_state(_state)


func _physics_process(delta: float) -> void:
	if _state == PlayerState.ATTACK or _prep_movement_enabled:
		_update_attack_movement(delta)


func _on_defense_action(track: Note.NoteType) -> void:
	if _state != PlayerState.DEFENSE:
		return
	if anim_config == null:
		return

	var anim_name: String = anim_config.get_defense_anim(track)
	_play_anim(anim_name, true)


func _on_attack_action(attack_type: int) -> void:
	if _state != PlayerState.ATTACK:
		return

	if attack_type == ATTACK_TYPE_ENHANCE:
		_is_next_attack_charged = true
		return

	var use_charged: bool = _is_next_attack_charged
	if _is_attack_anim_playing:
		_interrupt_attack_animation()

	_start_attack_action(attack_type, use_charged)
	if _attack_type_uses_hitbox(attack_type):
		_is_next_attack_charged = false


func _on_attack_phase_started() -> void:
	_is_next_attack_charged = false
	_prep_movement_enabled = false
	_attack_movement_enabled = true
	_clear_attack_action_runtime()
	_transition_to_state(PlayerState.ATTACK)


func _on_attack_phase_ended() -> void:
	_is_next_attack_charged = false
	_prep_movement_enabled = false
	_attack_movement_enabled = false
	_clear_attack_action_runtime()
	_transition_to_state(PlayerState.DEFENSE)
	_facing_sign = -1.0
	if animated_sprite != null:
		animated_sprite.flip_h = false
	velocity = Vector2.ZERO


func _transition_to_state(next_state: PlayerState) -> void:
	if next_state == _state:
		return

	_exit_state(_state)
	_state = next_state
	_enter_state(_state)


func _enter_state(state: PlayerState) -> void:
	match state:
		PlayerState.DEFENSE:
			_action_state = ActionState.IDLE
			velocity = Vector2.ZERO
			_clear_attack_action_runtime()
			_play_idle()
		PlayerState.ATTACK:
			_action_state = ActionState.IDLE
			velocity = Vector2.ZERO
			_clear_attack_action_runtime()
			_play_idle()


func _exit_state(state: PlayerState) -> void:
	match state:
		PlayerState.ATTACK:
			_clear_attack_action_runtime()
		_:
			pass


func _update_attack_movement(delta: float) -> void:
	if _state == PlayerState.ATTACK and not _attack_movement_enabled:
		velocity = Vector2.ZERO
		_action_state = ActionState.IDLE
		return

	if _is_attack_anim_playing and lock_movement_during_attack:
		velocity = Vector2.ZERO
		_action_state = ActionState.ATTACK
		return

	var input_dir: Vector2 = Input.get_vector(move_action_left, move_action_right, move_action_up, move_action_down)
	velocity = input_dir * maxf(0.0, attack_move_speed)
	global_position += velocity * delta

	if absf(input_dir.x) > 0.001:
		_facing_sign = signf(input_dir.x)
		if animated_sprite != null:
			animated_sprite.flip_h = _facing_sign > 0.0

	if _is_attack_anim_playing:
		_action_state = ActionState.ATTACK
	elif input_dir.length_squared() > 0.0001:
		_action_state = ActionState.MOVE
	else:
		_action_state = ActionState.IDLE


func _start_attack_action(attack_type: int, is_charged: bool) -> void:
	_current_attack_type = attack_type
	_current_attack_charged = is_charged
	_current_hitbox_open_frame = _get_attack_open_frame(attack_type, is_charged)
	_current_hitbox_close_frame = _get_attack_close_frame(attack_type, is_charged)

	_is_attack_anim_playing = true
	_action_state = ActionState.ATTACK

	_set_attack_hitbox_enabled(false)
	_apply_hitbox_preset_for_current_attack()

	if anim_config == null:
		_finish_attack_action()
		return

	var anim_name: String = anim_config.get_attack_anim_with_charge(attack_type, is_charged)
	if not _has_anim(anim_name):
		_finish_attack_action()
		return

	_play_anim(anim_name, false)
	_try_open_hitbox_at_current_frame()


func _finish_attack_action() -> void:
	if not _is_attack_anim_playing:
		return

	_is_attack_anim_playing = false
	_action_state = ActionState.IDLE
	_set_attack_hitbox_enabled(false)
	_play_idle()


func _interrupt_attack_animation() -> void:
	_set_attack_hitbox_enabled(false)
	if animated_sprite != null and animated_sprite.is_playing():
		animated_sprite.stop()
	_is_attack_anim_playing = false


func _apply_hitbox_preset_for_current_attack() -> void:
	var preset_name: StringName = _get_hitbox_preset_name(_current_attack_type, _current_attack_charged)
	var default_offset: Vector2 = _get_default_hitbox_offset_for_current_attack()
	var default_size: Vector2 = _get_default_hitbox_size_for_current_attack()

	if hitbox_presets_root == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var preset_node: Node2D = hitbox_presets_root.get_node_or_null(String(preset_name)) as Node2D
	if preset_node == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var preset_shape_node: CollisionShape2D = preset_node.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if preset_shape_node == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var rect_shape: RectangleShape2D = preset_shape_node.shape as RectangleShape2D
	if rect_shape == null:
		_current_hitbox_offset = default_offset
		_current_hitbox_size = default_size
		return

	var scale_abs: Vector2 = Vector2(absf(preset_shape_node.scale.x), absf(preset_shape_node.scale.y))
	_current_hitbox_offset = preset_node.position + preset_shape_node.position
	_current_hitbox_size = Vector2(
		rect_shape.size.x * maxf(0.001, scale_abs.x),
		rect_shape.size.y * maxf(0.001, scale_abs.y)
	)


func _open_attack_hitbox() -> void:
	if not attack_hitbox_enabled:
		return
	if attack_hitbox == null or attack_hitbox_shape == null:
		return

	var shape: RectangleShape2D = attack_hitbox_shape.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		attack_hitbox_shape.shape = shape

	shape.size = _current_hitbox_size
	attack_hitbox.position = Vector2(_get_attack_forward_sign() * _current_hitbox_offset.x, _current_hitbox_offset.y)
	_attack_hitbox_attack_type = _current_attack_type
	_attack_hit_targets.clear()
	_set_attack_hitbox_enabled(true)
	_process_attack_overlap_once()


func _close_attack_hitbox() -> void:
	_set_attack_hitbox_enabled(false)


func _process_attack_overlap_once() -> void:
	if attack_hitbox == null or not attack_hitbox.monitoring:
		return

	for area in attack_hitbox.get_overlapping_areas():
		var other_area: Area2D = area as Area2D
		if other_area == null:
			continue
		_process_single_attack_overlap(other_area)


func _on_attack_hitbox_area_entered(area: Area2D) -> void:
	_process_single_attack_overlap(area)


func _process_single_attack_overlap(area: Area2D) -> void:
	if _state != PlayerState.ATTACK:
		return
	if not _is_attack_hitbox_active:
		return
	if area == null or not is_instance_valid(area):
		return
	if not area.is_in_group(&"enemy_hurtbox"):
		return

	var area_id: int = area.get_instance_id()
	if _attack_hit_targets.has(area_id):
		return
	_attack_hit_targets[area_id] = true

	var target: Node = area.get_parent()
	EventBus.attack_hit_confirmed.emit(_attack_hitbox_attack_type, target)


func _get_attack_open_frame(attack_type: int, is_charged: bool) -> int:
	if attack_type == ATTACK_TYPE_LIGHT:
		return charged_light_hitbox_open_frame if is_charged else light_hitbox_open_frame
	if attack_type == ATTACK_TYPE_HEAVY:
		return charged_heavy_hitbox_open_frame if is_charged else heavy_hitbox_open_frame
	return 999


func _get_attack_close_frame(attack_type: int, is_charged: bool) -> int:
	if attack_type == ATTACK_TYPE_LIGHT:
		return charged_light_hitbox_close_frame if is_charged else light_hitbox_close_frame
	if attack_type == ATTACK_TYPE_HEAVY:
		return charged_heavy_hitbox_close_frame if is_charged else heavy_hitbox_close_frame
	return 1000


func _get_hitbox_preset_name(attack_type: int, is_charged: bool) -> StringName:
	if attack_type == ATTACK_TYPE_LIGHT:
		if is_charged and not charged_light_hitbox_preset_name.is_empty():
			return charged_light_hitbox_preset_name
		return light_hitbox_preset_name
	if attack_type == ATTACK_TYPE_HEAVY:
		if is_charged and not charged_heavy_hitbox_preset_name.is_empty():
			return charged_heavy_hitbox_preset_name
		return heavy_hitbox_preset_name
	return light_hitbox_preset_name


func _get_default_hitbox_offset_for_current_attack() -> Vector2:
	if _current_attack_type == ATTACK_TYPE_HEAVY:
		return Vector2(105.0, 0.0)
	return Vector2(90.0, 0.0)


func _get_default_hitbox_size_for_current_attack() -> Vector2:
	if _current_attack_type == ATTACK_TYPE_HEAVY:
		return Vector2(180.0, 120.0)
	return Vector2(120.0, 90.0)


func _get_attack_forward_sign() -> float:
	var closest_sign: float = 0.0
	var closest_distance: float = INF
	for node in get_tree().get_nodes_in_group(&"enemy_hurtbox"):
		var enemy_area: Area2D = node as Area2D
		if enemy_area == null:
			continue
		var dx: float = enemy_area.global_position.x - global_position.x
		var dist: float = absf(dx)
		if dist < closest_distance and dist > 0.001:
			closest_distance = dist
			closest_sign = signf(dx)

	if closest_sign != 0.0:
		_facing_sign = closest_sign
		if animated_sprite != null:
			animated_sprite.flip_h = _facing_sign > 0.0
		return closest_sign

	return _facing_sign if _facing_sign != 0.0 else -1.0


func _set_attack_hitbox_enabled(enabled: bool) -> void:
	if attack_hitbox == null:
		return
	attack_hitbox.monitoring = enabled
	attack_hitbox.monitorable = enabled
	if attack_hitbox_shape != null:
		attack_hitbox_shape.disabled = not enabled
	_is_attack_hitbox_active = enabled
	if not enabled:
		_attack_hitbox_attack_type = -1
		_attack_hit_targets.clear()


func _clear_attack_action_runtime() -> void:
	_is_attack_anim_playing = false
	_current_attack_type = -1
	_current_attack_charged = false
	_current_hitbox_open_frame = 0
	_current_hitbox_close_frame = 0
	_set_attack_hitbox_enabled(false)


func _play_idle() -> void:
	if anim_config == null:
		return
	if anim_config.idle_anim.is_empty():
		return
	_play_anim(anim_config.idle_anim, false)


func _has_anim(anim_name: String) -> bool:
	if anim_name.is_empty():
		return false
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return false
	return animated_sprite.sprite_frames.has_animation(anim_name)


func _play_anim(anim_name: String, beat_sync: bool) -> void:
	if anim_name.is_empty():
		return
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		push_warning("[Character] AnimatedSprite2D 缺少动画: %s" % anim_name)
		return

	if beat_sync:
		_apply_beat_sync_speed(anim_name)
	else:
		animated_sprite.speed_scale = 1.0

	animated_sprite.frame = 0
	animated_sprite.play(anim_name)


func _apply_beat_sync_speed(anim_name: String) -> void:
	if animated_sprite == null or animated_sprite.sprite_frames == null:
		return

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

	var total_duration_weight: float = 0.0
	for i in range(frame_count):
		total_duration_weight += sprite_frames.get_frame_duration(anim_name, i)

	var original_duration: float = total_duration_weight / base_fps
	animated_sprite.speed_scale = clampf(original_duration / bi, 0.1, 10.0)


func _on_animation_finished() -> void:
	if _state == PlayerState.DEFENSE:
		_play_idle()
		return

	if _state == PlayerState.ATTACK and _is_attack_anim_playing:
		_finish_attack_action()


func _on_animation_frame_changed() -> void:
	if not _is_attack_anim_playing:
		return
	if not _attack_type_uses_hitbox(_current_attack_type):
		return
	if animated_sprite == null:
		return

	var frame: int = animated_sprite.frame
	var open_frame: int = _current_hitbox_open_frame
	var close_frame: int = _current_hitbox_close_frame

	if close_frame < open_frame:
		close_frame = open_frame

	if frame == open_frame and not _is_attack_hitbox_active:
		_open_attack_hitbox()
	elif frame >= close_frame and _is_attack_hitbox_active:
		_close_attack_hitbox()


func _try_open_hitbox_at_current_frame() -> void:
	_on_animation_frame_changed()


func _attack_type_uses_hitbox(attack_type: int) -> bool:
	return attack_type == ATTACK_TYPE_LIGHT or attack_type == ATTACK_TYPE_HEAVY


func _on_attack_movement_enabled_changed(enabled: bool) -> void:
	if _state == PlayerState.ATTACK:
		_attack_movement_enabled = enabled
		if not enabled:
			velocity = Vector2.ZERO
		return

	_prep_movement_enabled = enabled
	if not enabled:
		velocity = Vector2.ZERO
