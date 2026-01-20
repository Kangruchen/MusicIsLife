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
