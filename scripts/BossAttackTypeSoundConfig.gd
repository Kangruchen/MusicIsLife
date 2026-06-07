extends Resource
class_name BossAttackTypeSoundConfig

@export var default_sound: RandomSoundPool = null
@export_range(0.0, 2.0, 0.001) var default_sound_time_offset: float = 0.0

@export var beat_sounds: Array[RandomSoundPool] = []
@export var beat_sound_time_offsets: Array[float] = []

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


func get_time_offset_for_beat(beat_index: int) -> float:
	if beat_sound_time_offsets.size() > 0:
		var effective_index: int = beat_index
		if loop_beat_sounds:
			effective_index = beat_index % beat_sound_time_offsets.size()
		if effective_index >= 0 and effective_index < beat_sound_time_offsets.size():
			return maxf(0.0, beat_sound_time_offsets[effective_index])
	return maxf(0.0, default_sound_time_offset)
