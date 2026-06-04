extends Node

const RhythmClock := preload("res://scripts/RhythmClock.gd")
const MusicClockEventQueue := preload("res://scripts/MusicClockEventQueue.gd")
const HitNoteSideAssignments := preload("res://scripts/HitNoteSideAssignments.gd")
const TrackCueRequestRegistry := preload("res://scripts/TrackCueRequestRegistry.gd")
const SpriteAnimationDuration := preload("res://scripts/SpriteAnimationDuration.gd")
const PrejudgeKeyHintStyle := preload("res://scripts/PrejudgeKeyHintStyle.gd")
const TrackedNoteRuntime := preload("res://scripts/TrackedNoteRuntime.gd")
## 轨道管理器 - 负责生成和管理音符的可视化


# 预制场景
const BLING_SCENE := preload("res://scenes/bling.tscn")
const PREJUDGE_KEY_HINT_SCRIPT := preload("res://scripts/PrejudgeKeyHint.gd")
const SETTINGS_FILE_PATH: String = "user://settings.cfg"
const SETTINGS_GAMEPLAY_SECTION: String = "gameplay"
const SETTINGS_PREJUDGE_HINT_MODE_KEY: String = "prejudge_key_hint_display_mode"

# Bling 特效配置
const BLING_BASE_X: float = 50.0  # 特效基础X坐标（屏幕左侧）
const BLING_OFFSET_X: float = 50.0  # 同行多个特效的水平偏移
const BLING_ROW_HEIGHT: float = 50.0  # 每行高度
const BLING_START_Y: float = 230.0  # 第一行Y坐标
const BLING_ANIMATIONS: Dictionary = {
	Note.NoteType.GUARD: "bling_blue",
	Note.NoteType.HIT: "bling_red",
	Note.NoteType.DODGE: "bling_green"
}
# 特效行排列顺序：blue第一排(J键)、red第二排(I键)、green第三排(L键)
const BLING_ROW_ORDER: Dictionary = {
	Note.NoteType.GUARD: 0,  # blue - 第一排 (J键)
	Note.NoteType.HIT: 1,    # red - 第二排 (I键)
	Note.NoteType.DODGE: 2   # green - 第三排 (L键)
}

# 生成提前量（拍数）
const SPAWN_ADVANCE := {
	Note.NoteType.GUARD: 1,  # 提前1拍（生成即播动画）(J键，第一轨道)
	Note.NoteType.HIT: 3,    # 提前3拍（生成后1拍不动，2拍移动）(I键，第二轨道)
	Note.NoteType.DODGE: 3   # 提前3拍（生成后1拍不动，2拍移动）(L键，第三轨道)
}

const MISSILE_SIDE_LEFT: int = 0
const MISSILE_SIDE_RIGHT: int = 1
const GUARD_LASER_BEAT_ALIGNMENT_FRAME: int = 2

const MISS_THRESHOLD: float = GameConstants.MISS_THRESHOLD

# 非可视音符追踪（用于判定和 MISS 检测）
var tracked_notes: Array[Note] = []
var _cue_requests: RefCounted = TrackCueRequestRegistry.new()
var _hit_note_sides: RefCounted = HitNoteSideAssignments.new()
var _boss_node: Node2D = null

# 音符生成音效配置
@export_group("Boss 导弹联动")
@export_node_path("Node2D") var boss_node_path: NodePath = NodePath("../Boss")
@export_range(0.0, 4.0, 0.25) var boss_charge_prepare_lead_beats: float = 0.75
@export var debug_missile_timing: bool = false
@export var debug_charge_timing: bool = false
@export_group("")

# 轨道动画配置（可配置每种音符类型的攻击动画，未配置则使用默认 Bling）
@export var track_animation_config: TrackAnimationConfig = null

# 各轨道动画轮换播放位置节点（在场景中放置 Marker2D/Node2D 并拖拽到此处）
# GUARD 建议配置 2 个、HIT 3 个、DODGE 4 个，使连续动画不重合
@export_group("动画位置节点")
@export var guard_position_nodes: Array[Node2D] = []
@export var hit_position_nodes: Array[Node2D] = []
@export var dodge_position_nodes: Array[Node2D] = []
@export_subgroup("Laser Pattern Layers")
@export var laser_pattern_position_nodes: Array[Node2D] = []
@export var laser_pattern_warn_position_nodes: Array[Node2D] = []
@export_range(0.05, 2.0, 0.05) var laser_pattern_warning_duration_beats: float = 1.0

# 可选：直接复用场景内现有 AnimatedSprite2D（不创建实例，保持原始位置不变）
@export_group("外部动画节点")
@export_node_path("AnimatedSprite2D") var guard_external_anim_sprite_path: NodePath
@export_node_path("AnimatedSprite2D") var hit_external_anim_sprite_path: NodePath
@export_node_path("AnimatedSprite2D") var dodge_external_anim_sprite_path: NodePath
@export var dodge_external_anim_persistent: bool = false
@export_group("")

# 教程模式配置
@export_group("教程模式")
@export var tutorial_mode: bool = false
@export_group("")

# 预警特效轮换播放位置节点（在主动画前1拍显示，数量应与对应轨道动画位置节点一致）
@export_subgroup("预警位置节点")
@export var guard_warn_position_nodes: Array[Node2D] = []
@export var hit_warn_position_nodes: Array[Node2D] = []
@export var dodge_warn_position_nodes: Array[Node2D] = []
@export_group("")

# CanvasLayer 引用（用于添加动画实例，在场景编辑器中设置指向 GameUI）
@export var game_ui: CanvasLayer = null

@export_group("Prejudge Key Hints")
@export var enable_prejudge_key_hint: bool = true
@export_enum("Always", "Limited") var prejudge_key_hint_display_mode: int = 1
@export_range(0, 10, 1) var defense_hint_max_per_attack_type: int = 2
@export_node_path("Node2D") var hint_player_node_path: NodePath = NodePath("../../Character")
@export var hint_guard_offset: Vector2 = Vector2(-70.0, -110.0)  # J: 左上
@export var hint_hit_offset: Vector2 = Vector2(0.0, -120.0)      # I: 正上
@export var hint_dodge_offset: Vector2 = Vector2(70.0, -110.0)    # L: 右上
@export_group("")

# 同级兄弟节点引用
@onready var music_player: Node = get_node("../MusicPlayer")

var current_chart: Chart = null
var scheduled_notes: Array[Note] = []  # 待生成的音符
var scheduled_laser_warnings: Array[Dictionary] = []
var current_time: float = 0.0
var is_paused: bool = false  # 是否暂停生成音符
var pause_start_time: float = 0.0  # 暂停开始的时间
var _attack_phase_blocked: bool = false



# 活跃的 Bling 特效追踪（按轨道分组，用于避免重叠）
var _active_blings: Dictionary = {}

# 活跃的预警特效追踪
var _active_warns: Array[Node2D] = []

# 轨道动画轮换计数器（用于循环使用不同位置，避免连续动画重叠）
var _spawn_counters: Dictionary = {
	Note.NoteType.GUARD: 0,
	Note.NoteType.HIT: 0,
	Note.NoteType.DODGE: 0
}

# 外部动画播放令牌（用于忽略过期延迟回调）
var _external_anim_tokens: Dictionary = {
	Note.NoteType.GUARD: 0,
	Note.NoteType.HIT: 0,
	Note.NoteType.DODGE: 0
}

var _effect_runtime_token: int = 0
var _hint_runtime_token: int = 0
var _active_key_hints: Array[Node2D] = []
var _hint_mode_toast_label: Label = null
var _hint_mode_toast_tween: Tween = null
var _hint_mode_toast_token: int = 0
var _music_clock_events: RefCounted = MusicClockEventQueue.new()
var _defense_hint_shown_counts: Dictionary = {
	Note.NoteType.GUARD: 0,
	Note.NoteType.HIT: 0,
	Note.NoteType.DODGE: 0
}


func _ready() -> void:
	_load_prejudge_hint_settings()
	_reset_defense_hint_counts()

	# 通过 EventBus 连接信号（替代 get_node 硬编码路径）
	EventBus.chart_loaded.connect(set_chart)
	EventBus.boss_energy_depleted.connect(_on_attack_phase_started)
	EventBus.attack_phase_started.connect(_on_attack_phase_started)
	EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	if not game_ui:
		push_warning("[TrackManager] game_ui 未设置，请在编辑器中拖拽 GameUI 节点到 @export")
	_resolve_boss_node()
	
	# 音符生成音效通过 SFXManager 播放，无需创建独立播放器

	# 外部动画节点在待机时保持隐藏，避免常驻显示
	for note_type in [Note.NoteType.GUARD, Note.NoteType.HIT, Note.NoteType.DODGE]:
		var external_sprite: AnimatedSprite2D = _get_external_anim_sprite(note_type)
		if external_sprite:
			external_sprite.stop()
			var persistent: bool = false
			if note_type == Note.NoteType.DODGE:
				persistent = dodge_external_anim_persistent
			if not persistent:
				external_sprite.visible = false


func _unhandled_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null:
		return
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode != KEY_F5:
		return

	_toggle_prejudge_hint_display_mode()
	get_viewport().set_input_as_handled()


func _load_prejudge_hint_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var err: int = config.load(SETTINGS_FILE_PATH)
	if err != OK:
		return

	var saved_mode: int = int(config.get_value(
		SETTINGS_GAMEPLAY_SECTION,
		SETTINGS_PREJUDGE_HINT_MODE_KEY,
		prejudge_key_hint_display_mode
	))
	prejudge_key_hint_display_mode = clampi(saved_mode, 0, 1)


func _save_prejudge_hint_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	var load_err: int = config.load(SETTINGS_FILE_PATH)
	if load_err != OK and load_err != ERR_FILE_NOT_FOUND:
		return

	config.set_value(
		SETTINGS_GAMEPLAY_SECTION,
		SETTINGS_PREJUDGE_HINT_MODE_KEY,
		prejudge_key_hint_display_mode
	)
	config.save(SETTINGS_FILE_PATH)


func _toggle_prejudge_hint_display_mode() -> void:
	prejudge_key_hint_display_mode = 1 if prejudge_key_hint_display_mode == 0 else 0
	_reset_defense_hint_counts()
	_save_prejudge_hint_settings()

	var mode_text: String = "Always" if prejudge_key_hint_display_mode == 0 else "Limited"
	_show_hint_mode_status_toast(mode_text)
	print("[HintMode] Key hint mode changed to: ", mode_text, " (F5)")


func _show_hint_mode_status_toast(mode_text: String) -> void:
	if game_ui == null:
		return

	if _hint_mode_toast_label == null or not is_instance_valid(_hint_mode_toast_label):
		_hint_mode_toast_label = Label.new()
		_hint_mode_toast_label.name = "HintModeToastLabel"
		_hint_mode_toast_label.text = ""
		_hint_mode_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint_mode_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hint_mode_toast_label.add_theme_font_size_override("font_size", 24)
		_hint_mode_toast_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.72, 1.0))
		_hint_mode_toast_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
		_hint_mode_toast_label.add_theme_constant_override("shadow_offset_x", 2)
		_hint_mode_toast_label.add_theme_constant_override("shadow_offset_y", 2)
		_hint_mode_toast_label.anchor_left = 0.0
		_hint_mode_toast_label.anchor_right = 1.0
		_hint_mode_toast_label.anchor_top = 0.0
		_hint_mode_toast_label.anchor_bottom = 0.0
		_hint_mode_toast_label.offset_top = 68.0
		_hint_mode_toast_label.offset_bottom = 108.0
		_hint_mode_toast_label.visible = false
		game_ui.add_child(_hint_mode_toast_label)

	if _hint_mode_toast_tween != null:
		_hint_mode_toast_tween.kill()
		_hint_mode_toast_tween = null

	_hint_mode_toast_token += 1
	var token: int = _hint_mode_toast_token
	_hint_mode_toast_label.text = "Key Hints: " + mode_text
	_hint_mode_toast_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_hint_mode_toast_label.visible = true

	_hint_mode_toast_tween = create_tween()
	_hint_mode_toast_tween.tween_interval(0.7)
	_hint_mode_toast_tween.tween_property(_hint_mode_toast_label, "modulate:a", 0.0, 0.25)
	_hint_mode_toast_tween.finished.connect(func() -> void:
		if token != _hint_mode_toast_token:
			return
		if _hint_mode_toast_label != null and is_instance_valid(_hint_mode_toast_label):
			_hint_mode_toast_label.visible = false
		_hint_mode_toast_tween = null
	)


func _process(_delta: float) -> void:
	# 如果暂停，不生成新音符
	if is_paused:
		return
	
	# 获取当前音乐时间
	if music_player and music_player.playing:
		current_time = _get_music_clock_time()
		_process_music_clock_events(current_time)
		_check_and_spawn_laser_warnings_by_time(current_time)
		
		# 检查是否需要生成音符（基于时间）
		_check_and_spawn_notes_by_time(current_time)
		
		# 检查非可视追踪音符的 MISS
		_process_tracked_note_runtime(current_time)


## 设置铺面数据
func set_chart(chart: Chart) -> void:
	clear_all_notes()
	current_chart = chart
	scheduled_notes = chart.notes.duplicate()
	_apply_laser_patterns_to_schedule(chart)
	_assign_hit_note_sides()
	print("TrackManager loaded chart: notes=", scheduled_notes.size(), ", laser_warnings=", scheduled_laser_warnings.size())


func _apply_laser_patterns_to_schedule(chart: Chart) -> void:
	scheduled_laser_warnings.clear()
	if chart == null:
		return

	var laser_patterns: Array = chart.get("laser_patterns")
	for pattern_value in laser_patterns:
		var pattern: Resource = pattern_value as Resource
		if pattern == null:
			continue
		var warning_steps: Array = pattern.get("warning_steps")
		var fire_steps: Array = pattern.get("fire_steps")
		for warning_step in warning_steps:
			scheduled_laser_warnings.append(warning_step.duplicate())
		for fire_step in fire_steps:
			var note := Note.new()
			note.type = Note.NoteType.GUARD
			note.beat_number = float(fire_step["beat_number"])
			note.beat_time = float(fire_step["beat_time"])
			note.slot_index = int(fire_step["slot_index"])
			note.source_layer = String(fire_step.get("source_layer", pattern.get("source_layer")))
			scheduled_notes.append(note)

	scheduled_notes.sort_custom(func(a: Note, b: Note) -> bool:
		return a.beat_time < b.beat_time
	)
	scheduled_laser_warnings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["beat_time"]) < float(b["beat_time"])
	)


func _assign_hit_note_sides() -> void:
	_hit_note_sides.assign_notes(scheduled_notes)


func _process_tracked_note_runtime(now_time: float) -> void:
	var resolved: Dictionary = TrackedNoteRuntime.collect_resolved_notes(
		tracked_notes,
		now_time,
		MISS_THRESHOLD,
		Callable(self, "_should_silently_drop_runtime_note")
	)

	for note in resolved["dropped_notes"]:
		tracked_notes.erase(note)
		_erase_note_runtime_state(note)

	for note in resolved["missed_notes"]:
		tracked_notes.erase(note)
		_erase_note_runtime_state(note)
		EventBus.miss_triggered.emit(note.type)


## 检查并生成需要提前生成的音符（基于时间）
func _check_and_spawn_laser_warnings_by_time(now_time: float) -> void:
	for warning_step in scheduled_laser_warnings.duplicate():
		if now_time < float(warning_step["beat_time"]):
			continue
		scheduled_laser_warnings.erase(warning_step)
		_spawn_laser_pattern_warning(warning_step)


func _spawn_laser_pattern_warning(warning_step: Dictionary) -> void:
	if _attack_phase_blocked:
		return
	if track_animation_config == null:
		return

	var warn_note := Note.new()
	warn_note.type = Note.NoteType.GUARD
	warn_note.beat_number = float(warning_step["beat_number"])
	warn_note.beat_time = float(warning_step["beat_time"])
	warn_note.slot_index = int(warning_step["slot_index"])
	warn_note.source_layer = String(warning_step.get("source_layer", "laser_pattern"))

	_spawn_guard_warn_animation(warn_note, warn_note.slot_index, laser_pattern_warning_duration_beats)
	_play_boss_attack_sound_for_note_type(Note.NoteType.GUARD, true)


func _check_and_spawn_notes_by_time(now_time: float) -> void:
	for note in scheduled_notes.duplicate():
		if note.type == Note.NoteType.HIT:
			var marked_side: int = _hit_note_sides.get_side(note)
			if _is_missile_side_destroyed(marked_side):

				scheduled_notes.erase(note)
				_cue_requests.erase(note)
				_hit_note_sides.erase(note)

				if debug_missile_timing:
					var side_name: String = "LEFT" if marked_side == MISSILE_SIDE_LEFT else "RIGHT"
					print("[MissileDebug][Track] skip hit_note=#", note.beat_number, " reason=marked_side_destroyed side=", side_name)
				continue

		if not _is_note_type_enabled_by_boss_parts(note.type):
			scheduled_notes.erase(note)
			_cue_requests.erase(note)
			if debug_missile_timing and note.type == Note.NoteType.HIT:
				print("[MissileDebug][Track] skip hit_note=#", note.beat_number, " reason=missile_parts_destroyed")
			if debug_charge_timing and note.type == Note.NoteType.DODGE:
				print("[ChargeDebug][Track] skip dodge_note=#", note.beat_number, " reason=middle_part_destroyed")
			continue

		var advance_beats: int = _get_spawn_advance_beats(note)
		var beat_interval: float = EventBus.beat_interval
		if beat_interval <= 0.0:
			beat_interval = 0.5
		var spawn_time: float = note.beat_time - advance_beats * beat_interval
		if note.type == Note.NoteType.HIT:
			var prepare_seconds: float = _get_boss_return_prepare_seconds()
			var request_time: float = spawn_time - prepare_seconds
			if now_time >= request_time and not _cue_requests.has_missile_request(note):
				var remaining_beats_to_hit: float = maxf(0.0, (note.beat_time - now_time) / beat_interval)
				var marked_side: int = _hit_note_sides.get_side(note)
				if _boss_node != null and is_instance_valid(_boss_node) and _boss_node.has_method("enqueue_missile_forced_side"):
					_boss_node.call("enqueue_missile_forced_side", marked_side)
				EventBus.boss_missile_requested.emit(remaining_beats_to_hit)
				if debug_missile_timing:
					var side_name: String = "LEFT" if marked_side == MISSILE_SIDE_LEFT else "RIGHT"
					print("[MissileDebug][Track] request hit_note=#", note.beat_number,
						" now=", "%.3f" % now_time,
						" request_time=", "%.3f" % request_time,
						" spawn_time=", "%.3f" % spawn_time,
						" prepare_s=", "%.3f" % prepare_seconds,
						" remain_beats=", "%.3f" % remaining_beats_to_hit,
						" side=", side_name)
				_cue_requests.mark_missile_request(note)

		if note.type == Note.NoteType.DODGE:
			var charge_prepare_lead_beats: float = maxf(0.0, boss_charge_prepare_lead_beats)
			var charge_request_time: float = spawn_time - charge_prepare_lead_beats * beat_interval
			if now_time >= charge_request_time and not _cue_requests.has_charge_request(note):
				var charge_remaining_beats_to_hit: float = maxf(0.0, (note.beat_time - now_time) / beat_interval)
				EventBus.boss_charge_requested.emit(charge_remaining_beats_to_hit)
				if debug_charge_timing:
					print("[ChargeDebug][Track] request dodge_note=#", note.beat_number,
						" now=", "%.3f" % now_time,
						" request_time=", "%.3f" % charge_request_time,
						" spawn_time=", "%.3f" % spawn_time,
						" remain_beats=", "%.3f" % charge_remaining_beats_to_hit)
				_cue_requests.mark_charge_request(note)
		
		# 如果当前时间已经到达或超过音符的生成时间
		if now_time >= spawn_time:
			if debug_charge_timing and note.type == Note.NoteType.DODGE:
				print("[ChargeDebug][Track] spawn dodge_note=#", note.beat_number,
					" now=", "%.3f" % now_time,
					" spawn_time=", "%.3f" % spawn_time)
			if debug_missile_timing and note.type == Note.NoteType.HIT:
				print("[MissileDebug][Track] spawn hit_note=#", note.beat_number,
					" now=", "%.3f" % now_time,
					" spawn_time=", "%.3f" % spawn_time)

			if (note.type == Note.NoteType.HIT or note.type == Note.NoteType.DODGE) and not tutorial_mode and not _is_attack_visual_ready_for_note(note.type):
				scheduled_notes.erase(note)
				_cue_requests.erase(note)
				if debug_missile_timing and note.type == Note.NoteType.HIT:
					print("[MissileDebug][Track] skip hit_note=#", note.beat_number, " reason=visual_not_active")
				if debug_charge_timing and note.type == Note.NoteType.DODGE:
					print("[ChargeDebug][Track] skip dodge_note=#", note.beat_number, " reason=visual_not_active")
				continue

			_spawn_note(note)
			scheduled_notes.erase(note)
			_cue_requests.erase(note)


func _get_spawn_advance_beats(note: Note) -> int:
	if note != null and SPAWN_ADVANCE.has(note.type):
		return int(SPAWN_ADVANCE[note.type])
	return 2


func _is_attack_visual_ready_for_note(note_type: Note.NoteType) -> bool:
	if _boss_node == null or not is_instance_valid(_boss_node):
		_resolve_boss_node()
	if _boss_node == null or not is_instance_valid(_boss_node):
		if note_type == Note.NoteType.GUARD:
			return true
		return false
	if _boss_node.has_method("is_track_attack_visual_active"):
		return bool(_boss_node.call("is_track_attack_visual_active", int(note_type)))
	return true


func _is_missile_side_destroyed(side: int) -> bool:
	if _boss_node == null or not is_instance_valid(_boss_node):
		_resolve_boss_node()
	if _boss_node == null or not is_instance_valid(_boss_node):
		return false
	if _boss_node.has_method("is_missile_side_destroyed"):
		return bool(_boss_node.call("is_missile_side_destroyed", side))
	return false


func _get_boss_return_prepare_seconds() -> float:
	if _boss_node == null or not is_instance_valid(_boss_node):
		_resolve_boss_node()

	var beat_interval: float = EventBus.beat_interval
	if beat_interval <= 0.0:
		beat_interval = 0.5

	var pre_return_enabled: bool = true
	if _boss_node != null and is_instance_valid(_boss_node):
		if _boss_node.has_method("is_pre_missile_return_enabled"):
			pre_return_enabled = bool(_boss_node.call("is_pre_missile_return_enabled"))
		else:
			var enabled_value: Variant = _boss_node.get("enable_pre_missile_return")
			if enabled_value != null:
				pre_return_enabled = bool(enabled_value)

	if not pre_return_enabled:
		if debug_missile_timing:
			print("[MissileDebug][Track] pre-return disabled, prepare_s=0")
		return 0.0

	var prepare_seconds: float = beat_interval
	if debug_missile_timing:
		print("[MissileDebug][Track] fixed prepare_s=", "%.3f" % prepare_seconds, " (1 beat)")
	return prepare_seconds


func _resolve_boss_node() -> void:
	if _boss_node != null and is_instance_valid(_boss_node):
		return

	if not boss_node_path.is_empty():
		_boss_node = get_node_or_null(boss_node_path) as Node2D

	if _boss_node == null:
		var parent_node: Node = get_parent()
		if parent_node != null:
			_boss_node = parent_node.get_node_or_null("Boss") as Node2D

	if _boss_node == null:
		var scene_root: Node = get_tree().current_scene
		if scene_root != null:
			_boss_node = scene_root.find_child("Boss", true, false) as Node2D

	if _boss_node == null:
		return

	if debug_missile_timing:
		print("[MissileDebug][Track] boss resolved: ", _boss_node.get_path())


## 生成音符
func _spawn_note(note: Note) -> void:
	if _attack_phase_blocked:
		return
	if not _is_note_type_enabled_by_boss_parts(note.type):
		return

	_schedule_prejudge_key_hint(note)

	# HIT / DODGE 轨道改为驱动 Boss 状态机攻击状态，不再走原轨道特效
	# DODGE 的蓄力请求在 _check_and_spawn_notes_by_time 中提前发送。
	# 教程模式下 HIT/DIT/DODGE 均使用外部动画节点，需要生成轨道动画
	var skip_track_anim: bool = (note.type == Note.NoteType.HIT or note.type == Note.NoteType.DODGE) and not tutorial_mode
	if tutorial_mode and note.type == Note.NoteType.HIT and not _has_external_anim_path(note.type):
		skip_track_anim = true
	if not skip_track_anim:
		_spawn_track_animation(note)

	tracked_notes.append(note)


func _is_note_type_enabled_by_boss_parts(note_type: Note.NoteType) -> bool:
	if _boss_node == null or not is_instance_valid(_boss_node):
		_resolve_boss_node()
	if _boss_node == null or not is_instance_valid(_boss_node):
		return true

	if note_type == Note.NoteType.DODGE:
		# 中间部位破坏后也允许继续蓄力，不再禁用 DODGE 轨道。
		return true

	if note_type == Note.NoteType.HIT:
		if _boss_node.has_method("are_missile_parts_all_destroyed"):
			return not bool(_boss_node.call("are_missile_parts_all_destroyed"))
		return true

	return true


func _should_silently_drop_runtime_note(note: Note) -> bool:
	if note == null:
		return true

	if not _is_note_type_enabled_by_boss_parts(note.type):
		return true

	if note.type == Note.NoteType.HIT:
		var marked_side: int = _hit_note_sides.get_side(note)
		if _is_missile_side_destroyed(marked_side):
			return true

	return false


func _erase_note_runtime_state(note: Note) -> void:
	if note == null:
		return
	_cue_requests.erase(note)
	if note.type == Note.NoteType.HIT:
		_hit_note_sides.erase(note)


## 在音符到判定线前 1 拍显示按键提示（玩家头顶）
func _schedule_prejudge_key_hint(note: Note) -> void:
	if not enable_prejudge_key_hint:
		return
	if _attack_phase_blocked:
		return
	if not game_ui:
		return
	if EventBus.beat_interval <= 0.0:
		return

	var token: int = _hint_runtime_token

	var hint_time: float = note.beat_time - EventBus.beat_interval
	var delay: float = hint_time - current_time

	if delay <= 0.01:
		if token == _hint_runtime_token and not _attack_phase_blocked:
			_spawn_prejudge_key_hint(note.type)
		return

	_schedule_music_clock_event(hint_time, Callable(self, "_on_prejudge_key_hint_time"), [token, note.type])


func _on_prejudge_key_hint_time(token: int, note_type: Note.NoteType) -> void:
	if token != _hint_runtime_token:
		return
	if _attack_phase_blocked:
		return
	_spawn_prejudge_key_hint(note_type)


func _spawn_prejudge_key_hint(note_type: Note.NoteType) -> void:
	if not enable_prejudge_key_hint:
		return
	if _attack_phase_blocked:
		return
	if not game_ui:
		return
	if not _can_show_prejudge_hint(note_type):
		return

	var hint := PREJUDGE_KEY_HINT_SCRIPT.new() as PrejudgeKeyHint
	if hint == null:
		return

	var hint_style: Dictionary = PrejudgeKeyHintStyle.get_style(note_type)
	var key_text: String = hint_style["key_text"]
	var core_color: Color = hint_style["core_color"]
	var glyph_family: String = String(hint_style.get("glyph_family", ""))

	hint.setup(key_text, EventBus.beat_interval, core_color, Color(1.0, 1.0, 1.0, 0.95), Color(1.0, 1.0, 1.0, 1.0), glyph_family)
	game_ui.add_child(hint)
	hint.position = _get_hint_screen_position(note_type)
	_active_key_hints.append(hint)
	_increment_prejudge_hint_count(note_type)


func _get_hint_screen_position(note_type: Note.NoteType) -> Vector2:
	var player_node: Node2D = null
	if not hint_player_node_path.is_empty():
		player_node = get_node_or_null(hint_player_node_path) as Node2D

	var offset: Vector2 = hint_hit_offset
	match note_type:
		Note.NoteType.GUARD:
			offset = hint_guard_offset
		Note.NoteType.HIT:
			offset = hint_hit_offset
		Note.NoteType.DODGE:
			offset = hint_dodge_offset

	if player_node != null:
		var world_pos: Vector2 = player_node.global_position + offset
		return get_viewport().get_canvas_transform() * world_pos

	# 兜底：屏幕左侧角色区域上方三点位
	return Vector2(220.0, 80.0) + offset


## 清除所有活跃的音符
func clear_all_notes() -> void:
	_invalidate_effect_callbacks()
	_clear_active_key_hints()

	tracked_notes.clear()
	_cue_requests.clear()
	_music_clock_events.clear()
	# 清除所有活跃的 Bling 特效
	for track_type in _active_blings:
		for bling in _active_blings[track_type]:
			if bling and is_instance_valid(bling):
				bling.queue_free()
	_active_blings.clear()
	# 清除所有活跃的预警特效
	for warn in _active_warns:
		if warn and is_instance_valid(warn):
			warn.queue_free()
	_active_warns.clear()
	# 重置轮换计数器
	for key in _spawn_counters:
		_spawn_counters[key] = 0
	print("已清除所有活跃音符")


func append_scheduled_notes(notes: Array[Note]) -> void:
	for note in notes:
		scheduled_notes.append(note)
		_hit_note_sides.append_note(note)
	scheduled_notes.sort_custom(func(a: Note, b: Note) -> bool: return a.beat_time < b.beat_time)


func _clear_active_key_hints() -> void:
	for hint in _active_key_hints:
		if hint and is_instance_valid(hint):
			hint.queue_free()
	_active_key_hints.clear()


func _invalidate_effect_callbacks() -> void:
	_effect_runtime_token += 1
	_hint_runtime_token += 1
	_music_clock_events.clear()
	for note_type in _external_anim_tokens.keys():
		_external_anim_tokens[note_type] = int(_external_anim_tokens[note_type]) + 1

	for note_type in [Note.NoteType.GUARD, Note.NoteType.HIT, Note.NoteType.DODGE]:
		var sprite: AnimatedSprite2D = _get_external_anim_sprite(note_type)
		if sprite and is_instance_valid(sprite):
			sprite.stop()
			var persistent: bool = false
			if note_type == Note.NoteType.DODGE:
				persistent = dodge_external_anim_persistent
			if not persistent:
				sprite.visible = false

	SFXManager.stop_all()


## 暂停音符生成
func pause_note_spawning() -> void:
	is_paused = true
	pause_start_time = current_time
	_music_clock_events.clear()
	print("音符生成已暂停，时间: ", pause_start_time)


## 恢复音符生成
func discard_attack_interrupted_notes(cutoff_time: float) -> void:
	var removed_count: int = 0
	var beat_interval: float = EventBus.beat_interval
	if beat_interval <= 0.0:
		beat_interval = 0.5

	for note in scheduled_notes.duplicate():
		var advance_beats: int = _get_spawn_advance_beats(note)
		var spawn_time: float = note.beat_time - advance_beats * beat_interval
		var should_discard: bool = spawn_time <= cutoff_time
		if note.type == Note.NoteType.HIT and _cue_requests.has_missile_request(note):
			should_discard = true
		elif note.type == Note.NoteType.DODGE and _cue_requests.has_charge_request(note):
			should_discard = true

		if not should_discard:
			continue

		scheduled_notes.erase(note)
		_cue_requests.erase(note)
		_hit_note_sides.erase(note)
		removed_count += 1

	for warning_step in scheduled_laser_warnings.duplicate():
		if float(warning_step["beat_time"]) <= cutoff_time:
			scheduled_laser_warnings.erase(warning_step)

	if removed_count > 0:
		print("Attack phase discarded ", removed_count, " interrupted defense notes")


func resume_note_spawning() -> void:
	# 先更新当前时间到最新值（避免使用暂停前的旧时间）
	if music_player and music_player.playing:
		current_time = _get_music_clock_time()
	
	# 清理所有已错过“生成时机”的音符，避免恢复后首帧补生成并立刻 MISS。
	var removed_count: int = 0
	var beat_interval: float = EventBus.beat_interval
	if beat_interval <= 0.0:
		beat_interval = 0.5
	
	for note in scheduled_notes.duplicate():
		var advance_beats: int = _get_spawn_advance_beats(note)
		var spawn_time: float = note.beat_time - advance_beats * beat_interval
		if spawn_time <= current_time:
			scheduled_notes.erase(note)
			_cue_requests.erase(note)
			_hit_note_sides.erase(note)
			removed_count += 1

	for warning_step in scheduled_laser_warnings.duplicate():
		if float(warning_step["beat_time"]) <= current_time:
			scheduled_laser_warnings.erase(warning_step)
	
	if removed_count > 0:
		print("已跳过 ", removed_count, " 个生成时机已过的音符")
	
	# 清空残留追踪，确保恢复时轨道判定干净。
	for i in range(tracked_notes.size() - 1, -1, -1):
		tracked_notes.remove_at(i)

	# 最后才恢复生成（避免_process在清理前执行）
	is_paused = false
	pause_start_time = 0.0
	
	print("音符生成已恢复")


func _on_attack_phase_started() -> void:
	if tutorial_mode:
		return
	if _attack_phase_blocked:
		return
	_attack_phase_blocked = true
	current_time = _get_music_clock_time()
	discard_attack_interrupted_notes(current_time)
	pause_note_spawning()
	clear_all_notes()


func _on_attack_phase_ended() -> void:
	_attack_phase_blocked = false
	# 由 ScoreManager 的 _on_pause_timeout 统一恢复生成，
	# 避免 attack_phase_ended（提前半拍）导致过早恢复。


func _can_show_prejudge_hint(note_type: Note.NoteType) -> bool:
	# 教学模式下强制全程显示按键提示
	if tutorial_mode:
		return true
	
	# 全程显示：忽略每轨显示次数上限
	if prejudge_key_hint_display_mode == 0:
		return true

	# 部分显示：沿用现有每轨次数上限逻辑
	if defense_hint_max_per_attack_type <= 0:
		return false
	var shown_count: int = int(_defense_hint_shown_counts.get(note_type, 0))
	return shown_count < defense_hint_max_per_attack_type


func _increment_prejudge_hint_count(note_type: Note.NoteType) -> void:
	var shown_count: int = int(_defense_hint_shown_counts.get(note_type, 0))
	_defense_hint_shown_counts[note_type] = shown_count + 1


func _reset_defense_hint_counts() -> void:
	_defense_hint_shown_counts[Note.NoteType.GUARD] = 0
	_defense_hint_shown_counts[Note.NoteType.HIT] = 0
	_defense_hint_shown_counts[Note.NoteType.DODGE] = 0


## 生成轨道动画（音符生成时自动播放，attack_end_frame 对齐判定时刻）
func _spawn_track_animation(note: Note) -> void:
	if _attack_phase_blocked:
		return

	var counter: int = _spawn_counters[note.type]
	_spawn_counters[note.type] = counter + 1
	
	if note.type == Note.NoteType.GUARD:
		if _uses_laser_pattern_positions(note):
			_spawn_guard_laser_attack(note, counter)
		else:
			_spawn_guard_warn_animation(note, counter, 1.0)
			_play_boss_attack_sound_for_note_type(Note.NoteType.GUARD, true)
			_spawn_guard_laser_attack(note, counter)
		return

	var advance_beats: int = _get_spawn_advance_beats(note)
	var main_target_beats: int = advance_beats
	_spawn_main_animation(note, main_target_beats, counter)


## 生成预警特效（在主动画之前显示，持续1拍后自动销毁）
func _get_main_position_nodes(note: Note) -> Array[Node2D]:
	if note.type == Note.NoteType.GUARD and _uses_laser_pattern_positions(note) and laser_pattern_position_nodes.size() > 0:
		return laser_pattern_position_nodes
	match note.type:
		Note.NoteType.GUARD:
			return guard_position_nodes
		Note.NoteType.HIT:
			return hit_position_nodes
		Note.NoteType.DODGE:
			return dodge_position_nodes
	return []


func _get_warn_position_nodes(note: Note) -> Array[Node2D]:
	if note.type == Note.NoteType.GUARD and _uses_laser_pattern_positions(note) and laser_pattern_warn_position_nodes.size() > 0:
		return laser_pattern_warn_position_nodes
	match note.type:
		Note.NoteType.GUARD:
			return guard_warn_position_nodes
		Note.NoteType.HIT:
			return hit_warn_position_nodes
		Note.NoteType.DODGE:
			return dodge_warn_position_nodes
	return []


func _get_position_node_index(note: Note, counter: int, node_count: int) -> int:
	if node_count <= 0:
		return 0
	if note.slot_index >= 0:
		return clampi(note.slot_index, 0, node_count - 1)
	return counter % node_count


func _uses_laser_pattern_positions(note: Note) -> bool:
	return note != null and not note.source_layer.is_empty() and note.source_layer.to_lower().contains("laser")


func _spawn_guard_warn_animation(note: Note, counter: int, duration_beats: float = 1.0) -> void:
	if track_animation_config == null:
		return

	var warn_scene: PackedScene = track_animation_config.get_warn_scene(Note.NoteType.GUARD)
	if warn_scene == null:
		return

	_spawn_warn(note, warn_scene, counter, duration_beats)


func _on_guard_laser_attack_time(token: int, note: Note, counter: int) -> void:
	if token != _effect_runtime_token or _attack_phase_blocked:
		return
	if note == null:
		return

	_play_guard_laser_attack(note, counter)


func _spawn_guard_laser_attack(note: Note, counter: int) -> void:
	var attack_start_time: float = _get_guard_laser_attack_start_time(note)
	if current_time >= attack_start_time - 0.001:
		_play_guard_laser_attack(note, counter)
		return

	var token: int = _effect_runtime_token
	_schedule_music_clock_event(attack_start_time, Callable(self, "_on_guard_laser_attack_time"), [token, note, counter])


func _play_guard_laser_attack(note: Note, counter: int) -> void:
	_spawn_main_animation(note, 0, counter, GUARD_LASER_BEAT_ALIGNMENT_FRAME)


func _get_guard_laser_attack_start_time(note: Note) -> float:
	if note == null:
		return _get_music_clock_time()
	return note.beat_time - _get_guard_laser_alignment_lead_seconds()


func _get_guard_laser_alignment_lead_seconds() -> float:
	if track_animation_config == null:
		return 0.0

	var scene: PackedScene = track_animation_config.get_scene(Note.NoteType.GUARD)
	if scene == null:
		return 0.0

	var instance: Node2D = scene.instantiate()
	var anim_sprite: AnimatedSprite2D = instance.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim_sprite == null:
		instance.queue_free()
		return 0.0

	var sprite_frames: SpriteFrames = anim_sprite.sprite_frames
	var anim_name: String = _resolve_animation_name_for_sprite(
		Note.NoteType.GUARD,
		track_animation_config.get_animation_name(Note.NoteType.GUARD),
		sprite_frames
	)
	var lead_seconds: float = 0.0
	if not anim_name.is_empty() and sprite_frames != null and sprite_frames.has_animation(anim_name):
		lead_seconds = SpriteAnimationDuration.get_duration(
			sprite_frames,
			anim_name,
			0,
			maxi(0, GUARD_LASER_BEAT_ALIGNMENT_FRAME - 1)
		)

	instance.queue_free()
	return maxf(0.0, lead_seconds)


func _spawn_warn(note: Note, warn_scene: PackedScene, counter: int, duration_beats: float = 1.0) -> void:
	var instance: Node2D = warn_scene.instantiate()
	
	# 获取预警位置节点
	var warn_pos_nodes: Array[Node2D] = _get_warn_position_nodes(note)
	
	if warn_pos_nodes.size() > 0:
		var pos_node: Node2D = warn_pos_nodes[_get_position_node_index(note, counter, warn_pos_nodes.size())]
		game_ui.add_child(instance)
		instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
	else:
		# 无预警位置节点时回退到主动画位置节点
		var pos_nodes: Array[Node2D] = _get_main_position_nodes(note)
		if pos_nodes.size() > 0:
			var pos_node: Node2D = pos_nodes[_get_position_node_index(note, counter, pos_nodes.size())]
			game_ui.add_child(instance)
			instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
		else:
			game_ui.add_child(instance)
	
	# 追踪预警实例（用于攻击阶段强制清除）
	_active_warns.append(instance)

	# 1拍后自动销毁
	var warn_duration: float = EventBus.beat_interval * maxf(0.05, duration_beats)
	var token: int = _effect_runtime_token
	var warn_instance_id: int = instance.get_instance_id()
	_schedule_music_clock_event(_get_music_clock_time() + warn_duration, Callable(self, "_on_warn_effect_timeout"), [token, warn_instance_id])
	
	print("[Warn] %s | counter=%d | duration=%.4fs" % [note.get_type_string(), counter, warn_duration])


func _on_warn_effect_timeout(token: int, warn_instance_id: int) -> void:
	if token != _effect_runtime_token:
		return
	_queue_free_node_by_instance_id(warn_instance_id)
	_erase_active_warn_by_id(warn_instance_id)


func _erase_active_warn_by_id(warn_instance_id: int) -> void:
	for i in range(_active_warns.size() - 1, -1, -1):
		var warn_node: Node = _active_warns[i] as Node
		if warn_node == null or not is_instance_valid(warn_node):
			_active_warns.remove_at(i)
			continue
		if warn_node.get_instance_id() == warn_instance_id:
			_active_warns.remove_at(i)


## 生成主轨道动画（立即播放，通过速度缩放使 attack_end_frame 对齐判定时刻）
func _spawn_main_animation(note: Note, target_beats: int, counter: int, alignment_frame: int = -1) -> void:
	# 只要配置了外部节点路径，就强制使用外部节点，不再回退到实例化特效
	if _has_external_anim_path(note.type):
		var forced_external_sprite: AnimatedSprite2D = _get_external_anim_sprite(note.type)
		if forced_external_sprite:
			var forced_anim_name: String = ""
			if track_animation_config:
				forced_anim_name = track_animation_config.get_animation_name(note.type)
			_play_external_track_animation(note, target_beats, forced_anim_name, forced_external_sprite)
			_play_boss_attack_sound_for_note_type(note.type, false)
			return
		push_warning("[TrackManager] 已配置外部动画路径，但未找到节点，已跳过该轨道动画: %s" % note.get_type_string())
		return

	# 决定使用自定义动画还是默认 Bling
	var scene: PackedScene = null
	var anim_name: String = ""
	
	if track_animation_config:
		scene = track_animation_config.get_scene(note.type)
		anim_name = track_animation_config.get_animation_name(note.type)

	if not game_ui:
		return
	
	# 未配置自定义动画时回退到默认 Bling
	var use_default_bling: bool = (scene == null)
	if use_default_bling:
		scene = BLING_SCENE
		anim_name = BLING_ANIMATIONS[note.type]
	
	var instance: Node2D = scene.instantiate()
	var anim_sprite: AnimatedSprite2D = instance.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	
	if not anim_sprite:
		push_warning("轨道动画场景缺少 AnimatedSprite2D 子节点")
		instance.queue_free()
		return

	var sprite_frames: SpriteFrames = anim_sprite.sprite_frames
	var resolved_anim_name: String = _resolve_animation_name_for_sprite(note.type, anim_name, sprite_frames)
	if resolved_anim_name.is_empty():
		instance.queue_free()
		return
	
	# === 计算播放速度 ===
	var target_duration: float = target_beats * EventBus.beat_interval
	var remaining_to_judge: float = note.beat_time - current_time
	if remaining_to_judge > 0.0:
		target_duration = remaining_to_judge
	var anim_speed_scale: float = 1.0
	var attack_end_delay: float = -1.0
	
	if sprite_frames and sprite_frames.has_animation(resolved_anim_name):
		# 获取攻击结束帧配置（-1 表示不设置）
		var attack_end_frame: int = alignment_frame
		if track_animation_config and not use_default_bling:
			if attack_end_frame < 0:
				attack_end_frame = track_animation_config.get_attack_end_frame(note.type)
		
		var frame_count: int = sprite_frames.get_frame_count(resolved_anim_name)
		
		if attack_end_frame > 0 and attack_end_frame < frame_count:
			# 计算帧 0 到 attack_end_frame-1 在原始速度下的播放时长，反推 speed_scale。
			var partial_duration: float = SpriteAnimationDuration.get_duration(sprite_frames, resolved_anim_name, 0, attack_end_frame - 1)
			if partial_duration > 0.0 and target_duration > 0.0:
				anim_speed_scale = clampf(partial_duration / target_duration, 0.05, 20.0)
				attack_end_delay = partial_duration / anim_speed_scale
			
			print("[TrackAnim] %s | anim=%s | total_frames=%d | attack_end_frame=%d | partial_dur=%.4fs | target_dur=%.4fs | speed_scale=%.4f" % [
				note.get_type_string(), resolved_anim_name, frame_count, attack_end_frame,
				partial_duration, target_duration, anim_speed_scale
			])
		else:
			print("[TrackAnim] %s | anim=%s | total_frames=%d | no attack_end_frame | target_dur=%.4fs | original speed" % [
				note.get_type_string(), resolved_anim_name, frame_count, target_duration
			])
	
	# 连接动画完成信号，播放结束后自动销毁
	var instance_id: int = instance.get_instance_id()
	anim_sprite.animation_finished.connect(_on_track_effect_animation_finished.bind(instance_id))
	
	# === 计算播放位置 ===
	# 根据音符类型获取对应的位置节点数组
	var pos_nodes: Array[Node2D] = _get_main_position_nodes(note)
	
	if pos_nodes.size() > 0:
		var pos_node: Node2D = pos_nodes[_get_position_node_index(note, counter, pos_nodes.size())]
		# 使用传入的计数器轮换位置，避免连续动画重叠
		# 先 add_child 再赋位置，将世界坐标转换为屏幕坐标（CanvasLayer 使用屏幕坐标系）
		game_ui.add_child(instance)
		instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
	else:
		# 默认 Bling 位置：固定行排列 + 同行槽位偏移
		var row_index: int = BLING_ROW_ORDER[note.type]
		var row_y: float = BLING_START_Y + row_index * BLING_ROW_HEIGHT
		var x_offset: float = _get_bling_x_offset(note.type)
		game_ui.add_child(instance)
		instance.position = Vector2(BLING_BASE_X + x_offset, row_y)
	
	# === 播放动画，并应用速度缩放 ===
	if track_animation_config and track_animation_config.get_flip_h(note.type):
		instance.scale.x = -instance.scale.x
	anim_sprite.speed_scale = anim_speed_scale
	anim_sprite.play(resolved_anim_name)
	_play_boss_attack_sound_for_note_type(note.type, false)
	
	# 追踪活跃特效（用于默认 Bling 槽位避重）
	if not _active_blings.has(note.type):
		_active_blings[note.type] = []
	_active_blings[note.type].append(instance)


func _on_track_effect_animation_finished(instance_id: int) -> void:
	var node_obj: Object = instance_from_id(instance_id)
	var node: Node = node_obj as Node
	if node != null and is_instance_valid(node):
		node.queue_free()

func _queue_free_node_by_instance_id(instance_id: int) -> void:
	var node_obj: Object = instance_from_id(instance_id)
	var node: Node = node_obj as Node
	if node != null and is_instance_valid(node):
		node.queue_free()


## 指定轨道是否配置了外部 AnimatedSprite2D 路径
func _has_external_anim_path(note_type: Note.NoteType) -> bool:
	match note_type:
		Note.NoteType.GUARD:
			return not guard_external_anim_sprite_path.is_empty()
		Note.NoteType.HIT:
			return not hit_external_anim_sprite_path.is_empty()
		Note.NoteType.DODGE:
			return not dodge_external_anim_sprite_path.is_empty()
	return false


## 获取指定轨道的外部 AnimatedSprite2D，未配置时返回 null
func _get_external_anim_sprite(note_type: Note.NoteType) -> AnimatedSprite2D:
	var path: NodePath
	match note_type:
		Note.NoteType.GUARD:
			path = guard_external_anim_sprite_path
		Note.NoteType.HIT:
			path = hit_external_anim_sprite_path
		Note.NoteType.DODGE:
			path = dodge_external_anim_sprite_path

	if path.is_empty():
		return null

	var sprite: AnimatedSprite2D = get_node_or_null(path) as AnimatedSprite2D
	if sprite:
		return sprite

	# 兜底：第三轨道默认尝试 Boss/Charge/ChargeAnim
	if note_type == Note.NoteType.DODGE:
		var current_scene: Node = get_tree().current_scene
		if current_scene:
			sprite = current_scene.get_node_or_null("Boss/Charge/ChargeAnim") as AnimatedSprite2D
			if sprite:
				return sprite
			sprite = current_scene.find_child("ChargeAnim", true, false) as AnimatedSprite2D
			if sprite:
				return sprite

	return null


## 在外部 AnimatedSprite2D 上播放轨道动画（不改变该节点位置）
func _play_external_track_animation(note: Note, target_beats: int, configured_anim_name: String, anim_sprite: AnimatedSprite2D) -> void:
	var sprite_frames: SpriteFrames = anim_sprite.sprite_frames
	if sprite_frames == null:
		push_warning("外部动画节点缺少 SpriteFrames")
		return

	var requested_anim_name: String = configured_anim_name
	if requested_anim_name.is_empty():
		requested_anim_name = String(anim_sprite.animation)
	var anim_name: String = _resolve_animation_name_for_sprite(note.type, requested_anim_name, sprite_frames)
	if anim_name.is_empty():
		return

	var target_duration: float = target_beats * EventBus.beat_interval
	var remaining_to_judge: float = note.beat_time - current_time
	if remaining_to_judge > 0.0:
		target_duration = remaining_to_judge

	var start_frame: int = 0
	var attack_end_frame: int = -1
	if track_animation_config:
		start_frame = track_animation_config.get_start_frame(note.type)
		attack_end_frame = track_animation_config.get_attack_end_frame(note.type)

	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	start_frame = clampi(start_frame, 0, frame_count - 1)
	if attack_end_frame < 0 or attack_end_frame >= frame_count:
		attack_end_frame = frame_count - 1
	if attack_end_frame < start_frame:
		attack_end_frame = start_frame

	var speed_scale: float = 1.0
	var base_duration: float = 0.0
	if attack_end_frame > start_frame:
		base_duration = SpriteAnimationDuration.get_duration(sprite_frames, anim_name, start_frame, attack_end_frame - 1)
	if base_duration > 0.0 and target_duration > 0.0:
		speed_scale = base_duration / target_duration

	var full_duration: float = SpriteAnimationDuration.get_duration(sprite_frames, anim_name, start_frame, frame_count - 1)
	var play_duration: float = target_duration
	if speed_scale > 0.0 and full_duration > 0.0:
		play_duration = full_duration / speed_scale

	var token: int = _external_anim_tokens[note.type] + 1
	_external_anim_tokens[note.type] = token

	var runtime_token: int = _effect_runtime_token
	var note_type: int = int(note.type)
	var anim_sprite_id: int = anim_sprite.get_instance_id()

	print("[ExtAnim] %s | anim=%s | frames=%d | start=%d | end=%d | base_dur=%.4f | target_dur=%.4f | speed=%.4f | play_dur=%.4f | remaining=%.4f | bi=%.4f" % [
		note.get_type_string(), anim_name, frame_count, start_frame, attack_end_frame,
		base_duration, target_duration, speed_scale, play_duration, remaining_to_judge, EventBus.beat_interval
	])

	_start_external_track_animation(note_type, token, runtime_token, anim_sprite_id, anim_name, play_duration, speed_scale, start_frame)


func _start_external_track_animation(note_type: int, token: int, runtime_token: int, anim_sprite_id: int, anim_name: String, play_duration: float, speed_scale: float = 1.0, start_frame: int = 0) -> void:
	if _external_anim_tokens[note_type] != token:
		return
	if runtime_token != _effect_runtime_token or _attack_phase_blocked:
		return

	var anim_obj: Object = instance_from_id(anim_sprite_id)
	var anim_sprite: AnimatedSprite2D = anim_obj as AnimatedSprite2D
	if anim_sprite == null or not is_instance_valid(anim_sprite):
		return

	anim_sprite.visible = true
	anim_sprite.stop()
	anim_sprite.speed_scale = maxf(0.01, speed_scale)
	anim_sprite.play(anim_name)
	anim_sprite.frame = start_frame
	anim_sprite.frame_progress = 0.0

	print("[ExtAnim] PLAY t=%.3f frame=%d progress=%.3f speed=%.4f anim=%s" % [
		_get_music_clock_time(), anim_sprite.frame, anim_sprite.frame_progress,
		anim_sprite.speed_scale, anim_name
	])

	_schedule_music_clock_event(
		_get_music_clock_time() + maxf(0.05, play_duration),
		Callable(self, "_on_external_anim_stop_timeout"),
		[note_type, token, runtime_token, anim_sprite_id]
	)


func _on_external_anim_stop_timeout(note_type: int, token: int, runtime_token: int, anim_sprite_id: int) -> void:
	if _external_anim_tokens[note_type] != token:
		return
	if runtime_token != _effect_runtime_token:
		return

	var anim_obj: Object = instance_from_id(anim_sprite_id)
	var anim_sprite: AnimatedSprite2D = anim_obj as AnimatedSprite2D
	if anim_sprite != null and is_instance_valid(anim_sprite):
		var persistent: bool = false
		if note_type == int(Note.NoteType.DODGE):
			persistent = dodge_external_anim_persistent
		if persistent:
			anim_sprite.stop()
			if anim_sprite.sprite_frames and anim_sprite.sprite_frames.has_animation(String(anim_sprite.animation)):
				anim_sprite.frame = 0
		else:
			anim_sprite.stop()
			anim_sprite.visible = false


## 解析可用动画名：优先请求名，失败后回退到轨道默认名，再回退到第一个可用动画
func _resolve_animation_name_for_sprite(note_type: Note.NoteType, requested_anim_name: String, sprite_frames: SpriteFrames) -> String:
	if sprite_frames == null:
		return ""

	if not requested_anim_name.is_empty() and sprite_frames.has_animation(requested_anim_name):
		return requested_anim_name

	var fallback_name: String = BLING_ANIMATIONS.get(note_type, "")
	if not fallback_name.is_empty() and sprite_frames.has_animation(fallback_name):
		if not requested_anim_name.is_empty():
			push_warning("动画 '%s' 不存在，已回退到 '%s'" % [requested_anim_name, fallback_name])
		return fallback_name

	var names: PackedStringArray = sprite_frames.get_animation_names()
	if names.size() > 0:
		if not requested_anim_name.is_empty():
			push_warning("动画 '%s' 不存在，已回退到首个动画 '%s'" % [requested_anim_name, String(names[0])])
		return String(names[0])

	push_warning("SpriteFrames 未包含任何动画")
	return ""


## 获取 Bling 特效的X偏移量（找到第一个没有被占据的位置）
func _get_bling_x_offset(note_type: Note.NoteType) -> float:
	if not _active_blings.has(note_type):
		return 0.0
	
	# 清理已销毁的特效引用
	_active_blings[note_type] = _active_blings[note_type].filter(
		func(e): return e != null and is_instance_valid(e)
	)
	
	# 收集所有已占据的X位置（取整到槽位索引避免浮点误差）
	var occupied_slots: Array[int] = []
	for existing_bling in _active_blings[note_type]:
		var slot: int = roundi((existing_bling.position.x - BLING_BASE_X) / BLING_OFFSET_X)
		if slot not in occupied_slots:
			occupied_slots.append(slot)
	
	# 找到第一个未被占据的槽位
	var target_slot: int = 0
	while target_slot in occupied_slots:
		target_slot += 1
	
	return target_slot * BLING_OFFSET_X


## 播放音符生成音效
func _schedule_music_clock_event(target_time: float, callback: Callable, args: Array = []) -> void:
	_music_clock_events.schedule(target_time, callback, args)


func _process_music_clock_events(now: float) -> void:
	_music_clock_events.process(now)


func _play_boss_attack_sound_for_note_type(note_type: Note.NoteType, is_warn: bool = false) -> void:
	if GameConfigs.sound == null or GameConfigs.sound.boss_sounds == null:
		return
	var attack_type: int = -1
	match note_type:
		Note.NoteType.GUARD:
			attack_type = BossAttackSoundConfig.ATTACK_LASER
		_:
			return
	var cfg: BossAttackTypeSoundConfig = GameConfigs.sound.boss_sounds.get_config(attack_type)
	if cfg == null:
		return
	var pool: RandomSoundPool
	if is_warn and cfg.beat_sounds.size() > 0:
		pool = cfg.beat_sounds[0]
	elif not is_warn and cfg.beat_sounds.size() > 1:
		pool = cfg.beat_sounds[1]
	else:
		pool = cfg.default_sound
	if pool == null or pool.is_empty():
		return
	var bus: StringName = cfg.sfx_bus
	SFXManager.play_pool(pool, bus)


func _get_music_clock_time() -> float:
	return RhythmClock.get_music_time(music_player)
