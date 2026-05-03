extends Resource
class_name GameSoundConfig
## 游戏音效与攻击数值统一配置
## 合并所有音效配置和攻击数值到一个资源文件，按功能分组管理
##
## 分组结构：
##   防御按键音效 — 防御阶段三种音符的按键音效
##   Boss攻击音效 — Boss 三种攻击类型的逐拍音效
##   玩家攻击配置 — 攻击阶段音效 + 数值效果
##   玩家防御音效 — 防御判定的成功/失误音效
##   Miss音效 — 失误音效

@export var sfx_bus: StringName = &"SFX"

@export_group("防御按键音效")
@export var key_guard_sound: RandomSoundPool = null
@export var key_hit_sound: RandomSoundPool = null
@export var key_dodge_sound: RandomSoundPool = null
@export var boss_phase_key_sound_muted: bool = true

@export_group("Boss攻击音效")
@export var boss_sounds: BossAttackSoundConfig = null

@export_group("玩家攻击配置")
@export_subgroup("音效")
@export var player_attack: PlayerAttackSoundConfig = null
@export_subgroup("轻攻击")
@export var light_player_health_cost: float = 5.0
@export var light_boss_damage: float = 20.0
@export var light_boss_energy_max_reduce: float = 5.0
@export_subgroup("重攻击")
@export var heavy_player_health_cost: float = 15.0
@export var heavy_boss_damage: float = 50.0
@export var heavy_boss_energy_max_reduce: float = 10.0
@export_subgroup("蓄力轻攻击")
@export var charged_light_player_health_cost: float = 2.0
@export var charged_light_boss_damage: float = 35.0
@export var charged_light_boss_energy_max_reduce: float = 8.0
@export_subgroup("蓄力重攻击")
@export var charged_heavy_player_health_cost: float = 8.0
@export var charged_heavy_boss_damage: float = 80.0
@export var charged_heavy_boss_energy_max_reduce: float = 15.0
@export_subgroup("回复")
@export var heal_amount: float = 20.0

@export_group("玩家防御音效")
@export var player_defense: PlayerDefenseSoundConfig = null

@export_group("Miss音效")
@export var miss_sound: AudioStream = null
@export_range(-80.0, 24.0, 0.1) var miss_sound_volume_db: float = 0.0


func get_key_sound(note_type: Note.NoteType) -> RandomSoundPool:
	match note_type:
		Note.NoteType.GUARD:
			return key_guard_sound
		Note.NoteType.HIT:
			return key_hit_sound
		Note.NoteType.DODGE:
			return key_dodge_sound
		_:
			return null
