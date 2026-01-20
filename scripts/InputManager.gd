extends Node
## 输入管理器 - 处理玩家输入和判定逻辑

# 判定信号
signal judgment_made(track: Note.NoteType, judgment: JudgmentType, timing_diff: float)
signal attack_performed(attack_type: AttackType)  # 玩家发动攻击信号

# 判定类型
enum JudgmentType {
	PERFECT,  # < 50ms
	GREAT,    # 50-100ms
	GOOD,     # 100-150ms
	MISS      # > 150ms
}

# 攻击类型
enum AttackType {
	LIGHT,     # 轻攻击（第一条轨道）
	HEAVY,     # 重攻击（第二条轨道）
	HEAL,      # 回复（第三条轨道）
	ENHANCE    # 强化（什么都不做）
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
@onready var music_player: Node = get_node("../MusicPlayer")

# 音效播放器（用于播放按键音效）
var audio_player_hit: AudioStreamPlayer = null
var audio_player_guard: AudioStreamPlayer = null
var audio_player_dodge: AudioStreamPlayer = null

# 暂停状态
var is_paused: bool = false

# 攻击阶段状态
var is_attack_phase: bool = false
var attack_phase_timer: Timer = null
var attack_beat_timer: Timer = null
var auto_enhance_timer: Timer = null  # 自动强化延迟计时器
var current_beat_in_attack: int = 0
var attack_beat_interval: float = 0.0
var current_beat_start_time: float = 0.0  # 当前拍的开始时间
var attack_phase_start_time: float = 0.0  # 攻击阶段开始时间
var current_beat_has_input: bool = false  # 当前拍是否已有输入


func _ready() -> void:
	# 创建攻击阶段计时器
	attack_phase_timer = Timer.new()
	attack_phase_timer.one_shot = true
	attack_phase_timer.timeout.connect(_on_attack_phase_end)
	add_child(attack_phase_timer)
	
	# 创建攻击节拍计时器
	attack_beat_timer = Timer.new()
	attack_beat_timer.timeout.connect(_on_attack_beat)
	add_child(attack_beat_timer)
	
	# 创建自动强化延迟计时器
	auto_enhance_timer = Timer.new()
	auto_enhance_timer.one_shot = true
	auto_enhance_timer.timeout.connect(_on_auto_enhance_timeout)
	add_child(auto_enhance_timer)
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
	
	# 加载音效到对应的播放器，并设置各自的音量
	if key_sound_config.hit_sound:
		audio_player_hit.stream = key_sound_config.hit_sound
		audio_player_hit.volume_db = key_sound_config.hit_volume_db
	
	if key_sound_config.guard_sound:
		audio_player_guard.stream = key_sound_config.guard_sound
		audio_player_guard.volume_db = key_sound_config.guard_volume_db
	
	if key_sound_config.dodge_sound:
		audio_player_dodge.stream = key_sound_config.dodge_sound
		audio_player_dodge.volume_db = key_sound_config.dodge_volume_db


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
	# 如果在攻击阶段，优先处理攻击输入（不检查音乐状态）
	if is_attack_phase:
		_handle_attack_phase_input(event)
		return
	
	if not music_player or not music_player.playing:
		return
	
	# 如果处于暂停状态，忽略输入
	if is_paused:
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
	# 如果处于暂停状态，不触发Miss
	if is_paused:
		return
	
	# 应用 Miss 音频效果
	_apply_miss_audio_effect()
	
	# 发送 MISS 判定信号
	judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
	print("判定: MISS (自动)")


## 暂停输入检测
func pause_input() -> void:
	is_paused = true
	print("输入检测已暂停")


## 恢复输入检测
func resume_input() -> void:
	is_paused = false
	print("输入检测已恢复")


## 开始攻击阶段
func start_attack_phase(duration: float, beat_interval: float) -> void:
	is_attack_phase = true
	attack_beat_interval = beat_interval
	current_beat_in_attack = 0  # 从0开始，显示为拍1
	attack_phase_start_time = Time.get_ticks_msec() / 1000.0
	current_beat_start_time = attack_phase_start_time
	current_beat_has_input = false
	
	# 立即显示UI（动画和前两个音符已在准备阶段生成）
	var game_ui: Node = get_node_or_null("../GameUI")
	if game_ui and game_ui.has_method("show_attack_ui"):
		game_ui.show_attack_ui()
		# 生成第三个音符（为总拍7准备）
		if game_ui.has_method("spawn_beat_note"):
			game_ui.spawn_beat_note(beat_interval * 2.0)
			print("DEBUG: 生成第3个音符 (总拍5开始)")
	
	# 打印第一拍的log（总拍5/24）
	print("[总拍5/24] 输入阶段 - 拍1/16")
	
	# 启动第一拍的自动强化计时器（150ms后触发）
	auto_enhance_timer.start(0.15)
	
	# 启动总计时器
	attack_phase_timer.start(duration)
	
	# 启动节拍计时器（每拍触发一次）
	attack_beat_timer.start(beat_interval)


## 攻击阶段的输入处理
func _handle_attack_phase_input(event: InputEvent) -> void:
	# 检测按键动作
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			# 检查当前拍是否已有输入
			if current_beat_has_input:
				print("当前拍已输入过攻击，不再接受新输入")
				return
			
			# 检查是否在当前拍的判定范围内（前后150ms）
			var current_time: float = Time.get_ticks_msec() / 1000.0
			var time_since_beat: float = current_time - current_beat_start_time
			
			# 允许在节拍前150ms到后150ms的范围内输入
			var next_beat_time: float = current_beat_start_time + attack_beat_interval
			var time_to_next_beat: float = next_beat_time - current_time
			
			# 如果离下一拍很近（150ms内），也允许输入
			if time_since_beat > 0.15 and time_to_next_beat > 0.15:
				print("输入时机不对，自动发动强化")
				# 标记当前拍已有输入
				current_beat_has_input = true
				# 立即发动强化
				attack_performed.emit(AttackType.ENHANCE)
				return
			
			var track: Note.NoteType = ACTION_MAPPING[action]
			var attack_type: AttackType = AttackType.ENHANCE
			
			match track:
				Note.NoteType.HIT:
					attack_type = AttackType.LIGHT
				Note.NoteType.GUARD:
					attack_type = AttackType.HEAVY
				Note.NoteType.DODGE:
					attack_type = AttackType.HEAL
			
			# 标记当前拍已有输入
			current_beat_has_input = true
			
			# 发送攻击信号
			attack_performed.emit(attack_type)
			print("发动攻击: ", _get_attack_name(attack_type), " (距离节拍 ", int(time_since_beat * 1000), "ms)")
			
			# 重攻击消耗两拍（若在最后一拍则只消耗一拍）
			if attack_type == AttackType.HEAVY and current_beat_in_attack < 15:
				# 立即填满下一个音符
				attack_performed.emit(AttackType.HEAVY)
				print("重攻击填充第二拍音符")
				
				# 跳过下一拍（标记下一拍也已有输入）
				get_tree().create_timer(attack_beat_interval).timeout.connect(func():
					if is_attack_phase and current_beat_in_attack < 16:
						current_beat_has_input = true
						print("重攻击消耗第二拍")
				)
			
			return


## 攻击节拍触发
func _on_attack_beat() -> void:
	# 打印当前状态用于调试
	print("DEBUG: _on_attack_beat触发 - current_beat=", current_beat_in_attack, ", has_input=", current_beat_has_input)
	
	# 递增拍数
	current_beat_in_attack += 1
	current_beat_start_time = Time.get_ticks_msec() / 1000.0
	current_beat_has_input = false  # 重置当前拍的输入标志
	
	# 为新的一拍启动自动强化计时器（仅前16拍）
	if current_beat_in_attack < 16:
		auto_enhance_timer.start(0.15)
		
		# 生成下一个节拍标记（仅前13拍，因为准备阶段2个+start_attack_phase1个=3个，再生成13个，共16个）
		if current_beat_in_attack < 14:
			var game_ui: Node = get_node_or_null("../GameUI")
			if game_ui and game_ui.has_method("spawn_beat_note"):
				game_ui.spawn_beat_note(attack_beat_interval * 2.0)
				print("DEBUG: 生成音符 (拍", current_beat_in_attack + 1, ")")
	
	if current_beat_in_attack < 16:
		var total_beat: int = current_beat_in_attack + 5  # 加上准备阶段的4拍，再加1（因为从0开始）
		var display_beat: int = current_beat_in_attack + 1  # 显示从1开始
		print("[总拍", total_beat, "/24] 输入阶段 - 拍", display_beat, "/16")
	elif current_beat_in_attack >= 16 and current_beat_in_attack < 20:
		var countdown: int = 20 - current_beat_in_attack  # 16->4, 17->3, 18->2, 19->1
		var total_beat: int = current_beat_in_attack + 5
		print("[总拍", total_beat, "/24] 结束阶段 - 倒计时", countdown)
		# 通知GameUI显示倒计时
		var game_ui: Node = get_node_or_null("../GameUI")
		if game_ui and game_ui.has_method("show_return_countdown"):
			game_ui.show_return_countdown(countdown)


## 自动强化超时（每拍150ms后触发）
func _on_auto_enhance_timeout() -> void:
	# 检查当前拍是否有输入
	if not current_beat_has_input and current_beat_in_attack < 16:
		# 标记已有输入（虽然是自动强化）
		current_beat_has_input = true
		# 发动强化攻击
		attack_performed.emit(AttackType.ENHANCE)
		print("自动强化（150ms超时）")


## 攻击阶段结束
func _on_attack_phase_end() -> void:
	is_attack_phase = false
	attack_beat_timer.stop()
	
	print("[总拍24/24] 攻击阶段结束")
	print("========== 攻击阶段结束 ==========\n")
	
	# 通知GameUI隐藏攻击UI
	var game_ui: Node = get_node_or_null("../GameUI")
	if game_ui and game_ui.has_method("hide_attack_ui"):
		game_ui.hide_attack_ui()


## 获取攻击类型名称
func _get_attack_name(attack_type: AttackType) -> String:
	match attack_type:
		AttackType.LIGHT:
			return "轻攻击"
		AttackType.HEAVY:
			return "重攻击"
		AttackType.HEAL:
			return "回复"
		AttackType.ENHANCE:
			return "强化"
		_:
			return "未知"
