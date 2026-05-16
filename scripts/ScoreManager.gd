extends Node
## 分数管理器 - 管理玩家分数、血量、Boss体力

signal player_died()
signal boss_defeated()

var current_player_health: float = 0.0
var current_boss_health: float = 0.0
var current_boss_energy: float = 0.0
var temporary_energy_reduce: float = 0.0
var pending_attack_hits: Array[Dictionary] = []
var is_game_over: bool = false
@export var enabled: bool = true

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
	
	# 减少Boss精力
	var old_energy: float = current_boss_energy
	current_boss_energy -= energy_cost
	current_boss_energy = clampf(current_boss_energy, 0.0, GameConfigs.judgment.max_boss_energy)
	
	# 检测精力条是否被打空
	if old_energy > 0.0 and current_boss_energy <= 0.0:
		EventBus.boss_energy_depleted.emit()
		_on_boss_energy_depleted()
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
	_update_health_bars()


## Boss 精力耗尽时的处理（进入攻击阶段）
func _on_boss_energy_depleted() -> void:
	if is_paused_for_attack:
		return  # 已经在暂停状态，不重复处理
	
	is_paused_for_attack = true
	
	# 使用 @onready 兄弟节点引用 + EventBus 常量
	var bi: float = beat_manager.beat_interval
	var countdown_duration: float = bi * GameConstants.COUNTDOWN_BEATS
	var attack_duration: float = bi * GameConstants.INPUT_BEATS
	var return_countdown_duration: float = bi * GameConstants.EXIT_BEATS
	var pause_duration: float = bi * GameConstants.TOTAL_ATTACK_BEATS
	
	print("\n========== 攻击阶段开始（共6小节", GameConstants.TOTAL_ATTACK_BEATS, "拍） ==========")
	
	# 为准备阶段添加节拍log
	for i in range(1, GameConstants.COUNTDOWN_BEATS + 1):
		var beat_num: int = i
		get_tree().create_timer(bi * (i - 1)).timeout.connect(func():
			if is_game_over:
				return
			print("[总拍", beat_num, "/", GameConstants.TOTAL_ATTACK_BEATS, "] 准备阶段 - 拍", beat_num, "/", GameConstants.COUNTDOWN_BEATS))
			
	
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
	EventBus.show_pause_countdown_requested.emit(bi)

	# 基于音乐时钟计算第一输入拍时间（秒）：不依赖系统时钟，避免进出阶段漂移。
	var depletion_music_time: float = _get_music_clock_time()
	var first_beat_abs_time: float = depletion_music_time + 4.0 * bi  # 输入拍第1拍（音乐时间轴）
	# 后四个小节：节拍闪光效果
	get_tree().create_timer(countdown_duration).timeout.connect(func():
		if is_game_over:
			return
		EventBus.play_beat_flash_requested.emit(bi, GameConstants.INPUT_BEATS)
	)
	# 在准备阶段开始时，直接启动攻击阶段；真正可输入时机由 beat 事件与 movement enabled 控制
	_start_attack_phase(countdown_duration + attack_duration + return_countdown_duration, bi, first_beat_abs_time)

	# 启动计时器（完整时长）
	if pause_timer != null:
		pause_timer.start(pause_duration)
	print("游戏已进入攻击阶段 ", pause_duration, " 秒（", GameConstants.TOTAL_ATTACK_BEATS, " 拍），音乐进度持续前进")


## 暂停结束的回调
func _on_pause_timeout() -> void:
	if is_game_over:
		return
	if current_boss_health <= 0.0:
		return

	is_paused_for_attack = false
	
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
	if music_player == null:
		return 0.0
	if music_player.has_method("get_playback_position"):
		return float(music_player.get_playback_position()) + AudioServer.get_time_to_next_mix()
	return 0.0


## 开始攻击阶段
func _start_attack_phase(duration: float, bi: float, first_beat_abs_time: float) -> void:
	if is_game_over:
		return

	print("攻击阶段开始！")
	
	temporary_energy_reduce = 0.0
	pending_attack_hits.clear()
	
	# 启用攻击输入监听（传入 first_beat_abs_time 统一时间基准）
	if input_manager and input_manager.has_method("start_attack_phase"):
		input_manager.start_attack_phase(duration, bi, first_beat_abs_time)
	
	# 通过 EventBus 通知 UI 显示攻击界面
	EventBus.show_attack_ui_requested.emit()


## 处理攻击效果
func _on_attack_performed(attack_type: int, heat_level: int = 0) -> void:
	if is_game_over or not enabled:
		return

	if not GameConfigs.sound:
		print("警告：未配置攻击数据 (GameConfigs.sound)")
		return

	_cleanup_pending_attack_hits()

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
			pending_attack_hits.append({
				"type": attack_type,
				"damage": boss_damage,
				"time": Time.get_ticks_msec() / 1000.0
			})

		1:  # HEAVY - 消耗热度
			_play_attack_action_sfx(attack_type, false)
			player_cost = GameConfigs.sound.heavy_player_health_cost
			var heat_multiplier: float = GameConstants.HEAT_DAMAGE_MULTIPLIER_BASE + heat_level * GameConstants.HEAT_DAMAGE_MULTIPLIER_PER_LEVEL
			boss_damage = GameConfigs.sound.heavy_boss_damage * heat_multiplier
			energy_max_reduce = GameConfigs.sound.heavy_boss_energy_max_reduce
			print("重攻击 - 热度:", heat_level, " 倍率:", heat_multiplier, " 伤害:", boss_damage)

			current_player_health -= player_cost
			temporary_energy_reduce += energy_max_reduce
			pending_attack_hits.append({
				"type": attack_type,
				"damage": boss_damage,
				"time": Time.get_ticks_msec() / 1000.0
			})

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

	_cleanup_pending_attack_hits()

	var hit_index: int = -1
	for i in range(pending_attack_hits.size()):
		var pending: Dictionary = pending_attack_hits[i]
		if pending.get("type", -1) == attack_type:
			hit_index = i
			break

	if hit_index < 0:
		return

	var damage: float = float(pending_attack_hits[hit_index].get("damage", 0.0))
	pending_attack_hits.remove_at(hit_index)

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


func _cleanup_pending_attack_hits() -> void:
	var now_time: float = Time.get_ticks_msec() / 1000.0
	for i in range(pending_attack_hits.size() - 1, -1, -1):
		var pending_time: float = float(pending_attack_hits[i].get("time", 0.0))
		if now_time - pending_time > PENDING_ATTACK_TIMEOUT:
			pending_attack_hits.remove_at(i)


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
	pending_attack_hits.clear()

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
	pending_attack_hits.clear()

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
