extends Resource
class_name BossAttackSoundConfig
## Boss 攻击音效配置
## 三类攻击：激光、导弹、蓄力子弹

const ATTACK_LASER: int = 0
const ATTACK_MISSILE: int = 1
const ATTACK_CHARGE_BULLET: int = 2

@export_group("通用")
@export var sfx_bus: StringName = &"Master"

@export_group("激光攻击")
@export var laser_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var laser_volume_db: float = -2.0
@export_range(0.1, 4.0, 0.01) var laser_pitch_scale: float = 1.0
@export_range(0.0, 10.0, 1.0) var laser_start_frame: float = 0.0
@export_range(0.0, 5.0, 0.01) var laser_start_offset_sec: float = 0.0

@export_group("导弹攻击")
@export var missile_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var missile_volume_db: float = -2.0
@export_range(0.1, 4.0, 0.01) var missile_pitch_scale: float = 1.0
@export_range(0.0, 30.0, 1.0) var missile_start_frame: float = 0.0
@export_range(0.0, 5.0, 0.01) var missile_start_offset_sec: float = 0.0

@export_group("蓄力子弹攻击")
@export var charge_bullet_sfx: AudioStream = null
@export_range(-40.0, 12.0, 0.1) var charge_bullet_volume_db: float = -2.0
@export_range(0.1, 4.0, 0.01) var charge_bullet_pitch_scale: float = 1.0
@export_range(0.0, 60.0, 1.0) var charge_bullet_start_frame: float = 16.0
@export_range(0.0, 5.0, 0.01) var charge_bullet_start_offset_sec: float = 0.0


func get_attack_sfx(attack_type: int) -> AudioStream:
	match attack_type:
		ATTACK_LASER:
			return laser_sfx
		ATTACK_MISSILE:
			return missile_sfx
		ATTACK_CHARGE_BULLET:
			return charge_bullet_sfx
		_:
			return null


func get_attack_sfx_volume_db(attack_type: int) -> float:
	match attack_type:
		ATTACK_LASER:
			return laser_volume_db
		ATTACK_MISSILE:
			return missile_volume_db
		ATTACK_CHARGE_BULLET:
			return charge_bullet_volume_db
		_:
			return 0.0


func get_attack_sfx_pitch_scale(attack_type: int) -> float:
	match attack_type:
		ATTACK_LASER:
			return laser_pitch_scale
		ATTACK_MISSILE:
			return missile_pitch_scale
		ATTACK_CHARGE_BULLET:
			return charge_bullet_pitch_scale
		_:
			return 1.0


func get_attack_sfx_start_frame(attack_type: int) -> int:
	match attack_type:
		ATTACK_LASER:
			return int(laser_start_frame)
		ATTACK_MISSILE:
			return int(missile_start_frame)
		ATTACK_CHARGE_BULLET:
			return int(charge_bullet_start_frame)
		_:
			return 0


func get_attack_sfx_start_offset_sec(attack_type: int) -> float:
	match attack_type:
		ATTACK_LASER:
			return laser_start_offset_sec
		ATTACK_MISSILE:
			return missile_start_offset_sec
		ATTACK_CHARGE_BULLET:
			return charge_bullet_start_offset_sec
		_:
			return 0.0
