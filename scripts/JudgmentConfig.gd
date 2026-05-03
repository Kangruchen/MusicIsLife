extends Resource
class_name JudgmentConfig
## 防御阶段判定数值配置
## 每种音符类型 × 每种判定等级 的 Boss精力伤害和玩家血量变化

@export_group("GUARD 音符 (防御) - J键第一轨道")
@export var guard_boss_damage_perfect: float = 5.0
@export var guard_boss_damage_great: float = 3.0
@export var guard_boss_damage_good: float = 2.0
@export var guard_boss_damage_miss: float = 0.0
@export var guard_player_health_perfect: float = 10.0
@export var guard_player_health_great: float = 7.0
@export var guard_player_health_good: float = 4.0
@export var guard_player_health_miss: float = -20.0

@export_group("HIT 音符 (攻击) - I键第二轨道")
@export var hit_boss_damage_perfect: float = 15.0
@export var hit_boss_damage_great: float = 10.0
@export var hit_boss_damage_good: float = 5.0
@export var hit_boss_damage_miss: float = 0.0
@export var hit_player_health_perfect: float = 3.0
@export var hit_player_health_great: float = 2.0
@export var hit_player_health_good: float = 1.0
@export var hit_player_health_miss: float = -15.0

@export_group("DODGE 音符 (闪避) - L键第三轨道")
@export var dodge_boss_damage_perfect: float = 8.0
@export var dodge_boss_damage_great: float = 5.0
@export var dodge_boss_damage_good: float = 3.0
@export var dodge_boss_damage_miss: float = 0.0
@export var dodge_player_health_perfect: float = 5.0
@export var dodge_player_health_great: float = 3.0
@export var dodge_player_health_good: float = 2.0
@export var dodge_player_health_miss: float = -10.0

@export_group("血量上限")
@export var max_player_health: float = 100.0
@export var max_boss_health: float = 500.0
@export var max_boss_energy: float = 100.0


func get_boss_damage(track: int, judgment: int) -> float:
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


func get_player_health_change(track: int, judgment: int) -> float:
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
