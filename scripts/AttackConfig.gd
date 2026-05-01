extends Resource
class_name AttackConfig
## 攻击阶段配置 - 定义各种攻击的数值效果

# === 轻攻击配置 ===
@export_group("轻攻击")
@export var light_player_health_cost: float = 5.0  # 玩家血量消耗
@export var light_boss_damage: float = 20.0  # BOSS伤害
@export var light_boss_energy_max_reduce: float = 5.0  # 减少BOSS精力条最大值

# === 重攻击配置 ===
@export_group("重攻击")
@export var heavy_player_health_cost: float = 15.0  # 玩家血量消耗
@export var heavy_boss_damage: float = 50.0  # BOSS伤害
@export var heavy_boss_energy_max_reduce: float = 10.0  # 减少BOSS精力条最大值

# === 蓄力轻攻击配置 ===
@export_group("蓄力轻攻击")
@export var charged_light_player_health_cost: float = 2.0  # 玩家血量消耗（较少）
@export var charged_light_boss_damage: float = 35.0  # BOSS伤害（较高）
@export var charged_light_boss_energy_max_reduce: float = 8.0  # 减少BOSS精力条最大值

# === 蓄力重攻击配置 ===
@export_group("蓄力重攻击")
@export var charged_heavy_player_health_cost: float = 8.0  # 玩家血量消耗（较少）
@export var charged_heavy_boss_damage: float = 80.0  # BOSS伤害（很高）
@export var charged_heavy_boss_energy_max_reduce: float = 15.0  # 减少BOSS精力条最大值

# === 回复配置 ===
@export_group("回复")
@export var heal_amount: float = 20.0  # 回复血量

# === 攻击动作音效配置 ===
@export_group("攻击动作音效")
@export var attack_sfx_bus: StringName = &"Master"

@export_subgroup("轻攻击")
@export var light_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var light_sfx_volume_db: float = 0.0

@export_subgroup("重攻击")
@export var heavy_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var heavy_sfx_volume_db: float = 0.0

@export_subgroup("蓄力轻攻击")
@export var charged_light_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var charged_light_sfx_volume_db: float = 0.0

@export_subgroup("蓄力重攻击")
@export var charged_heavy_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var charged_heavy_sfx_volume_db: float = 0.0

@export_subgroup("回复")
@export var heal_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var heal_sfx_volume_db: float = 0.0

@export_subgroup("蓄力")
@export var enhance_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var enhance_sfx_volume_db: float = 0.0


func get_attack_sfx(attack_type: int, is_charged: bool) -> AudioStream:
	match attack_type:
		0:  # LIGHT
			return charged_light_sfx if is_charged and charged_light_sfx != null else light_sfx
		1:  # HEAVY
			return charged_heavy_sfx if is_charged and charged_heavy_sfx != null else heavy_sfx
		2:  # HEAL
			return heal_sfx
		3:  # ENHANCE
			return enhance_sfx
		_:
			return null


func get_attack_sfx_volume_db(attack_type: int, is_charged: bool) -> float:
	match attack_type:
		0:  # LIGHT
			return charged_light_sfx_volume_db if is_charged and charged_light_sfx != null else light_sfx_volume_db
		1:  # HEAVY
			return charged_heavy_sfx_volume_db if is_charged and charged_heavy_sfx != null else heavy_sfx_volume_db
		2:  # HEAL
			return heal_sfx_volume_db
		3:  # ENHANCE
			return enhance_sfx_volume_db
		_:
			return 0.0
