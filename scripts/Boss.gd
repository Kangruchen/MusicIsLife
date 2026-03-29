extends Node2D
## Boss 状态机控制器
## 提供可扩展状态流转，并支持初始测试：在指定范围内持续随机移动。

enum BossState {
	IDLE,
	RANDOM_MOVE,
	BROKEN,
	PRE_MISSILE_RETURN,
	PRE_CHARGE_MOVE,
	CHARGE,
	MISSILE_ATTACK,
	ATTACK,
	STUNNED,
	DEAD,
}

@export_group("State Machine")
@export var initial_state: BossState = BossState.RANDOM_MOVE
@export var debug_print_state_changes: bool = false

@export_group("Random Move Test")
@export var move_speed: float = 120.0
@export var max_move_left: float = 600.0
@export var max_move_right: float = 600.0
@export var max_move_up: float = 350.0
@export var max_move_down: float = 350.0
@export var move_pick_min_distance: float = 80.0  # 基于当前坐标的最小选点距离
@export var move_pick_max_distance: float = 650.0  # 基于当前坐标的最大选点距离
@export var target_reach_distance: float = 10.0
@export var idle_between_moves_range: Vector2 = Vector2(0.15, 0.55)

@export_group("Aim")
@export var enable_charge_auto_aim: bool = true
@export_node_path("Node2D") var charge_node_path: NodePath = NodePath("Charge")
@export_node_path("AnimatedSprite2D") var charge_anim_path: NodePath = NodePath("Charge/ChargeAnim")
@export_node_path("Node2D") var target_character_path: NodePath = NodePath("../Character")
@export_node_path("Node2D") var player_node_path: NodePath = NodePath("../Character")
@export_node_path("Node2D") var boss_fall_target_path: NodePath = NodePath("../PositionNodes/BossFall")
@export_node_path("Node2D") var player_dash_target_path: NodePath = NodePath("../PositionNodes/PlayerDash")
@export var charge_rotation_offset_degrees: float = 0.0

@export_group("Broken Transition")
@export var broken_transition_beats: int = 4
@export var broken_fall_target_y: float = 131.0
@export var broken_shake_offset_x: float = 14.0
@export var broken_right_tilt_degrees: float = 10.0
@export var return_upright_rotation_degrees: float = 0.0
@export var broken_player_dash_offset_x: float = 50.0
@export var enable_player_dash_afterimage: bool = true
@export_range(0.01, 0.2, 0.01) var player_dash_afterimage_interval: float = 0.06
@export_range(0.05, 0.8, 0.01) var player_dash_afterimage_lifetime: float = 0.2
@export_range(0.05, 1.0, 0.01) var player_dash_afterimage_alpha: float = 0.55
@export var player_dash_afterimage_color: Color = Color(0.65, 0.95, 1.0, 1.0)

@export_group("Charge State")
@export var charge_duration_beats: int = 3
@export var charge_animation_name: StringName = &"charge"
@export var track_animation_config: TrackAnimationConfig = null
@export var pre_charge_distance_from_player: float = 150.0
@export var pre_charge_pick_attempts: int = 32

@export_group("Missile Attack State")
@export var missile_scene: PackedScene = preload("res://scenes/missile.tscn")
@export_node_path("Node2D") var missile_left_path: NodePath = NodePath("MissileLeft")
@export_node_path("Node2D") var missile_right_path: NodePath = NodePath("MissileRight")
@export var missile_total_beats: int = 3
@export var missile_phase1_beats: int = 1
@export var missile_phase2_beats: int = 2
@export var missile_outward_distance: float = 1200.0

@export_group("Animation")
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export_node_path("AnimatedSprite2D") var animated_sprite_path: NodePath
@export var idle_animation: StringName = &"idle"
@export var move_animation: StringName = &"move"
@export var attack_animation: StringName = &"attack"
@export var stunned_animation: StringName = &"stunned"
@export var broken_animation: StringName = &"stunned"
@export var dead_animation: StringName = &"dead"

@export_group("Attack Hit Flash")
@export_node_path("CanvasItem") var middle_body_visual_path: NodePath = NodePath("MiddlePad")
@export_node_path("CanvasItem") var left_missile_visual_path: NodePath = NodePath("LeftMissile")
@export_node_path("CanvasItem") var right_missile_visual_path: NodePath = NodePath("RightMissile")
@export_range(0.1, 8.0, 0.1) var attack_hint_flash_speed: float = 2.6
@export_range(0.05, 1.5, 0.01) var attack_hint_flash_strength: float = 0.9
@export_range(0.03, 0.5, 0.01) var hit_red_flash_duration: float = 0.14

var current_state: BossState = BossState.IDLE

# 条件输入（可由外部系统写入，用于状态切换）
var is_stunned: bool = false
var can_attack: bool = false
var is_dead: bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _spawn_position: Vector2 = Vector2.ZERO
var _move_target: Vector2 = Vector2.ZERO
var _has_move_target: bool = false
var _idle_timer: float = 0.0

var _animation_player: AnimationPlayer = null
var _animated_sprite: AnimatedSprite2D = null
var _middle_body_visual: CanvasItem = null
var _left_missile_visual: CanvasItem = null
var _right_missile_visual: CanvasItem = null
var _charge_node: Node2D = null
var _charge_anim_sprite: AnimatedSprite2D = null
var _target_character: Node2D = null
var _player_node: Node2D = null
var _missile_left_node: Node2D = null
var _missile_right_node: Node2D = null
var _boss_fall_target_node: Node2D = null
var _player_dash_target_node: Node2D = null
var _charge_state_remaining_time: float = 0.0
var _charge_visual_remaining_time: float = 0.0
var _missile_state_remaining_time: float = 0.0
var _cached_default_track_anim_config: TrackAnimationConfig = null
var _pending_charge_beats: int = 0
var _is_preparing_charge: bool = false
var _pre_charge_target_on_ring: bool = false
var _has_pending_charge_fire: bool = false
var _pending_charge_fire_time: float = 0.0
var _pending_missile_beats: int = 0
var _is_preparing_missile: bool = false
var _has_pending_missile_launch: bool = false
var _pending_missile_launch_time: float = 0.0
var _active_missiles: Array[Node2D] = []
var _missile_launch_side_index: int = 0
var _attack_phase_interrupted: bool = false
var _missile_effect_token: int = 0
var _break_transition_tween: Tween = null
var _break_tilt_tween: Tween = null
var _player_dash_tween: Tween = null
var _player_dash_afterimage_token: int = 0
var _break_start_rotation: float = 0.0
var _has_break_start_rotation: bool = false
var _return_to_origin_tween: Tween = null
var _return_to_origin_active: bool = false
var _attack_hint_flash_active: bool = false
var _attack_hint_flash_phase: float = 0.0
var _middle_red_flash_remaining: float = 0.0
var _left_red_flash_remaining: float = 0.0
var _right_red_flash_remaining: float = 0.0

const MISSILE_EFFECT_GROUP: StringName = &"boss_missile_effect"
const PLAYER_DASH_AFTERIMAGE_GROUP: StringName = &"player_dash_afterimage"


func _ready() -> void:
	_rng.randomize()
	_spawn_position = global_position
	_resolve_animation_nodes()
	_resolve_aim_nodes()
	_connect_global_signals()
	_set_state(initial_state)


func _process(delta: float) -> void:
	_update_attack_hit_flash(delta)

	if _attack_phase_interrupted:
		return

	_update_charge_aim()
	_update_pending_charge_schedule()
	_update_charge_state_timer(delta)
	_update_missile_state_timer(delta)
	_update_charge_visual_timer(delta)
	_update_pending_missile_launch()
	_evaluate_state_by_conditions()

	match current_state:
		BossState.IDLE:
			_update_idle(delta)
		BossState.RANDOM_MOVE:
			_update_random_move(delta)
		BossState.BROKEN:
			pass
		BossState.PRE_MISSILE_RETURN:
			_update_pre_missile_return(delta)
		BossState.PRE_CHARGE_MOVE:
			_update_pre_charge_move(delta)
		BossState.CHARGE:
			_update_charge(delta)
		BossState.MISSILE_ATTACK:
			_update_missile_attack(delta)
		BossState.ATTACK:
			_update_attack(delta)
		BossState.STUNNED:
			_update_stunned(delta)
		BossState.DEAD:
			pass


func _resolve_animation_nodes() -> void:
	if not animation_player_path.is_empty():
		_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if not animated_sprite_path.is_empty():
		_animated_sprite = get_node_or_null(animated_sprite_path) as AnimatedSprite2D
	if not middle_body_visual_path.is_empty():
		_middle_body_visual = get_node_or_null(middle_body_visual_path) as CanvasItem
	if not left_missile_visual_path.is_empty():
		_left_missile_visual = get_node_or_null(left_missile_visual_path) as CanvasItem
	if not right_missile_visual_path.is_empty():
		_right_missile_visual = get_node_or_null(right_missile_visual_path) as CanvasItem


func _resolve_aim_nodes() -> void:
	if not charge_node_path.is_empty():
		_charge_node = get_node_or_null(charge_node_path) as Node2D
	if not charge_anim_path.is_empty():
		_charge_anim_sprite = get_node_or_null(charge_anim_path) as AnimatedSprite2D
	if not missile_left_path.is_empty():
		_missile_left_node = get_node_or_null(missile_left_path) as Node2D
	if not missile_right_path.is_empty():
		_missile_right_node = get_node_or_null(missile_right_path) as Node2D

	if not target_character_path.is_empty():
		_target_character = get_node_or_null(target_character_path) as Node2D
	if not player_node_path.is_empty():
		_player_node = get_node_or_null(player_node_path) as Node2D
	if not boss_fall_target_path.is_empty():
		_boss_fall_target_node = get_node_or_null(boss_fall_target_path) as Node2D
	if not player_dash_target_path.is_empty():
		_player_dash_target_node = get_node_or_null(player_dash_target_path) as Node2D

	if _target_character == null:
		var parent_node: Node = get_parent()
		if parent_node != null:
			_target_character = parent_node.get_node_or_null("Character") as Node2D


func _connect_global_signals() -> void:
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)
	if not EventBus.boss_energy_depleted.is_connected(_on_boss_energy_depleted):
		EventBus.boss_energy_depleted.connect(_on_boss_energy_depleted)
	if not EventBus.boss_charge_requested.is_connected(_on_boss_charge_requested):
		EventBus.boss_charge_requested.connect(_on_boss_charge_requested)
	if not EventBus.boss_missile_requested.is_connected(_on_boss_missile_requested):
		EventBus.boss_missile_requested.connect(_on_boss_missile_requested)
	if not EventBus.attack_phase_started.is_connected(_on_attack_phase_started):
		EventBus.attack_phase_started.connect(_on_attack_phase_started)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not EventBus.attack_hit_confirmed.is_connected(_on_attack_hit_confirmed):
		EventBus.attack_hit_confirmed.connect(_on_attack_hit_confirmed)
	if not EventBus.show_return_countdown_requested.is_connected(_on_show_return_countdown_requested):
		EventBus.show_return_countdown_requested.connect(_on_show_return_countdown_requested)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)


func _evaluate_state_by_conditions() -> void:
	if is_dead:
		_set_state(BossState.DEAD)
		return
	if _attack_phase_interrupted:
		_set_state(BossState.IDLE)
		return
	if _is_preparing_missile:
		_set_state(BossState.PRE_MISSILE_RETURN)
		return
	if _missile_state_remaining_time > 0.0:
		_set_state(BossState.MISSILE_ATTACK)
		return
	if _is_preparing_charge:
		_set_state(BossState.PRE_CHARGE_MOVE)
		return
	if _charge_state_remaining_time > 0.0:
		_set_state(BossState.CHARGE)
		return
	if is_stunned:
		_set_state(BossState.STUNNED)
		return
	if can_attack:
		_set_state(BossState.ATTACK)
		return

	# 默认测试状态：持续随机移动
	_set_state(BossState.RANDOM_MOVE)


func _set_state(next_state: BossState) -> void:
	if next_state == current_state:
		return

	_exit_state(current_state)
	current_state = next_state
	_enter_state(current_state)

	if debug_print_state_changes:
		print("[Boss] state -> ", BossState.keys()[current_state])


func _enter_state(state: BossState) -> void:
	match state:
		BossState.IDLE:
			_play_state_animation(idle_animation)
		BossState.RANDOM_MOVE:
			_has_move_target = false
			_idle_timer = 0.0
			_play_state_animation(move_animation)
		BossState.BROKEN:
			_play_state_animation(broken_animation)
		BossState.PRE_MISSILE_RETURN:
			_idle_timer = 0.0
			_play_state_animation(move_animation)
		BossState.PRE_CHARGE_MOVE:
			_idle_timer = 0.0
			_play_state_animation(move_animation)
		BossState.CHARGE:
			_play_charge_animation()
		BossState.MISSILE_ATTACK:
			_play_state_animation(attack_animation)
			_start_missile_attack()
		BossState.ATTACK:
			_play_state_animation(attack_animation)
		BossState.STUNNED:
			_play_state_animation(stunned_animation)
		BossState.DEAD:
			_play_state_animation(dead_animation)


func _exit_state(state: BossState) -> void:
	match state:
		BossState.RANDOM_MOVE:
			_has_move_target = false
		BossState.BROKEN:
			_has_move_target = false
		BossState.PRE_MISSILE_RETURN:
			_has_move_target = false
		BossState.PRE_CHARGE_MOVE:
			_has_move_target = false
		_:
			pass


func _update_idle(delta: float) -> void:
	if _idle_timer > 0.0:
		_idle_timer -= delta


func _update_random_move(delta: float) -> void:
	if _idle_timer > 0.0:
		_idle_timer -= delta
		return

	if not _has_move_target:
		_pick_next_move_target()
		return

	if _move_towards_current_target(delta):
		_has_move_target = false
		_idle_timer = _rng.randf_range(idle_between_moves_range.x, idle_between_moves_range.y)


func _update_pre_charge_move(delta: float) -> void:
	if not _has_pending_charge_fire:
		_is_preparing_charge = false
		_begin_charge_attack(_pending_charge_beats)
		return

	if _target_character == null:
		_resolve_aim_nodes()
	if _target_character == null:
		return

	# 仅沿玩家方向直线移动，直到距离达到 150px。
	var to_player: Vector2 = _target_character.global_position - global_position
	var current_distance: float = to_player.length()
	var stop_distance: float = maxf(1.0, pre_charge_distance_from_player)
	var distance_error: float = current_distance - stop_distance

	if absf(distance_error) > target_reach_distance:
		var need_move: float = absf(distance_error)
		var step: float = minf(move_speed * delta, need_move)
		if step > 0.0:
			var move_dir: Vector2 = Vector2.ZERO
			if to_player.length_squared() > 0.0001:
				move_dir = to_player.normalized() if distance_error > 0.0 else (-to_player.normalized())
			else:
				# 与玩家重合时，默认向右拉开距离。
				move_dir = Vector2.RIGHT
			global_position += move_dir * step

	if _get_now_seconds() >= _pending_charge_fire_time:
		_has_pending_charge_fire = false
		_is_preparing_charge = false
		_begin_charge_attack(_pending_charge_beats)


func _update_pre_missile_return(delta: float) -> void:
	if not _has_move_target:
		_is_preparing_missile = false
		_begin_missile_attack(_pending_missile_beats)
		return

	if _move_towards_current_target(delta):
		_has_move_target = false
		_is_preparing_missile = false
		_begin_missile_attack(_pending_missile_beats)


func _move_towards_current_target(delta: float) -> bool:
	var to_target: Vector2 = _move_target - global_position
	var distance: float = to_target.length()
	if distance <= target_reach_distance:
		global_position = _move_target
		return true

	var move_step: Vector2 = to_target.normalized() * move_speed * delta
	if move_step.length() > distance:
		move_step = to_target
	global_position += move_step
	global_position = _clamp_to_move_area(global_position)
	return false


func _update_attack(_delta: float) -> void:
	# 预留攻击行为：接入攻击逻辑时可在此进行位移、技能或发弹控制。
	pass


func _update_charge(_delta: float) -> void:
	# charge 状态期间仅维持瞄准与动画，由计时器控制退出。
	pass


func _update_missile_attack(_delta: float) -> void:
	# 导弹轨道状态由时长计时控制退出。
	pass


func _update_stunned(_delta: float) -> void:
	# 预留眩晕行为：接入时可在此限制行动并处理恢复计时。
	pass


func _pick_next_move_target() -> void:
	var min_distance: float = maxf(0.0, move_pick_min_distance)
	var max_distance: float = maxf(min_distance, move_pick_max_distance)
	var found_target: bool = false

	# 先基于原点矩形范围采样，再额外要求与当前位置的距离在[min, max]区间。
	for _i in range(24):
		var candidate: Vector2 = _spawn_position + Vector2(
			_rng.randf_range(-max_move_left, max_move_right),
			_rng.randf_range(-max_move_up, max_move_down)
		)
		if _is_valid_candidate(candidate, min_distance, max_distance):
			_move_target = candidate
			found_target = true
			break

	if not found_target:
		# 当前姿态下可能暂时无可行点（例如靠边且最小距离过大），稍后重试。
		_has_move_target = false
		_idle_timer = 0.1
		return

	_move_target = _clamp_to_move_area(_move_target)
	_has_move_target = true


func _clamp_to_move_area(value: Vector2) -> Vector2:
	return Vector2(
		clampf(value.x, _spawn_position.x - max_move_left, _spawn_position.x + max_move_right),
		clampf(value.y, _spawn_position.y - max_move_up, _spawn_position.y + max_move_down)
	)


func _is_valid_candidate(candidate: Vector2, min_distance: float, max_distance: float) -> bool:
	var clamped_candidate: Vector2 = _clamp_to_move_area(candidate)
	if not candidate.is_equal_approx(clamped_candidate):
		return false

	var distance_from_current: float = global_position.distance_to(candidate)
	return distance_from_current >= min_distance and distance_from_current <= max_distance


func _is_within_move_area(candidate: Vector2) -> bool:
	var clamped_candidate: Vector2 = _clamp_to_move_area(candidate)
	return candidate.is_equal_approx(clamped_candidate)


func _update_charge_aim() -> void:
	if not enable_charge_auto_aim:
		return
	if _charge_node == null:
		return
	if _target_character == null:
		_resolve_aim_nodes()
		if _target_character == null:
			return

	var to_character: Vector2 = _target_character.global_position - _charge_node.global_position
	if to_character.length_squared() <= 0.0001:
		return

	_charge_node.global_rotation = to_character.angle() + deg_to_rad(charge_rotation_offset_degrees)


func _update_charge_state_timer(delta: float) -> void:
	if _charge_state_remaining_time <= 0.0:
		return
	_charge_state_remaining_time = maxf(0.0, _charge_state_remaining_time - delta)


func _update_missile_state_timer(delta: float) -> void:
	if _missile_state_remaining_time <= 0.0:
		return
	_missile_state_remaining_time = maxf(0.0, _missile_state_remaining_time - delta)


func _play_charge_animation() -> void:
	if _charge_anim_sprite == null:
		return
	if _charge_anim_sprite.sprite_frames == null:
		return
	if not _charge_anim_sprite.sprite_frames.has_animation(charge_animation_name):
		push_warning("[Boss] ChargeAnim 缺少动画: %s" % String(charge_animation_name))
		return

	var target_duration: float = maxf(0.01, _charge_state_remaining_time)
	var sprite_frames: SpriteFrames = _charge_anim_sprite.sprite_frames
	var anim_name: String = String(charge_animation_name)
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var attack_end_frame: int = _get_charge_attack_end_frame(frame_count)

	# 对齐规则：第4拍时刻对应 attack_end_frame（从 0 计）
	# 因此速度按 [0..attack_end_frame-1] 段时长进行缩放。
	var base_duration: float = 0.0
	if attack_end_frame > 0:
		base_duration = _get_sprite_animation_partial_duration(sprite_frames, anim_name, 0, attack_end_frame - 1)
	else:
		base_duration = _get_sprite_animation_duration(sprite_frames, anim_name)
	if base_duration > 0.0:
		# AnimatedSprite2D 实际时长 = base_duration / speed_scale
		# 令 attack_end_frame 对齐到目标时长（默认 4 拍）。
		_charge_anim_sprite.speed_scale = base_duration / target_duration
	else:
		_charge_anim_sprite.speed_scale = 1.0

	var full_base_duration: float = _get_sprite_animation_duration(sprite_frames, anim_name)
	if _charge_anim_sprite.speed_scale > 0.0 and full_base_duration > 0.0:
		# 第4拍对齐关键帧后，继续把整段动画剩余部分播完一轮。
		_charge_visual_remaining_time = full_base_duration / _charge_anim_sprite.speed_scale
	else:
		_charge_visual_remaining_time = target_duration

	_charge_anim_sprite.visible = true
	_charge_anim_sprite.stop()
	_charge_anim_sprite.frame = 0
	_charge_anim_sprite.frame_progress = 0.0
	_charge_anim_sprite.play(charge_animation_name)


func _stop_charge_animation() -> void:
	if _charge_anim_sprite == null:
		return
	if _charge_anim_sprite.sprite_frames != null and _charge_anim_sprite.sprite_frames.has_animation(charge_animation_name):
		var frame_count: int = _charge_anim_sprite.sprite_frames.get_frame_count(charge_animation_name)
		var last_frame: int = frame_count - 1
		if last_frame >= 0:
			_charge_anim_sprite.frame = last_frame
			_charge_anim_sprite.frame_progress = 0.0
	_charge_anim_sprite.stop()
	_charge_anim_sprite.speed_scale = 1.0
	_charge_visual_remaining_time = 0.0


func _update_charge_visual_timer(delta: float) -> void:
	if _charge_visual_remaining_time <= 0.0:
		return
	_charge_visual_remaining_time = maxf(0.0, _charge_visual_remaining_time - delta)
	if _charge_visual_remaining_time <= 0.0:
		_stop_charge_animation()


func _play_state_animation(anim_name: StringName) -> void:
	if anim_name.is_empty():
		return

	if _animated_sprite != null and _animated_sprite.sprite_frames != null:
		if _animated_sprite.sprite_frames.has_animation(anim_name):
			_animated_sprite.play(anim_name)
			return

	if _animation_player != null and _animation_player.has_animation(anim_name):
		_animation_player.play(anim_name)


func _on_boss_defeated() -> void:
	is_dead = true
	_set_attack_hint_flash_active(false)
	_reset_attack_hit_visuals()
	_stop_break_transition()
	_attack_phase_interrupted = false
	_is_preparing_missile = false
	_is_preparing_charge = false
	_has_pending_missile_launch = false
	_pending_charge_beats = 0
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_pending_missile_beats = 0
	_missile_state_remaining_time = 0.0
	_stop_charge_animation()
	_clear_active_missiles()


func _on_attack_phase_started() -> void:
	_set_attack_hint_flash_active(true)
	_stop_return_to_origin_transition()
	_interrupt_for_attack_phase(BossState.BROKEN)


func _on_boss_energy_depleted() -> void:
	_stop_return_to_origin_transition()
	_interrupt_for_attack_phase(BossState.BROKEN)
	_start_shield_break_transition()


func _interrupt_for_attack_phase(target_state: BossState = BossState.IDLE) -> void:
	if is_dead:
		return

	_attack_phase_interrupted = true
	_is_preparing_missile = false
	_is_preparing_charge = false
	_has_pending_missile_launch = false
	_pending_charge_beats = 0
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_pending_missile_beats = 0
	_charge_state_remaining_time = 0.0
	_missile_state_remaining_time = 0.0
	_has_move_target = false
	_stop_charge_animation()
	_clear_active_missiles()
	_set_state(target_state)


func _on_attack_phase_ended() -> void:
	if is_dead:
		return

	_set_attack_hint_flash_active(false)
	_reset_attack_hit_visuals()

	_stop_break_transition()
	_stop_return_to_origin_transition()
	_attack_phase_interrupted = false
	_is_preparing_missile = false
	_is_preparing_charge = false
	_has_pending_missile_launch = false
	_pending_charge_beats = 0
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_pending_missile_beats = 0
	_charge_state_remaining_time = 0.0
	_missile_state_remaining_time = 0.0

	# 攻击阶段结束后立即执行一次正常选位移动，避免观感像瞬移。
	_set_state(BossState.RANDOM_MOVE)
	_idle_timer = 0.0
	_has_move_target = false
	_pick_next_move_target()


func _on_show_return_countdown_requested(_count: int) -> void:
	# 需求变更：取消转阶段后撤。
	return


func _on_player_died() -> void:
	# 玩家死亡后，Boss 逻辑完全冻结（不再移动/攻击/调度）。
	is_dead = true
	_attack_phase_interrupted = true
	_has_move_target = false
	_is_preparing_missile = false
	_is_preparing_charge = false
	_has_pending_missile_launch = false
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_pending_missile_beats = 0
	_pending_charge_beats = 0
	_charge_state_remaining_time = 0.0
	_missile_state_remaining_time = 0.0
	_stop_charge_animation()
	_clear_active_missiles()
	set_process(false)


func _on_attack_hit_confirmed(_attack_type: int, target: Variant) -> void:
	if target == null:
		return

	var target_node: Node = target as Node
	if target_node == null:
		return

	var hit_visual: CanvasItem = _resolve_hit_visual_target(target_node)
	if hit_visual == null:
		return

	if hit_visual == _middle_body_visual:
		_middle_red_flash_remaining = maxf(_middle_red_flash_remaining, hit_red_flash_duration)
	elif hit_visual == _left_missile_visual:
		_left_red_flash_remaining = maxf(_left_red_flash_remaining, hit_red_flash_duration)
	elif hit_visual == _right_missile_visual:
		_right_red_flash_remaining = maxf(_right_red_flash_remaining, hit_red_flash_duration)


func _set_attack_hint_flash_active(enabled: bool) -> void:
	_attack_hint_flash_active = enabled
	if not enabled:
		_attack_hint_flash_phase = 0.0


func _update_attack_hit_flash(delta: float) -> void:
	if _middle_body_visual == null and _left_missile_visual == null and _right_missile_visual == null:
		return

	_middle_red_flash_remaining = maxf(0.0, _middle_red_flash_remaining - delta)
	_left_red_flash_remaining = maxf(0.0, _left_red_flash_remaining - delta)
	_right_red_flash_remaining = maxf(0.0, _right_red_flash_remaining - delta)

	var normal_color: Color = Color(1.0, 1.0, 1.0, 1.0)
	if _attack_hint_flash_active:
		_attack_hint_flash_phase += delta * maxf(0.1, attack_hint_flash_speed)
		var pulse: float = (sin(_attack_hint_flash_phase * TAU) + 1.0) * 0.5
		var strength: float = clampf(attack_hint_flash_strength, 0.0, 1.5)
		var boost: float = 0.18 + pulse * strength
		normal_color = Color(1.0 + boost, 1.0 + boost, 1.0 + boost, 1.0)

	var hit_red_color: Color = Color(1.75, 0.30, 0.30, 1.0)
	_apply_single_visual_color(_middle_body_visual, hit_red_color if _middle_red_flash_remaining > 0.0 else normal_color)
	_apply_single_visual_color(_left_missile_visual, hit_red_color if _left_red_flash_remaining > 0.0 else normal_color)
	_apply_single_visual_color(_right_missile_visual, hit_red_color if _right_red_flash_remaining > 0.0 else normal_color)


func _apply_attack_hit_visual_color(color_value: Color) -> void:
	for visual in _get_attack_hit_visuals():
		visual.self_modulate = color_value


func _apply_single_visual_color(visual: CanvasItem, color_value: Color) -> void:
	if visual == null:
		return
	visual.self_modulate = color_value


func _reset_attack_hit_visuals() -> void:
	_middle_red_flash_remaining = 0.0
	_left_red_flash_remaining = 0.0
	_right_red_flash_remaining = 0.0
	_apply_attack_hit_visual_color(Color(1.0, 1.0, 1.0, 1.0))


func _get_attack_hit_visuals() -> Array[CanvasItem]:
	var visuals: Array[CanvasItem] = []
	if _middle_body_visual != null:
		visuals.append(_middle_body_visual)
	if _left_missile_visual != null:
		visuals.append(_left_missile_visual)
	if _right_missile_visual != null:
		visuals.append(_right_missile_visual)
	return visuals


func _resolve_hit_visual_target(target_node: Node) -> CanvasItem:
	if target_node == null:
		return null
	if target_node == _middle_body_visual or (_middle_body_visual != null and _middle_body_visual.is_ancestor_of(target_node)):
		return _middle_body_visual
	if target_node == _left_missile_visual or (_left_missile_visual != null and _left_missile_visual.is_ancestor_of(target_node)):
		return _left_missile_visual
	if target_node == _right_missile_visual or (_right_missile_visual != null and _right_missile_visual.is_ancestor_of(target_node)):
		return _right_missile_visual
	return null


func _on_boss_charge_requested(duration_beats: int) -> void:
	if is_dead:
		return

	var lead_beats: int = duration_beats
	if lead_beats <= 0:
		lead_beats = charge_duration_beats
	lead_beats = maxi(0, lead_beats)

	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5

	_charge_state_remaining_time = 0.0
	_pending_charge_beats = maxi(1, charge_duration_beats)
	var now: float = _get_now_seconds()
	var requested_fire_time: float = now + float(lead_beats) * beat_seconds
	var windup_time: float = float(_pending_charge_beats) * beat_seconds
	# duration_beats 表示离“应命中时刻”的提前量；charge 需要提前进入蓄力。
	_pending_charge_fire_time = requested_fire_time - windup_time
	if _pending_charge_fire_time < now:
		_pending_charge_fire_time = now
	_has_pending_charge_fire = true
	_is_preparing_charge = false

	# 若请求即刻发射，直接进入 charge。
	if lead_beats <= 0 or _pending_charge_fire_time <= now:
		_has_pending_charge_fire = false
		_begin_charge_attack(_pending_charge_beats)


func _on_boss_missile_requested(duration_beats: int) -> void:
	if is_dead:
		return

	var beats: int = duration_beats
	if beats <= 0:
		beats = missile_total_beats
	beats = maxi(1, beats)

	_pending_missile_beats = beats

	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5

	# 以判定时刻为基准反推发射时刻：
	# 发射到命中耗时 = phase1 + phase2，确保第二轨到判定线时导弹命中玩家。
	var flight_beats: int = maxi(1, missile_phase1_beats) + maxi(1, missile_phase2_beats)
	var launch_lead_beats: int = maxi(0, beats - flight_beats)

	# 命中提前量不足时直接发射，避免依赖 _process 调度导致漏发。
	if launch_lead_beats <= 0:
		_has_pending_missile_launch = false
		_pending_missile_launch_time = 0.0
		_is_preparing_missile = false
		_launch_missile_attack_now()
		return

	# 预约“下一次导弹发射时间”，不再做发射前归位。
	_has_pending_missile_launch = true
	_pending_missile_launch_time = _get_now_seconds() + float(launch_lead_beats) * beat_seconds
	_is_preparing_missile = false


func _prepare_pre_charge_move_target() -> bool:
	if _target_character == null:
		_resolve_aim_nodes()
	if _target_character == null:
		return false

	return _refresh_pre_charge_target()


func _refresh_pre_charge_target() -> bool:
	if _target_character == null:
		_resolve_aim_nodes()
	if _target_character == null:
		return false

	var selection: Dictionary = _pick_pre_charge_target(_target_character.global_position)
	_pre_charge_target_on_ring = bool(selection.get("found_on_ring", false))
	var target: Vector2 = selection.get("target", global_position)
	_move_target = target
	_has_move_target = global_position.distance_to(_move_target) > target_reach_distance
	return true


func _pick_pre_charge_target(player_pos: Vector2) -> Dictionary:
	var radius: float = maxf(1.0, pre_charge_distance_from_player)
	var sample_count: int = maxi(96, pre_charge_pick_attempts)
	var best_ring_target: Vector2 = Vector2.ZERO
	var best_ring_distance: float = INF
	var found_ring_target: bool = false

	for i in range(sample_count):
		var angle: float = (TAU * float(i)) / float(sample_count)
		var candidate: Vector2 = player_pos + Vector2.RIGHT.rotated(angle) * radius
		if not _is_within_move_area(candidate):
			continue

		var travel_distance: float = global_position.distance_to(candidate)
		if travel_distance < best_ring_distance:
			best_ring_distance = travel_distance
			best_ring_target = candidate
			found_ring_target = true

	if found_ring_target:
		return {
			"found_on_ring": true,
			"target": best_ring_target
		}

	# 圆环无交点时，回退到可移动区域内最靠近玩家的位置。
	return {
		"found_on_ring": false,
		"target": _clamp_to_move_area(player_pos)
	}

func _prepare_pre_missile_return_target() -> bool:
	_move_target = _spawn_position
	if global_position.distance_to(_move_target) <= target_reach_distance:
		_has_move_target = false
		return false

	_has_move_target = true
	return true


func _begin_charge_attack(beats: int) -> void:
	var beat_count: int = maxi(1, beats)
	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5

	_pending_charge_beats = 0
	_pre_charge_target_on_ring = false
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_charge_state_remaining_time = float(beat_count) * beat_seconds
	if current_state == BossState.CHARGE:
		_play_charge_animation()
		return
	_set_state(BossState.CHARGE)


func _update_pending_charge_schedule() -> void:
	if not _has_pending_charge_fire:
		return
	if is_dead:
		_has_pending_charge_fire = false
		return

	if _target_character == null:
		_resolve_aim_nodes()
	if _target_character == null:
		return

	var now: float = _get_now_seconds()
	var time_left: float = _pending_charge_fire_time - now
	if time_left <= 0.0:
		_is_preparing_charge = false
		_has_pending_charge_fire = false
		_begin_charge_attack(_pending_charge_beats)
		return

	var current_distance: float = global_position.distance_to(_target_character.global_position)
	var stop_distance: float = maxf(1.0, pre_charge_distance_from_player)
	var need_distance: float = absf(current_distance - stop_distance)
	var can_cover_distance: float = move_speed * time_left

	# 当“剩余时间 * 移速”足以覆盖需要前进的距离时，启动预移动。
	if not _is_preparing_charge and need_distance <= can_cover_distance + target_reach_distance:
		_is_preparing_charge = true
		_set_state(BossState.PRE_CHARGE_MOVE)


func _begin_missile_attack(beats: int) -> void:
	var beat_count: int = maxi(1, beats)
	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5

	_pending_missile_beats = 0
	_has_pending_missile_launch = false
	var state_duration: float = float(beat_count) * beat_seconds
	_missile_state_remaining_time = maxf(_missile_state_remaining_time, state_duration)

	if current_state == BossState.MISSILE_ATTACK:
		_start_missile_attack()
	else:
		_set_state(BossState.MISSILE_ATTACK)


func _start_missile_attack() -> void:
	if missile_scene == null:
		push_warning("[Boss] missile_scene 未配置")
		return

	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5

	var phase1_duration: float = float(maxi(1, missile_phase1_beats)) * beat_seconds
	var phase2_duration: float = float(maxi(1, missile_phase2_beats)) * beat_seconds
	_spawn_missile_instance(phase1_duration, phase2_duration)


func _spawn_missile_instance(phase1_duration: float, phase2_duration: float) -> void:
	var token: int = _missile_effect_token

	var launch_node: Node2D = _pick_missile_launch_node()
	if launch_node == null:
		push_warning("[Boss] 缺少 MissileLeft/MissileRight 节点，无法发射导弹")
		return

	var missile: Node2D = missile_scene.instantiate() as Node2D
	if missile == null:
		push_warning("[Boss] missile_scene 不是 Node2D，无法发射导弹")
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	scene_root.add_child(missile)
	missile.add_to_group(MISSILE_EFFECT_GROUP)
	missile.global_position = launch_node.global_position
	_active_missiles.append(missile)

	var outward_dir: Vector2 = _get_missile_outward_direction(launch_node).normalized()
	var outward_target: Vector2 = _get_missile_offscreen_target(missile.global_position, outward_dir)
	var teleport_target: Vector2 = _get_missile_teleport_corner(launch_node)
	_orient_missile_to_direction(missile, outward_dir)

	var phase1_tween: Tween = missile.create_tween()
	phase1_tween.tween_property(missile, "global_position", outward_target, phase1_duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	phase1_tween.tween_callback(func() -> void:
		if token != _missile_effect_token:
			if is_instance_valid(missile):
				missile.queue_free()
			_active_missiles.erase(missile)
			return
		if not is_instance_valid(missile):
			return
		# 第二拍开始：瞬移到左上/右上屏幕外边缘。
		missile.global_position = teleport_target
		# 第二拍起始放大 2 倍。
		missile.scale *= 2.0
		var player_target: Vector2 = _get_current_target_position(outward_target)
		_orient_missile_to_direction(missile, player_target - missile.global_position)
		var phase2_tween: Tween = missile.create_tween()
		phase2_tween.tween_property(missile, "global_position", player_target, phase2_duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		phase2_tween.tween_callback(func() -> void:
			if token != _missile_effect_token:
				if is_instance_valid(missile):
					missile.queue_free()
				_active_missiles.erase(missile)
				return
			if is_instance_valid(missile):
				missile.queue_free()
			_active_missiles.erase(missile)
		)
	)


func _pick_missile_launch_node() -> Node2D:
	var candidates: Array[Node2D] = []
	if _missile_left_node != null:
		candidates.append(_missile_left_node)
	if _missile_right_node != null:
		candidates.append(_missile_right_node)
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		return candidates[0]

	# 两侧交替发射：0=left, 1=right。
	var picked: Node2D = _missile_left_node if (_missile_launch_side_index % 2 == 0) else _missile_right_node
	_missile_launch_side_index += 1

	if picked != null:
		return picked

	# 兜底：理论上不会走到这里。
	return candidates[0]


func _get_missile_outward_direction(launch_node: Node2D) -> Vector2:
	if launch_node == _missile_left_node:
		return Vector2(-1.0, -1.0)
	if launch_node == _missile_right_node:
		return Vector2(1.0, -1.0)

	# 兜底：按所在屏幕左右半区选择方向
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if launch_node.global_position.x <= viewport_size.x * 0.5:
		return Vector2(-1.0, -1.0)
	return Vector2(1.0, -1.0)


func _get_current_target_position(fallback: Vector2) -> Vector2:
	if _target_character == null:
		_resolve_aim_nodes()
	if _target_character != null:
		return _target_character.global_position
	return fallback


func _get_missile_teleport_corner(launch_node: Node2D) -> Vector2:
	var use_left: bool = (launch_node == _missile_left_node)
	if launch_node != _missile_left_node and launch_node != _missile_right_node:
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		use_left = (launch_node.global_position.x <= viewport_size.x * 0.5)

	var camera: Camera2D = get_viewport().get_camera_2d()
	var margin: float = 24.0
	if camera != null:
		var center: Vector2 = camera.get_screen_center_position()
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var zoom: Vector2 = camera.zoom
		var half_world_size: Vector2 = Vector2(viewport_size.x * zoom.x * 0.5, viewport_size.y * zoom.y * 0.5)
		var x: float = center.x - half_world_size.x - margin if use_left else center.x + half_world_size.x + margin
		var y: float = center.y - half_world_size.y - margin
		return Vector2(x, y)

	var rect: Rect2 = get_viewport().get_visible_rect()
	var x2: float = rect.position.x - margin if use_left else rect.position.x + rect.size.x + margin
	var y2: float = rect.position.y - margin
	return Vector2(x2, y2)


func _orient_missile_to_direction(missile: Node2D, direction: Vector2) -> void:
	if not is_instance_valid(missile):
		return
	if direction.length_squared() <= 0.0001:
		return
	# missile 贴图默认朝上，旋转到与移动方向一致。
	missile.global_rotation = Vector2.UP.angle_to(direction.normalized())


func _get_missile_offscreen_target(start: Vector2, direction: Vector2) -> Vector2:
	var dir: Vector2 = direction.normalized()
	if dir.length_squared() <= 0.0001:
		dir = Vector2(1.0, -1.0).normalized()

	var target: Vector2 = start + dir * maxf(200.0, missile_outward_distance)
	var visible_rect: Rect2 = get_viewport().get_visible_rect().grow(16.0)
	var step: float = maxf(120.0, missile_outward_distance * 0.25)

	for _i in range(16):
		if not visible_rect.has_point(target):
			return target
		target += dir * step

	return target


func _update_pending_missile_launch() -> void:
	if not _has_pending_missile_launch:
		return
	if is_dead:
		_has_pending_missile_launch = false
		return

	var now: float = _get_now_seconds()
	var remaining: float = _pending_missile_launch_time - now

	# 到达发射时刻：直接发射，不再等待归位。
	if remaining <= 0.0:
		_launch_missile_attack_now()


func _launch_missile_attack_now() -> void:
	_is_preparing_missile = false
	_has_pending_missile_launch = false
	_pending_missile_beats = 0
	_start_missile_attack()


func _start_return_to_origin_transition() -> void:
	_stop_return_to_origin_transition()

	var bi: float = EventBus.beat_interval
	if bi <= 0.0:
		bi = 0.5

	var rotate_duration: float = bi
	var move_duration: float = float(maxi(1, GameConstants.EXIT_BEATS - 1)) * bi
	var upright_rotation: float = deg_to_rad(return_upright_rotation_degrees)

	_return_to_origin_active = true
	_has_move_target = false
	_is_preparing_missile = false
	_is_preparing_charge = false
	_has_pending_missile_launch = false

	_return_to_origin_tween = create_tween()
	_return_to_origin_tween.tween_property(self, "rotation", upright_rotation, rotate_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_return_to_origin_tween.tween_property(self, "global_position", _spawn_position, move_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_return_to_origin_tween.tween_callback(func() -> void:
		_return_to_origin_active = false
	)


func _stop_return_to_origin_transition() -> void:
	if _return_to_origin_tween != null:
		_return_to_origin_tween.kill()
		_return_to_origin_tween = null
	_return_to_origin_active = false


func _get_now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _start_shield_break_transition() -> void:
	_stop_break_transition()
	if _player_node == null:
		_resolve_aim_nodes()

	var bi: float = EventBus.beat_interval
	if bi <= 0.0:
		bi = 0.5
	var total_beats: int = maxi(1, broken_transition_beats)
	var duration: float = float(total_beats) * bi
	var shake_duration: float = minf(duration, bi)
	var fall_duration: float = maxf(0.0, duration - shake_duration)

	# 第1拍：原地晃动并小幅右倾；第2-4拍：坠落。
	var start_x: float = global_position.x
	_break_start_rotation = rotation
	_has_break_start_rotation = true

	_break_transition_tween = create_tween()

	if shake_duration > 0.0:
		var shake_offset: float = maxf(0.0, broken_shake_offset_x)
		var tilt_target: float = _break_start_rotation + deg_to_rad(broken_right_tilt_degrees)

		_break_transition_tween.tween_property(self, "global_position:x", start_x + shake_offset, shake_duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_break_transition_tween.tween_property(self, "global_position:x", start_x - shake_offset, shake_duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_break_transition_tween.tween_property(self, "global_position:x", start_x + shake_offset * 0.5, shake_duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_break_transition_tween.tween_property(self, "global_position:x", start_x, shake_duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

		_break_tilt_tween = create_tween()
		_break_tilt_tween.tween_property(self, "rotation", tilt_target, shake_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	if fall_duration > 0.0:
		_break_transition_tween.tween_property(self, "global_position:y", broken_fall_target_y, fall_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	# 需求变更：取消转阶段冲刺，玩家位置保持不变。


func _stop_break_transition() -> void:
	if _break_transition_tween != null:
		_break_transition_tween.kill()
		_break_transition_tween = null
	if _break_tilt_tween != null:
		_break_tilt_tween.kill()
		_break_tilt_tween = null
	if _player_dash_tween != null:
		_player_dash_tween.kill()
		_player_dash_tween = null
	if _has_break_start_rotation:
		rotation = _break_start_rotation
		_has_break_start_rotation = false
	_stop_player_dash_afterimage()


func _clear_active_missiles() -> void:
	_missile_effect_token += 1

	for missile in _active_missiles:
		if missile != null and is_instance_valid(missile):
			missile.visible = false
			missile.queue_free()
	_active_missiles.clear()

	# 兜底清理：清掉可能未被数组追踪到的残留导弹实例。
	for node in get_tree().get_nodes_in_group(MISSILE_EFFECT_GROUP):
		var missile_node: Node = node as Node
		if missile_node != null and is_instance_valid(missile_node):
			if missile_node is CanvasItem:
				(missile_node as CanvasItem).visible = false
			missile_node.queue_free()


func _start_player_dash_afterimage(duration: float) -> void:
	if not enable_player_dash_afterimage:
		return
	if _player_node == null:
		return

	_player_dash_afterimage_token += 1
	var token: int = _player_dash_afterimage_token
	var end_time: float = _get_now_seconds() + maxf(0.01, duration)
	_emit_player_dash_afterimage_loop(token, end_time)


func _emit_player_dash_afterimage_loop(token: int, end_time: float) -> void:
	if token != _player_dash_afterimage_token:
		return
	if is_dead or not _attack_phase_interrupted:
		return
	if _get_now_seconds() > end_time:
		return

	_spawn_player_afterimage()
	var interval: float = maxf(0.01, player_dash_afterimage_interval)
	get_tree().create_timer(interval).timeout.connect(func() -> void:
		_emit_player_dash_afterimage_loop(token, end_time)
	)


func _spawn_player_afterimage() -> void:
	if _player_node == null:
		return

	var player_sprite: AnimatedSprite2D = _player_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if player_sprite == null:
		return
	if player_sprite.sprite_frames == null:
		return
	if not player_sprite.sprite_frames.has_animation(player_sprite.animation):
		return

	var frame_texture: Texture2D = player_sprite.sprite_frames.get_frame_texture(player_sprite.animation, player_sprite.frame)
	if frame_texture == null:
		return

	var ghost: Sprite2D = Sprite2D.new()
	ghost.texture = frame_texture
	ghost.centered = player_sprite.centered
	ghost.offset = player_sprite.offset
	ghost.flip_h = player_sprite.flip_h
	ghost.flip_v = player_sprite.flip_v
	ghost.global_transform = player_sprite.global_transform
	ghost.add_to_group(PLAYER_DASH_AFTERIMAGE_GROUP)

	var color: Color = player_dash_afterimage_color
	color.a = player_dash_afterimage_alpha
	ghost.modulate = color

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	scene_root.add_child(ghost)

	var life: float = maxf(0.05, player_dash_afterimage_lifetime)
	var fade_tween: Tween = ghost.create_tween()
	fade_tween.tween_property(ghost, "modulate:a", 0.0, life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	fade_tween.tween_callback(func() -> void:
		if is_instance_valid(ghost):
			ghost.queue_free()
	)


func _stop_player_dash_afterimage() -> void:
	_player_dash_afterimage_token += 1
	for node in get_tree().get_nodes_in_group(PLAYER_DASH_AFTERIMAGE_GROUP):
		var ghost_node: Node = node as Node
		if ghost_node != null and is_instance_valid(ghost_node):
			ghost_node.queue_free()


func _get_sprite_animation_duration(sprite_frames: SpriteFrames, anim_name: String) -> float:
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0.0:
		return 0.0

	var total_units: float = 0.0
	for i in range(frame_count):
		total_units += sprite_frames.get_frame_duration(anim_name, i)

	return total_units / base_fps


func _get_sprite_animation_partial_duration(sprite_frames: SpriteFrames, anim_name: String, from_frame: int, to_frame: int) -> float:
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0.0:
		return 0.0

	var from_idx: int = maxi(0, from_frame)
	var to_idx: int = mini(to_frame, frame_count - 1)
	if to_idx < from_idx:
		return 0.0

	var total_units: float = 0.0
	for i in range(from_idx, to_idx + 1):
		total_units += sprite_frames.get_frame_duration(anim_name, i)

	return total_units / base_fps


func _get_charge_attack_end_frame(frame_count: int) -> int:
	if frame_count <= 0:
		return -1

	var config: TrackAnimationConfig = track_animation_config
	if config == null:
		if _cached_default_track_anim_config == null:
			_cached_default_track_anim_config = load("res://config/track_animation_config.tres") as TrackAnimationConfig
		config = _cached_default_track_anim_config

	var attack_end_frame: int = -1
	if config != null:
		attack_end_frame = config.get_attack_end_frame(Note.NoteType.DODGE)

	if attack_end_frame < 0 or attack_end_frame >= frame_count:
		return frame_count - 1

	return attack_end_frame


# === 外部调用接口 ===

func set_stunned(value: bool) -> void:
	is_stunned = value


func set_can_attack(value: bool) -> void:
	can_attack = value


func set_dead(value: bool) -> void:
	is_dead = value
