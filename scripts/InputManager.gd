extends Node
## 输入管理器 - 处理玩家输入和判定逻辑

# 判定信号
signal judgment_made(track: Note.NoteType, judgment: JudgmentType, timing_diff: float)

# 判定类型
enum JudgmentType {
	PERFECT,  # < 50ms
	GREAT,    # 50-100ms
	GOOD,     # 100-150ms
	MISS      # > 150ms
}

# 判定时间窗口（秒）
const JUDGMENT_WINDOWS := {
	JudgmentType.PERFECT: 0.050,  # 50ms
	JudgmentType.GREAT: 0.100,    # 100ms
	JudgmentType.GOOD: 0.150,     # 150ms
}

# 动作映射到音符类型
const ACTION_MAPPING := {
	"note_hit": Note.NoteType.HIT,
	"note_guard": Note.NoteType.GUARD,
	"note_dodge": Note.NoteType.DODGE
}

# 按键音效配置
@export var key_sound_config: KeySoundConfig = null

@onready var track_manager: Node = get_node("../TrackManager")
@onready var music_player: AudioStreamPlayer = get_node("../MusicPlayer")

# 音效播放器（用于播放按键音效）
var audio_player_hit: AudioStreamPlayer = null
var audio_player_guard: AudioStreamPlayer = null
var audio_player_dodge: AudioStreamPlayer = null


func _ready() -> void:
	# 创建三个音效播放器
	audio_player_hit = AudioStreamPlayer.new()
	audio_player_guard = AudioStreamPlayer.new()
	audio_player_dodge = AudioStreamPlayer.new()
	
	# 添加到场景树
	add_child(audio_player_hit)
	add_child(audio_player_guard)
	add_child(audio_player_dodge)
	
	# 设置音效播放器参数
	audio_player_hit.bus = "Master"
	audio_player_guard.bus = "Master"
	audio_player_dodge.bus = "Master"
	
	# 如果有配置文件，加载音效
	_setup_key_sounds()


## 配置按键音效
func _setup_key_sounds() -> void:
	if not key_sound_config:
		return
	
	# 加载音效到对应的播放器
	if key_sound_config.hit_sound:
		audio_player_hit.stream = key_sound_config.hit_sound
		audio_player_hit.volume_db = key_sound_config.volume_db
	
	if key_sound_config.guard_sound:
		audio_player_guard.stream = key_sound_config.guard_sound
		audio_player_guard.volume_db = key_sound_config.volume_db
	
	if key_sound_config.dodge_sound:
		audio_player_dodge.stream = key_sound_config.dodge_sound
		audio_player_dodge.volume_db = key_sound_config.volume_db


## 播放按键音效
func _play_key_sound(note_type: Note.NoteType) -> void:
	if not key_sound_config:
		return
	
	var player: AudioStreamPlayer = null
	match note_type:
		Note.NoteType.HIT:
			player = audio_player_hit
		Note.NoteType.GUARD:
			player = audio_player_guard
		Note.NoteType.DODGE:
			player = audio_player_dodge
	
	if player and player.stream:
		player.play()


func _input(event: InputEvent) -> void:
	if not music_player or not music_player.playing:
		return
	
	# 检查输入动作
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			var track_type: Note.NoteType = ACTION_MAPPING[action]
			_handle_input(track_type)
			break  # 一次只处理一个输入


## 处理输入判定
func _handle_input(track_type: Note.NoteType) -> void:
	if not track_manager:
		return
	
	# 获取当前时间
	var current_time: float = music_player.get_playback_position() + AudioServer.get_time_to_next_mix()
	
	# 查找该轨道上最近的音符
	var closest_note: NoteVisual = null
	var min_time_diff: float = INF
	
	for note_visual in track_manager.active_notes:
		if not note_visual or not is_instance_valid(note_visual):
			continue
		
		# 只检查对应轨道的音符
		if note_visual.note_data.type != track_type:
			continue
		
		# 只检查尚未被判定的音符
		if not note_visual.is_active:
			continue
		
		# 计算时间差
		var time_diff: float = abs(current_time - note_visual.target_time)
		
		# 只考虑在判定窗口内的音符
		if time_diff <= JUDGMENT_WINDOWS[JudgmentType.GOOD]:
			if time_diff < min_time_diff:
				min_time_diff = time_diff
				closest_note = note_visual
	
	# 如果找到音符，进行判定
	if closest_note:
		var judgment: JudgmentType = _calculate_judgment(min_time_diff)
		var timing_diff: float = current_time - closest_note.target_time
		
		# 播放按键音效（击中音符时）
		_play_key_sound(track_type)
		
		# 标记音符为已判定
		closest_note.is_active = false
		closest_note.destroy()
		
		# 如果是 MISS，应用音频效果
		if judgment == JudgmentType.MISS:
			_apply_miss_audio_effect()
		
		# 发送判定信号
		judgment_made.emit(track_type, judgment, timing_diff)
		
		print("判定: ", _get_judgment_text(judgment), " (", int(min_time_diff * 1000), "ms)")
	else:
		# 没有音符在判定窗口内，视为空按Miss
		_apply_miss_audio_effect()
		judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
		print("判定: MISS (空按)")


## 计算判定等级
func _calculate_judgment(time_diff: float) -> JudgmentType:
	if time_diff < JUDGMENT_WINDOWS[JudgmentType.PERFECT]:
		return JudgmentType.PERFECT
	elif time_diff < JUDGMENT_WINDOWS[JudgmentType.GREAT]:
		return JudgmentType.GREAT
	elif time_diff < JUDGMENT_WINDOWS[JudgmentType.GOOD]:
		return JudgmentType.GOOD
	else:
		return JudgmentType.MISS


## 应用 Miss 音效
func _apply_miss_audio_effect() -> void:
	if music_player and music_player.has_method("apply_miss_effect"):
		music_player.apply_miss_effect()


## 获取判定文本
func _get_judgment_text(judgment: JudgmentType) -> String:
	match judgment:
		JudgmentType.PERFECT:
			return "PERFECT"
		JudgmentType.GREAT:
			return "GREAT"
		JudgmentType.GOOD:
			return "GOOD"
		JudgmentType.MISS:
			return "MISS"
		_:
			return "UNKNOWN"


## 获取判定颜色
func get_judgment_color(judgment: JudgmentType) -> Color:
	match judgment:
		JudgmentType.PERFECT:
			return Color(1.0, 0.84, 0.0)  # 金色
		JudgmentType.GREAT:
			return Color(0.0, 1.0, 0.5)   # 青绿色
		JudgmentType.GOOD:
			return Color(0.5, 0.5, 1.0)   # 淡蓝色
		JudgmentType.MISS:
			return Color(0.7, 0.7, 0.7)   # 灰色
		_:
			return Color.WHITE


## 触发 MISS 判定（由 TrackManager 调用）
func trigger_miss(track_type: Note.NoteType) -> void:
	# 应用 Miss 音频效果
	_apply_miss_audio_effect()
	
	# 发送 MISS 判定信号
	judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
	print("判定: MISS (自动)")
