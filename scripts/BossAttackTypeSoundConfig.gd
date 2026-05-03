extends Resource
class_name BossAttackTypeSoundConfig
## 单种 Boss 攻击类型的音效配置
## 支持为每次攻击（逐次/逐拍）配置独立音效，未配置的回退到 default_sound
##
## 使用示例：
##   default_sound = RandomSoundPool（含 laser_01.wav, laser_02.wav）
##   beat_sounds[0] = RandomSoundPool（第1次激光专用音效）
##   beat_sounds[2] = RandomSoundPool（第3次激光专用音效）

@export var default_sound: RandomSoundPool = null

@export var beat_sounds: Array[RandomSoundPool] = []

@export var sfx_bus: StringName = &"SFX"


func get_sound_for_beat(beat_index: int) -> RandomSoundPool:
	if beat_index >= 0 and beat_index < beat_sounds.size():
		var pool: RandomSoundPool = beat_sounds[beat_index]
		if pool != null and not pool.is_empty():
			return pool
	return default_sound
