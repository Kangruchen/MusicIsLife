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
	HEAL,      # 回复（攻击阶段无输入默认动作）
	ENHANCE    # 蓄力（第三条轨道，L键/DODGE）
}

# 游戏阶段状态机
enum PhaseState {
	DEFENSE,  # 防御阶段（正常游戏）
	ATTACK,   # 攻击阶段（含输入和退出）
	PAUSED    # 暂停（准备阶段等）
}

# 判定时间窗口（秒）— 值与 GameConstants 同步
const JUDGMENT_WINDOWS := {
	JudgmentType.PERFECT: GameConstants.PERFECT_WINDOW,
	JudgmentType.GREAT: GameConstants.GREAT_WINDOW,
	JudgmentType.GOOD: GameConstants.GOOD_WINDOW,
}

# 动作映射到音符类型
const ACTION_MAPPING := {
	"note_guard": Note.NoteType.GUARD,
	"note_hit": Note.NoteType.HIT,
	"note_dodge": Note.NoteType.DODGE
}

# 按键音效配置
@export var debug_attack_drum_alignment: bool = false
@export_group("判定")
@export var ignore_empty_press_without_nearby_notes: bool = false
@export_range(0.01, 0.5, 0.01) var empty_press_note_check_window: float = 0.15
@export_group("防御命中特效")
@export var defense_guard_hit_effect_scene: PackedScene = preload("res://scenes/laser_hit.tscn")
@export var defense_missile_hit_effect_scene: PackedScene = preload("res://scenes/missile_hit.tscn")
@export_node_path("Node2D") var defense_hit_effect_anchor_path: NodePath
@export_node_path("Node2D") var defense_hit_effect_boss_path: NodePath = NodePath("../Boss")
@export var defense_hit_effect_offset: Vector2 = Vector2(-24.0, 0.0)

@onready var track_manager: Node = get_node("../TrackManager")
@onready var music_player: Node = get_node("../MusicPlayer")

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
var _attack_beat_input_states: Dictionary = {}  # key=判定拍编号(1-based), value=该拍是否已有输入/占用
var _defense_hit_effect_anchor: Node2D = null
var _defense_hit_effect_boss: Node2D = null


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
	
	EventBus.miss_triggered.connect(_on_miss_triggered)


func _play_key_sound(note_type: Note.NoteType) -> void:
	if GameConfigs.sound == null:
		return
	if GameConfigs.sound.boss_phase_key_sound_muted and current_phase == PhaseState.ATTACK:
		return
	var pool: RandomSoundPool = GameConfigs.sound.get_key_sound(note_type)
	if pool == null:
		return
	SFXManager.play_pool(pool, GameConfigs.sound.sfx_bus)


func _play_defense_sound(note_type: Note.NoteType, is_miss: bool) -> void:
	if GameConfigs.sound == null or GameConfigs.sound.player_defense == null:
		return
	var pool: RandomSoundPool = GameConfigs.sound.player_defense.get_miss_sound(note_type) if is_miss else GameConfigs.sound.player_defense.get_success_sound(note_type)
	if pool == null:
		return
	SFXManager.play_pool(pool, GameConfigs.sound.player_defense.sfx_bus)


func _process(_delta: float) -> void:
	# 攻击阶段：基于绝对时间驱动节拍（替代 Timer，消除帧抖动导致的音符间隙）
	if current_phase != PhaseState.ATTACK:
		return
	
	var now: float = _get_music_clock_time()
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
		var is_miss: bool = judgment == JudgmentType.MISS
		if is_miss:
			_apply_miss_audio_effect()
		else:
			_spawn_defense_hit_effect(track_type)
		_play_defense_sound(track_type, is_miss)
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
		var is_miss: bool = judgment == JudgmentType.MISS
		if is_miss:
			_apply_miss_audio_effect()
		else:
			_spawn_defense_hit_effect(track_type)
		_play_defense_sound(track_type, is_miss)
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
		return

	# 真正的空按
	if ignore_empty_press_without_nearby_notes:
		if not _has_any_nearby_note(current_time, empty_press_note_check_window):
			_play_key_sound(track_type)
			print("判定: 忽略空按 (附近无音符)")
			return
	_apply_miss_audio_effect()
	EventBus.judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
	print("判定: MISS (空按)")


func _has_any_nearby_note(current_time: float, window: float) -> bool:
	for note_visual in track_manager.active_notes:
		if not note_visual or not is_instance_valid(note_visual):
			continue
		if not note_visual.is_active:
			continue
		if abs(current_time - note_visual.target_time) <= window:
			return true

	for note in track_manager.tracked_notes:
		if abs(current_time - note.beat_time) <= window:
			return true

	return false


func _spawn_defense_hit_effect(note_type: Note.NoteType) -> void:
	if current_phase != PhaseState.DEFENSE:
		return

	var effect_scene: PackedScene = _get_defense_hit_effect_scene(note_type)
	if effect_scene == null:
		return

	var effect_instance: Node2D = effect_scene.instantiate() as Node2D
	if effect_instance == null:
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_parent()
	if scene_root == null:
		effect_instance.queue_free()
		return

	scene_root.add_child(effect_instance)
	effect_instance.global_position = _get_defense_hit_effect_position(note_type)
	_play_defense_hit_effect_and_auto_free(effect_instance)


func _get_defense_hit_effect_scene(note_type: Note.NoteType) -> PackedScene:
	match note_type:
		Note.NoteType.GUARD:
			return defense_guard_hit_effect_scene
		Note.NoteType.HIT:
			return defense_missile_hit_effect_scene
		Note.NoteType.DODGE:
			return null
		_:
			return null


func _get_defense_hit_effect_position(note_type: Note.NoteType) -> Vector2:
	if note_type == Note.NoteType.HIT:
		var missile_pos: Variant = _get_missile_hit_effect_position_from_boss()
		if missile_pos is Vector2:
			return missile_pos as Vector2

	var anchor: Node2D = _resolve_defense_hit_effect_anchor()
	if anchor != null:
		return anchor.global_position + defense_hit_effect_offset
	return defense_hit_effect_offset


func _get_missile_hit_effect_position_from_boss() -> Variant:
	var boss_node: Node2D = _resolve_defense_hit_effect_boss()
	if boss_node == null:
		return null
	if boss_node.has_method("get_missile_hit_effect_position"):
		return boss_node.call("get_missile_hit_effect_position")
	return null


func _resolve_defense_hit_effect_anchor() -> Node2D:
	if _defense_hit_effect_anchor != null and is_instance_valid(_defense_hit_effect_anchor):
		return _defense_hit_effect_anchor

	if not defense_hit_effect_anchor_path.is_empty():
		_defense_hit_effect_anchor = get_node_or_null(defense_hit_effect_anchor_path) as Node2D
		if _defense_hit_effect_anchor != null:
			return _defense_hit_effect_anchor

	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		_defense_hit_effect_anchor = scene_root.find_child("Character", true, false) as Node2D

	return _defense_hit_effect_anchor


func _resolve_defense_hit_effect_boss() -> Node2D:
	if _defense_hit_effect_boss != null and is_instance_valid(_defense_hit_effect_boss):
		return _defense_hit_effect_boss

	if not defense_hit_effect_boss_path.is_empty():
		_defense_hit_effect_boss = get_node_or_null(defense_hit_effect_boss_path) as Node2D
		if _defense_hit_effect_boss != null:
			return _defense_hit_effect_boss

	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		_defense_hit_effect_boss = scene_root.find_child("Boss", true, false) as Node2D

	return _defense_hit_effect_boss


func _play_defense_hit_effect_and_auto_free(effect_instance: Node2D) -> void:
	if effect_instance == null or not is_instance_valid(effect_instance):
		return
	var effect_instance_id: int = effect_instance.get_instance_id()

	var anim_sprite: AnimatedSprite2D = effect_instance.find_child("AnimatedSprite2D", true, false) as AnimatedSprite2D
	if anim_sprite != null and anim_sprite.sprite_frames != null:
		var anim_name: StringName = &"default"
		if not anim_sprite.sprite_frames.has_animation(anim_name):
			var anim_names: PackedStringArray = anim_sprite.sprite_frames.get_animation_names()
			if anim_names.is_empty():
				effect_instance.queue_free()
				return
			anim_name = StringName(anim_names[0])

		anim_sprite.animation_finished.connect(_on_defense_hit_effect_anim_finished.bind(effect_instance_id), CONNECT_ONE_SHOT)
		anim_sprite.play(anim_name)
		return

	var animation_player: AnimationPlayer = effect_instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animation_player != null:
		var animation_list: PackedStringArray = animation_player.get_animation_list()
		if not animation_list.is_empty():
			var first_anim: StringName = StringName(animation_list[0])
			animation_player.animation_finished.connect(_on_defense_hit_effect_player_finished.bind(effect_instance_id), CONNECT_ONE_SHOT)
			animation_player.play(first_anim)
			return

	effect_instance.queue_free()


func _on_defense_hit_effect_anim_finished(effect_instance_id: int) -> void:
	_free_node_by_instance_id(effect_instance_id)


func _on_defense_hit_effect_player_finished(_finished_name: StringName, effect_instance_id: int) -> void:
	_free_node_by_instance_id(effect_instance_id)


func _free_node_by_instance_id(node_instance_id: int) -> void:
	var target_obj: Object = instance_from_id(node_instance_id)
	var target_node: Node = target_obj as Node
	if target_node != null and is_instance_valid(target_node):
		target_node.queue_free()


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
	if current_phase != PhaseState.DEFENSE:
		return
	_apply_miss_audio_effect()
	EventBus.judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
	print("判定: MISS (自动)")


## 暂停输入检测
func pause_input() -> void:
	current_phase = PhaseState.PAUSED
	_attack_beat_abs_times.clear()
	_attack_beat_input_states.clear()
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
	attack_phase_start_time = _get_music_clock_time()
	# 每拍窗口定义为 [重音前半拍, 重音后半拍)，因此拍起点 = 重音时刻 - 半拍。
	current_beat_start_time = first_beat_abs_time - 0.5 * bi
	current_beat_has_input = false
	_current_beat_forced_occupied = false
	_heavy_skip_next_beat = false
	_beat_generation += 1  # 使所有残留回调失效
	_attack_beat_input_states.clear()
	
	# 预计算所有拍的绝对时间（输入拍 + 退出拍），这里存储“每拍窗口起点”。
	_attack_beat_abs_times.clear()
	_attack_beat_abs_times.resize(GameConstants.INPUT_BEATS + GameConstants.EXIT_BEATS)
	for i in range(GameConstants.INPUT_BEATS + GameConstants.EXIT_BEATS):
		_attack_beat_abs_times[i] = current_beat_start_time + i * bi
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
	# 忽略键盘长按产生的重复事件，避免一次按住跨拍连续占位。
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.echo:
			return

	# 先将攻击拍状态追到当前时刻，避免输入事件先于 _process 导致落在旧拍状态。
	var synced_now: float = _get_music_clock_time()
	_advance_attack_beats_to_time(synced_now)

	# 检测按键动作
	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			var current_time: float = synced_now
			var judge_beat: int = _get_input_judge_beat_for_time(current_time)
			# 仅允许在输入阶段有效拍窗口内发动行动
			if judge_beat < 1 or judge_beat > GameConstants.INPUT_BEATS:
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
					attack_type = AttackType.ENHANCE

			var beat_used: bool = bool(_attack_beat_input_states.get(judge_beat, false))
			if beat_used:
				print("当前拍已被占用，等待下一次未占用拍")
				return

			var beat_start_time: float = _attack_beat_abs_times[judge_beat - 1]
			var time_since_beat: float = current_time - beat_start_time
			
			_attack_beat_input_states[judge_beat] = true
			if judge_beat == current_beat_in_attack:
				current_beat_has_input = true
			
			# 发送攻击信号
			EventBus.attack_performed.emit(attack_type)
			_log_attack_drum_alignment("input_" + _get_attack_name(attack_type))
			print("发动攻击: ", _get_attack_name(attack_type), " (距离节拍 ", int(time_since_beat * 1000), "ms)")
			
			# 重攻击消耗两拍：占用下一拍，不立即触发第二次攻击
			if attack_type == AttackType.HEAVY and judge_beat < GameConstants.INPUT_BEATS:
				_heavy_skip_next_beat = true
				print("重击占用下一拍")
			
			return


func _get_input_judge_beat_for_time(now: float) -> int:
	if attack_beat_interval <= 0.0:
		return -1
	if _attack_beat_abs_times.size() < GameConstants.INPUT_BEATS:
		return -1

	for i in range(GameConstants.INPUT_BEATS):
		var start_time: float = _attack_beat_abs_times[i]
		var end_time: float = start_time + attack_beat_interval
		if now >= start_time and now < end_time:
			return i + 1

	return -1


func _advance_attack_beats_to_time(now: float) -> void:
	if current_phase != PhaseState.ATTACK:
		return
	while _next_beat_idx < _attack_beat_abs_times.size() and now >= _attack_beat_abs_times[_next_beat_idx]:
		_on_attack_beat_timed(_next_beat_idx)
		_next_beat_idx += 1


## 攻击节拍触发（基于绝对时间，由 _process 调用）
## beat_idx: 拍子在 _attack_beat_abs_times 数组中的索引
func _on_attack_beat_timed(beat_idx: int) -> void:
	# 递增拍数，使用预计算的绝对时间（消除帧抖动漂移）
	current_beat_in_attack += 1
	current_beat_start_time = _attack_beat_abs_times[beat_idx]
	
	print("DEBUG: _on_attack_beat_timed - beat_idx=", beat_idx, ", current_beat=", current_beat_in_attack, ", has_input=", current_beat_has_input)
	
	# 继承占用状态：重击占用下一拍
	if _heavy_skip_next_beat:
		current_beat_has_input = true
		_current_beat_forced_occupied = true
		_attack_beat_input_states[current_beat_in_attack] = true
		_heavy_skip_next_beat = false
		print("重击占用本拍")
	else:
		current_beat_has_input = false
		_current_beat_forced_occupied = false
		_attack_beat_input_states[current_beat_in_attack] = false
	
	# 输入阶段（拍 1 ~ INPUT_BEATS）
	if current_beat_in_attack <= GameConstants.INPUT_BEATS:
		# 判定拍结束时（反拍）若无输入则自动回复。
		_schedule_auto_heal_for_beat(current_beat_in_attack, current_beat_start_time)

		# 生成下一个节拍标记视觉音符（覆盖拍 3 ~ 16）
		if current_beat_in_attack < (GameConstants.INPUT_BEATS - 1):
			# 目标时间使用“重音中心”，因此在窗口起点基础上加 2.5 拍。
			var note_target_time: float = _attack_beat_abs_times[beat_idx] + 2.5 * attack_beat_interval
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
	_attack_beat_input_states.clear()
	_current_beat_forced_occupied = false
	if attack_phase_timer != null:
		attack_phase_timer.stop()
	attack_beat_timer.stop()
	
	print("[总拍", GameConstants.TOTAL_ATTACK_BEATS, "/", GameConstants.TOTAL_ATTACK_BEATS, "] 攻击阶段结束")
	print("========== 攻击阶段结束 ==========\n")
	
	EventBus.attack_movement_enabled_changed.emit(false)
	EventBus.hide_attack_ui_requested.emit()
	EventBus.attack_phase_ended.emit()


func force_end_attack_phase() -> void:
	if current_phase != PhaseState.ATTACK:
		return

	current_phase = PhaseState.DEFENSE
	_beat_generation += 1
	_attack_beat_abs_times.clear()
	_attack_beat_input_states.clear()
	_current_beat_forced_occupied = false
	_heavy_skip_next_beat = false

	if attack_phase_timer != null:
		attack_phase_timer.stop()
	if attack_beat_timer != null:
		attack_beat_timer.stop()

	EventBus.attack_movement_enabled_changed.emit(false)
	EventBus.hide_attack_ui_requested.emit()
	EventBus.attack_phase_ended.emit()


func _get_attack_name(attack_type: AttackType) -> String:
	match attack_type:
		AttackType.LIGHT:
			return "轻攻击"
		AttackType.HEAVY:
			return "重攻击"
		AttackType.HEAL:
			return "回复"
		AttackType.ENHANCE:
			return "蓄力"
		_:
			return "未知"


func _log_attack_drum_alignment(tag: String) -> void:
	if not debug_attack_drum_alignment:
		return
	if attack_beat_interval <= 0.0:
		return
	if not music_player:
		return
	if not music_player.has_method("get_drum_playback_position"):
		return

	var drum_pos: float = float(music_player.call("get_drum_playback_position"))
	if drum_pos < 0.0:
		return

	var phase_in_beat: float = fposmod(drum_pos, attack_beat_interval)
	var distance_to_nearest_accent: float = minf(phase_in_beat, attack_beat_interval - phase_in_beat)
	print("[AttackDrumAlign] tag=", tag,
		" beat=", current_beat_in_attack,
		" drum_pos=", "%.4f" % drum_pos,
		" phase=", "%.4f" % phase_in_beat,
		" bi=", "%.4f" % attack_beat_interval,
		" dist_to_accent=", "%.4f" % distance_to_nearest_accent)


func _schedule_auto_heal_for_beat(beat_number: int, beat_start_time: float) -> void:
	if beat_number < 1 or beat_number > GameConstants.INPUT_BEATS:
		return

	var token: int = _beat_generation
	var beat_end_time: float = beat_start_time + attack_beat_interval
	var now: float = _get_music_clock_time()
	var delay: float = maxf(0.0, beat_end_time - now)

	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if token != _beat_generation:
			return
		if current_phase != PhaseState.ATTACK:
			return

		var already_used: bool = bool(_attack_beat_input_states.get(beat_number, false))
		if already_used:
			return

		_attack_beat_input_states[beat_number] = true
		if current_beat_in_attack == beat_number:
			current_beat_has_input = true

		EventBus.attack_performed.emit(AttackType.HEAL)
		_log_attack_drum_alignment("auto_heal")
		print("自动回复（拍", beat_number, "，本拍无输入）")
	)


func _get_music_clock_time() -> float:
	if music_player == null:
		return 0.0
	return float(music_player.get_playback_position()) + AudioServer.get_time_to_next_mix()
