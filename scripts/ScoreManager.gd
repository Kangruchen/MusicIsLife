extends Node
## 分数管理器 - 管理玩家分数、血量、Boss体力

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

var current_player_health: float = 0.0
var current_boss_health: float = 0.0
var current_boss_energy: float = 0.0
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
	
	# 连接自己的精力耗尽信号
	boss_energy_depleted.connect(_on_boss_energy_depleted)
	
	# 初始化血量
	_update_health_bars()


## 判定触发回调
func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
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
		boss_energy_bar.set_value(current_boss_energy)


## 重置游戏
func reset_game() -> void:
	current_player_health = max_player_health
	current_boss_health = max_boss_health
	current_boss_energy = max_boss_energy
	_update_health_bars()


## Boss 精力耗尽时的处理
func _on_boss_energy_depleted() -> void:
	if is_paused_for_attack:
		return  # 已经在暂停状态，不重复处理
	
	is_paused_for_attack = true
	
	# 获取 BeatManager 计算暂停时长（4 个小节）
	var beat_manager: Node = get_node("../BeatManager")
	if beat_manager:
		# 4 小节 = 4 拍/小节 * 4 = 16 拍
		var pause_duration: float = beat_manager.beat_interval * 16.0
		
		# 暂停音乐
		var music_player: AudioStreamPlayer = get_node("../MusicPlayer")
		if music_player:
			music_player.pause_music()
		
		# 暂停节拍检测
		beat_manager.pause_beat_detection()
		
		# 清除所有活跃音符
		var track_manager: Node = get_node("../TrackManager")
		if track_manager:
			track_manager.clear_all_notes()
		
		# 启动计时器
		pause_timer.start(pause_duration)
		print("游戏已暂停 ", pause_duration, " 秒（4 个小节），用于玩家攻击阶段")


## 暂停结束的回调
func _on_pause_timeout() -> void:
	is_paused_for_attack = false
	
	# 恢复音乐
	var music_player: AudioStreamPlayer = get_node("../MusicPlayer")
	if music_player:
		music_player.resume_music()
	
	# 恢复节拍检测
	var beat_manager: Node = get_node("../BeatManager")
	if beat_manager:
		beat_manager.resume_beat_detection()
	
	# 恢复 Boss 精力条
	current_boss_energy = max_boss_energy
	_update_health_bars()
	
	print("暂停结束，游戏继续")
