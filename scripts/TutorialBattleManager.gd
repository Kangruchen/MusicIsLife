extends Node

class_name TutorialBattleManager

const RhythmClock := preload("res://scripts/RhythmClock.gd")

enum BattleState {
	IDLE,
	CAMERA_TRANSITION,
	PLAYING,
	ENDED,
}

@export var battle_configs: Array[TutorialBattleConfig] = []
@export_node_path("Camera2D") var camera_path: NodePath = NodePath("")
@export_node_path("CharacterBody2D") var player_path: NodePath = NodePath("")
@export_node_path("CanvasLayer") var game_ui_path: NodePath = NodePath("")
@export_node_path("CanvasLayer") var battle_ui_path: NodePath = NodePath("")
@export_node_path("AnimatedSprite2D") var cannon_node_path: NodePath = NodePath("")
@export_node_path("Node2D") var cannon_bullet_spawn_path: NodePath = NodePath("")
@export var cannon_bullet_scene: PackedScene = preload("res://scenes/charge_bullet.tscn")
@export var cannon_bullet_fire_frame: int = 16
@export var cannon_bullet_hit_frame: int = 17
@export var cannon_bullet_despawn_frame: int = 19
@export var cannon_bullet_hit_distance_from_player: float = 50.0
@export var cannon_charge_warn_sound: AudioStream = preload("res://assets/SFX/charge/charge_warn.wav")
@export var cannon_charge_attack_sound: AudioStream = preload("res://assets/SFX/charge/charge_attack.wav")
@export var battle_zone_paths: Array[NodePath] = []

@export var missile_scene: PackedScene = preload("res://scenes/missile.tscn")
@export_node_path("Node2D") var missile_launch_path: NodePath = NodePath("")
@export var missile_attack_sound: AudioStream = preload("res://assets/SFX/missile/missile_attack_1.wav")
@export var missile_hit_distance_from_player: float = 0.0
@export var missile_warning_enabled: bool = true
@export var missile_warning_light_color: Color = Color(1.0, 0.12, 0.12, 1.0)
@export_range(0.05, 1.0, 0.01) var missile_warning_peak_alpha: float = 0.9
@export_range(0.05, 0.9, 0.01) var missile_warning_flash_ratio: float = 0.2
@export_range(0.2, 4.0, 0.01) var missile_warning_light_scale: float = 2.0
@export_range(4.0, 80.0, 0.5) var missile_warning_radius_px: float = 30.0
@export_range(0.6, 6.0, 0.1) var missile_warning_falloff_power: float = 2.4
@export var missile_warning_additive_blend: bool = true

var _state: BattleState = BattleState.IDLE
var _current_battle_index: int = -1
var _current_config: TutorialBattleConfig = null
var _success_count: int = 0
var _cannon_success_count: int = 0
var _missile_success_count: int = 0
var _camera: Camera2D = null
var _player: CharacterBody2D = null
var _game_ui: CanvasLayer = null
var _battle_ui: CanvasLayer = null
var _cannon: AnimatedSprite2D = null
var _camera_tween: Tween = null
var _saved_camera_zoom: Vector2 = Vector2.ONE
var _saved_camera_position: Vector2 = Vector2.ZERO
var _beat_interval: float = 0.0
var _battle_active: bool = false
var _music_player: Node = null
var _beat_manager: Node = null
var _track_manager: Node = null
var _last_generated_beat: float = 0.0
var _ending_scheduled: bool = false
var _battle_end_target_time: float = -1.0
var _cannon_bullet_fired: bool = false
var _cannon_warn_played: bool = false
var _cannon_last_logged_frame: int = -1
var _cannon_anim_start_time: float = -1.0
var _active_cannon_bullet: Node2D = null
var _cannon_bullet_spawn_node: Node2D = null

var _next_attack_type: int = -1
var _last_successful_type: int = -1
var _active_missile: Node2D = null
var _missile_launch_node: Node2D = null
var _missile_target_times: Array[float] = []
var _missile_fired_count: int = 0
var _missile_warning_light_texture: Texture2D = null
var _missile_warning_light_texture_signature: String = ""
var _missile_warning_blink_token: int = 0
var _missile_warning_next_blink_time: float = -1.0
var _missile_warning_blink_instance_id: int = 0

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int)
signal all_battles_completed


func _ready() -> void:
	EventBus.judgment_made.connect(_on_judgment_made)
	_hide_health_bars()


func _process(_delta: float) -> void:
	if _state != BattleState.PLAYING:
		return
	_process_scheduled_battle_end()
	_process_missile_warning_blink()
	if _battle_active:
		if _track_manager and _track_manager.scheduled_notes.size() <= 4:
			_append_more_notes()
		_try_fire_missiles()
	# 即使战斗已结束，仍然需要处理cannon子弹生成（cannon动画可能仍在播放中）
	_track_cannon_frames()
	_try_fire_cannon_bullet()


func _track_cannon_frames() -> void:
	if _cannon == null or not is_instance_valid(_cannon):
		return
	if not _cannon.is_playing() or _cannon.animation != "shoot":
		_cannon_last_logged_frame = -1
		_cannon_anim_start_time = -1.0
		return
	var cur_frame: int = _cannon.frame
	if _cannon_anim_start_time < 0.0:
		_cannon_anim_start_time = _get_music_clock_time()
	if cur_frame == _cannon_last_logged_frame:
		return
	_cannon_last_logged_frame = cur_frame
	var now: float = _get_music_clock_time()
	var elapsed: float = now - _cannon_anim_start_time
	var beat_interval: float = EventBus.beat_interval
	var beat_num: float = elapsed / beat_interval if beat_interval > 0.0 else 0.0
	if cur_frame in [0, 4, 8, 12, 16, 17, 19]:
		print("[CannonFrame] frame=%d elapsed=%.4fs beat=%.2f" % [cur_frame, elapsed, beat_num])


func _hide_health_bars() -> void:
	if game_ui_path.is_empty():
		return
	var ui: CanvasLayer = get_node_or_null(game_ui_path) as CanvasLayer
	if ui == null:
		return
	var boss_bar: MarginContainer = ui.get_node_or_null("MarginContainer")
	if boss_bar:
		boss_bar.visible = false
	var player_bar: MarginContainer = ui.get_node_or_null("MarginContainer2")
	if player_bar:
		player_bar.visible = false


func prepare_battle(battle_id: int) -> void:
	var index: int = -1
	for i in range(battle_configs.size()):
		if battle_configs[i].battle_id == battle_id:
			index = i
			break
	if index < 0:
		push_warning("TutorialBattleManager: 未找到 battle_id=%d 的配置" % battle_id)
		return

	_current_battle_index = index
	_current_config = battle_configs[index]
	_success_count = 0
	_cannon_success_count = 0
	_missile_success_count = 0
	_battle_active = false

	_resolve_nodes()
	_transition_camera()


func start_battle(battle_id: int) -> void:
	if _current_config == null or _current_config.battle_id != battle_id:
		prepare_battle(battle_id)
	_begin_battle()


func _resolve_nodes() -> void:
	if _camera == null or not is_instance_valid(_camera):
		if not camera_path.is_empty():
			_camera = get_node_or_null(camera_path) as Camera2D
		if _camera == null:
			_camera = get_viewport().get_camera_2d()
	if _player == null or not is_instance_valid(_player):
		if not player_path.is_empty():
			_player = get_node_or_null(player_path) as CharacterBody2D
	if _game_ui == null or not is_instance_valid(_game_ui):
		if not game_ui_path.is_empty():
			_game_ui = get_node_or_null(game_ui_path) as CanvasLayer
	if _battle_ui == null or not is_instance_valid(_battle_ui):
		if not battle_ui_path.is_empty():
			_battle_ui = get_node_or_null(battle_ui_path) as CanvasLayer
	if _cannon == null or not is_instance_valid(_cannon):
		if not cannon_node_path.is_empty():
			_cannon = get_node_or_null(cannon_node_path) as AnimatedSprite2D
		if _cannon == null:
			var scene_root: Node = get_tree().current_scene
			if scene_root:
				_cannon = scene_root.find_child("Cannon", true, false) as AnimatedSprite2D
	if _cannon_bullet_spawn_node == null or not is_instance_valid(_cannon_bullet_spawn_node):
		if not cannon_bullet_spawn_path.is_empty():
			_cannon_bullet_spawn_node = get_node_or_null(cannon_bullet_spawn_path) as Node2D
		if _cannon_bullet_spawn_node == null and _cannon:
			_cannon_bullet_spawn_node = _cannon.get_node_or_null("BulletPoint") as Node2D
	if _missile_launch_node == null or not is_instance_valid(_missile_launch_node):
		if not missile_launch_path.is_empty():
			_missile_launch_node = get_node_or_null(missile_launch_path) as Node2D
		if _missile_launch_node == null:
			var scene_root: Node = get_tree().current_scene
			if scene_root:
				_missile_launch_node = scene_root.find_child("Missile1", true, false) as Node2D
	var gm: Node = get_node_or_null("../GameManager")
	if gm:
		if _music_player == null or not is_instance_valid(_music_player):
			_music_player = gm.get_node_or_null("MusicPlayer")
		if _beat_manager == null or not is_instance_valid(_beat_manager):
			_beat_manager = gm.get_node_or_null("BeatManager")
		if _track_manager == null or not is_instance_valid(_track_manager):
			_track_manager = gm.get_node_or_null("TrackManager")


func _get_battle_zone_rect(battle_id: int) -> Rect2:
	var zone_index: int = battle_id - 1
	if zone_index < 0 or zone_index >= battle_zone_paths.size():
		return Rect2()
	var zone_path: NodePath = battle_zone_paths[zone_index]
	if zone_path.is_empty():
		return Rect2()
	var zone: Node = get_node_or_null(zone_path)
	if zone == null:
		return Rect2()
	var shape_index: int = 0
	var shapes: Array = zone.get_shape_owners()
	if shapes.is_empty():
		return Rect2()
	var owner_id: int = shapes[0]
	var shape_count: int = zone.shape_owner_get_shape_count(owner_id)
	if shape_count <= shape_index:
		return Rect2()
	var shape: Shape2D = zone.shape_owner_get_shape(owner_id, shape_index)
	if shape == null:
		return Rect2()
	var rect_shape: RectangleShape2D = shape as RectangleShape2D
	if rect_shape == null:
		return Rect2()
	var zone_global_pos: Vector2 = zone.global_position
	var cs: CollisionShape2D = _get_collision_shape_from_zone(zone, shape_index)
	var offset: Vector2 = Vector2.ZERO
	if cs:
		offset = cs.position
	var center: Vector2 = zone_global_pos + offset
	var half_size: Vector2 = rect_shape.size * 0.5
	return Rect2(center - half_size, rect_shape.size)


func _get_collision_shape_from_zone(zone: Node, shape_index: int) -> CollisionShape2D:
	for child in zone.get_children():
		var cs: CollisionShape2D = child as CollisionShape2D
		if cs and cs.shape:
			if shape_index <= 0:
				return cs
			shape_index -= 1
	return null


func _transition_camera() -> void:
	if _camera == null:
		return

	_state = BattleState.CAMERA_TRANSITION
	_saved_camera_zoom = _camera.zoom
	_saved_camera_position = _camera.global_position

	var target_zoom: Vector2 = _current_config.camera_zoom
	var focus_area: Rect2 = _get_battle_zone_rect(_current_config.battle_id)
	var target_position: Vector2
	if focus_area != Rect2():
		target_position = focus_area.position + focus_area.size * 0.5
	else:
		target_position = _camera.global_position

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_view: Vector2 = viewport_size * 0.5 / target_zoom
	target_position.x = clampf(target_position.x, _camera.limit_left + half_view.x, _camera.limit_right - half_view.x)
	target_position.y = clampf(target_position.y, _camera.limit_top + half_view.y, _camera.limit_bottom - half_view.y)
	if _current_config.camera_stick_bottom:
		target_position.y = _camera.limit_bottom - half_view.y

	if _camera_tween:
		_camera_tween.kill()
	_camera_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_camera, "zoom", target_zoom, 0.6)
	_camera_tween.parallel().tween_property(_camera, "global_position", target_position, 0.6)


func _begin_battle() -> void:
	_state = BattleState.PLAYING

	if _player:
		_player.set_physics_process(false)
		if _player.has_method("enter_battle"):
			_player.enter_battle()

	if _current_config.attack_type == TutorialBattleConfig.AttackType.CHARGE and _cannon:
		_battle_active = false
		_play_cannon_trans()
		return

	_start_battle_internal()


func _play_cannon_trans() -> void:
	if _cannon == null:
		_start_battle_internal()
		return
	_cannon.visible = true
	if _cannon.sprite_frames and _cannon.sprite_frames.has_animation("trans"):
		_cannon.animation = "trans"
		_cannon.frame = 0
		_cannon.play("trans")
		if not _cannon.animation_finished.is_connected(_on_cannon_trans_finished):
			_cannon.animation_finished.connect(_on_cannon_trans_finished)
	else:
		_start_battle_internal()


func _on_cannon_trans_finished() -> void:
	if _cannon and _cannon.animation_finished.is_connected(_on_cannon_trans_finished):
		_cannon.animation_finished.disconnect(_on_cannon_trans_finished)
	if _cannon and _cannon.sprite_frames and _cannon.sprite_frames.has_animation("shoot"):
		_cannon.animation = "shoot"
		_cannon.frame = 0
		_cannon.stop()
	_start_battle_internal()


func _start_battle_internal() -> void:
	_battle_active = true
	if _game_ui:
		_game_ui.show()
	if _battle_ui and _battle_ui.has_method("show_ui"):
		_battle_ui.show_ui(_current_config.battle_id)

	if _player:
		_player.set_physics_process(false)
		if _player.has_method("enter_battle"):
			_player.enter_battle()

	_beat_interval = 60.0 / _current_config.bpm

	if _beat_manager:
		_beat_manager.bpm = _current_config.bpm
		_beat_manager.beat_interval = _beat_interval
		_beat_manager.offset = _current_config.offset + _beat_manager.user_offset
		_beat_manager.current_beat = 0.0
		_beat_manager.next_beat_time = 0.0
		_beat_manager.is_playing = false
		_beat_manager.current_chart = null
		_beat_manager.chart_sm_path = ""
		_beat_manager.generate_test_chart = false

	EventBus.beat_interval = _beat_interval

	_missile_target_times.clear()
	_missile_fired_count = 0

	if _current_config.attack_type == TutorialBattleConfig.AttackType.ALTERNATING_MISSILE_CHARGE:
		_next_attack_type = int(Note.NoteType.HIT)
		_last_successful_type = -1
		# 第二场战斗使用双行进度显示
		if _current_config.battle_id == 2 and _battle_ui and _battle_ui.has_method("setup_dual_row_mode"):
			_battle_ui.setup_dual_row_mode()

	_generate_and_emit_chart()

	if _music_player:
		_music_player.auto_play = false
		if _music_player.has_method("load_and_play_music"):
			_music_player.load_and_play_music(_current_config.music_path)

	battle_started.emit(_current_config.battle_id)


func _generate_and_emit_chart() -> void:
	var chart := Chart.new()
	chart.chart_name = "Tutorial Battle %d" % _current_config.battle_id
	chart.bpm = _current_config.bpm
	var effective_offset: float = _current_config.offset
	if _beat_manager:
		effective_offset += _beat_manager.user_offset
	chart.offset = effective_offset

	var note_count: int = _current_config.max_notes
	_last_generated_beat = 0.0
	for i in range(note_count):
		var beat_num: float = float(_current_config.start_delay_beats + 1 + i * _current_config.beat_interval_beats)
		var note := Note.new()
		note.beat_number = beat_num
		note.beat_time = effective_offset + beat_num * _beat_interval
		
		if _current_config.attack_type == TutorialBattleConfig.AttackType.ALTERNATING_MISSILE_CHARGE:
			note.type = _next_attack_type as Note.NoteType
			if _next_attack_type == int(Note.NoteType.HIT):
				_next_attack_type = int(Note.NoteType.DODGE)
				_missile_target_times.append(note.beat_time)
			else:
				_next_attack_type = int(Note.NoteType.HIT)
		else:
			var note_type: Note.NoteType = _config_attack_type_to_note_type(_current_config.attack_type)
			note.type = note_type
			if note_type == Note.NoteType.HIT:
				_missile_target_times.append(note.beat_time)
		
		chart.add_note(note)
		if beat_num > _last_generated_beat:
			_last_generated_beat = beat_num

	chart.sort_notes()
	EventBus.chart_loaded.emit(chart)


func _config_attack_type_to_note_type(attack_type: TutorialBattleConfig.AttackType) -> Note.NoteType:
	match attack_type:
		TutorialBattleConfig.AttackType.LASER:
			return Note.NoteType.GUARD
		TutorialBattleConfig.AttackType.MISSILE:
			return Note.NoteType.HIT
		TutorialBattleConfig.AttackType.CHARGE:
			return Note.NoteType.DODGE
	return Note.NoteType.GUARD


func _append_more_notes() -> void:
	if _current_config == null or _track_manager == null:
		return
	var effective_offset: float = _current_config.offset
	if _beat_manager:
		effective_offset += _beat_manager.user_offset
	var batch_size: int = _current_config.max_notes
	var new_notes: Array[Note] = []
	for i in range(batch_size):
		var beat_num: float = _last_generated_beat + float((i + 1) * _current_config.beat_interval_beats)
		var note := Note.new()
		note.beat_number = beat_num
		note.beat_time = effective_offset + beat_num * _beat_interval
		
		if _current_config.attack_type == TutorialBattleConfig.AttackType.ALTERNATING_MISSILE_CHARGE:
			note.type = _next_attack_type as Note.NoteType
			if _next_attack_type == int(Note.NoteType.HIT):
				_next_attack_type = int(Note.NoteType.DODGE)
				_missile_target_times.append(note.beat_time)
			else:
				_next_attack_type = int(Note.NoteType.HIT)
		else:
			var note_type: Note.NoteType = _config_attack_type_to_note_type(_current_config.attack_type)
			note.type = note_type
			if note_type == Note.NoteType.HIT:
				_missile_target_times.append(note.beat_time)
		
		new_notes.append(note)
	_last_generated_beat = _last_generated_beat + float(batch_size * _current_config.beat_interval_beats)
	if _track_manager.has_method("append_scheduled_notes"):
		_track_manager.append_scheduled_notes(new_notes)


func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
	if _state != BattleState.PLAYING or not _battle_active:
		return
	if _current_config == null:
		return

	var is_valid_judgment: bool = false
	
	if _current_config.attack_type == TutorialBattleConfig.AttackType.ALTERNATING_MISSILE_CHARGE:
		if track == int(Note.NoteType.HIT) or track == int(Note.NoteType.DODGE):
			is_valid_judgment = true
	else:
		var expected_note_type: Note.NoteType = _config_attack_type_to_note_type(_current_config.attack_type)
		if track == expected_note_type:
			is_valid_judgment = true
	
	if not is_valid_judgment:
		return

	if judgment != 3:
		if _current_config.attack_type == TutorialBattleConfig.AttackType.ALTERNATING_MISSILE_CHARGE:
			# 第二场战斗：分别追踪cannon和missile
			if _current_config.battle_id == 2:
				if track == int(Note.NoteType.DODGE):
					# DODGE对应cannon防御
					_cannon_success_count += 1
				elif track == int(Note.NoteType.HIT):
					# HIT对应missile防御
					_missile_success_count += 1
				
				if _battle_ui and _battle_ui.has_method("set_dual_row_progress"):
					_battle_ui.set_dual_row_progress(_cannon_success_count, _missile_success_count)
				
				# 两个都达到required_successes时过关
				if _cannon_success_count >= _current_config.required_successes and _missile_success_count >= _current_config.required_successes and not _ending_scheduled:
					_schedule_end_battle_after_beats(2.0)
			else:
				# 其他ALTERNATING_MISSILE_CHARGE战斗沿用旧逻辑
				if track == int(Note.NoteType.HIT):
					if _last_successful_type == int(Note.NoteType.DODGE):
						_success_count += 1
						_last_successful_type = -1
					else:
						_last_successful_type = int(Note.NoteType.HIT)
				elif track == int(Note.NoteType.DODGE):
					if _last_successful_type == int(Note.NoteType.HIT):
						_success_count += 1
						_last_successful_type = -1
					else:
						_last_successful_type = int(Note.NoteType.DODGE)
				
				if _battle_ui and _battle_ui.has_method("set_progress"):
					_battle_ui.set_progress(_success_count)
				if _success_count >= _current_config.required_successes and not _ending_scheduled:
					_schedule_end_battle_after_beats(2.0)
		else:
			_success_count += 1
			
			if _battle_ui and _battle_ui.has_method("set_progress"):
				_battle_ui.set_progress(_success_count)
			if _success_count >= _current_config.required_successes and not _ending_scheduled:
				_schedule_end_battle_after_beats(2.0)


func _schedule_end_battle_after_beats(beats: float) -> void:
	_battle_active = false
	_ending_scheduled = true
	var beat_seconds: float = _beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5
	_battle_end_target_time = _get_music_clock_time() + maxf(0.0, beats) * beat_seconds


func _process_scheduled_battle_end() -> void:
	if not _ending_scheduled or _battle_end_target_time < 0.0:
		return
	if _get_music_clock_time() < _battle_end_target_time:
		return
	_end_battle()


func _end_battle() -> void:
	_state = BattleState.ENDED
	_battle_active = false
	_ending_scheduled = false
	_battle_end_target_time = -1.0
	_cannon_bullet_fired = false
	_clear_active_cannon_bullet()
	_clear_active_missile()

	if _battle_ui and _battle_ui.has_method("hide_ui"):
		_battle_ui.hide_ui()

	if _track_manager and _track_manager.has_method("clear_all_notes"):
		_track_manager.clear_all_notes()

	if _music_player and _music_player.has_method("fade_out_all_for_death"):
		_music_player.fade_out_all_for_death(1.0, -40.0)

	if _beat_manager:
		_beat_manager.is_playing = false

	if _player:
		_player.set_physics_process(true)
		if _player.has_method("exit_battle"):
			_player.exit_battle()

	_restore_camera()

	var fade_duration: float = 1.2
	get_tree().create_timer(fade_duration).timeout.connect(func() -> void:
		if _music_player and _music_player.has_method("stop_music"):
			_music_player.stop_music()
	)

	battle_ended.emit(_current_config.battle_id)

	if _current_battle_index >= battle_configs.size() - 1:
		all_battles_completed.emit()


func _restore_camera() -> void:
	if _camera == null:
		return
	if _camera_tween:
		_camera_tween.kill()
	_camera_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_camera, "zoom", _saved_camera_zoom, 0.5)
	_camera_tween.parallel().tween_property(_camera, "global_position", _saved_camera_position, 0.5)


func is_battle_active() -> bool:
	return _battle_active


func get_success_count() -> int:
	# 第二场战斗返回两个计数中的最小值
	if _current_config and _current_config.battle_id == 2:
		return mini(_cannon_success_count, _missile_success_count)
	return _success_count


func get_required_successes() -> int:
	if _current_config:
		return _current_config.required_successes
	return 0


func _try_fire_cannon_bullet() -> void:
	if _cannon == null or not is_instance_valid(_cannon):
		return
	if _cannon.animation != "shoot":
		if _cannon_bullet_fired:
			_cannon_bullet_fired = false
			_cannon_warn_played = false
		return
	if not _cannon.is_playing():
		if _cannon_bullet_fired:
			_cannon_bullet_fired = false
			_cannon_warn_played = false
		return
	if _cannon.frame == 0 and _cannon.frame_progress < 0.1:
		_cannon_bullet_fired = false
		_cannon_warn_played = false
	if not _cannon_warn_played:
		_cannon_warn_played = true
		_play_cannon_sound(cannon_charge_warn_sound)
	if _cannon_bullet_fired:
		return
	if _cannon.frame < cannon_bullet_fire_frame:
		return
	_cannon_bullet_fired = true
	_play_cannon_sound(cannon_charge_attack_sound)
	_spawn_cannon_bullet()


func _play_cannon_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	SFXManager.play_stream(stream, -5.0)


func _spawn_cannon_bullet() -> void:
	if cannon_bullet_scene == null:
		return
	if _cannon == null or not is_instance_valid(_cannon):
		return

	var spawn_node: Node2D = _cannon_bullet_spawn_node
	if spawn_node == null or not is_instance_valid(spawn_node):
		spawn_node = _cannon
	if spawn_node == null:
		return

	if _player == null or not is_instance_valid(_player):
		return

	var sprite_frames: SpriteFrames = _cannon.sprite_frames
	if sprite_frames == null or not sprite_frames.has_animation("shoot"):
		return

	var base_fps: float = sprite_frames.get_animation_speed("shoot")
	var fire_to_hit_duration: float = 0.12
	var hit_to_despawn_duration: float = 0.05
	if base_fps > 0.0:
		var units_fire_to_hit: float = 0.0
		for i in range(cannon_bullet_fire_frame, mini(cannon_bullet_hit_frame, sprite_frames.get_frame_count("shoot"))):
			units_fire_to_hit += sprite_frames.get_frame_duration("shoot", i)
		var units_hit_to_despawn: float = 0.0
		for i in range(cannon_bullet_hit_frame, mini(cannon_bullet_despawn_frame, sprite_frames.get_frame_count("shoot"))):
			units_hit_to_despawn += sprite_frames.get_frame_duration("shoot", i)
		var speed_scale: float = maxf(0.01, _cannon.speed_scale)
		fire_to_hit_duration = maxf(0.01, units_fire_to_hit / base_fps / speed_scale)
		hit_to_despawn_duration = maxf(0.01, units_hit_to_despawn / base_fps / speed_scale)

	_clear_active_cannon_bullet()

	var bullet: Node2D = cannon_bullet_scene.instantiate() as Node2D
	if bullet == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	scene_root.add_child(bullet)
	bullet.global_position = spawn_node.global_position

	var player_pos: Vector2 = _player.global_position
	var to_target: Vector2 = player_pos - bullet.global_position
	var move_dir: Vector2 = Vector2.DOWN
	if to_target.length_squared() > 0.0001:
		move_dir = to_target.normalized()

	var hit_pos: Vector2 = player_pos - move_dir * maxf(0.0, cannon_bullet_hit_distance_from_player)
	_active_cannon_bullet = bullet

	if move_dir.length_squared() > 0.0001:
		bullet.global_rotation = Vector2.UP.angle_to(move_dir) + PI

	var fly_tween: Tween = bullet.create_tween()
	fly_tween.tween_property(bullet, "global_position", hit_pos, fire_to_hit_duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	if hit_to_despawn_duration > 0.0:
		fly_tween.tween_interval(hit_to_despawn_duration)
	var bullet_instance_id: int = bullet.get_instance_id()
	fly_tween.tween_callback(_on_cannon_bullet_finished.bind(bullet_instance_id))


func _on_cannon_bullet_finished(bullet_instance_id: int) -> void:
	var bullet_obj: Object = instance_from_id(bullet_instance_id)
	var bullet_node: Node2D = bullet_obj as Node2D
	if bullet_node != null and is_instance_valid(bullet_node):
		bullet_node.queue_free()
	if _active_cannon_bullet == bullet_node:
		_active_cannon_bullet = null


func _clear_active_cannon_bullet() -> void:
	if _active_cannon_bullet != null and is_instance_valid(_active_cannon_bullet):
		_active_cannon_bullet.queue_free()
	_active_cannon_bullet = null



func _spawn_missile(target_time: float) -> void:
	if missile_scene == null:
		return
	if _player == null or not is_instance_valid(_player):
		return

	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5
	var travel_duration: float = 3.0 * beat_seconds

	_clear_active_missile()

	var missile: Node2D = missile_scene.instantiate() as Node2D
	if missile == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		return

	scene_root.add_child(missile)
	missile.scale *= 4.0
	_active_missile = missile

	var spawn_pos: Vector2 = _get_missile_spawn_position()
	missile.global_position = spawn_pos

	_attach_missile_warning_light(missile)
	_start_missile_warning_blink(missile)
	_play_missile_sound()

	var player_pos: Vector2 = _player.global_position
	var to_target: Vector2 = player_pos - missile.global_position
	var move_dir: Vector2 = Vector2.DOWN
	if to_target.length_squared() > 0.0001:
		move_dir = to_target.normalized()

	var hit_pos: Vector2 = player_pos - move_dir * maxf(0.0, missile_hit_distance_from_player)

	if move_dir.length_squared() > 0.0001:
		missile.global_rotation = Vector2.UP.angle_to(move_dir)

	var fly_tween: Tween = missile.create_tween()
	fly_tween.tween_property(missile, "global_position", hit_pos, maxf(0.01, travel_duration)).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	var missile_instance_id: int = missile.get_instance_id()
	fly_tween.tween_callback(_on_missile_finished.bind(missile_instance_id))


func _get_missile_spawn_position() -> Vector2:
	if _missile_launch_node != null and is_instance_valid(_missile_launch_node):
		return _missile_launch_node.global_position
	return Vector2.ZERO


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


func _configure_warning_light_sprite(warning_light: Sprite2D, owner_node: Node2D) -> void:
	if warning_light == null:
		return
	warning_light.texture = _get_missile_warning_light_texture()
	warning_light.centered = true
	warning_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	warning_light.z_index = 10
	var diameter_px: float = maxf(2.0, missile_warning_radius_px * 2.0 * maxf(0.1, missile_warning_light_scale))
	var texture_width: float = maxf(1.0, warning_light.texture.get_size().x)
	var local_scale: float = diameter_px / texture_width
	var owner_scale_x: float = 1.0
	var owner_scale_y: float = 1.0
	if owner_node != null:
		owner_scale_x = absf(owner_node.scale.x)
		owner_scale_y = absf(owner_node.scale.y)
	var owner_scale_avg: float = maxf(0.001, (owner_scale_x + owner_scale_y) * 0.5)
	warning_light.scale = Vector2.ONE * (local_scale / owner_scale_avg)
	var base_color: Color = missile_warning_light_color
	warning_light.modulate = Color(base_color.r, base_color.g, base_color.b, 0.0)
	if missile_warning_additive_blend:
		var add_material: CanvasItemMaterial = warning_light.material as CanvasItemMaterial
		if add_material == null:
			add_material = CanvasItemMaterial.new()
			warning_light.material = add_material
		add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	else:
		warning_light.material = null


func _get_missile_warning_light_texture() -> Texture2D:
	var texture_size_px: int = clampi(int(round(missile_warning_radius_px * 4.0)), 48, 256)
	var signature: String = "%d|%.3f" % [texture_size_px, missile_warning_falloff_power]
	if _missile_warning_light_texture != null and _missile_warning_light_texture_signature == signature:
		return _missile_warning_light_texture
	_missile_warning_light_texture_signature = signature
	var image: Image = Image.create(texture_size_px, texture_size_px, false, Image.FORMAT_RGBA8)
	var center: Vector2 = Vector2(float(texture_size_px) * 0.5, float(texture_size_px) * 0.5)
	var radius: float = maxf(1.0, float(texture_size_px) * 0.5)
	var falloff_power: float = maxf(0.6, missile_warning_falloff_power)
	for y in range(texture_size_px):
		for x in range(texture_size_px):
			var sample_pos: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var d_norm: float = center.distance_to(sample_pos) / radius
			if d_norm >= 1.0:
				image.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))
				continue
			var t: float = 1.0 - d_norm
			var alpha: float = pow(t, falloff_power)
			alpha += smoothstep(0.62, 1.0, t) * 0.22
			alpha = clampf(alpha, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	_missile_warning_light_texture = ImageTexture.create_from_image(image)
	return _missile_warning_light_texture


func _start_missile_warning_blink(missile: Node2D) -> void:
	if not missile_warning_enabled:
		return
	if missile == null or not is_instance_valid(missile):
		return
	_missile_warning_blink_token += 1
	_blink_missile_warning_once(missile, _missile_warning_blink_token)
	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5
	var missile_instance_id: int = missile.get_instance_id()
	var token: int = _missile_warning_blink_token
	_schedule_missile_warning_blink(token, missile_instance_id, beat_seconds)


func _on_missile_warning_blink_timeout(token: int, missile_instance_id: int) -> void:
	if token != _missile_warning_blink_token:
		return
	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D
	if missile_node == null or not is_instance_valid(missile_node):
		return
	_blink_missile_warning_once(missile_node, token)
	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5
	_schedule_missile_warning_blink(token, missile_instance_id, beat_seconds)


func _schedule_missile_warning_blink(token: int, missile_instance_id: int, beat_seconds: float) -> void:
	if token != _missile_warning_blink_token:
		return
	_missile_warning_blink_instance_id = missile_instance_id
	_missile_warning_next_blink_time = _get_music_clock_time() + beat_seconds


func _process_missile_warning_blink() -> void:
	if _missile_warning_next_blink_time < 0.0:
		return
	if _get_music_clock_time() < _missile_warning_next_blink_time:
		return
	var missile_instance_id: int = _missile_warning_blink_instance_id
	var token: int = _missile_warning_blink_token
	_missile_warning_next_blink_time = -1.0
	_on_missile_warning_blink_timeout(token, missile_instance_id)


func _blink_missile_warning_once(missile: Node2D, _token: int) -> void:
	if missile == null or not is_instance_valid(missile):
		return
	var warning_light: Sprite2D = missile.get_node_or_null("MissileWarningLight") as Sprite2D
	if warning_light == null:
		return
	_configure_warning_light_sprite(warning_light, missile)
	var beat_seconds: float = EventBus.beat_interval
	if beat_seconds <= 0.0:
		beat_seconds = 0.5
	var flash_ratio: float = clampf(missile_warning_flash_ratio, 0.05, 0.95)
	var flash_duration: float = maxf(0.03, beat_seconds * flash_ratio)
	var base_color: Color = missile_warning_light_color
	var peak_alpha: float = clampf(missile_warning_peak_alpha, 0.0, 1.0)
	var off_color: Color = Color(base_color.r, base_color.g, base_color.b, 0.0)
	var on_color: Color = Color(base_color.r, base_color.g, base_color.b, peak_alpha)
	warning_light.modulate = off_color
	if warning_light.get_tree() == null:
		return
	var flash_tween: Tween = warning_light.create_tween()
	flash_tween.tween_property(warning_light, "modulate", on_color, flash_duration * 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(warning_light, "modulate", off_color, flash_duration * 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _play_missile_sound() -> void:
	if missile_attack_sound == null:
		return
	SFXManager.play_stream(missile_attack_sound, -5.0)


func _on_missile_finished(missile_instance_id: int) -> void:
	var missile_obj: Object = instance_from_id(missile_instance_id)
	var missile_node: Node2D = missile_obj as Node2D
	if missile_node != null and is_instance_valid(missile_node):
		missile_node.queue_free()
	if _active_missile == missile_node:
		_active_missile = null


func _clear_active_missile() -> void:
	_missile_warning_blink_token += 1
	_missile_warning_next_blink_time = -1.0
	_missile_warning_blink_instance_id = 0
	if _active_missile != null and is_instance_valid(_active_missile):
		_active_missile.queue_free()
	_active_missile = null


func _try_fire_missiles() -> void:
	if _current_config.attack_type != TutorialBattleConfig.AttackType.ALTERNATING_MISSILE_CHARGE and _current_config.attack_type != TutorialBattleConfig.AttackType.MISSILE:
		return
	if _music_player == null:
		return

	var current_time: float = _get_music_clock_time()
	var beat_interval: float = EventBus.beat_interval
	if beat_interval <= 0.0:
		beat_interval = 0.5

	while _missile_fired_count < _missile_target_times.size():
		var target_time: float = _missile_target_times[_missile_fired_count]
		var spawn_time: float = target_time - 3.0 * beat_interval
		if current_time >= spawn_time:
			_missile_fired_count += 1
			_spawn_missile(target_time)
		else:
			break


func _get_music_clock_time() -> float:
	return RhythmClock.get_music_time(_music_player)
