extends Node
## 输入管理器 - 处理玩家输入和判定逻辑


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

# 游戏阶段状态机
enum PhaseState {
	DEFENSE,  # 防御阶段（正常游戏）
	ATTACK,   # 攻击阶段（含输入和退出）
	PAUSED    # 暂停（准备阶段等）
}

# 判定时间窗口（秒）— 值与 GameConstants 同步
const JUDGMENT_WINDOWS := {
	JudgmentType.PERFECT: 0.050,  # GameConstants.PERFECT_WINDOW
	JudgmentType.GREAT: 0.100,    # GameConstants.GREAT_WINDOW
	JudgmentType.GOOD: 0.150,     # GameConstants.GOOD_WINDOW
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

# 当前阶段
var current_phase: PhaseState = PhaseState.DEFENSE

# 攻击阶段状态
var attack_phase_timer: Timer = null
var attack_beat_timer: Timer = null
var current_beat_in_attack: int = 0
var attack_beat_interval: float = 0.0
var current_beat_start_time: float = 0.0  # 当前拍的开始时间
var attack_phase_start_time: float = 0.0  # 攻击阶段开始时间
var current_beat_has_input: bool = false  # 当前拍是否已有输入
var _current_beat_forced_occupied: bool = false  # 当前拍是否由重击占用（非玩家输入）
var _heavy_skip_next_beat: bool = false    # 重击占用下一拍标志
var _beat_generation: int = 0            # 每拍递增，用于使过期回调失效
var _attack_beat_abs_times: PackedFloat64Array = PackedFloat64Array()  # 预计算的每拍绝对时间
var _next_beat_idx: int = 0  # 下一个待处理的拍子索引


func _ready() -> void:
	# 创建攻击阶段计时器
	attack_phase_timer = Timer.new()
	attack_phase_timer.one_shot = true
	attack_phase_timer.timeout.connect(_on_attack_phase_end)
	add_child(attack_phase_timer)
	
	# 创建攻击节拍计时器（保留用于 stop() 清理，节拍由 _process 绝对时间驱动）
	attack_beat_timer = Timer.new()
	attack_beat_timer.one_shot = true
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
	
	# 通过 EventBus 监听 MISS 触发（由 TrackManager 发射）
	EventBus.miss_triggered.connect(_on_miss_triggered)


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


func _process(_delta: float) -> void:
	# 攻击阶段：基于绝对时间驱动节拍（替代 Timer，消除帧抖动导致的音符间隙）
	if current_phase != PhaseState.ATTACK:
		return
	
	var now: float = Time.get_ticks_msec() / 1000.0
	_advance_attack_beats_to_time(now)


func _input(event: InputEvent) -> void:
	# 根据阶段状态路由输入
	match current_phase:
		PhaseState.ATTACK:
			_handle_attack_phase_input(event)
			return
		PhaseState.PAUSED:
			return
		PhaseState.DEFENSE:
			pass
	
	# 防御阶段：按下轨道按键时触发角色动画信号（始终触发，不受音乐状态影响）
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			EventBus.defense_key_pressed.emit(ACTION_MAPPING[action])
			break
	
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
		EventBus.judgment_made.emit(track_type, judgment, timing_diff)
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
		EventBus.judgment_made.emit(track_type, judgment, timing_diff)
		print("判定: ", _get_judgment_text(judgment), " (", int(min_tracked_diff * 1000), "ms)")
		return
	
	# 没有同轨道音符在判定窗口内，检查是否按错了键（其他轨道有音符）
	var wrong_note: Note = null
	var wrong_diff: float = INF
	for note in track_manager.tracked_notes:
		if note.type == track_type:
			continue  # 跳过同轨道（前面已搜索过）
		var time_diff: float = abs(current_time - note.beat_time)
		if time_diff <= JUDGMENT_WINDOWS[JudgmentType.GOOD] and time_diff < wrong_diff:
			wrong_diff = time_diff
			wrong_note = note
	
	if wrong_note:
		# 按错键：消耗该音符并判定为 MISS（避免之后自动超时再触发一次 MISS）
		track_manager.tracked_notes.erase(wrong_note)
		_apply_miss_audio_effect()
		EventBus.judgment_made.emit(wrong_note.type, JudgmentType.MISS, 0.0)
		print("判定: MISS (按错键 - 应为 ", wrong_note.get_type_string(), ")")
	else:
		# 真正的空按
		_apply_miss_audio_effect()
		EventBus.judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
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


## 由 TrackManager 通过 EventBus.miss_triggered 触发
func _on_miss_triggered(track_type: int) -> void:
	if current_phase == PhaseState.PAUSED:
		return
	_apply_miss_audio_effect()
	EventBus.judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
	print("判定: MISS (自动)")


## 暂停输入检测
func pause_input() -> void:
	current_phase = PhaseState.PAUSED
	_attack_beat_abs_times.clear()
	_next_beat_idx = 0
	if attack_phase_timer != null:
		attack_phase_timer.stop()
	if attack_beat_timer != null:
		attack_beat_timer.stop()
	print("输入检测已暂停")


## 恢复输入检测
func resume_input() -> void:
	current_phase = PhaseState.DEFENSE
	print("输入检测已恢复")


## 开始攻击阶段
## first_beat_abs_time: 第一输入拍的绝对时间（与 ScoreManager 生成的前两个音符共享同一时间网格）
func start_attack_phase(duration: float, bi: float, first_beat_abs_time: float) -> void:
	current_phase = PhaseState.ATTACK
	attack_beat_interval = bi
	current_beat_in_attack = 0  # 代表输入拍第1拍（尚未到来）
	attack_phase_start_time = Time.get_ticks_msec() / 1000.0
	# 使用从 ScoreManager 传入的绝对时间，而非重新计算（消除 Timer 漂移导致的音符间隙）
	current_beat_start_time = first_beat_abs_time
	current_beat_has_input = false
	_current_beat_forced_occupied = false
	_heavy_skip_next_beat = false
	_beat_generation += 1  # 使所有残留回调失效
	
	# 预计算所有拍的绝对时间（输入拍 + 退出拍）——基于同一时间基准
	_attack_beat_abs_times.clear()
	_attack_beat_abs_times.resize(GameConstants.INPUT_BEATS + GameConstants.EXIT_BEATS)
	for i in range(GameConstants.INPUT_BEATS + GameConstants.EXIT_BEATS):
		_attack_beat_abs_times[i] = first_beat_abs_time + i * bi
	_next_beat_idx = 0
	
	# 通过 EventBus 通知 UI 显示攻击界面
	EventBus.show_attack_ui_requested.emit()
	EventBus.attack_phase_started.emit()
	
	# 打印第一拍的log
	var first_total: int = GameConstants.COUNTDOWN_BEATS + 1
	print("[总拍", first_total, "/", GameConstants.TOTAL_ATTACK_BEATS, "] 输入阶段 - 拍1/", GameConstants.INPUT_BEATS)
	
	# 启动总计时器（仅用于攻击阶段整体结束，节拍由 _process 驱动）
	attack_phase_timer.start(duration)


## 攻击阶段的输入处理
func _handle_attack_phase_input(event: InputEvent) -> void:
	# 先将攻击拍状态追到当前时刻，避免输入事件先于 _process 导致落在旧拍状态。
	var synced_now: float = Time.get_ticks_msec() / 1000.0
	_advance_attack_beats_to_time(synced_now)

	# 检测按键动作
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			# 仅允许在输入阶段且当前拍可用时发动行动
			if current_beat_in_attack < 1 or current_beat_in_attack > GameConstants.INPUT_BEATS:
				print("当前不在可输入拍，忽略攻击输入")
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

			if current_beat_has_input:
				# 重击占用拍允许用回复覆盖，避免“重击后无法及时回血”。
				if _current_beat_forced_occupied and attack_type == AttackType.HEAL:
					current_beat_has_input = false
					_current_beat_forced_occupied = false
					print("回复覆盖重击占用拍")
				else:
					print("当前拍已被占用，等待下一次未占用拍")
					return

			var current_time: float = synced_now
			var time_since_beat: float = current_time - current_beat_start_time
			var next_beat_time: float = current_beat_start_time + attack_beat_interval
			if current_time < current_beat_start_time or current_time >= next_beat_time:
				print("输入不在当前拍窗口内，忽略")
				return
			
			current_beat_has_input = true
			
			# 发送攻击信号
			EventBus.attack_performed.emit(attack_type)
			print("发动攻击: ", _get_attack_name(attack_type), " (距离节拍 ", int(time_since_beat * 1000), "ms)")
			
			# 重攻击消耗两拍：占用下一拍，不立即触发第二次攻击
			if attack_type == AttackType.HEAVY and current_beat_in_attack < GameConstants.INPUT_BEATS:
				_heavy_skip_next_beat = true
				print("重击占用下一拍")
			
			return


func _advance_attack_beats_to_time(now: float) -> void:
	if current_phase != PhaseState.ATTACK:
		return
	while _next_beat_idx < _attack_beat_abs_times.size() and now >= _attack_beat_abs_times[_next_beat_idx]:
		_on_attack_beat_timed(_next_beat_idx)
		_next_beat_idx += 1


## 攻击节拍触发（基于绝对时间，由 _process 调用）
## beat_idx: 拍子在 _attack_beat_abs_times 数组中的索引
func _on_attack_beat_timed(beat_idx: int) -> void:
	# 先结算上一拍：若该拍无任何动作且非重击占用，则自动蓄力。
	if current_beat_in_attack >= 1 and current_beat_in_attack <= GameConstants.INPUT_BEATS:
		if not current_beat_has_input and not _current_beat_forced_occupied:
			current_beat_has_input = true
			EventBus.attack_performed.emit(AttackType.ENHANCE)
			print("自动强化（拍", current_beat_in_attack, "，本拍无输入）")

	# 递增拍数，使用预计算的绝对时间（消除帧抖动漂移）
	current_beat_in_attack += 1
	current_beat_start_time = _attack_beat_abs_times[beat_idx]
	
	print("DEBUG: _on_attack_beat_timed - beat_idx=", beat_idx, ", current_beat=", current_beat_in_attack, ", has_input=", current_beat_has_input)
	
	# 继承占用状态：重击占用下一拍
	if _heavy_skip_next_beat:
		current_beat_has_input = true
		_current_beat_forced_occupied = true
		_heavy_skip_next_beat = false
		print("重击占用本拍")
	else:
		current_beat_has_input = false
		_current_beat_forced_occupied = false
	
	# 输入阶段（拍 1 ~ INPUT_BEATS）
	if current_beat_in_attack <= GameConstants.INPUT_BEATS:
		# 生成下一个节拍标记视觉音符（覆盖拍 3 ~ 16）
		if current_beat_in_attack < (GameConstants.INPUT_BEATS - 1):
			var note_target_time: float = _attack_beat_abs_times[beat_idx] + 2.0 * attack_beat_interval
			EventBus.spawn_beat_note_requested.emit(attack_beat_interval, note_target_time)
			print("DEBUG: 生成音符 (拍", current_beat_in_attack + 1, ")")
		
		var total_beat: int = current_beat_in_attack + GameConstants.COUNTDOWN_BEATS + 1
		var display_beat: int = current_beat_in_attack + 1
		print("[总拍", total_beat, "/", GameConstants.TOTAL_ATTACK_BEATS, "] 输入阶段 - 拍", display_beat, "/", GameConstants.INPUT_BEATS)
	# 退出阶段（拍 INPUT_BEATS+1 ~ INPUT_BEATS+EXIT_BEATS）
	elif current_beat_in_attack > GameConstants.INPUT_BEATS and current_beat_in_attack <= (GameConstants.INPUT_BEATS + GameConstants.EXIT_BEATS):
		if current_beat_in_attack == GameConstants.INPUT_BEATS + 1:
			EventBus.attack_movement_enabled_changed.emit(false)
		var countdown: int = (GameConstants.INPUT_BEATS + GameConstants.EXIT_BEATS) - current_beat_in_attack
		var total_beat: int = current_beat_in_attack + GameConstants.COUNTDOWN_BEATS + 1
		print("[总拍", total_beat, "/", GameConstants.TOTAL_ATTACK_BEATS, "] 结束阶段 - 倒计时", countdown)
		EventBus.show_return_countdown_requested.emit(countdown)



## 攻击阶段结束
func _on_attack_phase_end() -> void:
	if current_phase != PhaseState.ATTACK:
		return

	current_phase = PhaseState.DEFENSE
	_beat_generation += 1  # 使所有残留回调失效
	_attack_beat_abs_times.clear()
	_current_beat_forced_occupied = false
	if attack_phase_timer != null:
		attack_phase_timer.stop()
	attack_beat_timer.stop()
	
	print("[总拍", GameConstants.TOTAL_ATTACK_BEATS, "/", GameConstants.TOTAL_ATTACK_BEATS, "] 攻击阶段结束")
	print("========== 攻击阶段结束 ==========\n")
	
	EventBus.attack_movement_enabled_changed.emit(false)
	EventBus.hide_attack_ui_requested.emit()
	EventBus.attack_phase_ended.emit()


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
