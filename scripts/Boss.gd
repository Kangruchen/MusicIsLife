extends Node2D

const RhythmClock := preload("res://scripts/RhythmClock.gd")
const MusicClockEventQueue := preload("res://scripts/MusicClockEventQueue.gd")
const BossPartHealthModel := preload("res://scripts/BossPartHealthModel.gd")
const BossMissileSideSelector := preload("res://scripts/BossMissileSideSelector.gd")
const BossPreChargeTargetPicker := preload("res://scripts/BossPreChargeTargetPicker.gd")
const BossMissileWarningLightStyle := preload("res://scripts/BossMissileWarningLightStyle.gd")
const BossMissileLauncherRecoilState := preload("res://scripts/BossMissileLauncherRecoilState.gd")
const BossChargeBulletTiming := preload("res://scripts/BossChargeBulletTiming.gd")
const PlayerAfterimageFactory := preload("res://scripts/PlayerAfterimageFactory.gd")
const SpriteAnimationDuration := preload("res://scripts/SpriteAnimationDuration.gd")
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
@export_range(0.0, 1.0, 0.01) var charge_request_min_interval_sec: float = 0.12
@export var track_animation_config: TrackAnimationConfig = null
@export var pre_charge_distance_from_player: float = 150.0
@export var pre_charge_pick_attempts: int = 32

@export_group("Charge Bullet")
@export var charge_bullet_scene: PackedScene = preload("res://scenes/charge_bullet.tscn")
@export_node_path("Node2D") var charge_bullet_spawn_path: NodePath = NodePath("Charge/BulletPoint")
@export var charge_bullet_fire_frame: int = 16
@export var charge_bullet_move_start_frame: int = 16
@export var charge_bullet_hit_frame: int = 17
@export var charge_bullet_despawn_frame: int = 18
@export_range(0.0, 2000.0, 1.0) var charge_bullet_hit_distance_from_player: float = 0.0
@export var charge_bullet_use_scene_root_scale: bool = true
@export var charge_bullet_instance_scale: Vector2 = Vector2(0.333, 0.333)

@export_group("Missile Attack State")
@export var missile_scene: PackedScene = preload("res://scenes/missile.tscn")
@export_node_path("Node2D") var missile_left_path: NodePath = NodePath("MissileLeft")
@export_node_path("Node2D") var missile_right_path: NodePath = NodePath("MissileRight")
@export var missile_total_beats: int = 3
@export var missile_phase1_beats: int = 1
@export var missile_phase2_beats: int = 2
@export_range(0.1, 3.0, 0.05) var missile_dash_beats: float = 1.0
@export_range(0.0, 0.8, 0.01) var missile_lock_approach_ratio: float = 0.18
@export_range(0.5, 1.0, 0.01) var missile_lock_scale_factor: float = 0.86
@export_range(1.0, 1.8, 0.01) var missile_dash_scale_factor: float = 1.12
@export var enable_pre_missile_return: bool = false
@export var missile_outward_distance: float = 1200.0
@export_range(0.0, 200.0, 1.0) var missile_launcher_recoil_distance: float = 24.0
@export_range(0.01, 0.5, 0.01) var missile_launcher_recoil_out_duration: float = 0.06
@export_range(0.01, 0.8, 0.01) var missile_launcher_recoil_return_duration: float = 0.14
@export var missile_warning_enabled: bool = true
@export var missile_warning_light_color: Color = Color(1.0, 0.12, 0.12, 1.0)
@export_range(0.05, 1.0, 0.01) var missile_warning_peak_alpha: float = 0.9
@export_range(0.05, 0.9, 0.01) var missile_warning_flash_ratio: float = 0.2
@export_range(0.2, 4.0, 0.01) var missile_warning_light_scale: float = 1.2
@export_range(4.0, 80.0, 0.5) var missile_warning_radius_px: float = 11.0
@export_range(0.6, 6.0, 0.1) var missile_warning_falloff_power: float = 2.4
@export var missile_warning_additive_blend: bool = true
@export var missile_warning_preview_on_boss: bool = false
@export var missile_warning_preview_offset: Vector2 = Vector2(0.0, -22.0)
@export_group("Missile Barrage")
@export var enable_missile_barrage_mode: bool = true
@export_range(1, 8, 1) var missile_barrage_group_size: int = 4
@export_range(0.1, 4.0, 0.05) var missile_barrage_gather_beats: float = 1.0
@export_range(0.1, 6.0, 0.05) var missile_barrage_attack_beats: float = 2.0
@export var missile_barrage_prep_screen_margin: Vector2 = Vector2(96.0, 72.0)
@export_range(0.5, 3.0, 0.05) var missile_barrage_prep_scale_factor: float = 2.0
@export_range(0.0, 1.0, 0.01) var missile_barrage_spawn_lane_sweep: float = 0.85
@export var debug_missile_timing: bool = false
@export var debug_charge_timing: bool = false

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

@export_group("Part Health")
@export var middle_part_break_damage_threshold: float = 1000.0
@export var left_part_break_damage_threshold: float = 500.0
@export var right_part_break_damage_threshold: float = 500.0
@export var middle_part_hit_damage_multiplier: float = 1.5
@export_range(0, 10, 1) var middle_part_normal_frame: int = 0
@export_range(0, 10, 1) var middle_part_broken_frame: int = 1
@export_range(0, 10, 1) var left_part_normal_frame: int = 0
@export_range(0, 10, 1) var left_part_broken_frame: int = 1
@export_range(0, 10, 1) var right_part_normal_frame: int = 0
@export_range(0, 10, 1) var right_part_broken_frame: int = 1

@export_group("Part Debug Override")
@export var debug_enable_part_state_override: bool = false
@export var debug_middle_part_destroyed: bool = false
@export var debug_left_part_destroyed: bool = false
@export var debug_right_part_destroyed: bool = false

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
var _charge_gun_sprite: AnimatedSprite2D = null
var _charge_light_sprite: AnimatedSprite2D = null
var _charge_bullet_spawn_node: Node2D = null
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
var _pending_charge_beats: float = 0.0
var _charge_animation_started_early: bool = false
var _is_preparing_charge: bool = false
var _pre_charge_target_on_ring: bool = false
var _has_pending_charge_fire: bool = false
var _pending_charge_fire_time: float = 0.0
var _last_charge_request_time: float = -INF
var _pending_missile_beats: int = 0
var _is_preparing_missile: bool = false
var _has_pending_missile_launch: bool = false
var _pending_missile_launch_time: float = 0.0
var _active_missiles: Array[Node2D] = []
var _missile_side_selector: RefCounted = BossMissileSideSelector.new()
var _attack_phase_interrupted: bool = false
var _missile_effect_token: int = 0
var _missile_recoil_state: RefCounted = BossMissileLauncherRecoilState.new()
var _missile_return_arrived_logged: bool = false
var _last_missile_despawn_position: Vector2 = Vector2.ZERO
var _has_last_missile_despawn_position: bool = false
var _missile_warning_style: RefCounted = BossMissileWarningLightStyle.new()
var _missile_warning_preview_light: Sprite2D = null
var _missile_warning_preview_token: int = 0
var _pending_missile_barrage_group_index: int = -1
var _missile_barrage_spawn_by_group: Dictionary = {}
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
var _charge_bullet_fired_this_cycle: bool = false
var _charge_sfx_played_in_cycle: bool = false
var _active_charge_bullet: Node2D = null
var _charge_cycle_id: int = 0
var _charge_play_call_count: int = 0
var _charge_animation_started_in_cycle: bool = false
var _part_health: RefCounted = BossPartHealthModel.new()
var _boss_attack_beat_index: Dictionary = {}
var _boss_attack_sound_token: int = 0
var _music_player: Node = null
var _music_clock_events: RefCounted = MusicClockEventQueue.new()
var _waiting_for_intro: bool = false
var _debug_last_override_enabled: bool = false
var _debug_last_middle_destroyed: bool = false
var _debug_last_left_destroyed: bool = false
var _debug_last_right_destroyed: bool = false

const MISSILE_EFFECT_GROUP: StringName = &"boss_missile_effect"
const PLAYER_DASH_AFTERIMAGE_GROUP: StringName = &"player_dash_afterimage"
const ENEMY_HURTBOX_GROUP: StringName = &"enemy_hurtbox"
const CHARGE_START_FRAME: int = 2
const BOSS_PART_NONE: int = -1
const BOSS_PART_MIDDLE: int = 0
const BOSS_PART_LEFT: int = 1
const BOSS_PART_RIGHT: int = 2
const HURTBOX_RESTORE_META_KEY: StringName = &"boss_part_hurtbox_restore_group"
const MISSILE_SIDE_LEFT: int = 0
const MISSILE_SIDE_RIGHT: int = 1
const MISSILE_BARRAGE_CENTER_BAND_MIN: float = 1.0 / 3.0
const MISSILE_BARRAGE_CENTER_BAND_MAX: float = 2.0 / 3.0


func _ready() -> void:
	_rng.randomize()
	_spawn_position = global_position
	_resolve_animation_nodes()
	_resolve_aim_nodes()
	_resolve_music_player()
	_reset_part_health()
	_connect_global_signals()

	if not EventBus.boss_intro_completed:
		_waiting_for_intro = true
		if not EventBus.boss_intro_finished.is_connected(_on_boss_intro_finished):
			EventBus.boss_intro_finished.connect(_on_boss_intro_finished)
	else:
		_set_state(initial_state)


func _on_boss_intro_finished() -> void:
	if not _waiting_for_intro:
		return
	_waiting_for_intro = false
	_set_state(initial_state)


func _process(delta: float) -> void:
	_update_attack_hit_flash(delta)
	_apply_debug_part_state_override_if_needed()
	_update_missile_warning_preview()
	_process_music_clock_events(_get_now_seconds())

	if _waiting_for_intro:
		return

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
	var charge_root: Node2D = get_node_or_null("Charge") as Node2D
	_charge_gun_sprite = get_node_or_null("Charge/ChargeGun") as AnimatedSprite2D
	if _charge_gun_sprite == null:
		_charge_gun_sprite = get_node_or_null("ChargeGun") as AnimatedSprite2D
	_charge_light_sprite = get_node_or_null("Charge/ChargeLight") as AnimatedSprite2D
	if _charge_light_sprite == null:
		_charge_light_sprite = get_node_or_null("ChargeLight") as AnimatedSprite2D
	if not charge_bullet_spawn_path.is_empty():
		_charge_bullet_spawn_node = get_node_or_null(charge_bullet_spawn_path) as Node2D
	if _charge_bullet_spawn_node == null:
		_charge_bullet_spawn_node = get_node_or_null("Charge/BulletPoint") as Node2D
	if _charge_bullet_spawn_node == null:
		_charge_bullet_spawn_node = get_node_or_null("BulletPoint") as Node2D
	if _charge_node == null:
		_charge_node = charge_root
	if _charge_node == null:
		_charge_node = _charge_gun_sprite
	if _charge_anim_sprite == null:
		_charge_anim_sprite = _charge_gun_sprite
	if _charge_anim_sprite == null:
		_charge_anim_sprite = _charge_light_sprite
	if not missile_left_path.is_empty():
		_missile_left_node = get_node_or_null(missile_left_path) as Node2D
	if not missile_right_path.is_empty():
		_missile_right_node = get_node_or_null(missile_right_path) as Node2D
	_cache_missile_launcher_origin(_missile_left_node)
	_cache_missile_launcher_origin(_missile_right_node)

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


func _resolve_music_player() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var game_manager: Node = scene_root.get_node_or_null("GameManager")
		if game_manager != null:
			_music_player = game_manager.get_node_or_null("MusicPlayer")
		if _music_player == null:
			_music_player = scene_root.find_child("MusicPlayer", true, false)

	if _music_player == null:
		var parent_node: Node = get_parent()
		if parent_node != null:
			_music_player = parent_node.get_node_or_null("GameManager/MusicPlayer")


func _play_boss_attack_sound(attack_type: int) -> void:
	if GameConfigs.sound == null or GameConfigs.sound.boss_sounds == null:
		return
	var beat_index: int = int(_boss_attack_beat_index.get(attack_type, 0))
	var pool: RandomSoundPool = GameConfigs.sound.boss_sounds.get_sound_for_beat(attack_type, beat_index)
	if pool == null:
		return
	var cfg: BossAttackTypeSoundConfig = GameConfigs.sound.boss_sounds.get_config(attack_type)
	var bus: StringName = cfg.sfx_bus if cfg != null else &"SFX"
	var time_offset: float = cfg.get_time_offset_for_beat(beat_index) if cfg != null else 0.0
	SFXManager.play_pool(pool, bus, time_offset)
	_boss_attack_beat_index[attack_type] = beat_index + 1


func _schedule_boss_attack_sound_from_sprite(attack_type: int, sprite: AnimatedSprite2D) -> void:
	if GameConfigs.sound == null or GameConfigs.sound.boss_sounds == null:
		return
	if sprite == null or sprite.sprite_frames == null:
		_play_boss_attack_sound(attack_type)
		return

	var anim_name: String = String(sprite.animation)
	if anim_name.is_empty() or not sprite.sprite_frames.has_animation(anim_name):
		_play_boss_attack_sound(attack_type)
		return

	var frame_count: int = sprite.sprite_frames.get_frame_count(anim_name)
	if frame_count <= 0:
		_play_boss_attack_sound(attack_type)
		return

	var cfg: BossAttackTypeSoundConfig = GameConfigs.sound.boss_sounds.get_config(attack_type)
	if cfg == null:
		_play_boss_attack_sound(attack_type)
		return

	var start_frame: int = clampi(sprite.frame, 0, frame_count - 1)
	var default_pool: RandomSoundPool = cfg.default_sound
	var trigger_frame: int = start_frame
	if default_pool != null and not default_pool.is_empty() and default_pool.sounds.size() > 0:
		var first_entry: SoundEntry = default_pool.sounds[0]
		if first_entry != null:
			trigger_frame = clampi(int(first_entry.time_offset * 60.0), start_frame, frame_count - 1)

	var delay: float = 0.0
	if trigger_frame > start_frame:
		delay = SpriteAnimationDuration.get_duration(sprite.sprite_frames, anim_name, start_frame, trigger_frame - 1)
		delay /= maxf(0.01, sprite.speed_scale)

	if delay <= 0.001:
		_play_boss_attack_sound(attack_type)
		return

	var token: int = _boss_attack_sound_token
	_schedule_music_clock_event(_get_now_seconds() + delay, Callable(self, "_on_boss_attack_sound_time"), [token, attack_type])


func _on_boss_attack_sound_time(token: int, attack_type: int) -> void:
	if token != _boss_attack_sound_token:
		return
	if is_dead or _attack_phase_interrupted:
		return
	_play_boss_attack_sound(attack_type)


func _find_timing_sprite(root: Node) -> AnimatedSprite2D:
	if root == null:
		return null
	if root is AnimatedSprite2D:
		return root as AnimatedSprite2D
	return root.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D


func _invalidate_boss_attack_sounds() -> void:
	_boss_attack_sound_token += 1
	_boss_attack_beat_index.clear()
	SFXManager.invalidate_delayed()


func _connect_global_signals() -> void:
	if not EventBus.boss_defeated.is_connected(_on_boss_defeated):
		EventBus.boss_defeated.connect(_on_boss_defeated)
	if not EventBus.boss_energy_depleted.is_connected(_on_boss_energy_depleted):
		EventBus.boss_energy_depleted.connect(_on_boss_energy_depleted)
	if not EventBus.boss_break_intro_started.is_connected(_on_boss_break_intro_started):
		EventBus.boss_break_intro_started.connect(_on_boss_break_intro_started)
	if not EventBus.boss_charge_requested.is_connected(_on_boss_charge_requested):
		EventBus.boss_charge_requested.connect(_on_boss_charge_requested)
	if not EventBus.boss_missile_requested.is_connected(_on_boss_missile_requested):
		EventBus.boss_missile_requested.connect(_on_boss_missile_requested)
	if not EventBus.attack_phase_started.is_connected(_on_attack_phase_started):
		EventBus.attack_phase_started.connect(_on_attack_phase_started)
	if not EventBus.attack_phase_ended.is_connected(_on_attack_phase_ended):
		EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not EventBus.attack_hit_resolved.is_connected(_on_attack_hit_resolved):
		EventBus.attack_hit_resolved.connect(_on_attack_hit_resolved)
	if not EventBus.judgment_made.is_connected(_on_judgment_made):
		EventBus.judgment_made.connect(_on_judgment_made)
	if not EventBus.show_return_countdown_requested.is_connected(_on_show_return_countdown_requested):
		EventBus.show_return_countdown_requested.connect(_on_show_return_countdown_requested)
	if not EventBus.player_died.is_connected(_on_player_died):
		EventBus.player_died.connect(_on_player_died)


func _on_judgment_made(_track: int, judgment: int, _timing_diff: float) -> void:
	# 仅在成功判定（非 MISS）瞬间静音 Boss 攻击音效，避免覆盖按键反馈音。
	if judgment == 3:
		return
	_invalidate_boss_attack_sounds()


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
			if not _charge_sfx_played_in_cycle:
				_charge_sfx_played_in_cycle = true
				_play_boss_attack_sound(BossAttackSoundConfig.ATTACK_CHARGE_WINDUP)
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
		# 已到原点后保持待机，等待预约发射时刻。
		if debug_missile_timing and _is_preparing_missile and not _missile_return_arrived_logged:
			print("[MissileDebug][Boss] arrived origin pos=", global_position,
				" spawn=", _spawn_position,
				" pending_s=", "%.3f" % maxf(0.0, _pending_missile_launch_time - _get_now_seconds()))
			_missile_return_arrived_logged = true
		return

	var return_speed: float = move_speed
	if _has_pending_missile_launch:
		var remaining: float = maxf(0.0, _pending_missile_launch_time - _get_now_seconds())
		if remaining > 0.0:
			var distance_to_target: float = maxf(0.0, global_position.distance_to(_move_target) - target_reach_distance)
			if distance_to_target > 0.0:
				var required_speed: float = distance_to_target / maxf(0.0001, remaining)
				# 按剩余时间精确求速，避免提前到达原点。
				return_speed = maxf(0.0, required_speed)

	if _move_towards_current_target_with_speed(delta, return_speed):
		_has_move_target = false
		if debug_missile_timing:
			print("[MissileDebug][Boss] reached origin by move pos=", global_position,
				" speed=", "%.3f" % return_speed,
				" pending_s=", "%.3f" % maxf(0.0, _pending_missile_launch_time - _get_now_seconds()))
		_missile_return_arrived_logged = true
		# 到达原点后继续保持 PRE_MISSILE_RETURN，直到预约发射时刻到达。


func _move_towards_current_target(delta: float) -> bool:
	return _move_towards_current_target_with_speed(delta, move_speed)


func _move_towards_current_target_with_speed(delta: float, speed: float) -> bool:
	var to_target: Vector2 = _move_target - global_position
	var distance: float = to_target.length()
	if distance <= target_reach_distance:
		global_position = _move_target
		return true

	var move_step: Vector2 = to_target.normalized() * maxf(0.0, speed) * delta
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
	_try_fire_charge_bullet()


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


func _play_charge_animation(target_duration_sec: float = -1.0) -> void:
	if _charge_animation_started_in_cycle:
		if debug_charge_timing:
			print("[ChargeDebug][Boss] play skipped cycle=", _charge_cycle_id,
				" reason=already_started",
				" state=", BossState.keys()[current_state],
				" remaining_s=", "%.3f" % _charge_state_remaining_time)
		return
	_charge_play_call_count += 1
	if debug_charge_timing:
		print("[ChargeDebug][Boss] play cycle=", _charge_cycle_id,
			" call=", _charge_play_call_count,
			" state=", BossState.keys()[current_state],
			" remaining_s=", "%.3f" % _charge_state_remaining_time)
	var target_duration: float = maxf(0.01, _charge_state_remaining_time)
	if target_duration_sec > 0.0:
		target_duration = maxf(0.01, target_duration_sec)
	var visual_duration: float = 0.0
	var has_playable_charge_anim: bool = false
	for charge_sprite in _get_charge_anim_sprites():
		var played_duration: float = _play_single_charge_sprite(charge_sprite, target_duration)
		if played_duration > 0.0:
			has_playable_charge_anim = true
			visual_duration = maxf(visual_duration, played_duration)

	if has_playable_charge_anim:
		_charge_animation_started_in_cycle = true
		_charge_visual_remaining_time = maxf(target_duration, visual_duration)
	else:
		_charge_visual_remaining_time = 0.0


func _stop_charge_animation() -> void:
	if debug_charge_timing and _charge_cycle_id > 0:
		print("[ChargeDebug][Boss] stop cycle=", _charge_cycle_id,
			" visual_remaining_s=", "%.3f" % _charge_visual_remaining_time,
			" state=", BossState.keys()[current_state])
	for charge_sprite in _get_charge_anim_sprites():
		if charge_sprite == null:
			continue
		if charge_sprite.sprite_frames != null:
			var stop_anim_name: StringName = _resolve_charge_animation_name(charge_sprite.sprite_frames)
			if not stop_anim_name.is_empty():
				var frame_count: int = charge_sprite.sprite_frames.get_frame_count(stop_anim_name)
				var last_frame: int = frame_count - 1
				if last_frame >= 0:
					charge_sprite.frame = last_frame
					charge_sprite.frame_progress = 0.0
		charge_sprite.stop()
		charge_sprite.speed_scale = 1.0
	_clear_active_charge_bullet()
	_charge_visual_remaining_time = 0.0


func _get_charge_anim_sprites() -> Array[AnimatedSprite2D]:
	var sprites: Array[AnimatedSprite2D] = []
	if _charge_anim_sprite != null:
		sprites.append(_charge_anim_sprite)
	if _charge_gun_sprite != null and not sprites.has(_charge_gun_sprite):
		sprites.append(_charge_gun_sprite)
	if _charge_light_sprite != null and not sprites.has(_charge_light_sprite):
		sprites.append(_charge_light_sprite)
	return sprites


func _resolve_charge_animation_name(sprite_frames: SpriteFrames) -> StringName:
	if sprite_frames == null:
		return StringName()
	if sprite_frames.has_animation(charge_animation_name):
		return charge_animation_name
	if sprite_frames.has_animation(&"default"):
		return &"default"
	return StringName()


func _play_single_charge_sprite(charge_sprite: AnimatedSprite2D, target_duration: float) -> float:
	if charge_sprite == null:
		return 0.0
	if charge_sprite.sprite_frames == null:
		return 0.0

	var sprite_frames: SpriteFrames = charge_sprite.sprite_frames
	var anim_name: StringName = _resolve_charge_animation_name(sprite_frames)
	if anim_name.is_empty():
		push_warning("[Boss] Charge 贴图缺少动画: %s / default" % String(charge_animation_name))
		return 0.0

	var anim_name_text: String = String(anim_name)
	var frame_count: int = sprite_frames.get_frame_count(anim_name_text)
	if frame_count <= 0:
		return 0.0

	var start_frame: int = mini(CHARGE_START_FRAME, frame_count - 1)
	var attack_end_frame: int = _get_charge_attack_end_frame(frame_count)
	if attack_end_frame < start_frame:
		attack_end_frame = start_frame

	# 对齐规则：提前三拍开播，从序列 2 起播；音符到判定线时对齐 attack_end_frame。
	var base_duration: float = 0.0
	if attack_end_frame > start_frame:
		base_duration = SpriteAnimationDuration.get_duration(sprite_frames, anim_name_text, start_frame, attack_end_frame - 1)
	if base_duration > 0.0:
		charge_sprite.speed_scale = base_duration / target_duration
	else:
		charge_sprite.speed_scale = 1.0

	var full_base_duration: float = SpriteAnimationDuration.get_duration(sprite_frames, anim_name_text, start_frame, frame_count - 1)
	var played_duration: float = target_duration
	if charge_sprite.speed_scale > 0.0 and full_base_duration > 0.0:
		played_duration = full_base_duration / charge_sprite.speed_scale

	charge_sprite.visible = true
	charge_sprite.stop()
	charge_sprite.play(anim_name)
	charge_sprite.frame = start_frame
	charge_sprite.frame_progress = 0.0
	return played_duration


func _update_charge_visual_timer(delta: float) -> void:
	if _charge_visual_remaining_time <= 0.0:
		return
	_try_fire_charge_bullet()
	_charge_visual_remaining_time = maxf(0.0, _charge_visual_remaining_time - delta)
	if _charge_visual_remaining_time <= 0.0:
		_stop_charge_animation()


func _try_fire_charge_bullet() -> void:
	if _charge_bullet_fired_this_cycle:
		return
	if charge_bullet_scene == null:
		return
	if not BossChargeBulletTiming.are_frame_markers_valid(
		charge_bullet_fire_frame,
		charge_bullet_move_start_frame,
		charge_bullet_hit_frame,
		charge_bullet_despawn_frame
	):
		return

	var timing_sprite: AnimatedSprite2D = _get_charge_timing_sprite()
	if timing_sprite == null:
		return
	if timing_sprite.frame < charge_bullet_fire_frame:
		return

	var wait_duration: float = BossChargeBulletTiming.get_phase_duration(
		timing_sprite,
		charge_animation_name,
		charge_bullet_fire_frame,
		charge_bullet_move_start_frame,
		0.0
	)
	var travel_duration: float = BossChargeBulletTiming.get_phase_duration(
		timing_sprite,
		charge_animation_name,
		charge_bullet_move_start_frame,
		charge_bullet_hit_frame,
		0.12
	)
	var despawn_delay: float = BossChargeBulletTiming.get_phase_duration(
		timing_sprite,
		charge_animation_name,
		charge_bullet_hit_frame,
		charge_bullet_despawn_frame,
		0.05
	)
	_spawn_charge_bullet(wait_duration, travel_duration, despawn_delay)
	_charge_bullet_fired_this_cycle = true
	_play_boss_attack_sound(BossAttackSoundConfig.ATTACK_CHARGE_BULLET)


func _get_charge_timing_sprite() -> AnimatedSprite2D:
	if _charge_gun_sprite != null:
		return _charge_gun_sprite
	if _charge_anim_sprite != null:
		return _charge_anim_sprite
	if _charge_light_sprite != null:
		return _charge_light_sprite
	return null


func _spawn_charge_bullet(wait_duration: float, travel_duration: float, despawn_delay: float) -> void:
	if _charge_bullet_spawn_node == null:
		_resolve_aim_nodes()
	if _charge_bullet_spawn_node == null:
		push_warning("[Boss] ChargeBullet 缺少 BulletPoint 节点，无法发射")
		return

	if _target_character == null:
		_resolve_aim_nodes()
	if _target_character == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	_clear_active_charge_bullet()

	var bullet: Node2D = charge_bullet_scene.instantiate() as Node2D
	if bullet == null:
		push_warning("[Boss] charge_bullet_scene 不是 Node2D，无法发射")
		return

	scene_root.add_child(bullet)
	if not charge_bullet_use_scene_root_scale:
		bullet.scale = Vector2(
			charge_bullet_instance_scale.x * global_scale.x,
			charge_bullet_instance_scale.y * global_scale.y
		)
	bullet.global_position = _charge_bullet_spawn_node.global_position
	var player_pos: Vector2 = _target_character.global_position
	var to_target: Vector2 = player_pos - bullet.global_position
	var move_dir: Vector2 = Vector2.ZERO
	if to_target.length_squared() > 0.0001:
		move_dir = to_target.normalized()
	else:
		move_dir = Vector2.UP.rotated(bullet.global_rotation)

	var hit_pos: Vector2 = player_pos - move_dir * maxf(0.0, charge_bullet_hit_distance_from_player)
	_active_charge_bullet = bullet

	if move_dir.length_squared() > 0.0001:
		bullet.global_rotation = Vector2.UP.angle_to(move_dir) + PI

	var fly_tween: Tween = bullet.create_tween()
	if wait_duration > 0.0:
		fly_tween.tween_interval(wait_duration)
	fly_tween.tween_property(bullet, "global_position", hit_pos, maxf(0.01, travel_duration)).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	if despawn_delay > 0.0:
		fly_tween.tween_interval(despawn_delay)
	var bullet_instance_id: int = bullet.get_instance_id()
	fly_tween.tween_callback(_on_charge_bullet_fly_finished.bind(bullet_instance_id))


func _on_charge_bullet_fly_finished(bullet_instance_id: int) -> void:
	var bullet_obj: Object = instance_from_id(bullet_instance_id)
	var bullet_node: Node2D = bullet_obj as Node2D
	if bullet_node != null and is_instance_valid(bullet_node):
		bullet_node.queue_free()
	if _active_charge_bullet == bullet_node:
		_active_charge_bullet = null


func _clear_active_charge_bullet() -> void:
	if _active_charge_bullet != null and is_instance_valid(_active_charge_bullet):
		_active_charge_bullet.queue_free()
	_active_charge_bullet = null


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
	_invalidate_boss_attack_sounds()
	_set_attack_hint_flash_active(false)
	_reset_attack_hit_visuals()
	_stop_break_transition()
	_attack_phase_interrupted = false
	_reset_charge_flow(false, false)
	_reset_missile_flow(true)
	_set_visual_frame(_middle_body_visual, middle_part_broken_frame)
	_set_visual_frame(_left_missile_visual, left_part_broken_frame)
	_set_visual_frame(_right_missile_visual, right_part_broken_frame)


func _on_attack_phase_started() -> void:
	_invalidate_boss_attack_sounds()
	_set_attack_hint_flash_active(true)
	_stop_return_to_origin_transition()
	_interrupt_for_attack_phase(BossState.BROKEN)
	_play_shield_break_sound_delayed()


func _on_boss_energy_depleted() -> void:
	_stop_return_to_origin_transition()
	_interrupt_for_attack_phase(BossState.BROKEN)
	_start_shield_break_transition()


func _on_boss_break_intro_started() -> void:
	_stop_return_to_origin_transition()
	_interrupt_for_attack_phase(BossState.BROKEN)
	_start_shield_break_transition()


func _interrupt_for_attack_phase(target_state: BossState = BossState.IDLE) -> void:
	if is_dead:
		return

	_invalidate_boss_attack_sounds()
	_attack_phase_interrupted = true
	_reset_charge_flow(false, false)
	_reset_missile_flow(true)
	_has_move_target = false
	_set_state(target_state)


func _on_attack_phase_ended() -> void:
	if is_dead:
		return

	_invalidate_boss_attack_sounds()
	_set_attack_hint_flash_active(false)
	_reset_attack_hit_visuals()

	_stop_break_transition()
	_stop_return_to_origin_transition()
	_attack_phase_interrupted = false
	_reset_charge_flow(false, false)
	_reset_missile_flow(true)

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
	_invalidate_boss_attack_sounds()
	_attack_phase_interrupted = true
	_has_move_target = false
	_reset_charge_flow(false, false)
	_reset_missile_flow(true)
	set_process(false)


func _on_attack_hit_resolved(applied_damage: float, target: Variant) -> void:
	if target == null:
		return
	if applied_damage <= 0.0:
		return

	var target_node: Node = target as Node
	if target_node == null:
		return

	var hit_visual: CanvasItem = _resolve_hit_visual_target(target_node)
	if hit_visual == null:
		return

	var hit_part: int = _get_part_from_visual(hit_visual)
	if hit_part == BOSS_PART_NONE:
		return
	if _is_part_destroyed(hit_part):
		return

	if hit_visual == _middle_body_visual:
		_middle_red_flash_remaining = maxf(_middle_red_flash_remaining, hit_red_flash_duration)
	elif hit_visual == _left_missile_visual:
		_left_red_flash_remaining = maxf(_left_red_flash_remaining, hit_red_flash_duration)
	elif hit_visual == _right_missile_visual:
		_right_red_flash_remaining = maxf(_right_red_flash_remaining, hit_red_flash_duration)

	_apply_damage_to_part(hit_part, applied_damage)


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
	_apply_single_visual_color(_middle_body_visual, _get_part_flash_color(BOSS_PART_MIDDLE, _middle_red_flash_remaining, normal_color, hit_red_color))
	_apply_single_visual_color(_left_missile_visual, _get_part_flash_color(BOSS_PART_LEFT, _left_red_flash_remaining, normal_color, hit_red_color))
	_apply_single_visual_color(_right_missile_visual, _get_part_flash_color(BOSS_PART_RIGHT, _right_red_flash_remaining, normal_color, hit_red_color))


func _get_part_flash_color(part: int, red_flash_remaining: float, normal_flash_color: Color, red_flash_color: Color) -> Color:
	if _is_part_destroyed(part):
		# 破坏后不参与红闪/白闪，保持基础显示。
		return Color(1.0, 1.0, 1.0, 1.0)
	if red_flash_remaining > 0.0:
		return red_flash_color
	return normal_flash_color


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

	var cursor: Node = target_node
	while cursor != null:
		if cursor == _middle_body_visual:
			return _middle_body_visual
		if cursor == _left_missile_visual:
			return _left_missile_visual
		if cursor == _right_missile_visual:
			return _right_missile_visual
		cursor = cursor.get_parent()

	if _middle_body_visual != null and _middle_body_visual.is_ancestor_of(target_node):
		return _middle_body_visual
	if _left_missile_visual != null and _left_missile_visual.is_ancestor_of(target_node):
		return _left_missile_visual
	if _right_missile_visual != null and _right_missile_visual.is_ancestor_of(target_node):
		return _right_missile_visual
	return null


func _set_visual_frame(visual: CanvasItem, frame_index: int) -> void:
	if visual == null:
		return

	if visual is AnimatedSprite2D:
		var animated_visual: AnimatedSprite2D = visual as AnimatedSprite2D
		if animated_visual != null:
			animated_visual.pause()
			animated_visual.frame = maxi(0, frame_index)
		return

	if visual is Sprite2D:
		var sprite_visual: Sprite2D = visual as Sprite2D
		if sprite_visual != null:
			sprite_visual.frame = maxi(0, frame_index)


func _reset_part_visual_frames() -> void:
	_set_visual_frame(_middle_body_visual, middle_part_normal_frame)
	_set_visual_frame(_left_missile_visual, left_part_normal_frame)
	_set_visual_frame(_right_missile_visual, right_part_normal_frame)


func _get_part_from_visual(hit_visual: CanvasItem) -> int:
	if hit_visual == _middle_body_visual:
		return BOSS_PART_MIDDLE
	if hit_visual == _left_missile_visual:
		return BOSS_PART_LEFT
	if hit_visual == _right_missile_visual:
		return BOSS_PART_RIGHT
	return BOSS_PART_NONE


func _is_part_destroyed(part: int) -> bool:
	return _part_health.is_destroyed(part)


func _apply_damage_to_part(part: int, damage: float) -> void:
	if _part_health.apply_damage(part, damage):
		_on_part_destroyed(part)


func _on_part_destroyed(part: int) -> void:
	if part == BOSS_PART_MIDDLE:
		_set_visual_frame(_middle_body_visual, middle_part_broken_frame)
		_middle_red_flash_remaining = 0.0
		_set_part_hurtbox_active(BOSS_PART_MIDDLE, false)
		return

	if part == BOSS_PART_LEFT:
		_set_visual_frame(_left_missile_visual, left_part_broken_frame)
		_left_red_flash_remaining = 0.0
		_set_part_hurtbox_active(BOSS_PART_LEFT, false)
	elif part == BOSS_PART_RIGHT:
		_set_visual_frame(_right_missile_visual, right_part_broken_frame)
		_right_red_flash_remaining = 0.0
		_set_part_hurtbox_active(BOSS_PART_RIGHT, false)

	if _are_missile_parts_all_destroyed():
		_cancel_missile_flow_after_parts_broken()


func _apply_debug_part_state_override_if_needed() -> void:
	var changed: bool = false
	if _debug_last_override_enabled != debug_enable_part_state_override:
		changed = true
	if _debug_last_middle_destroyed != debug_middle_part_destroyed:
		changed = true
	if _debug_last_left_destroyed != debug_left_part_destroyed:
		changed = true
	if _debug_last_right_destroyed != debug_right_part_destroyed:
		changed = true

	if not changed:
		return

	_debug_last_override_enabled = debug_enable_part_state_override
	_debug_last_middle_destroyed = debug_middle_part_destroyed
	_debug_last_left_destroyed = debug_left_part_destroyed
	_debug_last_right_destroyed = debug_right_part_destroyed

	if not debug_enable_part_state_override:
		return

	_set_part_destroyed_for_debug(BOSS_PART_MIDDLE, debug_middle_part_destroyed)
	_set_part_destroyed_for_debug(BOSS_PART_LEFT, debug_left_part_destroyed)
	_set_part_destroyed_for_debug(BOSS_PART_RIGHT, debug_right_part_destroyed)


func _set_part_destroyed_for_debug(part: int, destroyed: bool) -> void:
	if not _part_health.set_destroyed_for_debug(part, destroyed):
		return

	if destroyed:
		_on_part_destroyed(part)
		return

	if part == BOSS_PART_MIDDLE:
		_set_visual_frame(_middle_body_visual, middle_part_normal_frame)
		_middle_red_flash_remaining = 0.0
		_set_part_hurtbox_active(BOSS_PART_MIDDLE, true)
	elif part == BOSS_PART_LEFT:
		_set_visual_frame(_left_missile_visual, left_part_normal_frame)
		_left_red_flash_remaining = 0.0
		_set_part_hurtbox_active(BOSS_PART_LEFT, true)
	elif part == BOSS_PART_RIGHT:
		_set_visual_frame(_right_missile_visual, right_part_normal_frame)
		_right_red_flash_remaining = 0.0
		_set_part_hurtbox_active(BOSS_PART_RIGHT, true)


func _cancel_charge_flow_after_part_broken() -> void:
	_reset_charge_flow(true, true)


func _cancel_missile_flow_after_parts_broken() -> void:
	_reset_missile_flow(true)


func _reset_charge_flow(reset_visual_runtime: bool, clear_active_bullet: bool) -> void:
	_is_preparing_charge = false
	_pending_charge_beats = 0.0
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_charge_state_remaining_time = 0.0
	_charge_bullet_fired_this_cycle = false
	if reset_visual_runtime:
		_charge_visual_remaining_time = 0.0
		_charge_sfx_played_in_cycle = false
	if clear_active_bullet:
		_clear_active_charge_bullet()
	_stop_charge_animation()


func _reset_missile_flow(clear_active_missiles: bool) -> void:
	_is_preparing_missile = false
	_has_pending_missile_launch = false
	_pending_missile_launch_time = 0.0
	_pending_missile_beats = 0
	_missile_state_remaining_time = 0.0
	_pending_missile_barrage_group_index = -1
	_missile_barrage_spawn_by_group.clear()
	_missile_side_selector.clear_forced_sides()
	if clear_active_missiles:
		_clear_active_missiles()


func _are_missile_parts_all_destroyed() -> bool:
	return _part_health.are_missile_parts_all_destroyed()


func _reset_part_health() -> void:
	_part_health.configure(
		middle_part_break_damage_threshold,
		left_part_break_damage_threshold,
		right_part_break_damage_threshold
	)
	_part_health.reset()
	_missile_side_selector.clear_forced_sides()
	_set_part_hurtbox_active(BOSS_PART_MIDDLE, true)
	_set_part_hurtbox_active(BOSS_PART_LEFT, true)
	_set_part_hurtbox_active(BOSS_PART_RIGHT, true)
	_reset_part_visual_frames()


func _get_visual_for_part(part: int) -> CanvasItem:
	if part == BOSS_PART_MIDDLE:
		return _middle_body_visual
	if part == BOSS_PART_LEFT:
		return _left_missile_visual
	if part == BOSS_PART_RIGHT:
		return _right_missile_visual
	return null


func _collect_area_nodes(root_node: Node) -> Array[Area2D]:
	var areas: Array[Area2D] = []
	if root_node == null:
		return areas

	var stack: Array[Node] = [root_node]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Area2D:
			areas.append(node as Area2D)
		for child in node.get_children():
			stack.append(child as Node)

	return areas


func _set_area_collision_shapes_enabled(area: Area2D, enabled: bool) -> void:
	for child in area.get_children():
		if child is CollisionShape2D:
			(child as CollisionShape2D).set_deferred("disabled", not enabled)


func _set_part_hurtbox_active(part: int, enabled: bool) -> void:
	var part_visual: CanvasItem = _get_visual_for_part(part)
	if part_visual == null:
		return

	for area in _collect_area_nodes(part_visual):
		if area == null:
			continue

		if enabled:
			if bool(area.get_meta(HURTBOX_RESTORE_META_KEY, false)):
				if not area.is_in_group(ENEMY_HURTBOX_GROUP):
					area.add_to_group(ENEMY_HURTBOX_GROUP)
				area.set_meta(HURTBOX_RESTORE_META_KEY, false)
			area.set_deferred("monitoring", true)
			area.set_deferred("monitorable", true)
			_set_area_collision_shapes_enabled(area, true)
			continue

		if area.is_in_group(ENEMY_HURTBOX_GROUP):
			area.set_meta(HURTBOX_RESTORE_META_KEY, true)
			area.remove_from_group(ENEMY_HURTBOX_GROUP)
		area.set_deferred("monitoring", false)
		area.set_deferred("monitorable", false)
		_set_area_collision_shapes_enabled(area, false)


func is_middle_part_destroyed() -> bool:
	return _is_part_destroyed(BOSS_PART_MIDDLE)


func are_missile_parts_all_destroyed() -> bool:
	return _are_missile_parts_all_destroyed()


func get_next_missile_turn_side() -> int:
	return _missile_side_selector.get_next_turn_side()


func is_missile_side_destroyed(side: int) -> bool:
	if side == MISSILE_SIDE_LEFT:
		return _is_part_destroyed(BOSS_PART_LEFT)
	if side == MISSILE_SIDE_RIGHT:
		return _is_part_destroyed(BOSS_PART_RIGHT)
	return true


func is_pre_missile_return_enabled() -> bool:
	return enable_pre_missile_return


func consume_missile_turn() -> void:
	_missile_side_selector.consume_turn()


func enqueue_missile_forced_side(side: int) -> void:
	_missile_side_selector.enqueue_forced_side(side)


func set_next_missile_barrage_group_context(group_index: int) -> void:
	_pending_missile_barrage_group_index = group_index


func is_track_attack_visual_active(note_type: int) -> bool:
	if note_type == Note.NoteType.HIT:
		if _are_missile_parts_all_destroyed():
			return false
		if enable_missile_barrage_mode and not _active_missiles.is_empty():
			return true
		if _is_preparing_missile or _has_pending_missile_launch:
			return true
		if _missile_state_remaining_time > 0.0:
			return true
		return current_state == BossState.PRE_MISSILE_RETURN or current_state == BossState.MISSILE_ATTACK

	if note_type == Note.NoteType.DODGE:
		if _is_preparing_charge or _has_pending_charge_fire:
			return true
		if _charge_state_remaining_time > 0.0 or _charge_visual_remaining_time > 0.0:
			return true
		return current_state == BossState.PRE_CHARGE_MOVE or current_state == BossState.CHARGE

	return true


func get_hit_damage_multiplier(target: Variant) -> float:
	var target_node: Node = target as Node
	if target_node == null:
		return 1.0

	var hit_visual: CanvasItem = _resolve_hit_visual_target(target_node)
	if hit_visual == _middle_body_visual and not _is_part_destroyed(BOSS_PART_MIDDLE):
		return maxf(0.0, middle_part_hit_damage_multiplier)

	return 1.0


func _on_boss_charge_requested(duration_beats: float) -> void:
	if is_dead:
		return
	var now: float = _get_now_seconds()

	# 防抖：避免同一时刻重复事件导致蓄力动画重启抖动。
	if now - _last_charge_request_time < maxf(0.0, charge_request_min_interval_sec):
		if debug_charge_timing:
			print("[ChargeDebug][Boss] request ignored by debounce now=", "%.3f" % now,
				" dt=", "%.3f" % (now - _last_charge_request_time))
		return

	# 防重入：正在蓄力或已有待触发蓄力时，忽略新请求，避免动画二连/加速。
	if current_state == BossState.CHARGE or _charge_state_remaining_time > 0.0 or _has_pending_charge_fire:
		if debug_charge_timing:
			print("[ChargeDebug][Boss] request ignored by reentry state=", BossState.keys()[current_state],
				" charge_remaining_s=", "%.3f" % _charge_state_remaining_time,
				" pending_fire=", _has_pending_charge_fire)
		return

	_last_charge_request_time = now

	var lead_beats: float = duration_beats
	if lead_beats <= 0.0:
		lead_beats = float(charge_duration_beats)
	lead_beats = maxf(0.0, lead_beats)
	if debug_charge_timing:
		print("[ChargeDebug][Boss] request accepted lead_beats=", "%.3f" % lead_beats,
			" now=", "%.3f" % now,
			" state=", BossState.keys()[current_state])

	var beat_seconds: float = _get_beat_seconds()

	_charge_state_remaining_time = 0.0
	# 蓄力动画播放时长保持固定，避免因请求剩余拍数波动导致时快时慢。
	_pending_charge_beats = float(maxi(1, charge_duration_beats))
	_charge_animation_started_in_cycle = false
	_charge_animation_started_early = false
	_charge_sfx_played_in_cycle = false
	var requested_fire_time: float = now + float(lead_beats) * beat_seconds
	var windup_time: float = _pending_charge_beats * beat_seconds
	# duration_beats 表示离“应命中时刻”的提前量；charge 需要提前进入蓄力。
	_pending_charge_fire_time = requested_fire_time - windup_time
	if _pending_charge_fire_time < now:
		_pending_charge_fire_time = now
	_has_pending_charge_fire = true
	_is_preparing_charge = false
	if lead_beats > _pending_charge_beats:
		_charge_animation_started_early = true
		_play_charge_animation(lead_beats * beat_seconds)
	if debug_charge_timing:
		print("[ChargeDebug][Boss] schedule fire_time=", "%.3f" % _pending_charge_fire_time,
			" windup_s=", "%.3f" % windup_time)

	# 若请求即刻发射，直接进入 charge。
	if lead_beats <= 0.0 or _pending_charge_fire_time <= now:
		_has_pending_charge_fire = false
		_begin_charge_attack(_pending_charge_beats)


func _on_boss_missile_requested(duration_beats: float) -> void:
	if is_dead:
		return
	if _are_missile_parts_all_destroyed():
		if debug_missile_timing:
			print("[MissileDebug][Boss] request ignored reason=both_missile_parts_destroyed")
		return

	if enable_missile_barrage_mode:
		_request_missile_barrage_member(duration_beats)
		return

	request_legacy_missile_attack(duration_beats)


func request_legacy_missile_attack(duration_beats: float) -> void:
	if is_dead:
		return
	if _are_missile_parts_all_destroyed():
		if debug_missile_timing:
			print("[MissileDebug][Boss] request ignored reason=both_missile_parts_destroyed")
		return

	var beats: float = duration_beats
	if beats <= 0.0:
		beats = float(missile_total_beats)
	beats = maxf(0.0, beats)

	_pending_missile_beats = maxi(1, int(ceili(beats)))
	_missile_return_arrived_logged = false

	var beat_seconds: float = _get_beat_seconds()

	# duration_beats 语义：距命中剩余拍数。发射到命中耗时=phase1+phase2。
	var flight_beats: float = float(maxi(1, missile_phase1_beats) + maxi(1, missile_phase2_beats))
	var launch_lead_beats: float = maxf(0.0, beats - flight_beats)
	if debug_missile_timing:
		print("[MissileDebug][Boss] request recv beats=", "%.3f" % beats,
			" flight_beats=", "%.3f" % flight_beats,
			" lead_beats=", "%.3f" % launch_lead_beats,
			" pos=", global_position,
			" spawn=", _spawn_position)

	if launch_lead_beats <= 0.0:
		_has_pending_missile_launch = false
		_pending_missile_launch_time = 0.0
		_is_preparing_missile = false
		_launch_missile_attack_now()
		return

	_has_pending_missile_launch = true
	_pending_missile_launch_time = _get_now_seconds() + float(launch_lead_beats) * beat_seconds
	if enable_pre_missile_return:
		_move_target = _spawn_position
		_has_move_target = global_position.distance_to(_move_target) > target_reach_distance
		_is_preparing_missile = true
	else:
		_has_move_target = false
		_is_preparing_missile = false
	if debug_missile_timing:
		print("[MissileDebug][Boss] schedule launch_at=", "%.3f" % _pending_missile_launch_time,
			" move_target=", _move_target,
			" need_move=", _has_move_target,
			" pre_return_enabled=", enable_pre_missile_return)


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

	var selection: Dictionary = BossPreChargeTargetPicker.pick(
		global_position,
		_target_character.global_position,
		_spawn_position,
		max_move_left,
		max_move_right,
		max_move_up,
		max_move_down,
		pre_charge_distance_from_player,
		pre_charge_pick_attempts
	)
	_pre_charge_target_on_ring = bool(selection.get("found_on_ring", false))
	var target: Vector2 = selection.get("target", global_position)
	_move_target = target
	_has_move_target = global_position.distance_to(_move_target) > target_reach_distance
	return true


func _prepare_pre_missile_return_target() -> bool:
	_move_target = _spawn_position
	if global_position.distance_to(_move_target) <= target_reach_distance:
		_has_move_target = false
		return false

	_has_move_target = true
	return true


func _request_missile_barrage_member(duration_beats: float) -> void:
	if missile_scene == null:
		push_warning("[Boss] missile_scene is not configured")
		return

	var now: float = _get_now_seconds()
	var beat_seconds: float = _get_beat_seconds()
	var total_beats: float = duration_beats
	if total_beats <= 0.0:
		total_beats = maxf(0.1, missile_barrage_gather_beats) + maxf(0.1, missile_barrage_attack_beats)
	total_beats = maxf(0.1, total_beats)
	var total_duration: float = maxf(0.01, total_beats * beat_seconds)
	var attack_duration: float = maxf(0.01, maxf(0.1, missile_barrage_attack_beats) * beat_seconds)
	attack_duration = minf(attack_duration, total_duration)
	var gather_duration: float = maxf(0.0, total_duration - attack_duration)

	var member: Dictionary = _spawn_missile_barrage_member(now, duration_beats, gather_duration)
	if member.is_empty():
		return

	var group_index: int = _pending_missile_barrage_group_index
	_pending_missile_barrage_group_index = -1
	var token: int = int(member.get("token", _missile_effect_token))
	var launch_side: int = int(member.get("launch_side", MISSILE_SIDE_LEFT))
	var attack_spawn_position: Vector2 = _get_missile_barrage_attack_spawn_position(group_index, launch_side)
	var start_time: float = now + gather_duration
	_schedule_music_clock_event(start_time, Callable(self, "_spawn_missile_barrage_dash_from_prep"), [token, attack_spawn_position, attack_duration])
	_missile_state_remaining_time = maxf(_missile_state_remaining_time, total_duration)

	if debug_missile_timing:
		print("[MissileDebug][Boss] barrage launch now=", "%.3f" % now,
			" total_beats=", "%.3f" % total_beats,
			" gather_s=", "%.3f" % gather_duration,
			" attack_s=", "%.3f" % attack_duration,
			" remain_beats=", "%.3f" % duration_beats)


func _spawn_missile_barrage_member(_launch_time: float, _duration_beats: float, gather_duration: float) -> Dictionary:
	var launch_node: Node2D = _pick_missile_launch_node()
	if launch_node == null:
		push_warning("[Boss] missing MissileLeft/MissileRight node; cannot launch missile")
		return {}

	var missile: Node2D = missile_scene.instantiate() as Node2D
	if missile == null:
		push_warning("[Boss] missile_scene is not a Node2D; cannot launch missile")
		return {}

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		missile.queue_free()
		return {}

	scene_root.add_child(missile)
	missile.add_to_group(MISSILE_EFFECT_GROUP)
	missile.global_position = launch_node.global_position
	_active_missiles.append(missile)
	_attach_missile_warning_light(missile)
	_start_missile_warning_blink(missile, _missile_effect_token)
	_schedule_boss_attack_sound_from_sprite(BossAttackSoundConfig.ATTACK_MISSILE, _find_timing_sprite(missile))

	var outward_dir: Vector2 = _get_missile_outward_direction(launch_node).normalized()
	var launch_exit_target: Vector2 = _get_missile_offscreen_target(missile.global_position, outward_dir)
	var safe_gather_duration: float = maxf(0.01, gather_duration)
	var base_scale: Vector2 = missile.scale

	_play_missile_launcher_recoil(launch_node, outward_dir)
	_orient_missile_to_direction(missile, outward_dir)

	var missile_instance_id: int = missile.get_instance_id()
	var token: int = _missile_effect_token
	var gather_tween: Tween = missile.create_tween()
	gather_tween.tween_property(missile, "global_position", launch_exit_target, safe_gather_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	gather_tween.parallel().tween_property(missile, "scale", base_scale * missile_barrage_prep_scale_factor, safe_gather_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	gather_tween.tween_callback(_on_missile_barrage_prep_arrived.bind(token, missile_instance_id))

	return {
		"token": token,
		"missile_id": missile_instance_id,
		"launch_side": _get_missile_side_for_launch_node(launch_node)
	}


func _on_missile_barrage_prep_arrived(token: int, missile_instance_id: int) -> void:
	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D
	if token != _missile_effect_token:
		if missile_node != null and is_instance_valid(missile_node):
			_record_missile_despawn_position(missile_node)
			missile_node.queue_free()
		_remove_active_missile_by_id(missile_instance_id)
		return
	if missile_node == null or not is_instance_valid(missile_node):
		_remove_active_missile_by_id(missile_instance_id)
		return

	_record_missile_despawn_position(missile_node)
	missile_node.queue_free()
	_remove_active_missile_by_id(missile_instance_id)


func _spawn_missile_barrage_dash_from_prep(token: int, prep_position: Vector2, dash_duration: float) -> void:
	if token != _missile_effect_token:
		return

	var missile_node: Node2D = missile_scene.instantiate() as Node2D
	if missile_node == null or not is_instance_valid(missile_node):
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		missile_node.queue_free()
		return

	scene_root.add_child(missile_node)
	missile_node.add_to_group(MISSILE_EFFECT_GROUP)
	missile_node.global_position = prep_position
	missile_node.scale *= missile_barrage_prep_scale_factor
	_active_missiles.append(missile_node)
	_attach_missile_warning_light(missile_node)
	_start_missile_warning_blink(missile_node, token)

	var missile_instance_id: int = missile_node.get_instance_id()
	var player_target: Vector2 = _get_current_target_position(missile_node.global_position)
	_orient_missile_to_direction(missile_node, player_target - missile_node.global_position)
	var safe_dash_duration: float = maxf(0.01, dash_duration)
	var dash_tween: Tween = missile_node.create_tween()
	dash_tween.tween_property(missile_node, "global_position", player_target, safe_dash_duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	dash_tween.tween_callback(_on_missile_phase2_finished.bind(token, missile_instance_id))


func _begin_charge_attack(beats: float) -> void:
	var beat_count: float = maxf(0.01, beats)
	var beat_seconds: float = _get_beat_seconds()
	_charge_cycle_id += 1
	_charge_play_call_count = 0
	if _charge_animation_started_early:
		_charge_animation_started_early = false
	else:
		_charge_animation_started_in_cycle = false
	if debug_charge_timing:
		print("[ChargeDebug][Boss] begin cycle=", _charge_cycle_id,
			" beat_count=", "%.3f" % beat_count,
			" duration_s=", "%.3f" % (beat_count * beat_seconds),
			" now_state=", BossState.keys()[current_state])

	_pending_charge_beats = 0.0
	_pre_charge_target_on_ring = false
	_has_pending_charge_fire = false
	_pending_charge_fire_time = 0.0
	_charge_bullet_fired_this_cycle = false
	_clear_active_charge_bullet()
	_charge_state_remaining_time = beat_count * beat_seconds
	if current_state == BossState.CHARGE:
		return
	_set_state(BossState.CHARGE)


func _update_pending_charge_schedule() -> void:
	if not _has_pending_charge_fire:
		return
	if is_dead:
		_has_pending_charge_fire = false
		return

	var now: float = _get_now_seconds()
	var time_left: float = _pending_charge_fire_time - now
	if time_left <= 0.0:
		_is_preparing_charge = false
		_has_pending_charge_fire = false
		_begin_charge_attack(_pending_charge_beats)
		return


func _begin_missile_attack(beats: int) -> void:
	var beat_count: int = maxi(1, beats)
	var beat_seconds: float = _get_beat_seconds()

	_pending_missile_beats = 0
	_has_pending_missile_launch = false
	var state_duration: float = float(beat_count) * beat_seconds
	_missile_state_remaining_time = maxf(_missile_state_remaining_time, state_duration)

	# 发射导弹后立即恢复随机移动；导弹飞行中的“攻击可视激活”由 _missile_state_remaining_time 负责。
	_start_missile_attack()
	if not is_dead and not _attack_phase_interrupted:
		_set_state(BossState.RANDOM_MOVE)


func _start_missile_attack() -> void:
	if missile_scene == null:
		push_warning("[Boss] missile_scene 未配置")
		return

	var beat_seconds: float = _get_beat_seconds()

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
	_attach_missile_warning_light(missile)
	_start_missile_warning_blink(missile, token)
	_schedule_boss_attack_sound_from_sprite(BossAttackSoundConfig.ATTACK_MISSILE, _find_timing_sprite(missile))

	var outward_dir: Vector2 = _get_missile_outward_direction(launch_node).normalized()
	_play_missile_launcher_recoil(launch_node, outward_dir)
	var outward_target: Vector2 = _get_missile_offscreen_target(missile.global_position, outward_dir)
	var teleport_target: Vector2 = _get_missile_teleport_corner(launch_node)
	_orient_missile_to_direction(missile, outward_dir)

	var phase1_tween: Tween = missile.create_tween()
	phase1_tween.tween_property(missile, "global_position", outward_target, phase1_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var missile_instance_id: int = missile.get_instance_id()
	phase1_tween.tween_callback(_on_missile_phase1_finished.bind(token, missile_instance_id, outward_target, teleport_target, phase2_duration))


func _on_missile_phase1_finished(token: int, missile_instance_id: int, outward_target: Vector2, teleport_target: Vector2, phase2_duration: float) -> void:
	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D

	if token != _missile_effect_token:
		if missile_node != null and is_instance_valid(missile_node):
			_record_missile_despawn_position(missile_node)
			missile_node.queue_free()
		_remove_active_missile_by_id(missile_instance_id)
		return

	if missile_node == null or not is_instance_valid(missile_node):
		_remove_active_missile_by_id(missile_instance_id)
		return

	# 第二拍开始：瞬移到左上/右上屏幕外边缘。
	missile_node.global_position = teleport_target
	# 第二拍起始放大 2 倍。
	missile_node.scale *= 2.0
	_refresh_missile_warning_light(missile_node)
	var player_target: Vector2 = _get_current_target_position(outward_target)
	_orient_missile_to_direction(missile_node, player_target - missile_node.global_position)
	var total_phase2_duration: float = maxf(0.01, phase2_duration)
	var dash_duration: float = _get_missile_dash_duration(total_phase2_duration)
	var lock_duration: float = maxf(0.0, total_phase2_duration - dash_duration)
	var base_scale: Vector2 = missile_node.scale
	if lock_duration > 0.03:
		var lock_target: Vector2 = _get_missile_lock_target(missile_node.global_position, player_target)
		var lock_tween: Tween = missile_node.create_tween()
		lock_tween.tween_property(missile_node, "global_position", lock_target, lock_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		lock_tween.parallel().tween_property(missile_node, "scale", base_scale * missile_lock_scale_factor, lock_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lock_tween.tween_callback(_start_missile_dash.bind(token, missile_instance_id, player_target, dash_duration, base_scale))
	else:
		_start_missile_dash(token, missile_instance_id, player_target, dash_duration, base_scale)


func _start_missile_dash(token: int, missile_instance_id: int, fallback_target: Vector2, dash_duration: float, base_scale: Vector2) -> void:
	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D

	if token != _missile_effect_token:
		if missile_node != null and is_instance_valid(missile_node):
			_record_missile_despawn_position(missile_node)
			missile_node.queue_free()
		_remove_active_missile_by_id(missile_instance_id)
		return

	if missile_node == null or not is_instance_valid(missile_node):
		_remove_active_missile_by_id(missile_instance_id)
		return

	var player_target: Vector2 = _get_current_target_position(fallback_target)
	_orient_missile_to_direction(missile_node, player_target - missile_node.global_position)
	var safe_dash_duration: float = maxf(0.01, dash_duration)
	var dash_tween: Tween = missile_node.create_tween()
	dash_tween.tween_property(missile_node, "global_position", player_target, safe_dash_duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	dash_tween.parallel().tween_property(missile_node, "scale", base_scale * missile_dash_scale_factor, minf(0.12, maxf(0.01, safe_dash_duration * 0.35))).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	dash_tween.tween_callback(_on_missile_phase2_finished.bind(token, missile_instance_id))


func _on_missile_phase2_finished(token: int, missile_instance_id: int) -> void:
	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D

	if token != _missile_effect_token:
		if missile_node != null and is_instance_valid(missile_node):
			_record_missile_despawn_position(missile_node)
			missile_node.queue_free()
		_remove_active_missile_by_id(missile_instance_id)
		return

	if missile_node != null and is_instance_valid(missile_node):
		_record_missile_despawn_position(missile_node)
		missile_node.queue_free()
	_remove_active_missile_by_id(missile_instance_id)


func _remove_active_missile_by_id(missile_instance_id: int) -> void:
	for i in range(_active_missiles.size() - 1, -1, -1):
		var active_missile: Node2D = _active_missiles[i]
		if active_missile == null or not is_instance_valid(active_missile):
			_active_missiles.remove_at(i)
			continue
		if active_missile.get_instance_id() == missile_instance_id:
			_active_missiles.remove_at(i)


func _record_missile_despawn_position(missile: Node2D) -> void:
	if missile == null or not is_instance_valid(missile):
		return
	_last_missile_despawn_position = missile.global_position
	_has_last_missile_despawn_position = true


func _get_missile_dash_duration(total_duration: float) -> float:
	var beat_seconds: float = _get_beat_seconds()
	var requested: float = maxf(0.1, missile_dash_beats) * beat_seconds
	return clampf(requested, 0.01, maxf(0.01, total_duration))


func _get_missile_lock_target(start_pos: Vector2, target_pos: Vector2) -> Vector2:
	var approach: float = clampf(missile_lock_approach_ratio, 0.0, 0.8)
	return start_pos.lerp(target_pos, approach)


func get_missile_hit_effect_position() -> Vector2:
	if _target_character == null:
		_resolve_aim_nodes()

	var reference_pos: Vector2 = global_position
	if _target_character != null:
		reference_pos = _target_character.global_position
		return reference_pos

	var best_pos: Vector2 = Vector2.ZERO
	var best_dist_sq: float = INF
	var found_active: bool = false
	for active_missile in _active_missiles:
		if active_missile == null or not is_instance_valid(active_missile):
			continue
		var dist_sq: float = active_missile.global_position.distance_squared_to(reference_pos)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_pos = active_missile.global_position
			found_active = true

	if found_active:
		return best_pos

	if _has_last_missile_despawn_position:
		return _last_missile_despawn_position
	if _target_character != null:
		return _target_character.global_position

	return global_position


func _attach_missile_warning_light(missile: Node2D) -> void:
	if not missile_warning_enabled:
		return
	if missile == null or not is_instance_valid(missile):
		return
	if missile.get_node_or_null("MissileWarningLight") != null:
		return

	var warning_light: Sprite2D = Sprite2D.new()
	warning_light.name = "MissileWarningLight"
	missile.add_child(warning_light)
	_configure_warning_light_sprite(warning_light, missile)


func _refresh_missile_warning_light(missile: Node2D) -> void:
	if missile == null or not is_instance_valid(missile):
		return
	var warning_light: Sprite2D = missile.get_node_or_null("MissileWarningLight") as Sprite2D
	if warning_light == null:
		return
	_configure_warning_light_sprite(warning_light, missile)


func _start_missile_warning_blink(missile: Node2D, token: int) -> void:
	if not missile_warning_enabled:
		return
	if missile == null or not is_instance_valid(missile):
		return
	if token != _missile_effect_token:
		return

	_blink_missile_warning_once(missile)

	var beat_seconds: float = _get_beat_seconds()
	var missile_instance_id: int = missile.get_instance_id()
	_schedule_music_clock_event(_get_now_seconds() + beat_seconds, Callable(self, "_on_missile_warning_blink_timeout"), [token, missile_instance_id])


func _on_missile_warning_blink_timeout(token: int, missile_instance_id: int) -> void:
	if token != _missile_effect_token:
		return

	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D
	if missile_node == null or not is_instance_valid(missile_node):
		return

	_start_missile_warning_blink(missile_node, token)


func _blink_missile_warning_once(missile: Node2D) -> void:
	if missile == null or not is_instance_valid(missile):
		return
	var warning_light: Sprite2D = missile.get_node_or_null("MissileWarningLight") as Sprite2D
	if warning_light == null:
		return
	_blink_warning_light_once(warning_light, missile)


func _blink_warning_light_once(warning_light: Sprite2D, owner_node: Node2D) -> void:
	if warning_light == null or not is_instance_valid(warning_light):
		return

	var beat_seconds: float = _get_beat_seconds()
	_missile_warning_style.blink_once(
		warning_light,
		owner_node,
		beat_seconds,
		missile_warning_flash_ratio,
		missile_warning_light_color,
		missile_warning_peak_alpha,
		missile_warning_radius_px,
		missile_warning_falloff_power,
		missile_warning_light_scale,
		missile_warning_additive_blend
	)


func _configure_warning_light_sprite(warning_light: Sprite2D, owner_node: Node2D) -> void:
	_missile_warning_style.configure_sprite(
		warning_light,
		owner_node,
		missile_warning_radius_px,
		missile_warning_falloff_power,
		missile_warning_light_scale,
		missile_warning_light_color,
		missile_warning_additive_blend
	)


func _update_missile_warning_preview() -> void:
	if not missile_warning_preview_on_boss or not missile_warning_enabled:
		_clear_missile_warning_preview()
		return

	if _missile_warning_preview_light == null or not is_instance_valid(_missile_warning_preview_light):
		_missile_warning_preview_light = Sprite2D.new()
		_missile_warning_preview_light.name = "MissileWarningPreview"
		add_child(_missile_warning_preview_light)
		_missile_warning_preview_token += 1
		_start_missile_warning_preview_blink(_missile_warning_preview_token)

	if _missile_warning_preview_light == null or not is_instance_valid(_missile_warning_preview_light):
		return

	_missile_warning_preview_light.position = missile_warning_preview_offset
	_configure_warning_light_sprite(_missile_warning_preview_light, self)


func _start_missile_warning_preview_blink(token: int) -> void:
	if token != _missile_warning_preview_token:
		return
	if _missile_warning_preview_light == null or not is_instance_valid(_missile_warning_preview_light):
		return

	_blink_warning_light_once(_missile_warning_preview_light, self)

	var beat_seconds: float = _get_beat_seconds()

	_schedule_music_clock_event(_get_now_seconds() + beat_seconds, Callable(self, "_on_missile_warning_preview_blink_timeout"), [token])


func _on_missile_warning_preview_blink_timeout(token: int) -> void:
	if token != _missile_warning_preview_token:
		return
	if not missile_warning_preview_on_boss:
		return
	if _missile_warning_preview_light == null or not is_instance_valid(_missile_warning_preview_light):
		return
	_start_missile_warning_preview_blink(token)


func _clear_missile_warning_preview() -> void:
	_missile_warning_preview_token += 1
	if _missile_warning_preview_light != null and is_instance_valid(_missile_warning_preview_light):
		_missile_warning_preview_light.queue_free()
	_missile_warning_preview_light = null


func _pick_missile_launch_node() -> Node2D:
	var launch_side: int = _missile_side_selector.pick_launch_side(
		_missile_left_node != null and not _is_part_destroyed(BOSS_PART_LEFT),
		_missile_right_node != null and not _is_part_destroyed(BOSS_PART_RIGHT)
	)
	if launch_side == MISSILE_SIDE_LEFT:
		return _missile_left_node
	if launch_side == MISSILE_SIDE_RIGHT:
		return _missile_right_node
	return null


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
		var half_world_size: Vector2 = Vector2(
			viewport_size.x / maxf(0.01, zoom.x) * 0.5,
			viewport_size.y / maxf(0.01, zoom.y) * 0.5
		)
		var x: float = center.x - half_world_size.x - margin if use_left else center.x + half_world_size.x + margin
		var y: float = center.y - half_world_size.y - margin
		return Vector2(x, y)

	var rect: Rect2 = get_viewport().get_visible_rect()
	var x2: float = rect.position.x - margin if use_left else rect.position.x + rect.size.x + margin
	var y2: float = rect.position.y - margin
	return Vector2(x2, y2)


func _get_missile_barrage_attack_spawn_position(group_index: int, launch_side: int) -> Vector2:
	if group_index >= 0 and _missile_barrage_spawn_by_group.has(group_index):
		return _missile_barrage_spawn_by_group[group_index]

	var resolved_group_index: int = group_index
	if resolved_group_index < 0:
		resolved_group_index = _missile_barrage_spawn_by_group.size()
	var camera: Camera2D = get_viewport().get_camera_2d()
	var spawn_position: Vector2
	if camera != null:
		var center: Vector2 = camera.get_screen_center_position()
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size
		var zoom: Vector2 = camera.zoom
		var half_world_size: Vector2 = Vector2(
			viewport_size.x / maxf(0.01, zoom.x) * 0.5,
			viewport_size.y / maxf(0.01, zoom.y) * 0.5
		)
		var top_left: Vector2 = center - half_world_size
		var bottom_right: Vector2 = center + half_world_size
		spawn_position = _pick_missile_barrage_spawn_in_rect(top_left, bottom_right, resolved_group_index, launch_side)
	else:
		var rect: Rect2 = get_viewport().get_visible_rect()
		spawn_position = _pick_missile_barrage_spawn_in_rect(rect.position, rect.position + rect.size, resolved_group_index, launch_side)

	if group_index >= 0:
		_missile_barrage_spawn_by_group[group_index] = spawn_position
	return spawn_position


func _pick_missile_barrage_spawn_in_rect(top_left: Vector2, bottom_right: Vector2, group_index: int, launch_side: int) -> Vector2:
	var player_target: Vector2 = _get_current_target_position(global_position)
	var width: float = maxf(1.0, bottom_right.x - top_left.x)
	var height: float = maxf(1.0, bottom_right.y - top_left.y)
	var x_ratio: float = clampf((player_target.x - top_left.x) / width, 0.0, 1.0)

	var spawn_left: bool
	if x_ratio > MISSILE_BARRAGE_CENTER_BAND_MAX:
		spawn_left = true
	elif x_ratio < MISSILE_BARRAGE_CENTER_BAND_MIN:
		spawn_left = false
	else:
		if launch_side == MISSILE_SIDE_LEFT:
			spawn_left = true
		elif launch_side == MISSILE_SIDE_RIGHT:
			spawn_left = false
		else:
			spawn_left = (group_index % 2) == 0

	var lane_sweep: float = clampf(missile_barrage_spawn_lane_sweep, 0.0, 1.0)
	var lane_phase: float = _get_missile_barrage_lane_phase(group_index, lane_sweep)
	var horizontal_margin: float = maxf(16.0, missile_barrage_prep_screen_margin.x)
	var vertical_margin: float = maxf(16.0, missile_barrage_prep_screen_margin.y)
	var top_y: float = top_left.y - vertical_margin
	var mid_y: float = top_left.y + height * 0.48
	var center_x: float = top_left.x + width * 0.5
	var left_x: float = top_left.x - horizontal_margin
	var right_x: float = bottom_right.x + horizontal_margin

	if spawn_left:
		if launch_side == MISSILE_SIDE_LEFT:
			return Vector2(left_x, lerpf(mid_y, top_y, lane_phase))
		if launch_side == MISSILE_SIDE_RIGHT:
			return Vector2(lerpf(left_x, center_x, lane_phase), top_y)
		return Vector2(left_x, top_y)

	if launch_side == MISSILE_SIDE_RIGHT:
		return Vector2(right_x, lerpf(mid_y, top_y, lane_phase))
	if launch_side == MISSILE_SIDE_LEFT:
		return Vector2(lerpf(right_x, center_x, lane_phase), top_y)
	return Vector2(right_x, top_y)


func _get_missile_barrage_lane_phase(group_index: int, lane_sweep: float) -> float:
	var base: float = 0.5
	if group_index >= 0:
		match group_index % 4:
			0:
				base = 0.2
			1:
				base = 0.8
			2:
				base = 0.4
			_:
				base = 0.65
	return lerpf(0.5, base, lane_sweep)


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

	# 导弹预约期间持续锁定目标为原点，避免被随机移动改写。
	if remaining > 0.0:
		if enable_pre_missile_return:
			if not _is_preparing_missile:
				_is_preparing_missile = true
			_move_target = _spawn_position
			if global_position.distance_to(_move_target) <= target_reach_distance:
				_has_move_target = false
			else:
				_has_move_target = true
		else:
			_is_preparing_missile = false
			_has_move_target = false

	# 到达发射时刻：无论当前位置如何，都准点发射。
	if remaining <= 0.0:
		_launch_missile_attack_now()


func _launch_missile_attack_now() -> void:
	if debug_missile_timing:
		print("[MissileDebug][Boss] launch now pos=", global_position,
			" spawn=", _spawn_position,
			" dist_to_spawn=", "%.3f" % global_position.distance_to(_spawn_position))
	var immediate_beats: int = _pending_missile_beats
	if immediate_beats <= 0:
		immediate_beats = maxi(1, missile_total_beats)
	_has_pending_missile_launch = false
	_pending_missile_launch_time = 0.0
	_has_move_target = false
	_is_preparing_missile = false
	_begin_missile_attack(immediate_beats)


func _start_return_to_origin_transition() -> void:
	_stop_return_to_origin_transition()

	var bi: float = _get_beat_seconds()

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
	if _music_player == null or not is_instance_valid(_music_player):
		_resolve_music_player()
	return RhythmClock.get_music_or_wall_time(_music_player)


func _get_beat_seconds() -> float:
	if EventBus.beat_interval > 0.0:
		return EventBus.beat_interval
	return 0.5


func _schedule_music_clock_event(target_time: float, callback: Callable, args: Array = []) -> void:
	_music_clock_events.schedule(target_time, callback, args)


func _process_music_clock_events(now: float) -> void:
	_music_clock_events.process(now)


func get_spawn_position() -> Vector2:
	return _spawn_position


func _start_shield_break_transition() -> void:
	_stop_break_transition()
	if _player_node == null:
		_resolve_aim_nodes()

	var bi: float = _get_beat_seconds()
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
		_break_transition_tween.tween_callback(_emit_boss_break_fall_started)
		_break_transition_tween.tween_property(self, "global_position:y", broken_fall_target_y, fall_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	else:
		call_deferred("_emit_boss_break_fall_started")

	# 需求变更：取消转阶段冲刺，玩家位置保持不变。


func _emit_boss_break_fall_started() -> void:
	if is_dead:
		return
	if current_state != BossState.BROKEN:
		return
	EventBus.boss_break_fall_started.emit()


func _play_shield_break_sound_delayed() -> void:
	if GameConfigs.sound == null or GameConfigs.sound.player_defense == null:
		return
	var break_sound: RandomSoundPool = GameConfigs.sound.player_defense.guard_success
	if break_sound == null:
		return
	_schedule_music_clock_event(_get_now_seconds() + 0.08, Callable(self, "_on_shield_break_sound_time"), [break_sound])


func _on_shield_break_sound_time(break_sound: RandomSoundPool) -> void:
	if is_dead or current_state != BossState.BROKEN:
		return
	var time_offset: float = GameConfigs.sound.player_defense.get_success_time_offset(Note.NoteType.GUARD)
	SFXManager.play_pool(break_sound, GameConfigs.sound.player_defense.sfx_bus, time_offset)


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
	_reset_missile_launcher_recoil()
	_pending_missile_barrage_group_index = -1
	_missile_barrage_spawn_by_group.clear()

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


func _cache_missile_launcher_origin(launch_node: Node2D) -> void:
	if launch_node == null:
		return
	var recoil_node: Node2D = _get_missile_recoil_node_by_launch_node(launch_node)
	if recoil_node == null:
		return
	_missile_recoil_state.cache_origin(_get_missile_side_for_launch_node(launch_node), recoil_node)


func _get_missile_launcher_origin(launch_node: Node2D) -> Vector2:
	if launch_node == null:
		return Vector2.ZERO
	return _missile_recoil_state.get_origin(_get_missile_side_for_launch_node(launch_node), launch_node.position)


func _get_missile_side_for_launch_node(launch_node: Node2D) -> int:
	if launch_node == _missile_left_node:
		return MISSILE_SIDE_LEFT
	if launch_node == _missile_right_node:
		return MISSILE_SIDE_RIGHT
	return -1


func _kill_missile_launcher_recoil_tween(launch_node: Node2D) -> void:
	if launch_node == null:
		return
	_missile_recoil_state.kill_tween(_get_missile_side_for_launch_node(launch_node))


func _play_missile_launcher_recoil(launch_node: Node2D, outward_dir: Vector2) -> void:
	if launch_node == null:
		return
	var recoil_node: Node2D = _get_missile_recoil_node_by_launch_node(launch_node)
	if recoil_node == null:
		return
	if outward_dir.length_squared() <= 0.0001:
		return
	if missile_launcher_recoil_distance <= 0.0:
		return

	var launch_side: int = _get_missile_side_for_launch_node(launch_node)
	_cache_missile_launcher_origin(launch_node)
	_missile_recoil_state.kill_tween(launch_side)

	var origin_local: Vector2 = _get_missile_launcher_origin(launch_node)
	recoil_node.position = origin_local

	var recoil_dir_global: Vector2 = -outward_dir.normalized()
	var recoil_global_target: Vector2 = recoil_node.global_position + recoil_dir_global * missile_launcher_recoil_distance
	var recoil_local_target: Vector2 = origin_local + recoil_dir_global * missile_launcher_recoil_distance
	var parent_2d: Node2D = recoil_node.get_parent() as Node2D
	if parent_2d != null:
		recoil_local_target = parent_2d.to_local(recoil_global_target)

	var recoil_tween: Tween = create_tween()
	_missile_recoil_state.set_tween(launch_side, recoil_tween)

	recoil_tween.tween_property(recoil_node, "position", recoil_local_target, maxf(0.01, missile_launcher_recoil_out_duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	recoil_tween.tween_property(recoil_node, "position", origin_local, maxf(0.01, missile_launcher_recoil_return_duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	recoil_tween.tween_callback(_on_missile_launcher_recoil_finished.bind(launch_side))


func _on_missile_launcher_recoil_finished(launch_side: int) -> void:
	_missile_recoil_state.clear_tween(launch_side)


func _reset_missile_launcher_recoil() -> void:
	_missile_recoil_state.reset_side(MISSILE_SIDE_LEFT)
	_missile_recoil_state.reset_side(MISSILE_SIDE_RIGHT)


func _get_missile_recoil_node_by_launch_node(launch_node: Node2D) -> Node2D:
	if launch_node == _missile_left_node:
		var left_visual_node: Node2D = _left_missile_visual as Node2D
		if left_visual_node != null:
			return left_visual_node
		return _missile_left_node
	if launch_node == _missile_right_node:
		var right_visual_node: Node2D = _right_missile_visual as Node2D
		if right_visual_node != null:
			return right_visual_node
		return _missile_right_node
	return launch_node


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
	_schedule_music_clock_event(_get_now_seconds() + interval, Callable(self, "_emit_player_dash_afterimage_loop"), [token, end_time])


func _spawn_player_afterimage() -> void:
	if _player_node == null:
		return

	var player_sprite: AnimatedSprite2D = _player_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var ghost: Sprite2D = PlayerAfterimageFactory.create_from_sprite(
		player_sprite,
		PLAYER_DASH_AFTERIMAGE_GROUP,
		player_dash_afterimage_color,
		player_dash_afterimage_alpha
	)
	if ghost == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	scene_root.add_child(ghost)

	var life: float = maxf(0.05, player_dash_afterimage_lifetime)
	var fade_tween: Tween = ghost.create_tween()
	fade_tween.tween_property(ghost, "modulate:a", 0.0, life).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var ghost_instance_id: int = ghost.get_instance_id()
	fade_tween.tween_callback(_on_player_afterimage_fade_finished.bind(ghost_instance_id))


func _on_player_afterimage_fade_finished(ghost_instance_id: int) -> void:
	var ghost_obj: Object = instance_from_id(ghost_instance_id)
	var ghost_node: Node = ghost_obj as Node
	if ghost_node != null and is_instance_valid(ghost_node):
		ghost_node.queue_free()


func _stop_player_dash_afterimage() -> void:
	_player_dash_afterimage_token += 1
	for node in get_tree().get_nodes_in_group(PLAYER_DASH_AFTERIMAGE_GROUP):
		var ghost_node: Node = node as Node
		if ghost_node != null and is_instance_valid(ghost_node):
			ghost_node.queue_free()


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
