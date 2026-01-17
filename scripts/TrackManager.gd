extends Node
## 轨道管理器 - 负责生成和管理音符的可视化

# 预制场景
const NOTE_VISUAL_SCENE := preload("res://scenes/NoteVisual.tscn")

# 生成提前量（拍数）
const SPAWN_ADVANCE := {
	Note.NoteType.HIT: 2,    # 提前2拍（生成后1拍不动，1拍移动）
	Note.NoteType.GUARD: 3,  # 提前3拍（生成后1拍不动，2拍移动）
	Note.NoteType.DODGE: 4   # 提前4拍（生成后1拍不动，3拍移动）
}

# 音符生成位置X坐标
const SPAWN_X: float = 900.0

# MISS 判定窗口（超过判定线后多久算 MISS）
const MISS_THRESHOLD: float = 0.200  # 200ms

# 音符生成音效配置
@export var key_sound_config: KeySoundConfig = null

var game_ui: Control = null
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


func _ready() -> void:
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
	if not game_ui:
		return
	
	# 创建音符实例
	var note_visual := NOTE_VISUAL_SCENE.instantiate() as NoteVisual
	
	# 计算位置
	var track_y: float = game_ui.get_track_y(note.type)
	var judgment_x: float = game_ui.get_judgment_line_x()
	var spawn_pos := Vector2(SPAWN_X, track_y)
	var target_pos := Vector2(judgment_x, track_y)
	
	# 计算时间
	var advance_beats: int = SPAWN_ADVANCE[note.type]
	var spawn_time: float = note.beat_time - advance_beats * beat_manager.beat_interval
	var move_start_time: float = spawn_time + beat_manager.beat_interval  # 延迟1拍开始移动
	var target_time: float = note.beat_time
	
	# 初始化音符
	note_visual.initialize(note, spawn_pos, target_pos, move_start_time, target_time)
	
	# 添加到场景
	game_ui.get_notes_container().add_child(note_visual)
	active_notes.append(note_visual)
	
	print("生成音符: 节拍 #", note.beat_number, " ", note.get_type_string(), " 在时间 ", "%.3f" % spawn_time)


## 清除所有活跃的音符
func clear_all_notes() -> void:
	for note_visual in active_notes:
		if note_visual and is_instance_valid(note_visual):
			note_visual.destroy()
	active_notes.clear()
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
	
	# 最后才恢复生成（避免_process在清理前执行）
	is_paused = false
	pause_start_time = 0.0
	
	print("音符生成已恢复")


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
