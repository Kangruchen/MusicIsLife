extends Node
class_name TrackManager
## 轨道管理器 - 负责生成和管理音符的可视化

# 预制场景
const NOTE_VISUAL_SCENE := preload("res://scenes/NoteVisual.tscn")
const BLING_SCENE := preload("res://scenes/bling.tscn")

# Bling 特效配置
const BLING_BASE_X: float = 50.0  # 特效基础X坐标（屏幕左侧）
const BLING_OFFSET_X: float = 50.0  # 同行多个特效的水平偏移
const BLING_ROW_HEIGHT: float = 50.0  # 每行高度
const BLING_START_Y: float = 230.0  # 第一行Y坐标
const BLING_ANIMATIONS: Dictionary = {
	Note.NoteType.HIT: "bling_red",
	Note.NoteType.GUARD: "bling_blue",
	Note.NoteType.DODGE: "bling_green"
}
# 特效行排列顺序：red第一排、green第二排、blue第三排
const BLING_ROW_ORDER: Dictionary = {
	Note.NoteType.HIT: 0,    # red - 第一排
	Note.NoteType.GUARD: 1,  # blue - 第二排
	Note.NoteType.DODGE: 2   # green - 第三排
}

# 生成提前量（拍数）
const SPAWN_ADVANCE := {
	Note.NoteType.HIT: 2,    # 提前2拍（生成后1拍不动，1拍移动）
	Note.NoteType.GUARD: 3,  # 提前3拍（生成后1拍不动，2拍移动）
	Note.NoteType.DODGE: 4   # 提前4拍（生成后1拍不动，3拍移动）
}

# 音符生成位置X坐标（动态计算，在 _ready 中初始化）
var spawn_x: float = 900.0

# MISS 判定窗口（超过判定线后多久算 MISS）
const MISS_THRESHOLD: float = 0.200  # 200ms

# 音符视觉生成开关（暂时停用）
var note_visual_enabled: bool = false

# 非可视音符追踪（用于判定和 MISS 检测）
var tracked_notes: Array[Note] = []

# 音符生成音效配置
@export var key_sound_config: KeySoundConfig = null

var game_ui: Node = null
var beat_manager: Node = null
var input_manager: Node = null
var current_chart: Chart = null
var active_notes: Array[NoteVisual] = []
var scheduled_notes: Array[Note] = []  # 待生成的音符
var current_time: float = 0.0
var is_paused: bool = false  # 是否暂停生成音符
var pause_start_time: float = 0.0  # 暂停开始的时间

# 音符生成音效播放器
var spawn_audio_player_hit: AudioStreamPlayer = null
var spawn_audio_player_guard: AudioStreamPlayer = null
var spawn_audio_player_dodge: AudioStreamPlayer = null

# 活跃的 Bling 特效追踪（按轨道分组，用于避免重叠）
var _active_blings: Dictionary = {}


func _ready() -> void:
	# 根据实际视口宽度动态计算音符生成X坐标（屏幕右侧外100px）
	spawn_x = get_viewport().get_visible_rect().size.x + 100.0
	
	# 获取引用
	game_ui = get_node("../GameUI")
	beat_manager = get_node("../BeatManager")
	input_manager = get_node("../InputManager")
	
	if beat_manager:
		beat_manager.beat_hit.connect(_on_beat_hit)
	
	# 创建音符生成音效播放器
	spawn_audio_player_hit = AudioStreamPlayer.new()
	spawn_audio_player_guard = AudioStreamPlayer.new()
	spawn_audio_player_dodge = AudioStreamPlayer.new()
	
	spawn_audio_player_hit.name = "SpawnAudioHit"
	spawn_audio_player_guard.name = "SpawnAudioGuard"
	spawn_audio_player_dodge.name = "SpawnAudioDodge"
	
	add_child(spawn_audio_player_hit)
	add_child(spawn_audio_player_guard)
	add_child(spawn_audio_player_dodge)
	
	spawn_audio_player_hit.bus = "Master"
	spawn_audio_player_guard.bus = "Master"
	spawn_audio_player_dodge.bus = "Master"
	
	# 加载音符生成音效
	if key_sound_config:
		if key_sound_config.hit_sound:
			spawn_audio_player_hit.stream = key_sound_config.hit_sound
			spawn_audio_player_hit.volume_db = key_sound_config.hit_volume_db
		if key_sound_config.guard_sound:
			spawn_audio_player_guard.stream = key_sound_config.guard_sound
			spawn_audio_player_guard.volume_db = key_sound_config.guard_volume_db
		if key_sound_config.dodge_sound:
			spawn_audio_player_dodge.stream = key_sound_config.dodge_sound
			spawn_audio_player_dodge.volume_db = key_sound_config.dodge_volume_db


func _process(_delta: float) -> void:
	# 如果暂停，不生成新音符
	if is_paused:
		return
	
	# 获取当前音乐时间
	var music_player: Node = get_node("../MusicPlayer")
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
				var two_beats_duration: float = 2.0 * beat_manager.beat_interval
				if not note_visual.spawn_sound_played and time_before_target <= two_beats_duration:
					_play_spawn_sound(note_visual.note_data.type)
					note_visual.spawn_sound_played = true
				
				# 检查是否超过判定窗口（自动 MISS）
				var time_past_target: float = current_time - note_visual.target_time
				if time_past_target > MISS_THRESHOLD:
					# 触发 MISS 判定
					if input_manager:
						input_manager.trigger_miss(note_visual.note_data.type)
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
				if input_manager:
					input_manager.trigger_miss(note.type)
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
		var spawn_time: float = note.beat_time - advance_beats * beat_manager.beat_interval
		
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
	# 生成屏幕左侧特效动画（无论音符可视化是否启用）
	_spawn_bling_effect(note)
	
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
		var spawn_time: float = note.beat_time - advance_beats * beat_manager.beat_interval
		var move_start_time: float = spawn_time + beat_manager.beat_interval
		var target_time: float = note.beat_time
		
		note_visual.initialize(note, spawn_pos, target_pos, move_start_time, target_time)
		notes_container.add_child(note_visual)
		active_notes.append(note_visual)
		print("生成音符: 节拍 #", note.beat_number, " ", note.get_type_string(), " 在时间 ", "%.3f" % spawn_time)
	else:
		# 非可视模式：仅追踪音符用于判定
		tracked_notes.append(note)


## 清除所有活跃的音符
func clear_all_notes() -> void:
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
	print("已清除所有活跃音符")


## 暂停音符生成
func pause_note_spawning() -> void:
	is_paused = true
	pause_start_time = current_time
	print("音符生成已暂停，时间: ", pause_start_time)


## 恢复音符生成
func resume_note_spawning() -> void:
	# 先更新当前时间到最新值（避免使用暂停前的旧时间）
	var music_player: Node = get_node("../MusicPlayer")
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


## 生成 Bling 特效动画
func _spawn_bling_effect(note: Note) -> void:
	if not game_ui:
		return
	
	var bling: Node2D = BLING_SCENE.instantiate()
	var anim_sprite: AnimatedSprite2D = bling.get_node("AnimatedSprite2D")
	
	# 获取对应的动画名称
	var anim_name: String = BLING_ANIMATIONS[note.type]
	
	# 调整动画速度：每帧对应1拍
	# 动画帧数恰好等于提前拍数（red=2帧/2拍, blue=3帧/3拍, green=4帧/4拍）
	# 基础FPS=1.0，所以 speed_scale = 1/beat_interval 即可让每帧持续1拍
	if beat_manager.beat_interval > 0:
		anim_sprite.speed_scale = 1.0 / beat_manager.beat_interval
	
	# 计算位置（固定行排列，同行多个特效向右偏移）
	var row_index: int = BLING_ROW_ORDER[note.type]
	var row_y: float = BLING_START_Y + row_index * BLING_ROW_HEIGHT
	var x_offset: float = _get_bling_x_offset(note.type)
	bling.position = Vector2(BLING_BASE_X + x_offset, row_y)
	
	# 连接动画完成信号，播放结束后自动销毁
	anim_sprite.animation_finished.connect(func() -> void: bling.queue_free())
	
	# 添加到 GameUI（CanvasLayer）并播放
	game_ui.add_child(bling)
	anim_sprite.play(anim_name)
	
	# 追踪活跃特效（用于避免重叠）
	if not _active_blings.has(note.type):
		_active_blings[note.type] = []
	_active_blings[note.type].append(bling)


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
		Note.NoteType.HIT:
			if spawn_audio_player_hit and spawn_audio_player_hit.stream:
				spawn_audio_player_hit.play()
		Note.NoteType.GUARD:
			if spawn_audio_player_guard and spawn_audio_player_guard.stream:
				spawn_audio_player_guard.play()
		Note.NoteType.DODGE:
			if spawn_audio_player_dodge and spawn_audio_player_dodge.stream:
				spawn_audio_player_dodge.play()
