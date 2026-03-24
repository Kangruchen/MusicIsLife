extends Node
## 轨道管理器 - 负责生成和管理音符的可视化


# 预制场景
const NOTE_VISUAL_SCENE := preload("res://scenes/NoteVisual.tscn")
const BLING_SCENE := preload("res://scenes/bling.tscn")
const PREJUDGE_KEY_HINT_SCRIPT := preload("res://scripts/PrejudgeKeyHint.gd")

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
	Note.NoteType.GUARD: 2,  # 提前2拍（生成后1拍不动，1拍移动）(J键，第一轨道)
	Note.NoteType.HIT: 3,    # 提前3拍（生成后1拍不动，2拍移动）(I键，第二轨道)
	Note.NoteType.DODGE: 4   # 提前4拍（生成后1拍不动，3拍移动）(L键，第三轨道)
}

# 音符生成位置X坐标（动态计算，在 _ready 中初始化）
var spawn_x: float = 900.0

# MISS 判定窗口 — 值与 GameConstants.MISS_THRESHOLD 同步
const MISS_THRESHOLD: float = 0.200

# 音符视觉生成开关（暂时停用）
var note_visual_enabled: bool = false

# 非可视音符追踪（用于判定和 MISS 检测）
var tracked_notes: Array[Note] = []

# 音符生成音效配置
@export var key_sound_config: KeySoundConfig = null

@export_group("临时音效")
@export var boss_laser_sound: AudioStream = preload("res://assets/SFX/laser3.wav")
@export var boss_laser_volume_db: float = -2.0
@export_range(0.0, 5.0, 0.01) var boss_laser_start_offset_sec: float = 0.0
@export_group("")

# 轨道动画配置（可配置每种音符类型的攻击动画，未配置则使用默认 Bling）
@export var track_animation_config: TrackAnimationConfig = null

# 各轨道动画轮换播放位置节点（在场景中放置 Marker2D/Node2D 并拖拽到此处）
# GUARD 建议配置 2 个、HIT 3 个、DODGE 4 个，使连续动画不重合
@export_group("动画位置节点")
@export var guard_position_nodes: Array[Node2D] = []
@export var hit_position_nodes: Array[Node2D] = []
@export var dodge_position_nodes: Array[Node2D] = []

# 可选：直接复用场景内现有 AnimatedSprite2D（不创建实例，保持原始位置不变）
@export_group("外部动画节点")
@export_node_path("AnimatedSprite2D") var guard_external_anim_sprite_path: NodePath
@export_node_path("AnimatedSprite2D") var hit_external_anim_sprite_path: NodePath
@export_node_path("AnimatedSprite2D") var dodge_external_anim_sprite_path: NodePath
@export_group("")

# 预警特效轮换播放位置节点（在主动画前1拍显示，数量应与对应轨道动画位置节点一致）
@export_subgroup("预警位置节点")
@export var guard_warn_position_nodes: Array[Node2D] = []
@export var hit_warn_position_nodes: Array[Node2D] = []
@export var dodge_warn_position_nodes: Array[Node2D] = []
@export_group("")

# CanvasLayer 引用（用于添加动画实例，在场景编辑器中设置指向 GameUI）
@export var game_ui: CanvasLayer = null

@export_group("判定前按键提示")
@export var enable_prejudge_key_hint: bool = true
@export_node_path("Node2D") var hint_player_node_path: NodePath = NodePath("../../Character")
@export var hint_guard_offset: Vector2 = Vector2(-70.0, -110.0)  # J: 左上
@export var hint_hit_offset: Vector2 = Vector2(0.0, -120.0)      # I: 正上
@export var hint_dodge_offset: Vector2 = Vector2(70.0, -110.0)    # L: 右上
@export_group("")

# 同级兄弟节点引用
@onready var music_player: Node = get_node("../MusicPlayer")

var current_chart: Chart = null
var active_notes: Array[NoteVisual] = []
var scheduled_notes: Array[Note] = []  # 待生成的音符
var current_time: float = 0.0
var is_paused: bool = false  # 是否暂停生成音符
var pause_start_time: float = 0.0  # 暂停开始的时间
var _attack_phase_blocked: bool = false

# 音符生成音效播放器
var spawn_audio_player_hit: AudioStreamPlayer = null
var spawn_audio_player_guard: AudioStreamPlayer = null
var spawn_audio_player_dodge: AudioStreamPlayer = null
var _boss_laser_audio_player: AudioStreamPlayer = null

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


func _ready() -> void:
	# 根据实际视口宽度动态计算音符生成X坐标（屏幕右侧外100px）
	spawn_x = get_viewport().get_visible_rect().size.x + 100.0
	
	# 通过 EventBus 连接信号（替代 get_node 硬编码路径）
	EventBus.beat_hit.connect(_on_beat_hit)
	EventBus.chart_loaded.connect(set_chart)
	EventBus.boss_energy_depleted.connect(_on_attack_phase_started)
	EventBus.attack_phase_started.connect(_on_attack_phase_started)
	EventBus.attack_phase_ended.connect(_on_attack_phase_ended)
	
	if not game_ui:
		push_warning("[TrackManager] game_ui 未设置，请在编辑器中拖拽 GameUI 节点到 @export")
	
	# 创建音符生成音效播放器
	spawn_audio_player_hit = AudioStreamPlayer.new()
	spawn_audio_player_guard = AudioStreamPlayer.new()
	spawn_audio_player_dodge = AudioStreamPlayer.new()
	
	spawn_audio_player_guard.name = "SpawnAudioGuard"
	spawn_audio_player_hit.name = "SpawnAudioHit"
	spawn_audio_player_dodge.name = "SpawnAudioDodge"
	
	add_child(spawn_audio_player_guard)
	add_child(spawn_audio_player_hit)
	add_child(spawn_audio_player_dodge)
	
	spawn_audio_player_guard.bus = "Master"
	spawn_audio_player_hit.bus = "Master"
	spawn_audio_player_dodge.bus = "Master"

	# Boss 激光临时音效播放器
	_boss_laser_audio_player = AudioStreamPlayer.new()
	_boss_laser_audio_player.name = "BossLaserAudio"
	_boss_laser_audio_player.bus = "Master"
	add_child(_boss_laser_audio_player)
	if boss_laser_sound:
		_boss_laser_audio_player.stream = boss_laser_sound
	_boss_laser_audio_player.volume_db = boss_laser_volume_db
	
	# 加载音符生成音效
	if key_sound_config:
		if key_sound_config.guard_sound:
			spawn_audio_player_guard.stream = key_sound_config.guard_sound
			spawn_audio_player_guard.volume_db = key_sound_config.guard_volume_db
		if key_sound_config.hit_sound:
			spawn_audio_player_hit.stream = key_sound_config.hit_sound
			spawn_audio_player_hit.volume_db = key_sound_config.hit_volume_db
		if key_sound_config.dodge_sound:
			spawn_audio_player_dodge.stream = key_sound_config.dodge_sound
			spawn_audio_player_dodge.volume_db = key_sound_config.dodge_volume_db

	# 外部动画节点在待机时保持隐藏，避免常驻显示
	for note_type in [Note.NoteType.GUARD, Note.NoteType.HIT, Note.NoteType.DODGE]:
		var external_sprite: AnimatedSprite2D = _get_external_anim_sprite(note_type)
		if external_sprite:
			external_sprite.stop()
			external_sprite.visible = false


func _process(_delta: float) -> void:
	# 如果暂停，不生成新音符
	if is_paused:
		return
	
	# 获取当前音乐时间
	if music_player and music_player.playing:
		current_time = music_player.get_playback_position() + AudioServer.get_time_to_next_mix()
		
		# 检查是否需要生成音符（基于时间）
		_check_and_spawn_notes_by_time(current_time)
		
		# 更新所有活跃音符
		for note_visual in active_notes:
			if note_visual and note_visual.is_active:
				note_visual.update_position(current_time)
				
				# 检查是否到达判定线前两拍，播放音符音效
				var time_before_target: float = note_visual.target_time - current_time
				var two_beats_duration: float = 2.0 * EventBus.beat_interval
				if not note_visual.spawn_sound_played and time_before_target <= two_beats_duration:
					_play_spawn_sound(note_visual.note_data.type)
					note_visual.spawn_sound_played = true
				
				# 检查是否超过判定窗口（自动 MISS）
				var time_past_target: float = current_time - note_visual.target_time
				if time_past_target > MISS_THRESHOLD:
					EventBus.miss_triggered.emit(note_visual.note_data.type)
					note_visual.is_active = false
					note_visual.destroy()
			elif note_visual:
				# 清理非活跃音符
				note_visual.destroy()
		
		# 移除已销毁的音符
		active_notes = active_notes.filter(func(n): return n != null and is_instance_valid(n))
		
		# 检查非可视追踪音符的 MISS
		for i in range(tracked_notes.size() - 1, -1, -1):
			var note: Note = tracked_notes[i]
			var time_past: float = current_time - note.beat_time
			if time_past > MISS_THRESHOLD:
				EventBus.miss_triggered.emit(note.type)
				tracked_notes.remove_at(i)


## 设置铺面数据
func set_chart(chart: Chart) -> void:
	current_chart = chart
	scheduled_notes = chart.notes.duplicate()
	print("轨道管理器已加载铺面，共 ", scheduled_notes.size(), " 个音符待生成")


## 节拍触发回调
func _on_beat_hit(beat_number: float, _note: Note) -> void:
	if not current_chart:
		return
	
	# 检查是否需要提前生成音符
	_check_and_spawn_notes(beat_number)


## 检查并生成需要提前生成的音符（基于时间）
func _check_and_spawn_notes_by_time(current_time: float) -> void:
	for note in scheduled_notes.duplicate():
		var advance_beats: int = SPAWN_ADVANCE[note.type]
		var spawn_time: float = note.beat_time - advance_beats * EventBus.beat_interval
		
		# 如果当前时间已经到达或超过音符的生成时间
		if current_time >= spawn_time:
			_spawn_note(note)
			scheduled_notes.erase(note)


## 检查并生成需要提前生成的音符（已废弃，保留用于节拍信号触发）
func _check_and_spawn_notes(current_beat: float) -> void:
	# 此方法已被 _check_and_spawn_notes_by_time 替代
	# 但保留用于兼容 beat_hit 信号的调用
	pass


## 生成音符
func _spawn_note(note: Note) -> void:
	if _attack_phase_blocked:
		return

	_schedule_prejudge_key_hint(note)

	# HIT / DODGE 轨道改为驱动 Boss 状态机攻击状态，不再走原轨道特效
	if note.type == Note.NoteType.HIT:
		EventBus.boss_missile_requested.emit(SPAWN_ADVANCE[Note.NoteType.HIT])
	if note.type == Note.NoteType.DODGE:
		EventBus.boss_charge_requested.emit(SPAWN_ADVANCE[Note.NoteType.DODGE])
	if note.type != Note.NoteType.HIT and note.type != Note.NoteType.DODGE:
		# 其他轨道沿用原特效逻辑
		_spawn_track_animation(note)
	
	if note_visual_enabled:
		# 可视模式：创建 NoteVisual 实例
		if not game_ui:
			return
		var notes_container: Control = game_ui.get_notes_container()
		if not notes_container:
			return
		
		var note_visual := NOTE_VISUAL_SCENE.instantiate() as NoteVisual
		var track_y: float = game_ui.get_track_y(note.type)
		var judgment_x: float = game_ui.get_judgment_line_x()
		var spawn_pos := Vector2(spawn_x, track_y)
		var target_pos := Vector2(judgment_x, track_y)
		
		var advance_beats: int = SPAWN_ADVANCE[note.type]
		var spawn_time: float = note.beat_time - advance_beats * EventBus.beat_interval
		var move_start_time: float = spawn_time + EventBus.beat_interval
		var target_time: float = note.beat_time
		
		note_visual.initialize(note, spawn_pos, target_pos, move_start_time, target_time)
		notes_container.add_child(note_visual)
		active_notes.append(note_visual)
		print("生成音符: 节拍 #", note.beat_number, " ", note.get_type_string(), " 在时间 ", "%.3f" % spawn_time)
	else:
		# 非可视模式：仅追踪音符用于判定
		tracked_notes.append(note)


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

	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if token != _hint_runtime_token:
			return
		if _attack_phase_blocked:
			return
		_spawn_prejudge_key_hint(note.type)
	)


func _spawn_prejudge_key_hint(note_type: Note.NoteType) -> void:
	if not enable_prejudge_key_hint:
		return
	if _attack_phase_blocked:
		return
	if not game_ui:
		return

	var hint := PREJUDGE_KEY_HINT_SCRIPT.new() as PrejudgeKeyHint
	if hint == null:
		return

	var key_text: String = "J"
	var core_color: Color = Color(0.22, 0.56, 0.98, 0.9)
	match note_type:
		Note.NoteType.GUARD:
			key_text = "J"
			core_color = Color(0.22, 0.56, 0.98, 0.9)
		Note.NoteType.HIT:
			key_text = "I"
			core_color = Color(0.95, 0.24, 0.24, 0.9)
		Note.NoteType.DODGE:
			key_text = "L"
			core_color = Color(0.20, 0.78, 0.38, 0.9)

	hint.setup(key_text, EventBus.beat_interval, core_color, Color(1.0, 1.0, 1.0, 0.95), Color(1.0, 1.0, 1.0, 1.0))
	game_ui.add_child(hint)
	hint.position = _get_hint_screen_position(note_type)
	_active_key_hints.append(hint)


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

	for note_visual in active_notes:
		if note_visual and is_instance_valid(note_visual):
			note_visual.destroy()
	active_notes.clear()
	tracked_notes.clear()
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


func _clear_active_key_hints() -> void:
	for hint in _active_key_hints:
		if hint and is_instance_valid(hint):
			hint.queue_free()
	_active_key_hints.clear()


func _invalidate_effect_callbacks() -> void:
	_effect_runtime_token += 1
	_hint_runtime_token += 1
	for note_type in _external_anim_tokens.keys():
		_external_anim_tokens[note_type] = int(_external_anim_tokens[note_type]) + 1

	for note_type in [Note.NoteType.GUARD, Note.NoteType.HIT, Note.NoteType.DODGE]:
		var sprite: AnimatedSprite2D = _get_external_anim_sprite(note_type)
		if sprite and is_instance_valid(sprite):
			sprite.stop()
			sprite.visible = false


## 暂停音符生成
func pause_note_spawning() -> void:
	is_paused = true
	pause_start_time = current_time
	print("音符生成已暂停，时间: ", pause_start_time)


## 恢复音符生成
func resume_note_spawning() -> void:
	# 先更新当前时间到最新值（避免使用暂停前的旧时间）
	if music_player and music_player.playing:
		current_time = music_player.get_playback_position() + AudioServer.get_time_to_next_mix()
	
	# 只清理判定时间在当前时间之前的音符（已经来不及打了）
	# 保留判定时间还在未来的音符，即使它们的生成时间已过
	var removed_count: int = 0
	var buffer_time: float = 0.2  # 0.2秒缓冲，太接近当前时间的也跳过
	
	for note in scheduled_notes.duplicate():
		# 如果音符的判定时间已经过去（加上小缓冲），则跳过
		if note.beat_time < (current_time - buffer_time):
			scheduled_notes.erase(note)
			removed_count += 1
	
	if removed_count > 0:
		print("已跳过 ", removed_count, " 个判定时间已过的音符")
	
	# 清理已过期的追踪音符
	for i in range(tracked_notes.size() - 1, -1, -1):
		if tracked_notes[i].beat_time < (current_time - buffer_time):
			tracked_notes.remove_at(i)
	
	# 最后才恢复生成（避免_process在清理前执行）
	is_paused = false
	pause_start_time = 0.0
	
	print("音符生成已恢复")


func _on_attack_phase_started() -> void:
	_attack_phase_blocked = true
	pause_note_spawning()
	clear_all_notes()


func _on_attack_phase_ended() -> void:
	_attack_phase_blocked = false
	# 由 ScoreManager 的 _on_pause_timeout 统一恢复生成，
	# 避免 attack_phase_ended（提前半拍）导致过早恢复。


## 生成轨道动画（音符生成时自动播放，attack_end_frame 对齐判定时刻）
func _spawn_track_animation(note: Note) -> void:
	if _attack_phase_blocked:
		return

	# 获取当前轮换计数器并递增（warn 和主动画共用同一计数器以保持位置配对）
	var counter: int = _spawn_counters[note.type]
	_spawn_counters[note.type] = counter + 1
	
	var advance_beats: int = SPAWN_ADVANCE[note.type]
	var main_target_beats: int = advance_beats

	# GUARD 激光不再播放预警：从第一拍开始直接播放。
	# 对齐窗口使用完整提前量（GUARD=2拍），使 guard_attack_end_frame 在第二拍结束时到达。

	# 第一拍直接播放主动画
	_spawn_main_animation(note, main_target_beats, counter)


func _schedule_guard_laser_sound(delay: float) -> void:
	if delay <= 0.0:
		_play_boss_laser_sound()
		return

	var token: int = _effect_runtime_token
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if token != _effect_runtime_token or _attack_phase_blocked:
			return
		_play_boss_laser_sound()
	)


func _play_boss_laser_sound() -> void:
	if _boss_laser_audio_player == null:
		return
	if _boss_laser_audio_player.stream == null:
		return
	_boss_laser_audio_player.stop()
	_boss_laser_audio_player.play(maxf(0.0, boss_laser_start_offset_sec))


## 生成预警特效（在主动画之前显示，持续1拍后自动销毁）
func _spawn_warn(note: Note, warn_scene: PackedScene, counter: int) -> void:
	var instance: Node2D = warn_scene.instantiate()
	
	# 获取预警位置节点
	var warn_pos_nodes: Array[Node2D]
	match note.type:
		Note.NoteType.GUARD: warn_pos_nodes = guard_warn_position_nodes
		Note.NoteType.HIT:   warn_pos_nodes = hit_warn_position_nodes
		Note.NoteType.DODGE: warn_pos_nodes = dodge_warn_position_nodes
	
	if warn_pos_nodes.size() > 0:
		var pos_node: Node2D = warn_pos_nodes[counter % warn_pos_nodes.size()]
		game_ui.add_child(instance)
		instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
	else:
		# 无预警位置节点时回退到主动画位置节点
		var pos_nodes: Array[Node2D]
		match note.type:
			Note.NoteType.GUARD: pos_nodes = guard_position_nodes
			Note.NoteType.HIT:   pos_nodes = hit_position_nodes
			Note.NoteType.DODGE: pos_nodes = dodge_position_nodes
		if pos_nodes.size() > 0:
			var pos_node: Node2D = pos_nodes[counter % pos_nodes.size()]
			game_ui.add_child(instance)
			instance.position = get_viewport().get_canvas_transform() * pos_node.global_position
		else:
			game_ui.add_child(instance)
	
	# 追踪预警实例（用于攻击阶段强制清除）
	_active_warns.append(instance)

	# 1拍后自动销毁
	var warn_duration: float = EventBus.beat_interval
	var token: int = _effect_runtime_token
	get_tree().create_timer(warn_duration).timeout.connect(func() -> void:
		if token != _effect_runtime_token:
			return
		if instance and is_instance_valid(instance):
			instance.queue_free()
		_active_warns.erase(instance)
	)
	
	print("[Warn] %s | counter=%d | duration=%.4fs" % [note.get_type_string(), counter, warn_duration])


## 生成主轨道动画（立即播放，通过速度缩放使 attack_end_frame 对齐判定时刻）
func _spawn_main_animation(note: Note, target_beats: int, counter: int) -> void:
	# 只要配置了外部节点路径，就强制使用外部节点，不再回退到实例化特效
	if _has_external_anim_path(note.type):
		var forced_external_sprite: AnimatedSprite2D = _get_external_anim_sprite(note.type)
		if forced_external_sprite:
			var forced_anim_name: String = ""
			if track_animation_config:
				forced_anim_name = track_animation_config.get_animation_name(note.type)
			_play_external_track_animation(note, target_beats, forced_anim_name, forced_external_sprite)
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
	# 优先使用“当前时刻到该音符判定时刻”的真实剩余时间，避免节拍估算误差导致错位。
	var target_duration: float = target_beats * EventBus.beat_interval
	var remaining_to_judge: float = note.beat_time - current_time
	if remaining_to_judge > 0.0:
		target_duration = remaining_to_judge
	var anim_speed_scale: float = 1.0
	var attack_end_delay: float = -1.0
	
	if sprite_frames and sprite_frames.has_animation(resolved_anim_name):
		# 获取攻击结束帧配置（-1 表示不设置）
		var attack_end_frame: int = -1
		if track_animation_config and not use_default_bling:
			attack_end_frame = track_animation_config.get_attack_end_frame(note.type)
		
		var frame_count: int = sprite_frames.get_frame_count(resolved_anim_name)
		
		if attack_end_frame > 0 and attack_end_frame < frame_count:
			# 计算帧 0 到 attack_end_frame-1 在原始速度下的播放时长，反推 speed_scale。
			var partial_duration: float = _get_animation_duration(sprite_frames, resolved_anim_name, 0, attack_end_frame - 1)
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
	anim_sprite.animation_finished.connect(func() -> void: instance.queue_free())
	
	# === 计算播放位置 ===
	# 根据音符类型获取对应的位置节点数组
	var pos_nodes: Array[Node2D]
	match note.type:
		Note.NoteType.GUARD: pos_nodes = guard_position_nodes
		Note.NoteType.HIT:   pos_nodes = hit_position_nodes
		Note.NoteType.DODGE: pos_nodes = dodge_position_nodes
	
	if pos_nodes.size() > 0:
		# 使用传入的计数器轮换位置，避免连续动画重叠
		var pos_node: Node2D = pos_nodes[counter % pos_nodes.size()]
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
	
	# === 立即播放动画，并应用速度缩放 ===
	anim_sprite.speed_scale = anim_speed_scale
	anim_sprite.play(resolved_anim_name)
	if note.type == Note.NoteType.GUARD:
		_schedule_guard_laser_sound(attack_end_delay)
	
	# 追踪活跃特效（用于默认 Bling 槽位避重）
	if not _active_blings.has(note.type):
		_active_blings[note.type] = []
	_active_blings[note.type].append(instance)


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
	var start_delay: float = 0.0
	var attack_end_frame: int = -1
	if track_animation_config:
		attack_end_frame = track_animation_config.get_attack_end_frame(note.type)

	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	if attack_end_frame > 0 and attack_end_frame < frame_count:
		var partial_duration: float = _get_animation_duration(sprite_frames, anim_name, 0, attack_end_frame - 1)
		start_delay = maxf(0.0, target_duration - partial_duration)

	# 更新令牌，保证同轨道只执行最新一次触发
	var token: int = _external_anim_tokens[note.type] + 1
	_external_anim_tokens[note.type] = token

	var play_duration: float = maxf(0.05, target_duration - start_delay)
	var runtime_token: int = _effect_runtime_token

	var play_func := func() -> void:
		if _external_anim_tokens[note.type] != token:
			return
		if runtime_token != _effect_runtime_token or _attack_phase_blocked:
			return
		if not is_instance_valid(anim_sprite):
			return

		anim_sprite.visible = true
		anim_sprite.stop()
		anim_sprite.frame = 0
		anim_sprite.frame_progress = 0.0
		anim_sprite.speed_scale = 1.0
		anim_sprite.play(anim_name)

		get_tree().create_timer(play_duration).timeout.connect(func() -> void:
			if _external_anim_tokens[note.type] != token:
				return
			if runtime_token != _effect_runtime_token:
				return
			if is_instance_valid(anim_sprite):
				anim_sprite.stop()
				anim_sprite.visible = false
		)

	if start_delay > 0.01:
		get_tree().create_timer(start_delay).timeout.connect(play_func)
	else:
		play_func.call()


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


## 计算 SpriteFrames 中指定动画帧范围 [from_frame, to_frame] 的播放时长（秒）
## to_frame 不传则计算全部帧
func _get_animation_duration(sprite_frames: SpriteFrames, anim_name: String, from_frame: int = 0, to_frame: int = -1) -> float:
	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var base_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count <= 0 or base_fps <= 0:
		return 0.0
	var end: int = to_frame if (to_frame >= 0 and to_frame < frame_count) else frame_count - 1
	var total: float = 0.0
	for i in range(from_frame, end + 1):
		total += sprite_frames.get_frame_duration(anim_name, i)
	return total / base_fps


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
func _play_spawn_sound(note_type: Note.NoteType) -> void:
	if not key_sound_config:
		return
	
	match note_type:
		Note.NoteType.GUARD:
			if spawn_audio_player_guard and spawn_audio_player_guard.stream:
				spawn_audio_player_guard.play()
		Note.NoteType.HIT:
			if spawn_audio_player_hit and spawn_audio_player_hit.stream:
				spawn_audio_player_hit.play()
		Note.NoteType.DODGE:
			if spawn_audio_player_dodge and spawn_audio_player_dodge.stream:
				spawn_audio_player_dodge.play()
