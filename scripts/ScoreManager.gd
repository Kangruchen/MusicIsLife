extends Node
## 分数管理器 - 管理玩家分数、血量、Boss体力

# 信号
signal player_health_changed(new_value: float)
signal boss_health_changed(new_value: float)
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

var current_player_health: float = 0.0
var current_boss_health: float = 0.0
var current_boss_energy: float = 0.0
var player_health_bar: HealthBar = null
var boss_health_bar: HealthBar = null
var boss_energy_bar: HealthBar = null


func _ready() -> void:
	# 初始化血量值
	current_player_health = max_player_health
	current_boss_health = max_boss_health
	current_boss_energy = 100.0
	
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
			boss_energy_bar.max_value = 100.0
			boss_energy_bar.current_value = current_boss_energy
	
	# 连接输入管理器信号
	var input_manager: Node = get_node("../InputManager")
	if input_manager:
		input_manager.judgment_made.connect(_on_judgment_made)
	
	# 初始化血量
	_update_health_bars()


## 判定触发回调
func _on_judgment_made(track: int, judgment: int, _timing_diff: float) -> void:
	# 根据音符类型和判定等级获取数值
	var energy_cost: float = _get_boss_damage(track, judgment)
	var health_change: float = _get_player_health_change(track, judgment)
	
	# 减少Boss精力
	current_boss_energy -= energy_cost
	current_boss_energy = clampf(current_boss_energy, 0.0, 100.0)
	
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
	current_boss_energy = 100.0
	_update_health_bars()
