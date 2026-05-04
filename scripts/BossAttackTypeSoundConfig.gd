extends Resource
class_name BossAttackTypeSoundConfig

@export var default_sound: RandomSoundPool = null

@export var beat_sounds: Array[RandomSoundPool] = []

@export var loop_beat_sounds: bool = false

@export var sfx_bus: StringName = &"SFX"


func get_sound_for_beat(beat_index: int) -> RandomSoundPool:
	if beat_sounds.size() > 0:
		var effective_index: int = beat_index
		if loop_beat_sounds:
			effective_index = beat_index % beat_sounds.size()
		if effective_index >= 0 and effective_index < beat_sounds.size():
			var pool: RandomSoundPool = beat_sounds[effective_index]
			if pool != null and not pool.is_empty():
				return pool
	return default_sound
