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
@export_subgroup("失误")
@export var guard_miss: RandomSoundPool = null

@export_group("攻击 (I键)")
@export_subgroup("成功")
@export var hit_success: RandomSoundPool = null
@export_subgroup("失误")
@export var hit_miss: RandomSoundPool = null

@export_group("闪避 (L键)")
@export_subgroup("成功")
@export var dodge_success: RandomSoundPool = null
@export_subgroup("失误")
@export var dodge_miss: RandomSoundPool = null


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
