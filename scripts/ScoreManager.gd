extends Node
## 分数管理器 - 管理玩家分数、血量、Boss体力

# 预加载资源类型
const AttackConfig = preload("res://scripts/AttackConfig.gd")

# 信号
signal player_health_changed(new_value: float)
signal boss_health_changed(new_value: float)
signal boss_energy_depleted()  # Boss 精力条被打空
signal player_died()
signal boss_defeated()

# === HIT 音符配置 ===
@export_group("HIT 音符 (攻击)")
@export var hit_boss_damage_perfect: float = 15.0
@export var hit_boss_damage_great: float = 10.0
@export var hit_boss_damage_good: float = 5.0
@export var hit_boss_damage_miss: float = 0.0

@export var hit_player_health_perfect: float = 3.0
@export var hit_player_health_great: float = 2.0
@export var hit_player_health_good: float = 1.0
@export var hit_player_health_miss: float = -15.0

# === GUARD 音符配置 ===
@export_group("GUARD 音符 (防御)")
@export var guard_boss_damage_perfect: float = 5.0
@export var guard_boss_damage_great: float = 3.0
@export var guard_boss_damage_good: float = 2.0
@export var guard_boss_damage_miss: float = 0.0

@export var guard_player_health_perfect: float = 10.0
@export var guard_player_health_great: float = 7.0
@export var guard_player_health_good: float = 4.0
@export var guard_player_health_miss: float = -20.0

# === DODGE 音符配置 ===
@export_group("DODGE 音符 (闪避)")
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
var player_health_bar: HealthBar = null
var boss_health_bar: HealthBar = null
var boss_energy_bar: HealthBar = null

# 暂停相关
var is_paused_for_attack: bool = false  # 是否因精力耗尽而暂停
var pause_timer: Timer = null  # 暂停计时器


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
	
	# 获取血量条引用
	var game_ui: Control = get_node("../GameUI")
	if game_ui:
		player_health_bar = game_ui.get_node_or_null("PlayerHealthBar")
		boss_health_bar = game_ui.get_node_or_null("BossHealthBar")
		boss_energy_bar = game_ui.get_node_or_null("BossEnergyBar")
		
		# 设置血量条的最大值
		if player_health_bar:
			player_health_bar.max_value = max_player_health
			player_health_bar.current_value = current_player_health
		if boss_health_bar:
			boss_health_bar.max_value = max_boss_health
			boss_health_bar.current_value = current_boss_health
		if boss_energy_bar:
			boss_energy_bar.max_value = max_boss_energy
			boss_energy_bar.current_value = current_boss_energy
	
	# 连接输入管理器信号
	var input_manager: Node = get_node("../InputManager")
	if input_manager:
		input_manager.judgment_made.connect(_on_judgment_made)
		input_manager.attack_performed.connect(_on_attack_performed)  # 连接攻击信号
	
	# 连接自己的精力耗尽信号
	boss_energy_depleted.connect(_on_boss_energy_depleted)
	
	# 初始化血量
	_update_health_bars()


## 判定触发回调
func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
	# 如果是 MISS 判定，触发对应轨道的音效衰减
	if judgment == 3:  # MISS
		var music_player: Node = get_node("../MusicPlayer")
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
		boss_energy_depleted.emit()
		print("Boss 精力耗尽！")
	
	# 改变玩家血量
	current_player_health += health_change
	current_player_health = clampf(current_player_health, 0.0, max_player_health)
	
	# 更新显示
	_update_health_bars()
	
	# 发送信号
	player_health_changed.emit(current_player_health)
	boss_health_changed.emit(current_boss_health)
	
	# 检查胜负条件
	if current_player_health <= 0.0:
		player_died.emit()
		print("玩家失败！")
	elif current_boss_health <= 0.0:
		boss_defeated.emit()
		print("Boss 被击败！")


## 获取对Boss的伤害值
func _get_boss_damage(track: int, judgment: int) -> float:
	match track:
		Note.NoteType.HIT:
			match judgment:
				0: return hit_boss_damage_perfect
				1: return hit_boss_damage_great
				2: return hit_boss_damage_good
				3: return hit_boss_damage_miss
		Note.NoteType.GUARD:
			match judgment:
				0: return guard_boss_damage_perfect
				1: return guard_boss_damage_great
				2: return guard_boss_damage_good
				3: return guard_boss_damage_miss
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
		Note.NoteType.HIT:
			match judgment:
				0: return hit_player_health_perfect
				1: return hit_player_health_great
				2: return hit_player_health_good
				3: return hit_player_health_miss
		Note.NoteType.GUARD:
			match judgment:
				0: return guard_player_health_perfect
				1: return guard_player_health_great
				2: return guard_player_health_good
				3: return guard_player_health_miss
		Note.NoteType.DODGE:
			match judgment:
				0: return dodge_player_health_perfect
				1: return dodge_player_health_great
				2: return dodge_player_health_good
				3: return dodge_player_health_miss
	return 0.0


## 更新血量条显示
func _update_health_bars() -> void:
	if player_health_bar:
		player_health_bar.set_value(current_player_health)
	
	if boss_health_bar:
		boss_health_bar.set_value(current_boss_health)
	
	if boss_energy_bar:
		if boss_energy_bar.has_method("set_max_value"):
			boss_energy_bar.set_max_value(max_boss_energy)
		else:
			boss_energy_bar.max_value = max_boss_energy
		boss_energy_bar.set_value(current_boss_energy)


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
	
	# 获取 BeatManager 计算攻击阶段时长（第2-5小节，共16拍 + 第6小节倒计时4拍）
	var beat_manager: Node = get_node("../BeatManager")
	if beat_manager:
		# 第1小节：倒计时准备阶段（4拍）
		var countdown_duration: float = beat_manager.beat_interval * 4.0
		# 第2-5小节：攻击阶段（4小节 * 4拍 = 16拍）
		var attack_duration: float = beat_manager.beat_interval * 16.0
		# 第6小节：返回倒计时（4拍）
		var return_countdown_duration: float = beat_manager.beat_interval * 4.0
		# 总暂停时长（6小节 = 24拍）
		var pause_duration: float = beat_manager.beat_interval * 24.0
		
		print("\n========== 攻击阶段开始（共6小节24拍） ==========")
		
		# 为准备阶段添加节拍log（拍1-4）
		for i in range(1, 5):
			get_tree().create_timer(beat_manager.beat_interval * (i - 1)).timeout.connect(func():
				var beat_num: int = i
				print("[总拍", beat_num, "/24] 准备阶段 - 拍", beat_num, "/4"))
				
		
		# 暂停节拍检测
		beat_manager.pause_beat_detection()
		
		# 暂停音符生成和清理已生成的音符
		var track_manager: Node = get_node("../TrackManager")
		if track_manager:
			if track_manager.has_method("pause_note_spawning"):
				track_manager.pause_note_spawning()
			track_manager.clear_all_notes()
		
		# 暂停输入检测
		var input_manager: Node = get_node("../InputManager")
		if input_manager and input_manager.has_method("pause_input"):
			input_manager.pause_input()
		
		# 启动暂停阶段视觉效果
		var game_ui: Node = get_node("../GameUI")
		if game_ui:
			# 立即显示迷你音轨
			if game_ui.has_method("show_beat_track"):
				game_ui.show_beat_track()
			
			# 第一个小节：倒计时
			game_ui.show_pause_countdown(beat_manager)
			
			# 在准备阶段第3拍开始时生成第一个音符（让它移动2拍到达判定线）
			var beat_interval_value: float = beat_manager.beat_interval
			get_tree().create_timer(beat_interval_value * 2.0).timeout.connect(func():
				if game_ui and game_ui.has_method("spawn_beat_note"):
					game_ui.spawn_beat_note(beat_interval_value * 2.0)  # 2倍时间，速度减半
			)
			# 在准备阶段第4拍开始时生成第二个音符
			get_tree().create_timer(beat_interval_value * 3.0).timeout.connect(func():
				if game_ui and game_ui.has_method("spawn_beat_note"):
					game_ui.spawn_beat_note(beat_interval_value * 2.0)
			)
			# 后四个小节：节拍闪光效果（延迟一个小节后开始）
			get_tree().create_timer(beat_manager.beat_interval * 4.0).timeout.connect(func():
				if game_ui and game_ui.has_method("play_beat_flash_effects"):
					game_ui.play_beat_flash_effects(beat_manager, 16)
			)
			# 倒计时后启动攻击阶段（20拍：16拍攻击 + 4拍返回倒计时）
			get_tree().create_timer(countdown_duration).timeout.connect(func():
				_start_attack_phase(attack_duration + return_countdown_duration, beat_manager.beat_interval)
			)
		
		# 暂停音乐（保留鼓点，并让drum跳到第9小节）
		var music_player: Node = get_node("../MusicPlayer")
		if music_player:
			if music_player.has_method("pause_music_keep_drum"):
				# 第9小节开始 = beat 32 (8小节 * 4拍)
				var measure_9_time: float = beat_manager.offset + 32.0 * beat_manager.beat_interval
				music_player.pause_music_keep_drum(measure_9_time)
			else:
				music_player.pause_music()
			
			# 提前0.5秒调用resume_music开始淡入
			get_tree().create_timer(pause_duration - 0.5).timeout.connect(func():
				if music_player and music_player.has_method("resume_music"):
					music_player.resume_music()
			)
		
		# 启动计时器（完整时长）
		pause_timer.start(pause_duration)
		print("游戏已暂停 ", pause_duration, " 秒（5 个小节），drum播放第9-13小节")


## 暂停结束的回调
func _on_pause_timeout() -> void:
	is_paused_for_attack = false
	
	# 隐藏暂停视觉效果
	var game_ui: Node = get_node("../GameUI")
	if game_ui and game_ui.has_method("hide_pause_effects"):
		game_ui.hide_pause_effects()
	
	# 恢复节拍检测
	var beat_manager: Node = get_node("../BeatManager")
	if beat_manager:
		beat_manager.resume_beat_detection()
	
	# 恢复输入检测
	var input_manager: Node = get_node("../InputManager")
	if input_manager and input_manager.has_method("resume_input"):
		input_manager.resume_input()
	
	# 音乐恢复已在0.5秒前开始淡入，这里不需要再调用
	
	# 恢复音符生成
	var track_manager: Node = get_node("../TrackManager")
	if track_manager and track_manager.has_method("resume_note_spawning"):
		track_manager.resume_note_spawning()
	
	# 恢复 Boss 精力条（减去临时削减量）
	var recovery_amount: float = max_boss_energy - temporary_energy_reduce
	recovery_amount = max(recovery_amount, 10.0)  # 最小保留10点
	current_boss_energy = recovery_amount
	_update_health_bars()
	
	print("暂停结束，游戏继续 - BOSS精力恢复到:", recovery_amount, " (临时削减:", temporary_energy_reduce, ")")


## 开始攻击阶段（第2-5小节，共16拍）
func _start_attack_phase(duration: float, beat_interval: float) -> void:
	print("攻击阶段开始！")
	
	# 重置蓄力状态和临时精力削减量
	is_next_attack_charged = false
	temporary_energy_reduce = 0.0
	
	# 启用攻击输入监听
	var input_manager: Node = get_node("../InputManager")
	if input_manager and input_manager.has_method("start_attack_phase"):
		input_manager.start_attack_phase(duration, beat_interval)
	
	# 显示攻击UI
	var game_ui: Node = get_node("../GameUI")
	if game_ui and game_ui.has_method("show_attack_ui"):
		game_ui.show_attack_ui()


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
	
	# 更新显示
	_update_health_bars()
	
	# 发送信号
	player_health_changed.emit(current_player_health)
	boss_health_changed.emit(current_boss_health)
	
	# 检查胜负
	if current_player_health <= 0.0:
		player_died.emit()
		print("玩家失败！")
	elif current_boss_health <= 0.0:
		boss_defeated.emit()
		print("Boss被击败！")
