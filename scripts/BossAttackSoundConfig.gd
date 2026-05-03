extends Resource
class_name BossAttackSoundConfig
## Boss 攻击音效总配置
## 三类攻击（激光/导弹/蓄力子弹）各自拥有独立的 BossAttackTypeSoundConfig
## 每种攻击类型支持逐拍/逐次配置独立音效，支持随机播放和时间偏移
##
## 使用示例：
##   laser_config.default_sound = RandomSoundPool（含 laser_01.wav, laser_02.wav）
##   laser_config.beat_sounds[0] = RandomSoundPool（第1次激光专用音效池）
##   missile_config.default_sound = RandomSoundPool（含 missile_01.wav）

const ATTACK_LASER: int = 0
const ATTACK_MISSILE: int = 1
const ATTACK_CHARGE_BULLET: int = 2

@export_group("激光攻击")
@export var laser_config: BossAttackTypeSoundConfig = null

@export_group("导弹攻击")
@export var missile_config: BossAttackTypeSoundConfig = null

@export_group("蓄力子弹攻击")
@export var charge_bullet_config: BossAttackTypeSoundConfig = null


func get_config(attack_type: int) -> BossAttackTypeSoundConfig:
	match attack_type:
		ATTACK_LASER:
			return laser_config
		ATTACK_MISSILE:
			return missile_config
		ATTACK_CHARGE_BULLET:
			return charge_bullet_config
		_:
			return null


func get_sound_for_beat(attack_type: int, beat_index: int) -> RandomSoundPool:
	var cfg: BossAttackTypeSoundConfig = get_config(attack_type)
	if cfg == null:
		return null
	return cfg.get_sound_for_beat(beat_index)


func get_sfx_bus(attack_type: int) -> StringName:
	var cfg: BossAttackTypeSoundConfig = get_config(attack_type)
	if cfg == null:
		return &"SFX"
	return cfg.sfx_bus
