extends Resource
class_name PlayerDefenseSoundConfig
## 玩家防御阶段音效配置
## 为每种防御操作分别配置成功和失误状态的音效
## 所有音效均支持 RandomSoundPool 多候选随机播放
##
## 使用示例：
##   guard_success = RandomSoundPool（含 block_01.wav, block_02.wav）
##   guard_miss = RandomSoundPool（含 miss_guard.wav）
##   hit_success = RandomSoundPool（含 deflect_01.wav, deflect_02.wav）

@export var sfx_bus: StringName = &"SFX"

@export_group("防御 (J键)")
@export_subgroup("成功")
@export var guard_success: RandomSoundPool = null
@export_range(0.0, 0.2, 0.001) var guard_success_time_offset: float = 0.0
@export_subgroup("失误")
@export var guard_miss: RandomSoundPool = null
@export_range(0.0, 0.2, 0.001) var guard_miss_time_offset: float = 0.0

@export_group("攻击 (I键)")
@export_subgroup("成功")
@export var hit_success: RandomSoundPool = null
@export_range(0.0, 0.2, 0.001) var hit_success_time_offset: float = 0.0
@export_subgroup("失误")
@export var hit_miss: RandomSoundPool = null
@export_range(0.0, 0.2, 0.001) var hit_miss_time_offset: float = 0.0

@export_group("闪避 (L键)")
@export_subgroup("成功")
@export var dodge_success: RandomSoundPool = null
@export_range(0.0, 0.2, 0.001) var dodge_success_time_offset: float = 0.0
@export_subgroup("失误")
@export var dodge_miss: RandomSoundPool = null
@export_range(0.0, 0.2, 0.001) var dodge_miss_time_offset: float = 0.0


func get_success_sound(note_type: int) -> RandomSoundPool:
	match note_type:
		Note.NoteType.GUARD:
			return guard_success
		Note.NoteType.HIT:
			return hit_success
		Note.NoteType.DODGE:
			return dodge_success
		_:
			return null


func get_miss_sound(note_type: int) -> RandomSoundPool:
	match note_type:
		Note.NoteType.GUARD:
			return guard_miss
		Note.NoteType.HIT:
			return hit_miss
		Note.NoteType.DODGE:
			return dodge_miss
		_:
			return null


func get_success_time_offset(note_type: int) -> float:
	match note_type:
		Note.NoteType.GUARD:
			return guard_success_time_offset
		Note.NoteType.HIT:
			return hit_success_time_offset
		Note.NoteType.DODGE:
			return dodge_success_time_offset
		_:
			return 0.0


func get_miss_time_offset(note_type: int) -> float:
	match note_type:
		Note.NoteType.GUARD:
			return guard_miss_time_offset
		Note.NoteType.HIT:
			return hit_miss_time_offset
		Note.NoteType.DODGE:
			return dodge_miss_time_offset
		_:
			return 0.0
