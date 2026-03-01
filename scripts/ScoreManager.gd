extends Node
## 分数管理器 - 管理玩家分数、血量、Boss体力

# AttackConfig 已通过 class_name 注册为全局类型，无需 preload

# 信号（保留用于本地监听）
signal player_died()
signal boss_defeated()

# === GUARD 音符配置 ===
@export_group("GUARD 音符 (防御) - J键第一轨道")
@export var guard_boss_damage_perfect: float = 5.0
@export var guard_boss_damage_great: float = 3.0
@export var guard_boss_damage_good: float = 2.0
@export var guard_boss_damage_miss: float = 0.0

@export var guard_player_health_perfect: float = 10.0
@export var guard_player_health_great: float = 7.0
@export var guard_player_health_good: float = 4.0
@export var guard_player_health_miss: float = -20.0

# === HIT 音符配置 ===
@export_group("HIT 音符 (攻击) - I键第二轨道")
@export var hit_boss_damage_perfect: float = 15.0
@export var hit_boss_damage_great: float = 10.0
@export var hit_boss_damage_good: float = 5.0
@export var hit_boss_damage_miss: float = 0.0

@export var hit_player_health_perfect: float = 3.0
@export var hit_player_health_great: float = 2.0
@export var hit_player_health_good: float = 1.0
@export var hit_player_health_miss: float = -15.0

# === DODGE 音符配置 ===
@export_group("DODGE 音符 (闪避) - L键第三轨道")
@export var dodge_boss_damage_perfect: float = 8.0
@export var dodge_boss_damage_great: float = 5.0
@export var dodge_boss_damage_good: float = 3.0
@export var dodge_boss_damage_miss: float = 0.0

@export var dodge_player_health_perfect: float = 5.0
@export var dodge_player_health_great: float = 3.0
@export var dodge_player_health_good: float = 2.0
@export var dodge_player_health_miss: float = -10.0

# === 基础配置 ===
@export_group("血量上限")
@export var max_player_health: float = 100.0
@export var max_boss_health: float = 500.0
@export var max_boss_energy: float = 100.0  # Boss 精力条最大值

# === 攻击阶段配置 ===
@export_group("攻击阶段")
@export var attack_config: AttackConfig = null  # 攻击配置资源

var current_player_health: float = 0.0
var current_boss_health: float = 0.0
var current_boss_energy: float = 0.0
var temporary_energy_reduce: float = 0.0  # 本次攻击阶段的临时精力削减量
var is_next_attack_charged: bool = false  # 下次攻击是否为蓄力版本

# 同级兄弟节点引用（GameManager 内部）
@onready var beat_manager: Node = get_node("../BeatManager")
@onready var track_manager: Node = get_node("../TrackManager")
@onready var input_manager: Node = get_node("../InputManager")
@onready var music_player: Node = get_node("../MusicPlayer")

# 暂停相关
var is_paused_for_attack: bool = false
var pause_timer: Timer = null


func _ready() -> void:
	# 初始化血量值
	current_player_health = max_player_health
	current_boss_health = max_boss_health
	current_boss_energy = max_boss_energy
	
	# 创建暂停计时器
	pause_timer = Timer.new()
	pause_timer.one_shot = true
	pause_timer.timeout.connect(_on_pause_timeout)
	add_child(pause_timer)
	
	# 通过 EventBus 连接信号（替代 get_node + signal connect）
	EventBus.judgment_made.connect(_on_judgment_made)
	EventBus.attack_performed.connect(_on_attack_performed)
	
	# 延迟一帧广播初始血量（确保 GameUI 已连接 EventBus）
	call_deferred("_emit_health_update")


## 广播所有血量/精力状态到 EventBus
func _emit_health_update() -> void:
	EventBus.player_health_updated.emit(current_player_health, max_player_health)
	EventBus.boss_health_updated.emit(current_boss_health, max_boss_health)
	EventBus.boss_energy_updated.emit(current_boss_energy, max_boss_energy)


## 判定触发回调
func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
	# 如果是 MISS 判定，触发对应轨道的音效衰减
	if judgment == 3:  # MISS
		if music_player and music_player.has_method("apply_track_miss_effect"):
			music_player.apply_track_miss_effect(track)
	
	# 根据音符类型和判定等级获取数值
	var energy_cost: float = _get_boss_damage(track, judgment)
	var health_change: float = _get_player_health_change(track, judgment)
	
	# 减少Boss精力
	var old_energy: float = current_boss_energy
	current_boss_energy -= energy_cost
	current_boss_energy = clampf(current_boss_energy, 0.0, max_boss_energy)
	
	# 检测精力条是否被打空
	if old_energy > 0.0 and current_boss_energy <= 0.0:
		EventBus.boss_energy_depleted.emit()
		_on_boss_energy_depleted()
		print("Boss 精力耗尽！")
	
	# 改变玩家血量
	current_player_health += health_change
	current_player_health = clampf(current_player_health, 0.0, max_player_health)
	
	# 通过 EventBus 广播血量变化
	_emit_health_update()
	
	# 检查胜负条件
	if current_player_health <= 0.0:
		player_died.emit()
		EventBus.player_died.emit()
		print("玩家失败！")
	elif current_boss_health <= 0.0:
		boss_defeated.emit()
		EventBus.boss_defeated.emit()
		print("Boss 被击败！")


## 获取对Boss的伤害值
func _get_boss_damage(track: int, judgment: int) -> float:
	match track:
		Note.NoteType.GUARD:
			match judgment:
				0: return guard_boss_damage_perfect
				1: return guard_boss_damage_great
				2: return guard_boss_damage_good
				3: return guard_boss_damage_miss
		Note.NoteType.HIT:
			match judgment:
				0: return hit_boss_damage_perfect
				1: return hit_boss_damage_great
				2: return hit_boss_damage_good
				3: return hit_boss_damage_miss
		Note.NoteType.DODGE:
			match judgment:
				0: return dodge_boss_damage_perfect
				1: return dodge_boss_damage_great
				2: return dodge_boss_damage_good
				3: return dodge_boss_damage_miss
	return 0.0


## 获取玩家血量变化值
func _get_player_health_change(track: int, judgment: int) -> float:
	match track:
		Note.NoteType.GUARD:
			match judgment:
				0: return guard_player_health_perfect
				1: return guard_player_health_great
				2: return guard_player_health_good
				3: return guard_player_health_miss
		Note.NoteType.HIT:
			match judgment:
				0: return hit_player_health_perfect
				1: return hit_player_health_great
				2: return hit_player_health_good
				3: return hit_player_health_miss
		Note.NoteType.DODGE:
			match judgment:
				0: return dodge_player_health_perfect
				1: return dodge_player_health_great
				2: return dodge_player_health_good
				3: return dodge_player_health_miss
	return 0.0


## 更新血量条显示（通过 EventBus 广播）
func _update_health_bars() -> void:
	_emit_health_update()


## 重置游戏
func reset_game() -> void:
	current_player_health = max_player_health
	current_boss_health = max_boss_health
	current_boss_energy = max_boss_energy
	temporary_energy_reduce = 0.0
	is_next_attack_charged = false
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
	EventBus.show_beat_track_requested.emit()
	EventBus.show_pause_countdown_requested.emit(bi)
	
	# 计算第一输入拍的绝对时间（所有音符共享同一时间网格）
	var depletion_time: float = Time.get_ticks_msec() / 1000.0
	var first_beat_abs_time: float = depletion_time + 4.0 * bi  # 输入拍第1拍
	var note1_target: float = first_beat_abs_time
	var note2_target: float = first_beat_abs_time + bi
	# 在准备阶段第3拍开始时生成第一个音符
	get_tree().create_timer(bi * 2.0).timeout.connect(func():
		EventBus.spawn_beat_note_requested.emit(bi, note1_target)
	)
	# 在准备阶段第4拍开始时生成第二个音符
	get_tree().create_timer(bi * 3.0).timeout.connect(func():
		EventBus.spawn_beat_note_requested.emit(bi, note2_target)
	)
	# 后四个小节：节拍闪光效果
	get_tree().create_timer(countdown_duration).timeout.connect(func():
		EventBus.play_beat_flash_requested.emit(bi, GameConstants.INPUT_BEATS)
	)
	# 提前半拍启动攻击阶段（传入 first_beat_abs_time 保证时间网格一证）
	var _fba := first_beat_abs_time
	get_tree().create_timer(countdown_duration - bi * GameConstants.FIRST_BEAT_DELAY_RATIO).timeout.connect(func():
		_start_attack_phase(attack_duration + return_countdown_duration, bi, _fba)
	)
	
	# 暂停音乐（保留鼓点，让drum跳到指定小节）
	if music_player:
		if music_player.has_method("pause_music_keep_drum"):
			var measure_time: float = beat_manager.offset + GameConstants.DRUM_START_BEAT * bi
			music_player.pause_music_keep_drum(measure_time)
		else:
			music_player.pause_music()
		
		# 提前淡入恢复音乐
		get_tree().create_timer(pause_duration - GameConstants.MUSIC_RESUME_LEAD_TIME).timeout.connect(func():
			if music_player and music_player.has_method("resume_music"):
				music_player.resume_music()
		)
	
	# 启动计时器（完整时长）
	pause_timer.start(pause_duration)
	print("游戏已暂停 ", pause_duration, " 秒（", GameConstants.TOTAL_ATTACK_BEATS, " 拍），drum播放第9-13小节")


## 暂停结束的回调
func _on_pause_timeout() -> void:
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
	
	# 恢复 Boss 精力条（减去临时削减量）
	var recovery_amount: float = max_boss_energy - temporary_energy_reduce
	recovery_amount = max(recovery_amount, 10.0)  # 最小保留10点
	current_boss_energy = recovery_amount
	_emit_health_update()
	
	print("暂停结束，游戏继续 - BOSS精力恢复到:", recovery_amount, " (临时削减:", temporary_energy_reduce, ")")


## 开始攻击阶段
func _start_attack_phase(duration: float, bi: float, first_beat_abs_time: float) -> void:
	print("攻击阶段开始！")
	
	# 重置蓄力状态和临时精力削减量
	is_next_attack_charged = false
	temporary_energy_reduce = 0.0
	
	# 启用攻击输入监听（传入 first_beat_abs_time 统一时间基准）
	if input_manager and input_manager.has_method("start_attack_phase"):
		input_manager.start_attack_phase(duration, bi, first_beat_abs_time)
	
	# 通过 EventBus 通知 UI 显示攻击界面
	EventBus.show_attack_ui_requested.emit()


## 处理攻击效果
func _on_attack_performed(attack_type: int) -> void:
	if not attack_config:
		print("警告：未配置攻击数据 (attack_config)")
		return
	
	var player_cost: float = 0.0
	var boss_damage: float = 0.0
	var energy_max_reduce: float = 0.0
	var heal_amount: float = 0.0
	
	match attack_type:
		0:  # LIGHT
			if is_next_attack_charged:
				# 蓄力轻攻击
				player_cost = attack_config.charged_light_player_health_cost
				boss_damage = attack_config.charged_light_boss_damage
				energy_max_reduce = attack_config.charged_light_boss_energy_max_reduce
				print("发动蓄力轻攻击 - 消耗:", player_cost, " 伤害:", boss_damage, " 精力上限减少:", energy_max_reduce)
				is_next_attack_charged = false  # 消耗蓄力状态
			else:
				# 普通轻攻击
				player_cost = attack_config.light_player_health_cost
				boss_damage = attack_config.light_boss_damage
				energy_max_reduce = attack_config.light_boss_energy_max_reduce
				print("发动轻攻击 - 消耗:", player_cost, " 伤害:", boss_damage, " 精力上限减少:", energy_max_reduce)
			
			# 应用效果
			current_player_health -= player_cost
			current_boss_health -= boss_damage
			temporary_energy_reduce += energy_max_reduce  # 累加临时削减量
		
		1:  # HEAVY
			if is_next_attack_charged:
				# 蓄力重攻击
				player_cost = attack_config.charged_heavy_player_health_cost
				boss_damage = attack_config.charged_heavy_boss_damage
				energy_max_reduce = attack_config.charged_heavy_boss_energy_max_reduce
				print("发动蓄力重攻击 - 消耗:", player_cost, " 伤害:", boss_damage, " 精力上限减少:", energy_max_reduce)
				is_next_attack_charged = false  # 消耗蓄力状态
			else:
				# 普通重攻击
				player_cost = attack_config.heavy_player_health_cost
				boss_damage = attack_config.heavy_boss_damage
				energy_max_reduce = attack_config.heavy_boss_energy_max_reduce
				print("发动重攻击 - 消耗:", player_cost, " 伤害:", boss_damage, " 精力上限减少:", energy_max_reduce)
			
			# 应用效果
			current_player_health -= player_cost
			current_boss_health -= boss_damage
			temporary_energy_reduce += energy_max_reduce  # 累加临时削减量
		
		2:  # HEAL
			# 回复
			heal_amount = attack_config.heal_amount
			current_player_health += heal_amount
			print("发动回复 - 恢复:", heal_amount)
		
		3:  # ENHANCE
			# 蓄力（只在非蓄力状态时生效）
			if not is_next_attack_charged:
				is_next_attack_charged = true
				print("发动蓄力 - 下次攻击将为蓄力版本")
			else:
				print("已处于蓄力状态，连续蓄力无效果")
	
	# 限制数值范围
	current_player_health = clampf(current_player_health, 0.0, max_player_health)
	current_boss_health = clampf(current_boss_health, 0.0, max_boss_health)
	
	# 通过 EventBus 广播血量变化
	_emit_health_update()
	
	# 检查胜负
	if current_player_health <= 0.0:
		player_died.emit()
		EventBus.player_died.emit()
		print("玩家失败！")
	elif current_boss_health <= 0.0:
		boss_defeated.emit()
		EventBus.boss_defeated.emit()
		print("Boss被击败！")
