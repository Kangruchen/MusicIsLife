extends Resource
class_name PlayerAttackSoundConfig
## 玩家攻击阶段音效配置
## 为每种攻击操作配置 RandomSoundPool，支持多候选音效随机播放
##
## 使用示例：
##   light_attack = RandomSoundPool（含 slash_01.wav, slash_02.wav, slash_03.wav）
##   heavy_attack = RandomSoundPool（含 heavy_slash_01.wav, heavy_slash_02.wav）
##   heal = RandomSoundPool（含 heal.wav）

@export var sfx_bus: StringName = &"SFX"

@export_group("轻攻击")
@export var light_attack: RandomSoundPool = null

@export_group("重攻击")
@export var heavy_attack: RandomSoundPool = null

@export_group("蓄力轻攻击")
@export var charged_light_attack: RandomSoundPool = null

@export_group("蓄力重攻击")
@export var charged_heavy_attack: RandomSoundPool = null

@export_group("回复")
@export var heal: RandomSoundPool = null

@export_group("蓄力")
@export var enhance: RandomSoundPool = null


func get_sound(attack_type: int, is_charged: bool) -> RandomSoundPool:
	match attack_type:
		0:
			return charged_light_attack if is_charged and charged_light_attack != null and not charged_light_attack.is_empty() else light_attack
		1:
			return charged_heavy_attack if is_charged and charged_heavy_attack != null and not charged_heavy_attack.is_empty() else heavy_attack
		2:
			return heal
		3:
			return enhance
		_:
			return null
