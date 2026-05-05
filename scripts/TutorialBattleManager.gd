extends Node
class_name TutorialBattleManager

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
@export var battle_zone_paths: Array[NodePath] = []

var _state: BattleState = BattleState.IDLE
var _current_battle_index: int = -1
var _current_config: TutorialBattleConfig = null
var _success_count: int = 0
var _camera: Camera2D = null
var _player: CharacterBody2D = null
var _game_ui: CanvasLayer = null
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

signal battle_started(battle_id: int)
signal battle_ended(battle_id: int)
signal all_battles_completed


func _ready() -> void:
	EventBus.judgment_made.connect(_on_judgment_made)
	_hide_health_bars()


func _process(_delta: float) -> void:
	if _state != BattleState.PLAYING or not _battle_active:
		return
	if _track_manager and _track_manager.scheduled_notes.size() <= 4:
		_append_more_notes()


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

	if _camera_tween:
		_camera_tween.kill()
	_camera_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_camera_tween.tween_property(_camera, "zoom", target_zoom, 0.6)
	_camera_tween.parallel().tween_property(_camera, "global_position", target_position, 0.6)


func _begin_battle() -> void:
	_state = BattleState.PLAYING
	_battle_active = true

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

	EventBus.beat_interval = _beat_interval

	_generate_and_emit_chart()

	if _music_player:
		_music_player.auto_play = false
		if _music_player.has_method("load_and_play_music"):
			_music_player.load_and_play_music(_current_config.music_path)

	battle_started.emit(_current_config.battle_id)


func _generate_and_emit_chart() -> void:
	var note_type: Note.NoteType = _config_attack_type_to_note_type(_current_config.attack_type)
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
		note.type = note_type
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
	var note_type: Note.NoteType = _config_attack_type_to_note_type(_current_config.attack_type)
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
		note.type = note_type
		new_notes.append(note)
	_last_generated_beat = _last_generated_beat + float(batch_size * _current_config.beat_interval_beats)
	if _track_manager.has_method("append_scheduled_notes"):
		_track_manager.append_scheduled_notes(new_notes)


func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
	if _state != BattleState.PLAYING or not _battle_active:
		return
	if _current_config == null:
		return

	var expected_note_type: Note.NoteType = _config_attack_type_to_note_type(_current_config.attack_type)
	if track != expected_note_type:
		return

	if judgment != 3:
		_success_count += 1
		if _success_count >= _current_config.required_successes and not _ending_scheduled:
			_battle_active = false
			_ending_scheduled = true
			var delay: float = _beat_interval * 2.0
			get_tree().create_timer(delay).timeout.connect(_end_battle)


func _end_battle() -> void:
	_state = BattleState.ENDED
	_battle_active = false
	_ending_scheduled = false

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
	return _success_count


func get_required_successes() -> int:
	if _current_config:
		return _current_config.required_successes
	return 0
