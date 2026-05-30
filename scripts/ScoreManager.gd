extends Node

const RhythmClock := preload("res://scripts/RhythmClock.gd")
const AttackHitQueue := preload("res://scripts/AttackHitQueue.gd")
const DialoguePauseState := preload("res://scripts/DialoguePauseState.gd")
const AttackPhaseTiming := preload("res://scripts/AttackPhaseTiming.gd")
## 分数管理器 - 管理玩家分数、血量、Boss体力

signal player_died()
signal boss_defeated()

var current_player_health: float = 0.0
var current_boss_health: float = 0.0
var current_boss_energy: float = 0.0
var temporary_energy_reduce: float = 0.0
var is_game_over: bool = false
@export var enabled: bool = true
@export_group("Attack Phase Beats")
@export_range(1, 32, 1) var attack_countdown_beats: int = GameConstants.COUNTDOWN_BEATS
@export_range(1, 64, 1) var attack_input_beats: int = GameConstants.INPUT_BEATS
@export_range(1, 32, 1) var attack_exit_beats: int = GameConstants.EXIT_BEATS
@export_group("First Break Dialogue")
@export var enable_first_break_dialogue: bool = false
@export var first_break_dialogue_ui: DialogueUI = null
@export var first_break_dialogue_lines: Array[DialogueLine] = []

const PENDING_ATTACK_TIMEOUT: float = 0.6

# 同级兄弟节点引用（GameManager 内部）
@onready var beat_manager: Node = get_node("../BeatManager")
@onready var track_manager: Node = get_node("../TrackManager")
@onready var input_manager: Node = get_node("../InputManager")
@onready var music_player: Node = get_node("../MusicPlayer")
@onready var boss_node: Node = get_node_or_null("../Boss")

# 暂停相关
var is_paused_for_attack: bool = false
var pause_timer: Timer = null
var pause_end_music_time: float = 0.0
var pending_attack_anchor_music_time: float = -1.0
var _first_break_dialogue_played: bool = false
var _first_break_dialogue_active: bool = false
var _attack_hit_queue: RefCounted = AttackHitQueue.new(PENDING_ATTACK_TIMEOUT)
var _first_break_pause_state: RefCounted = DialoguePauseState.new()


func _ready() -> void:
	current_player_health = GameConfigs.judgment.max_player_health
	current_boss_health = GameConfigs.judgment.max_boss_health
	current_boss_energy = GameConfigs.judgment.max_boss_energy

	pause_timer = Timer.new()
	pause_timer.one_shot = true
	pause_timer.timeout.connect(_on_pause_timeout)
	add_child(pause_timer)
	
	# 通过 EventBus 连接信号（替代 get_node + signal connect）
	EventBus.judgment_made.connect(_on_judgment_made)
	EventBus.attack_performed.connect(_on_attack_performed)
	EventBus.attack_hit_confirmed.connect(_on_attack_hit_confirmed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	
	# 延迟一帧广播初始血量（确保 GameUI 已连接 EventBus）
	call_deferred("_emit_health_update")


func _process(_delta: float) -> void:
	if is_paused_for_attack and pause_end_music_time > 0.0 and _get_music_clock_time() >= pause_end_music_time:
		_on_pause_timeout()


## 广播所有血量/精力状态到 EventBus
func _emit_health_update() -> void:
	EventBus.player_health_updated.emit(current_player_health, GameConfigs.judgment.max_player_health)
	EventBus.boss_health_updated.emit(current_boss_health, GameConfigs.judgment.max_boss_health)
	EventBus.boss_energy_updated.emit(current_boss_energy, GameConfigs.judgment.max_boss_energy)


## 判定触发回调
func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
	if is_game_over or not enabled:
		return

	# 攻击阶段整段暂停窗口内（含退出倒计时到真正恢复前），忽略防御判定，
	# 避免提前扣盾后被 _on_pause_timeout 的精力恢复覆盖。
	if is_paused_for_attack:
		return

	# 如果是 MISS 判定，触发对应轨道的音效衰减
	if judgment == 3:  # MISS
		if music_player and music_player.has_method("apply_track_miss_effect"):
			music_player.apply_track_miss_effect(track)
	
	# 根据音符类型和判定等级获取数值
	var energy_cost: float = GameConfigs.judgment.get_boss_damage(track, judgment)
	var health_change: float = GameConfigs.judgment.get_player_health_change(track, judgment)
	var judgment_target_music_time: float = _get_music_clock_time() - _timing_diff
	
	# 减少Boss精力
	var old_energy: float = current_boss_energy
	current_boss_energy -= energy_cost
	current_boss_energy = clampf(current_boss_energy, 0.0, GameConfigs.judgment.max_boss_energy)
	
	# 检测精力条是否被打空
	if old_energy > 0.0 and current_boss_energy <= 0.0:
		pending_attack_anchor_music_time = judgment_target_music_time
		if not _try_start_first_break_dialogue():
			_trigger_boss_energy_depleted()
		print("Boss 精力耗尽！")
	
	# 改变玩家血量
	current_player_health += health_change
	current_player_health = clampf(current_player_health, 0.0, GameConfigs.judgment.max_player_health)
	
	# 通过 EventBus 广播血量变化
	_emit_health_update()
	
	# 检查胜负条件
	if current_player_health <= 0.0:
		_trigger_player_game_over()
		print("玩家失败！")
	elif current_boss_health <= 0.0:
		boss_defeated.emit()
		EventBus.boss_defeated.emit()
		print("Boss 被击败！")


## 更新血量条显示（通过 EventBus 广播）
func _update_health_bars() -> void:
	_emit_health_update()


## 重置游戏
func reset_game() -> void:
	current_player_health = GameConfigs.judgment.max_player_health
	current_boss_health = GameConfigs.judgment.max_boss_health
	current_boss_energy = GameConfigs.judgment.max_boss_energy
	temporary_energy_reduce = 0.0
	_first_break_dialogue_played = false
	_first_break_dialogue_active = false
	_update_health_bars()


## Boss 精力耗尽时的处理（进入攻击阶段）
func _on_boss_energy_depleted() -> void:
	if is_paused_for_attack:
		pending_attack_anchor_music_time = -1.0
		return  # 已经在暂停状态，不重复处理
	
	is_paused_for_attack = true
	
	# 使用 @onready 兄弟节点引用 + EventBus 常量
	var timing: Dictionary = AttackPhaseTiming.build(
		beat_manager.beat_interval,
		attack_countdown_beats,
		attack_input_beats,
		attack_exit_beats
	)
	var bi: float = float(timing["beat_interval"])
	var countdown_beats: int = int(timing["countdown_beats"])
	var input_beats: int = int(timing["input_beats"])
	var exit_beats: int = int(timing["exit_beats"])
	var total_attack_beats: int = int(timing["total_beats"])
	var pause_duration: float = float(timing["total_duration"])
	
	print("\n========== 攻击阶段开始（共", total_attack_beats, "拍） ==========")
	
	# 暂停节拍检测
	beat_manager.pause_beat_detection()
	
	# 暂停音符生成和清理已生成的音符
	if track_manager:
		if track_manager.has_method("pause_note_spawning"):
			track_manager.pause_note_spawning()
		track_manager.clear_all_notes()
	
	# 暂停输入检测
	if input_manager and input_manager.has_method("pause_input"):
		input_manager.pause_input()
	
	# 通过 EventBus 通知 UI 层（替代 get_node GameUI）
	var depletion_music_time: float = _consume_attack_anchor_music_time()
	EventBus.show_pause_countdown_requested.emit(bi, countdown_beats, depletion_music_time)

	# 基于音乐时钟计算第一输入拍时间（秒）：不依赖系统时钟，避免进出阶段漂移。
	var first_beat_abs_time: float = depletion_music_time + float(countdown_beats) * bi  # 输入拍第1拍（音乐时间轴）
	pause_end_music_time = depletion_music_time + pause_duration
	# 后四个小节：节拍闪光效果
	EventBus.play_beat_flash_requested.emit(bi, input_beats, first_beat_abs_time)
	# 在准备阶段开始时，直接启动攻击阶段；真正可输入时机由 beat 事件与 movement enabled 控制
	_start_attack_phase(pause_duration, bi, first_beat_abs_time, countdown_beats, input_beats, exit_beats)

	# 保留 Timer 作为兜底清理；真正的阶段边界由音乐时钟驱动。
	if pause_timer != null:
		pause_timer.start(pause_duration + 0.5)
	print("游戏已进入攻击阶段 ", pause_duration, " 秒（", total_attack_beats, " 拍），音乐进度持续前进")


func _trigger_boss_energy_depleted() -> void:
	EventBus.boss_energy_depleted.emit()
	_on_boss_energy_depleted()


func _try_start_first_break_dialogue() -> bool:
	if not enable_first_break_dialogue:
		return false
	if _first_break_dialogue_played or _first_break_dialogue_active:
		return false
	if first_break_dialogue_ui == null or first_break_dialogue_lines.is_empty():
		return false
	if first_break_dialogue_ui.is_busy:
		return false

	_first_break_dialogue_played = true
	_first_break_dialogue_active = true
	_pause_for_first_break_dialogue()

	if not first_break_dialogue_ui.dialogue_closed.is_connected(_on_first_break_dialogue_closed):
		first_break_dialogue_ui.dialogue_closed.connect(_on_first_break_dialogue_closed, CONNECT_ONE_SHOT)
	first_break_dialogue_ui.play_sequence(first_break_dialogue_lines)
	print("First boss shield break dialogue started.")
	return true


func _pause_for_first_break_dialogue() -> void:
	if music_player and music_player.has_method("pause_music"):
		music_player.pause_music()

	if beat_manager and beat_manager.has_method("pause_beat_detection"):
		beat_manager.pause_beat_detection()

	if track_manager:
		if track_manager.has_method("pause_note_spawning"):
			track_manager.pause_note_spawning()
		if track_manager.has_method("clear_all_notes"):
			track_manager.clear_all_notes()

	if input_manager and input_manager.has_method("pause_input"):
		input_manager.pause_input()

	_first_break_pause_state.enter(get_tree(), first_break_dialogue_ui)


func _on_first_break_dialogue_closed() -> void:
	if not _first_break_dialogue_active:
		return

	_first_break_dialogue_active = false
	_first_break_pause_state.exit(get_tree(), first_break_dialogue_ui)

	if is_game_over:
		return

	if music_player and music_player.has_method("resume_music"):
		music_player.resume_music()

	_trigger_boss_energy_depleted()
	print("First boss shield break dialogue finished; attack phase resumed.")


## 暂停结束的回调
func _on_pause_timeout() -> void:
	if not is_paused_for_attack and pause_end_music_time <= 0.0:
		return
	if pause_end_music_time > 0.0 and _get_music_clock_time() < pause_end_music_time:
		return
	if is_game_over:
		return
	if current_boss_health <= 0.0:
		return

	is_paused_for_attack = false
	pause_end_music_time = 0.0
	
	# 通知 UI 隐藏暂停效果
	EventBus.hide_pause_effects_requested.emit()
	
	# 恢复节拍检测
	beat_manager.resume_beat_detection()
	
	# 恢复输入检测
	if input_manager and input_manager.has_method("resume_input"):
		input_manager.resume_input()
	
	# 恢复音符生成
	if track_manager and track_manager.has_method("resume_note_spawning"):
		track_manager.resume_note_spawning()

	# 退出攻击阶段混音
	if music_player and music_player.has_method("end_attack_mix_mode"):
		music_player.end_attack_mix_mode()
	
	# 恢复 Boss 精力条（减去临时削减量）
	var recovery_amount: float = GameConfigs.judgment.max_boss_energy - temporary_energy_reduce
	recovery_amount = max(recovery_amount, 10.0)  # 最小保留10点
	current_boss_energy = recovery_amount
	_emit_health_update()
	
	print("暂停结束，游戏继续 - BOSS精力恢复到:", recovery_amount, " (临时削减:", temporary_energy_reduce, ")")
func _get_music_clock_time() -> float:
	return RhythmClock.get_music_time(music_player)


func _consume_attack_anchor_music_time() -> float:
	if pending_attack_anchor_music_time >= 0.0:
		var anchor_time := pending_attack_anchor_music_time
		pending_attack_anchor_music_time = -1.0
		return anchor_time
	return _get_music_clock_time()


## 开始攻击阶段
func _start_attack_phase(
	duration: float,
	bi: float,
	first_beat_abs_time: float,
	countdown_beats: int,
	input_beats: int,
	exit_beats: int
) -> void:
	if is_game_over:
		return

	print("攻击阶段开始！")
	
	temporary_energy_reduce = 0.0
	_attack_hit_queue.clear()
	
	# 启用攻击输入监听（传入 first_beat_abs_time 统一时间基准）
	if input_manager and input_manager.has_method("start_attack_phase"):
		input_manager.start_attack_phase(duration, bi, first_beat_abs_time, countdown_beats, input_beats, exit_beats)
	
	# 通过 EventBus 通知 UI 显示攻击界面
	EventBus.show_attack_ui_requested.emit()


## 处理攻击效果
func _on_attack_performed(attack_type: int, heat_level: int = 0) -> void:
	if is_game_over or not enabled:
		return

	if not GameConfigs.sound:
		print("警告：未配置攻击数据 (GameConfigs.sound)")
		return

	_attack_hit_queue.cleanup(_get_music_clock_time())

	var player_cost: float = 0.0
	var boss_damage: float = 0.0
	var energy_max_reduce: float = 0.0
	var heal_amount: float = 0.0

	match attack_type:
		0:  # LIGHT - 积攒热度
			_play_attack_action_sfx(attack_type, false)
			player_cost = GameConfigs.sound.light_player_health_cost
			boss_damage = GameConfigs.sound.light_boss_damage
			energy_max_reduce = GameConfigs.sound.light_boss_energy_max_reduce
			print("轻攻击 - 伤害:", boss_damage)

			current_player_health -= player_cost
			temporary_energy_reduce += energy_max_reduce
			_queue_attack_hit(attack_type, boss_damage)

		1:  # HEAVY - 消耗热度
			_play_attack_action_sfx(attack_type, false)
			player_cost = GameConfigs.sound.heavy_player_health_cost
			var heat_multiplier: float = GameConstants.HEAT_DAMAGE_MULTIPLIER_BASE + heat_level * GameConstants.HEAT_DAMAGE_MULTIPLIER_PER_LEVEL
			boss_damage = GameConfigs.sound.heavy_boss_damage * heat_multiplier
			energy_max_reduce = GameConfigs.sound.heavy_boss_energy_max_reduce
			print("重攻击 - 热度:", heat_level, " 倍率:", heat_multiplier, " 伤害:", boss_damage)

			current_player_health -= player_cost
			temporary_energy_reduce += energy_max_reduce
			_queue_attack_hit(attack_type, boss_damage)

		2:  # HEAL - 回复
			_play_attack_action_sfx(attack_type, false)
			heal_amount = GameConfigs.sound.heal_amount
			current_player_health += heal_amount
			print("回复 - 恢复:", heal_amount)

		_:
			return

	current_player_health = clampf(current_player_health, 0.0, GameConfigs.judgment.max_player_health)
	current_boss_health = clampf(current_boss_health, 0.0, GameConfigs.judgment.max_boss_health)

	_emit_health_update()

	if current_player_health <= 0.0:
		_trigger_player_game_over()
		print("玩家失败！")
	elif current_boss_health <= 0.0:
		boss_defeated.emit()
		EventBus.boss_defeated.emit()
		print("Boss被击败！")


func _on_attack_hit_confirmed(attack_type: int, _target: Variant) -> void:
	if is_game_over or not enabled:
		return

	var damage: float = _attack_hit_queue.take_damage_for_type(attack_type, _get_music_clock_time())

	var damage_multiplier: float = 1.0
	var resolved_boss: Node = _resolve_boss_node()
	if resolved_boss != null and is_instance_valid(resolved_boss) and resolved_boss.has_method("get_hit_damage_multiplier"):
		damage_multiplier = float(resolved_boss.call("get_hit_damage_multiplier", _target))
	damage *= maxf(0.0, damage_multiplier)

	if damage <= 0.0:
		return

	var old_boss_health: float = current_boss_health
	current_boss_health -= damage
	current_boss_health = clampf(current_boss_health, 0.0, GameConfigs.judgment.max_boss_health)
	var applied_damage: float = maxf(0.0, old_boss_health - current_boss_health)
	_emit_health_update()
	print("攻击命中 - 造成伤害:", damage)
	if applied_damage > 0.0:
		EventBus.attack_hit_resolved.emit(applied_damage, _target)

	if current_boss_health <= 0.0:
		boss_defeated.emit()
		EventBus.boss_defeated.emit()
		print("Boss被击败！")


func _resolve_boss_node() -> Node:
	if boss_node != null and is_instance_valid(boss_node):
		return boss_node

	boss_node = get_node_or_null("../Boss")
	if boss_node != null and is_instance_valid(boss_node):
		return boss_node

	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var direct_boss: Node = scene_root.get_node_or_null("Boss")
		if direct_boss != null and is_instance_valid(direct_boss):
			boss_node = direct_boss
			return boss_node

		var found_boss: Node = scene_root.find_child("Boss", true, false)
		if found_boss != null and is_instance_valid(found_boss):
			boss_node = found_boss
			return boss_node

	return null


func _queue_attack_hit(attack_type: int, damage: float) -> void:
	_attack_hit_queue.queue_hit(attack_type, damage, _get_music_clock_time())


func _play_attack_action_sfx(attack_type: int, is_charged: bool) -> void:
	if GameConfigs.sound == null or GameConfigs.sound.player_attack == null:
		return
	var pool: RandomSoundPool = GameConfigs.sound.player_attack.get_sound(attack_type, is_charged)
	if pool == null:
		return
	SFXManager.play_pool(pool, GameConfigs.sound.player_attack.sfx_bus)


func _trigger_player_game_over() -> void:
	if is_game_over:
		return

	is_game_over = true
	is_paused_for_attack = false
	pause_end_music_time = 0.0
	_attack_hit_queue.clear()

	if pause_timer != null:
		pause_timer.stop()

	if beat_manager != null and beat_manager.has_method("pause_beat_detection"):
		beat_manager.pause_beat_detection()

	if track_manager != null:
		if track_manager.has_method("pause_note_spawning"):
			track_manager.pause_note_spawning()
		if track_manager.has_method("clear_all_notes"):
			track_manager.clear_all_notes()

	if input_manager != null and input_manager.has_method("pause_input"):
		input_manager.pause_input()

	player_died.emit()
	EventBus.player_died.emit()


func _on_boss_defeated() -> void:
	if is_game_over or not enabled:
		return

	is_game_over = true
	pause_end_music_time = 0.0
	_attack_hit_queue.clear()

	if pause_timer != null:
		pause_timer.stop()

	if is_paused_for_attack:
		is_paused_for_attack = false

		if input_manager and input_manager.has_method("force_end_attack_phase"):
			input_manager.force_end_attack_phase()

		if music_player and music_player.has_method("end_attack_mix_mode"):
			music_player.end_attack_mix_mode()

		EventBus.hide_attack_ui_requested.emit()
		EventBus.hide_pause_effects_requested.emit()

	if music_player and music_player.has_method("fade_out_all_for_death"):
		music_player.fade_out_all_for_death()

	if beat_manager and beat_manager.has_method("pause_beat_detection"):
		beat_manager.pause_beat_detection()

	if track_manager:
		if track_manager.has_method("pause_note_spawning"):
			track_manager.pause_note_spawning()
		if track_manager.has_method("clear_all_notes"):
			track_manager.clear_all_notes()

	if input_manager and input_manager.has_method("pause_input"):
		input_manager.pause_input()

	print("Boss被击败！游戏结束。")
