extends Node

const RhythmClock := preload("res://scripts/RhythmClock.gd")
const AttackHeatModel := preload("res://scripts/AttackHeatModel.gd")
const AttackBeatGrid := preload("res://scripts/AttackBeatGrid.gd")
const DefenseJudgmentRules := preload("res://scripts/DefenseJudgmentRules.gd")
const DefenseInputResolution := preload("res://scripts/DefenseInputResolution.gd")
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
}

# 游戏阶段状态机
enum PhaseState {
	DEFENSE,  # 防御阶段（正常游戏）
	ATTACK,   # 攻击阶段（含输入和退出）
	PAUSED    # 暂停（准备阶段等）
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
@export var defense_hit_effect_scale_multiplier: Vector2 = Vector2(1.0, 1.0)
@export var defense_hit_effect_follow_anchor_scale: bool = false

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
var attack_phase_end_time: float = 0.0
var current_beat_has_input: bool = false  # 当前拍是否已有输入
var _heavy_skip_next_beat: bool = false    # 重击占用下一拍标志
var _beat_generation: int = 0            # 每拍递增，用于使过期回调失效
var attack_beat_grid: RefCounted = AttackBeatGrid.new()
var attack_countdown_beats: int = GameConstants.COUNTDOWN_BEATS
var attack_input_beats: int = GameConstants.INPUT_BEATS
var attack_exit_beats: int = GameConstants.EXIT_BEATS
var _attack_clock_active: bool = false
var _attack_clock_base_time: float = 0.0
var _attack_clock_wall_start: float = 0.0
var _defense_hit_effect_anchor: Node2D = null
var _defense_hit_effect_boss: Node2D = null

var heat_model: RefCounted = AttackHeatModel.new()


func _ready() -> void:
	Input.use_accumulated_input = false

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
	if attack_phase_end_time > 0.0 and now >= attack_phase_end_time:
		_on_attack_phase_end()


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
	var current_time: float = _get_music_clock_time()
	
	var resolution: Dictionary = DefenseInputResolution.resolve(
		track_manager.tracked_notes,
		track_type,
		current_time,
		DefenseJudgmentRules.good_window(),
		ignore_empty_press_without_nearby_notes,
		empty_press_note_check_window
	)
	var resolution_kind: int = int(resolution["kind"])
	var closest_tracked: Note = null
	if resolution_kind == DefenseInputResolution.KIND_TRACKED_NOTE:
		closest_tracked = resolution["note"]
	
	if closest_tracked:
		var min_tracked_diff: float = abs(current_time - closest_tracked.beat_time)
		var judgment: JudgmentType = _calculate_judgment(min_tracked_diff)
		var timing_diff: float = current_time - closest_tracked.beat_time
		track_manager.tracked_notes.erase(closest_tracked)
		var is_miss: bool = judgment == JudgmentType.MISS
		if is_miss:
			_apply_miss_audio_effect()
			_play_key_sound(track_type)
		else:
			_spawn_defense_hit_effect(track_type)
		_play_defense_sound(track_type, is_miss)
		EventBus.judgment_made.emit(track_type, judgment, timing_diff)
		print("判定: ", _get_judgment_text(judgment), " (", int(min_tracked_diff * 1000), "ms)")
		return
	
	# 没有同轨道音符在判定窗口内，检查是否按错了键（其他轨道有音符）
	var wrong_note: Note = null
	if resolution_kind == DefenseInputResolution.KIND_WRONG_NOTE:
		wrong_note = resolution["note"]
	
	if wrong_note:
		# 按错键：消耗该音符并判定为 MISS（避免之后自动超时再触发一次 MISS）
		track_manager.tracked_notes.erase(wrong_note)
		_apply_miss_audio_effect()
		EventBus.judgment_made.emit(wrong_note.type, JudgmentType.MISS, 0.0)
		print("判定: MISS (按错键 - 应为 ", wrong_note.get_type_string(), ")")
		return

	# 真正的空按
	if ignore_empty_press_without_nearby_notes:
		if resolution_kind == DefenseInputResolution.KIND_EMPTY_IGNORED:
			_play_key_sound(track_type)
			print("判定: 忽略空按 (附近无音符)")
			return
	_apply_miss_audio_effect()
	EventBus.judgment_made.emit(track_type, JudgmentType.MISS, 0.0)
	print("判定: MISS (空按)")


func _spawn_defense_hit_effect(note_type: Note.NoteType) -> void:
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
	_configure_defense_hit_effect_visual(effect_instance)
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
		var visual_anchor: Node2D = _get_defense_hit_effect_visual_anchor(anchor)
		var base_position: Vector2 = visual_anchor.global_position if visual_anchor != null else anchor.global_position
		return base_position + _get_scaled_facing_effect_offset(visual_anchor if visual_anchor != null else anchor)
	return defense_hit_effect_offset


func _configure_defense_hit_effect_visual(effect_instance: Node2D) -> void:
	if effect_instance == null:
		return

	var anchor: Node2D = _resolve_defense_hit_effect_anchor()
	var visual_anchor: Node2D = _get_defense_hit_effect_visual_anchor(anchor) if anchor != null else null
	var scale_source: Node2D = visual_anchor if visual_anchor != null else anchor
	var source_scale: Vector2 = _get_abs_global_scale(scale_source) if defense_hit_effect_follow_anchor_scale else Vector2.ONE
	effect_instance.scale *= source_scale * defense_hit_effect_scale_multiplier

	effect_instance.z_as_relative = false
	var source_z: int = 0
	if visual_anchor != null:
		source_z = visual_anchor.z_index
	elif anchor != null:
		source_z = anchor.z_index
	effect_instance.z_index = max(effect_instance.z_index, source_z + 10, 50)


func _get_scaled_facing_effect_offset(source: Node2D) -> Vector2:
	var scale_abs: Vector2 = _get_abs_global_scale(source) if defense_hit_effect_follow_anchor_scale else Vector2.ONE
	var forward_sign: float = _get_visual_forward_sign(source)
	return Vector2(absf(defense_hit_effect_offset.x) * forward_sign * scale_abs.x, defense_hit_effect_offset.y * scale_abs.y)


func _get_defense_hit_effect_visual_anchor(anchor: Node2D) -> Node2D:
	if anchor == null:
		return null
	if anchor is AnimatedSprite2D:
		return anchor

	var preferred: Node2D = anchor.get_node_or_null("CharacterVisual/AnimatedSprite2D") as Node2D
	if preferred != null:
		return preferred

	return anchor.find_child("AnimatedSprite2D", true, false) as Node2D


func _get_visual_forward_sign(source: Node2D) -> float:
	var sprite: AnimatedSprite2D = source as AnimatedSprite2D
	if sprite != null:
		return 1.0 if sprite.flip_h else -1.0
	if source != null and source.global_scale.x < 0.0:
		return 1.0
	return -1.0


func _get_abs_global_scale(source: Node2D) -> Vector2:
	if source == null:
		return Vector2.ONE
	return Vector2(maxf(0.01, absf(source.global_scale.x)), maxf(0.01, absf(source.global_scale.y)))


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
	return DefenseJudgmentRules.calculate(time_diff)


## 应用 Miss 音效
func _apply_miss_audio_effect() -> void:
	if music_player and music_player.has_method("apply_miss_effect"):
		music_player.apply_miss_effect()


## 获取判定文本
func _get_judgment_text(judgment: JudgmentType) -> String:
	return DefenseJudgmentRules.get_text(judgment)


## 获取判定颜色
func get_judgment_color(judgment: JudgmentType) -> Color:
	return DefenseJudgmentRules.get_color(judgment)


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
	attack_phase_end_time = 0.0
	attack_beat_grid.clear()
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
func start_attack_phase(
	_duration: float,
	bi: float,
	first_beat_abs_time: float,
	countdown_beats: int = GameConstants.COUNTDOWN_BEATS,
	input_beats: int = GameConstants.INPUT_BEATS,
	exit_beats: int = GameConstants.EXIT_BEATS
) -> void:
	attack_beat_interval = bi
	attack_countdown_beats = maxi(1, countdown_beats)
	attack_input_beats = maxi(1, input_beats)
	attack_exit_beats = maxi(1, exit_beats)
	_start_attack_clock(first_beat_abs_time - float(attack_countdown_beats) * attack_beat_interval)
	current_phase = PhaseState.ATTACK
	current_beat_in_attack = 0
	attack_phase_start_time = _get_music_clock_time()
	attack_phase_end_time = first_beat_abs_time + float(attack_input_beats + attack_exit_beats) * attack_beat_interval
	current_beat_start_time = first_beat_abs_time
	current_beat_has_input = false
	_heavy_skip_next_beat = false
	_beat_generation += 1
	
	heat_model.reset()
	EventBus.heat_changed.emit(0, 0)
	
	attack_beat_grid.configure(first_beat_abs_time, attack_beat_interval, attack_input_beats, attack_exit_beats)
	
	EventBus.show_attack_ui_requested.emit()
	EventBus.attack_track_setup.emit(bi, first_beat_abs_time, attack_countdown_beats, attack_input_beats, attack_exit_beats)
	EventBus.attack_phase_started.emit()
	
	var total_attack_beats: int = attack_countdown_beats + attack_input_beats + attack_exit_beats
	var first_total: int = attack_countdown_beats + 1
	print("[总拍", first_total, "/", total_attack_beats, "] 输入阶段 - 拍1/", attack_input_beats)
	
	attack_phase_timer.stop()


## 攻击阶段的输入处理
func _handle_attack_phase_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.echo:
			return

	var synced_now: float = _get_music_clock_time()
	_advance_attack_beats_to_time(synced_now)

	for action in ACTION_MAPPING:
		if event.is_action_pressed(action):
			var current_time: float = synced_now
			var judge_beat: int = _get_input_judge_beat_for_time(current_time)
			if judge_beat < 1 or judge_beat > attack_input_beats:
				print("当前不在可输入拍，忽略攻击输入")
				return

			var track: Note.NoteType = ACTION_MAPPING[action]
			var attack_type: AttackType
			match track:
				Note.NoteType.GUARD:
					attack_type = AttackType.LIGHT
				Note.NoteType.HIT:
					attack_type = AttackType.HEAVY
				Note.NoteType.DODGE:
					attack_type = AttackType.HEAL

			var beat_used: bool = attack_beat_grid.is_beat_used(judge_beat)
			if beat_used:
				print("当前拍已被占用，等待下一次未占用拍")
				return

			var beat_start_time: float = attack_beat_grid.get_beat_time(judge_beat)
			var time_since_beat: float = current_time - beat_start_time

			attack_beat_grid.set_beat_used(judge_beat, true)
			if judge_beat == current_beat_in_attack:
				current_beat_has_input = true

			match attack_type:
				AttackType.LIGHT:
					var is_perfect: bool = absf(time_since_beat) < GameConstants.ATTACK_PERFECT_WINDOW
					heat_model.record_light_result(is_perfect)
					EventBus.attack_performed.emit(AttackType.LIGHT, 0)
					EventBus.attack_result_display.emit(AttackType.LIGHT, is_perfect, heat_model.heat_level)
					EventBus.heat_changed.emit(heat_model.heat_level, heat_model.heat_counter)
					_log_attack_drum_alignment("light_" + ("perfect" if is_perfect else "miss"))
					print("Light attack - ", "PERFECT" if is_perfect else "MISS", " Heat:", heat_model.heat_level, "(", heat_model.heat_counter, "/", GameConstants.PERFECTS_PER_LEVEL, ")")

				AttackType.HEAVY:
					var current_heat: int = heat_model.consume_heavy_heat()
					EventBus.attack_performed.emit(AttackType.HEAVY, current_heat)
					EventBus.attack_result_display.emit(AttackType.HEAVY, true, current_heat)
					EventBus.heat_changed.emit(0, 0)
					if judge_beat + 1 <= attack_input_beats + attack_exit_beats:
						attack_beat_grid.set_beat_used(judge_beat + 1, true)
						_heavy_skip_next_beat = true
					_log_attack_drum_alignment("heavy")
					print("Heavy attack - spent heat:", current_heat, " damage multiplier:", 1 + current_heat * GameConstants.HEAT_DAMAGE_MULTIPLIER_PER_LEVEL)

				AttackType.HEAL:
					EventBus.attack_performed.emit(AttackType.HEAL, 0)
					EventBus.attack_result_display.emit(AttackType.HEAL, true, 0)
					_log_attack_drum_alignment("heal")
					print("Heal")

			return


func _get_input_judge_beat_for_time(now: float) -> int:
	return attack_beat_grid.get_input_judge_beat(now)


func _advance_attack_beats_to_time(now: float) -> void:
	if current_phase != PhaseState.ATTACK:
		return
	attack_beat_grid.advance_due_beats(now, Callable(self, "_on_attack_beat_timed"))


## 攻击节拍触发（基于绝对时间，由 _process 调用）
## beat_idx: beat index inside the attack beat grid.
func _on_attack_beat_timed(beat_idx: int) -> void:
	current_beat_in_attack += 1
	current_beat_start_time = attack_beat_grid.get_beat_time_by_index(beat_idx)

	if _heavy_skip_next_beat:
		current_beat_has_input = true
		attack_beat_grid.set_beat_used(current_beat_in_attack, true)
		_heavy_skip_next_beat = false
	else:
		current_beat_has_input = false
		attack_beat_grid.set_beat_used(current_beat_in_attack, false)

	var total_attack_beats: int = attack_countdown_beats + attack_input_beats + attack_exit_beats
	if current_beat_in_attack <= attack_input_beats:
		if current_beat_in_attack == 1:
			EventBus.attack_movement_enabled_changed.emit(true)

		var total_beat: int = current_beat_in_attack + attack_countdown_beats
		print("[总拍", total_beat, "/", total_attack_beats, "] 输入阶段 - 拍", current_beat_in_attack, "/", attack_input_beats)
	elif current_beat_in_attack > attack_input_beats and current_beat_in_attack <= attack_input_beats + attack_exit_beats:
		if current_beat_in_attack == attack_input_beats + 1:
			EventBus.attack_movement_enabled_changed.emit(false)
		var countdown: int = attack_input_beats + attack_exit_beats - current_beat_in_attack + 1
		var total_beat: int = current_beat_in_attack + attack_countdown_beats
		print("[总拍", total_beat, "/", total_attack_beats, "] 结束阶段 - 倒计时", countdown)
		EventBus.show_return_countdown_requested.emit(countdown)



## 攻击阶段结束
func _on_attack_phase_end() -> void:
	if current_phase != PhaseState.ATTACK:
		return

	_reset_attack_phase_runtime()
	
	var total_attack_beats: int = attack_countdown_beats + attack_input_beats + attack_exit_beats
	print("[总拍", total_attack_beats, "/", total_attack_beats, "] 攻击阶段结束")
	print("========== 攻击阶段结束 ==========\n")
	
	_emit_attack_phase_ended()


func force_end_attack_phase() -> void:
	if current_phase != PhaseState.ATTACK:
		return

	_reset_attack_phase_runtime()

	_emit_attack_phase_ended()


func _reset_attack_phase_runtime() -> void:
	current_phase = PhaseState.DEFENSE
	_stop_attack_clock()
	attack_phase_end_time = 0.0
	_beat_generation += 1
	attack_beat_grid.clear()
	_heavy_skip_next_beat = false
	if attack_phase_timer != null:
		attack_phase_timer.stop()
	if attack_beat_timer != null:
		attack_beat_timer.stop()


func _emit_attack_phase_ended() -> void:
	EventBus.attack_movement_enabled_changed.emit(false)
	EventBus.hide_attack_ui_requested.emit()
	EventBus.attack_phase_ended.emit()


func _get_attack_name(attack_type: AttackType) -> String:
	match attack_type:
		AttackType.LIGHT:
			return "Light Attack"
		AttackType.HEAVY:
			return "Heavy Attack"
		AttackType.HEAL:
			return "Heal"
		_:
			return "Unknown"


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


func _get_music_clock_time() -> float:
	if _attack_clock_active:
		return _attack_clock_base_time + (RhythmClock.get_wall_time_seconds() - _attack_clock_wall_start)
	return RhythmClock.get_music_time(music_player)


func _start_attack_clock(base_time: float) -> void:
	_attack_clock_base_time = base_time
	_attack_clock_wall_start = RhythmClock.get_wall_time_seconds()
	_attack_clock_active = true


func _stop_attack_clock() -> void:
	_attack_clock_active = false
