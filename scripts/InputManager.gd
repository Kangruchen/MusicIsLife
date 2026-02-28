extends Node
## 输入管理器 - 处理玩家输入和判定逻辑

# 判定信号
signal judgment_made(track: Note.NoteType, judgment: JudgmentType, timing_diff: float)
signal attack_performed(attack_type: AttackType)  # 玩家发动攻击信号
signal defense_key_pressed(track: Note.NoteType)  # 防御阶段按键触发（携带轨道信息，用于角色动画）

# 判定类型
enum JudgmentType {
	PERFECT,  # < 50ms
	GREAT,    # 50-100ms
	GOOD,     # 100-150ms
	MISS      # > 150ms
}

# 攻击类型
enum AttackType {
	LIGHT,     # 轻攻击（第一条轨道，J键/GUARD）
	HEAVY,     # 重攻击（第二条轨道，I键/HIT）
	HEAL,      # 回复（第三条轨道，L键/DODGE）
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
	"note_guard": Note.NoteType.GUARD,
	"note_hit": Note.NoteType.HIT,
	"note_dodge": Note.NoteType.DODGE
}

# 按键音效配置
@export var key_sound_config: KeySoundConfig = null

@onready var track_manager: Node = get_node("../TrackManager")
@onready var music_player: Node = get_node("../MusicPlayer")

# 音效播放器（用于播放按键音效）
var audio_player_guard: AudioStreamPlayer = null
var audio_player_hit: AudioStreamPlayer = null
var audio_player_dodge: AudioStreamPlayer = null

# 暂停状态
var is_paused: bool = false

# 攻击阶段状态
var is_attack_phase: bool = false
var attack_phase_timer: Timer = null
var attack_beat_timer: Timer = null
var current_beat_in_attack: int = 0
var attack_beat_interval: float = 0.0
var current_beat_start_time: float = 0.0  # 当前拍的开始时间
var attack_phase_start_time: float = 0.0  # 攻击阶段开始时间
var current_beat_has_input: bool = false  # 当前拍是否已有输入
var _pre_beat_input_received: bool = false  # 下一拍已收到预输入（节拍前半拍窗口）
var _heavy_skip_next_beat: bool = false    # 重击占用下一拍标志
var _beat_generation: int = 0            # 每拍递增，用于使过期的自动强化回调失效


func _ready() -> void:
	# 创建攻击阶段计时器
	attack_phase_timer = Timer.new()
	attack_phase_timer.one_shot = true
	attack_phase_timer.timeout.connect(_on_attack_phase_end)
	add_child(attack_phase_timer)
	
	# 创建攻击节拍计时器（one_shot，每拍手动重启以支持第一拍半拍延迟）
	attack_beat_timer = Timer.new()
	attack_beat_timer.one_shot = true
	attack_beat_timer.timeout.connect(_on_attack_beat)
	add_child(attack_beat_timer)
	
	# auto_enhance 已改为在 _on_attack_beat 内同步处理，不再使用独立 Timer
	# 创建三个音效播放器
	audio_player_guard = AudioStreamPlayer.new()
	audio_player_hit = AudioStreamPlayer.new()
	audio_player_dodge = AudioStreamPlayer.new()
	
	# 添加到场景树
	add_child(audio_player_guard)
	add_child(audio_player_hit)
	add_child(audio_player_dodge)
	
	# 设置音效播放器参数
	audio_player_guard.bus = "Master"
	audio_player_hit.bus = "Master"
	audio_player_dodge.bus = "Master"
	
	# 如果有配置文件，加载音效
	_setup_key_sounds()


## 配置按键音效
func _setup_key_sounds() -> void:
	if not key_sound_config:
		return
	
	# 加载音效到对应的播放器，并设置各自的音量
	if key_sound_config.guard_sound:
		audio_player_guard.stream = key_sound_config.guard_sound
		audio_player_guard.volume_db = key_sound_config.guard_volume_db
	
	if key_sound_config.hit_sound:
		audio_player_hit.stream = key_sound_config.hit_sound
		audio_player_hit.volume_db = key_sound_config.hit_volume_db
	
	if key_sound_config.dodge_sound:
		audio_player_dodge.stream = key_sound_config.dodge_sound
		audio_player_dodge.volume_db = key_sound_config.dodge_volume_db


## 播放按键音效
func _play_key_sound(note_type: Note.NoteType) -> void:
	if not key_sound_config:
		return
	
	var player: AudioStreamPlayer = null
	match note_type:
		Note.NoteType.GUARD:
			player = audio_player_guard
		Note.NoteType.HIT:
			player = audio_player_hit
		Note.NoteType.DODGE:
			player = audio_player_dodge
	
	if player and player.stream:
		player.play()


func _input(event: InputEvent) -> void:
	# 如果在攻击阶段，优先处理攻击输入（不检查音乐状态）
	if is_attack_phase:
		_handle_attack_phase_input(event)
		return
	
	# 防御阶段：按下轨道按键时触发角色动画信号（携带轨道信息）
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			defense_key_pressed.emit(ACTION_MAPPING[action])
			break
	
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
	
	# 查找该轨道上最近的可视音符
	var closest_note: NoteVisual = null
	var min_time_diff: float = INF
	
	for note_visual in track_manager.active_notes:
		if not note_visual or not is_instance_valid(note_visual):
			continue
		if note_visual.note_data.type != track_type:
			continue
		if not note_visual.is_active:
			continue
		var time_diff: float = abs(current_time - note_visual.target_time)
		if time_diff <= JUDGMENT_WINDOWS[JudgmentType.GOOD]:
			if time_diff < min_time_diff:
				min_time_diff = time_diff
				closest_note = note_visual
	
	# 可视音符判定
	if closest_note:
		var judgment: JudgmentType = _calculate_judgment(min_time_diff)
		var timing_diff: float = current_time - closest_note.target_time
		_play_key_sound(track_type)
		closest_note.is_active = false
		closest_note.destroy()
		if judgment == JudgmentType.MISS:
			_apply_miss_audio_effect()
		judgment_made.emit(track_type, judgment, timing_diff)
		print("判定: ", _get_judgment_text(judgment), " (", int(min_time_diff * 1000), "ms)")
		return
	
	# 查找非可视追踪音符
	var closest_tracked: Note = null
	var min_tracked_diff: float = INF
	
	for note in track_manager.tracked_notes:
		if note.type != track_type:
			continue
		var time_diff: float = abs(current_time - note.beat_time)
		if time_diff <= JUDGMENT_WINDOWS[JudgmentType.GOOD]:
			if time_diff < min_tracked_diff:
				min_tracked_diff = time_diff
				closest_tracked = note
	
	if closest_tracked:
		var judgment: JudgmentType = _calculate_judgment(min_tracked_diff)
		var timing_diff: float = current_time - closest_tracked.beat_time
		_play_key_sound(track_type)
		track_manager.tracked_notes.erase(closest_tracked)
		if judgment == JudgmentType.MISS:
			_apply_miss_audio_effect()
		judgment_made.emit(track_type, judgment, timing_diff)
		print("判定: ", _get_judgment_text(judgment), " (", int(min_tracked_diff * 1000), "ms)")
		return
	
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
	current_beat_in_attack = 0  # 代表输入拍第1拍（尚未到来）
	attack_phase_start_time = Time.get_ticks_msec() / 1000.0
	# 第一输入拍在 0.5*BI 之后到来（本函数提前半拍被调用）
	current_beat_start_time = attack_phase_start_time + 0.5 * beat_interval
	current_beat_has_input = false
	_pre_beat_input_received = false
	_heavy_skip_next_beat = false
	
	# 立即显示UI（动画和前两个音符已在准备阶段生成，分别对应输入第1、第2拍）
	var game_ui: Node = get_node_or_null("../../GameUI")
	if game_ui and game_ui.has_method("show_attack_ui"):
		game_ui.show_attack_ui()
	
	# 打印第一拍的log（总拍5/24）
	print("[总拍5/24] 输入阶段 - 拍1/16")
	
	# 启动总计时器
	attack_phase_timer.start(duration)
	
	# 第一输入拍在半拍后到来（one_shot，之后在 _on_attack_beat 内手动重启）
	attack_beat_timer.start(0.5 * beat_interval)
	
	# 为输入拍第1拍安排自动强化（在第1拍重音后半拍触发）
	# 自动强化时机 = 第1拍到来时刻 + 0.5*BI = 距现在 1.0*BI
	_beat_generation += 1
	var _gen := _beat_generation
	var _bidx := 0
	get_tree().create_timer(beat_interval).timeout.connect(func():
		_try_auto_enhance(_gen, _bidx)
	)


## 攻击阶段的输入处理
func _handle_attack_phase_input(event: InputEvent) -> void:
	# 检测按键动作
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			# 提前计算时机（需在 has_input 判断前完成，以支持节拍前预输入）
			var current_time: float = Time.get_ticks_msec() / 1000.0
			var time_since_beat: float = current_time - current_beat_start_time
			var next_beat_time: float = current_beat_start_time + attack_beat_interval
			var time_to_next_beat: float = next_beat_time - current_time
			# 半拍窗口：每拍重音前后各半拍均属于该拍的输入时间
			var half_window: float = attack_beat_interval * 0.5
			# 情形A：当前拍的前半拍（仅第1拍时 time_since_beat < 0）
			var is_pre_current_beat: bool = time_since_beat < 0.0 and time_since_beat >= -half_window
			# 情形B：下一拍的前半拍（下一拍重音前半拍内）
			var is_pre_next_beat: bool = time_to_next_beat >= 0.0 and time_to_next_beat < half_window
			# 两种情形都应设置 _pre_beat_input_received，等待对应拍的 _on_attack_beat 继承
			var is_pre_beat: bool = is_pre_current_beat or is_pre_next_beat
			
			# 检查当前拍是否已有输入；预输入归属于将要到来的拍，跳过此限制
			if current_beat_has_input and not is_pre_beat:
				print("当前拍已输入过攻击，不再接受新输入")
				return
			
			# 如果时机不对（既不在当前拍后半窗口，也不在任何预输入窗口）
			if time_since_beat > half_window and time_to_next_beat > half_window:
				print("输入时机不对，自动发动强化")
				current_beat_has_input = true
				attack_performed.emit(AttackType.ENHANCE)
				return
			
			var track: Note.NoteType = ACTION_MAPPING[action]
			var attack_type: AttackType = AttackType.ENHANCE
			
			match track:
				Note.NoteType.GUARD:
					attack_type = AttackType.LIGHT
				Note.NoteType.HIT:
					attack_type = AttackType.HEAVY
				Note.NoteType.DODGE:
					attack_type = AttackType.HEAL
			
			# 标记输入已接收：预输入等待 _on_attack_beat 继承，否则归属当前拍
			if is_pre_beat:
				_pre_beat_input_received = true
				print("预输入（距下一拍 ", int(time_to_next_beat * 1000), "ms / 距本拍 ", int(time_since_beat * 1000), "ms）")
			else:
				current_beat_has_input = true
			
			# 发送攻击信号
			attack_performed.emit(attack_type)
			print("发动攻击: ", _get_attack_name(attack_type), " (距离节拍 ", int(time_since_beat * 1000), "ms)")
			
			# 重攻击消耗两拍（若在最后一拍则只消耗一拍）
			if attack_type == AttackType.HEAVY and current_beat_in_attack < 15:
				# 立即填满下一个音符
				attack_performed.emit(AttackType.HEAVY)
				print("重攻击填充第二拍音符")
				# 用标志位记录下一拍已占用，_on_attack_beat 同步读取（无竞态）
				_heavy_skip_next_beat = true
				print("重击占用下一拍")
			
			return


## 攻击节拍触发（每一个输入拍重音到来时触发）
func _on_attack_beat() -> void:
	print("DEBUG: _on_attack_beat触发 - current_beat=", current_beat_in_attack, ", has_input=", current_beat_has_input)
	
	# 递增拍数，更新当前拍起始时间
	current_beat_in_attack += 1
	current_beat_start_time = Time.get_ticks_msec() / 1000.0
	# 继承占用状态，优先级：预输入 > 重击占用 > 默认
	# 注意：_pre_beat_input_received 和 _heavy_skip_next_beat 可同时为 true（预输入搭配重击）
	# 此时 _pre_beat_input_received 负责当前拍，_heavy_skip_next_beat 保留至下一拍
	if _pre_beat_input_received:
		current_beat_has_input = true
		_pre_beat_input_received = false
		# _heavy_skip_next_beat 不清除，留待下一次 _on_attack_beat 消耗
	elif _heavy_skip_next_beat:
		current_beat_has_input = true
		_heavy_skip_next_beat = false
		print("重击占用本拍")
	else:
		current_beat_has_input = false
	
	# 16 拍输入阶段内
	if current_beat_in_attack < 16:
		# 重启节拍计时器，等待下一拍重音（第16拍后不再需要）
		attack_beat_timer.start(attack_beat_interval)
	
	if current_beat_in_attack <= 16:
		# 安排自动强化（本拍重音后半拍触发），第16拍同样需要
		_beat_generation += 1
		var _gen := _beat_generation
		var _bidx := current_beat_in_attack
		get_tree().create_timer(attack_beat_interval * 0.5).timeout.connect(func():
			_try_auto_enhance(_gen, _bidx)
		)
		# 生成下一个节拍标记视觉音符（小于15时生成，覆盖拍3-16）
		if current_beat_in_attack < 15:
			var game_ui: Node = get_node_or_null("../../GameUI")
			if game_ui and game_ui.has_method("spawn_beat_note"):
				game_ui.spawn_beat_note(attack_beat_interval * 2.0)
				print("DEBUG: 生成音符 (拍", current_beat_in_attack + 1, ")")
		
		var total_beat: int = current_beat_in_attack + 5
		var display_beat: int = current_beat_in_attack + 1
		print("[总拍", total_beat, "/24] 输入阶段 - 拍", display_beat, "/16")
	elif current_beat_in_attack >= 16 and current_beat_in_attack < 20:
		# 退出阶段：继续驱动节拍计时器以支持返回倒计时显示
		attack_beat_timer.start(attack_beat_interval)
		var countdown: int = 20 - current_beat_in_attack
		var total_beat: int = current_beat_in_attack + 5
		print("[总拍", total_beat, "/24] 结束阶段 - 倒计时", countdown)
		var game_ui: Node = get_node_or_null("../../GameUI")
		if game_ui and game_ui.has_method("show_return_countdown"):
			game_ui.show_return_countdown(countdown)


## 尝试自动强化（带生成计数器校验，防止过期回调误触发）
func _try_auto_enhance(gen: int, beat_idx: int) -> void:
	if not is_attack_phase:
		return
	if _beat_generation != gen:
		return  # 该回调已过期（新的一拍已经开始）
	if current_beat_in_attack != beat_idx:
		return  # 拍数已推进，不属于目标拍
	if not current_beat_has_input:
		current_beat_has_input = true
		attack_performed.emit(AttackType.ENHANCE)
		print("自动强化（拍", beat_idx + 1, "，无输入）")



## 攻击阶段结束
func _on_attack_phase_end() -> void:
	is_attack_phase = false
	_beat_generation += 1  # 使所有待回调的自动强化全部失效
	attack_beat_timer.stop()
	
	print("[总拍24/24] 攻击阶段结束")
	print("========== 攻击阶段结束 ==========\n")
	
	# 通知GameUI隐藏攻击UI
	var game_ui: Node = get_node_or_null("../../GameUI")
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
