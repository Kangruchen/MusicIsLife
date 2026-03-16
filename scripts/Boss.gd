extends Node2D
## Boss 状态机控制器
## 提供可扩展状态流转，并支持初始测试：在指定范围内持续随机移动。

enum BossState {
	IDLE,
	RANDOM_MOVE,
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
@export var target_reach_distance: float = 10.0
@export var idle_between_moves_range: Vector2 = Vector2(0.15, 0.55)

@export_group("Animation")
@export_node_path("AnimationPlayer") var animation_player_path: NodePath
@export_node_path("AnimatedSprite2D") var animated_sprite_path: NodePath
@export var idle_animation: StringName = &"idle"
@export var move_animation: StringName = &"move"
@export var attack_animation: StringName = &"attack"
@export var stunned_animation: StringName = &"stunned"
@export var dead_animation: StringName = &"dead"

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


func _ready() -> void:
	_rng.randomize()
	_spawn_position = global_position
	_resolve_animation_nodes()
	_connect_global_signals()
	_set_state(initial_state)


func _process(delta: float) -> void:
	_evaluate_state_by_conditions()

	match current_state:
		BossState.IDLE:
			_update_idle(delta)
		BossState.RANDOM_MOVE:
			_update_random_move(delta)
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


func _connect_global_signals() -> void:
	if EventBus.boss_defeated.is_connected(_on_boss_defeated):
		return
	EventBus.boss_defeated.connect(_on_boss_defeated)


func _evaluate_state_by_conditions() -> void:
	if is_dead:
		_set_state(BossState.DEAD)
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

	var to_target: Vector2 = _move_target - global_position
	var distance: float = to_target.length()
	if distance <= target_reach_distance:
		global_position = _move_target
		_has_move_target = false
		_idle_timer = _rng.randf_range(idle_between_moves_range.x, idle_between_moves_range.y)
		return

	var move_step: Vector2 = to_target.normalized() * move_speed * delta
	if move_step.length() > distance:
		move_step = to_target
	global_position += move_step
	global_position = _clamp_to_move_area(global_position)


func _update_attack(_delta: float) -> void:
	# 预留攻击行为：接入攻击逻辑时可在此进行位移、技能或发弹控制。
	pass


func _update_stunned(_delta: float) -> void:
	# 预留眩晕行为：接入时可在此限制行动并处理恢复计时。
	pass


func _pick_next_move_target() -> void:
	var random_offset: Vector2 = Vector2(
		_rng.randf_range(-max_move_left, max_move_right),
		_rng.randf_range(-max_move_up, max_move_down)
	)
	_move_target = _spawn_position + random_offset
	_move_target = _clamp_to_move_area(_move_target)
	_has_move_target = true


func _clamp_to_move_area(value: Vector2) -> Vector2:
	return Vector2(
		clampf(value.x, _spawn_position.x - max_move_left, _spawn_position.x + max_move_right),
		clampf(value.y, _spawn_position.y - max_move_up, _spawn_position.y + max_move_down)
	)


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


# === 外部调用接口 ===

func set_stunned(value: bool) -> void:
	is_stunned = value


func set_can_attack(value: bool) -> void:
	can_attack = value


func set_dead(value: bool) -> void:
	is_dead = value
